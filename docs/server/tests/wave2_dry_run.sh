# server-rules-wave2.md dry run. Run on the VM as ubuntu, files scp'd to /tmp/w2 first:
#   tok.pb.js mk.pb.js fm.pb.js 1794810000_updated_rules_wave2.js wave2_probe.py wave2_request_table.py
# "before" = live copy; "after" = live copy + the migration. Both get the live user_fields_unhide and
# former_member_record hooks plus the test-only routes. Nothing live is changed: the live DB is only read.
set -e
T=/tmp/pbtest; M=/tmp/w2; rm -rf $T; mkdir -p $T/h
sudo cp /opt/pocketbase/pb_hooks/user_fields_unhide.pb.js /opt/pocketbase/pb_hooks/former_member_record.pb.js $T/h/
cp $M/tok.pb.js $M/mk.pb.js $M/fm.pb.js $T/h/
for v in before after probe; do
  mkdir -p $T/$v/pb_data
  sudo sqlite3 -readonly /opt/pocketbase/pb_data/data.db ".backup $T/$v/pb_data/data.db"
  sudo cp -r /opt/pocketbase/pb_migrations $T/$v/
done
sudo chown -R ubuntu $T
for v in after probe; do
  cp $M/1794810000_updated_rules_wave2.js $T/$v/pb_migrations/
  /opt/pocketbase/pocketbase migrate up --dir=$T/$v/pb_data --migrationsDir=$T/$v/pb_migrations --hooksDir=$T/h 2>&1 | tail -1
done
APPLIED=$(sqlite3 -readonly $T/after/pb_data/data.db "select count(*) from _migrations where file='1794810000_updated_rules_wave2.js'")
echo "##### migration applied on the after copy: $APPLIED"; [ "$APPLIED" = 1 ] || { rm -rf $T $M; exit 1; }
COLS="'conversations','conversation_members','friendships','friend_requests','reactions','message_media','polls','scheduled_messages'"
RULES="select name, createRule, updateRule, deleteRule from _collections where name in ($COLS) order by name"
echo "##### table sizes (copy of live)"
sqlite3 -readonly $T/before/pb_data/data.db "select 'users', count(*) from users; select 'conversations', count(*) from conversations; select 'conversation_members', count(*) from conversation_members; select 'friendships', count(*) from friendships; select 'friend_requests', count(*) from friend_requests; select 'group_invites', count(*) from group_invites; select 'messages', count(*) from messages; select 'reactions', count(*) from reactions"
echo "##### X-7 counts (read-only, before copy)"
sqlite3 -readonly $T/before/pb_data/data.db "
select 'friendships with no accepted request either way', count(*) from friendships f where not exists (select 1 from friend_requests r where r.status = 'accepted' and ((r.from_user = f.user_b and r.to_user = f.user_a) or (r.from_user = f.user_a and r.to_user = f.user_b)));
select 'DM pairs who are not friends', count(*) from conversation_members m1 join conversation_members m2 on m2.conversation_id = m1.conversation_id and m1.user_id < m2.user_id join conversations c on c.id = m1.conversation_id and c.type = 'direct' where not exists (select 1 from friendships f where (f.user_a = m1.user_id and f.user_b = m2.user_id) or (f.user_a = m2.user_id and f.user_b = m1.user_id));
select 'chats whose creator is no longer a member', count(*) from conversations c where not exists (select 1 from conversation_members m where m.conversation_id = c.id and m.user_id = c.created_by);
select 'reactions by someone not a member now', count(*) from reactions r where not exists (select 1 from conversation_members m where m.conversation_id = r.conversation_id and m.user_id = r.user_id);
select 'reactions whose message is in another chat', count(*) from reactions r join messages g on g.id = r.message_id where g.conversation_id != r.conversation_id;
select 'media rows in another chat than their message', count(*) from message_media mm join messages g on g.id = mm.message_id where g.conversation_id != mm.conversation_id;
select 'polls rows', count(*) from polls;
select 'scheduled_messages rows', count(*) from scheduled_messages;"
nohup /opt/pocketbase/pocketbase serve --http=127.0.0.1:8098 --dir=$T/before/pb_data --migrationsDir=$T/before/pb_migrations --hooksDir=$T/h >$T/b.log 2>&1 & P1=$!
# the probe PATCHes rules, which writes auto-migration files: it gets its own copy (8097)
nohup /opt/pocketbase/pocketbase serve --http=127.0.0.1:8097 --dir=$T/probe/pb_data --migrationsDir=$T/probe/pb_migrations --hooksDir=$T/h >$T/p.log 2>&1 & P3=$!
nohup /opt/pocketbase/pocketbase serve --http=127.0.0.1:8099 --dir=$T/after/pb_data --migrationsDir=$T/after/pb_migrations --hooksDir=$T/h >$T/a.log 2>&1 & P2=$!
sleep 4
set +e
echo "##### PROBE (after copy): N11 shapes";  timeout 600 python3 $M/wave2_probe.py 8097 2>&1 | tail -15
echo "##### Q table BEFORE"; timeout 400 python3 $M/wave2_request_table.py 8098 2>&1 | tail -30
echo "##### Q table AFTER";  timeout 400 python3 $M/wave2_request_table.py 8099 2>&1 | tail -30
kill $P1 $P2 $P3; sleep 1
echo "##### after-copy migrations newer than ours (must be none)"; ls $T/after/pb_migrations | sort | tail -1
echo "##### rollback on the after copy"
yes | /opt/pocketbase/pocketbase migrate down 1 --dir=$T/after/pb_data --migrationsDir=$T/after/pb_migrations --hooksDir=$T/h 2>&1 | tail -2
sqlite3 -readonly $T/after/pb_data/data.db "$RULES" > $T/down.txt
sqlite3 -readonly $T/before/pb_data/data.db "$RULES" > $T/orig.txt
diff $T/down.txt $T/orig.txt && echo "rules after down == original (8 collections)"
echo "##### errors in logs"; grep -i "error\|panic\|exception" $T/a.log $T/b.log $T/p.log | head -10
rm -rf $T $M
