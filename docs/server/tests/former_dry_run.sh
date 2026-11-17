# former-member-history.md dry run. Run on the VM as ubuntu, files scp'd to /tmp/fm first:
#   tok.pb.js mk.pb.js fm.pb.js former_member_record.pb.js 1794800000_former_members.js
#   former_request_table.py rules_request_table.py membership_request_table.py
# "before" = live copy + live user_fields_unhide; "after" = + migration + former_member_record hook.
# Nothing live is changed: the live DB is only read (.backup / -readonly).
set -e
T=/tmp/pbtest; M=/tmp/fm; rm -rf $T; mkdir -p $T/hb $T/ha
sudo cp /opt/pocketbase/pb_hooks/user_fields_unhide.pb.js $T/hb/
cp $M/tok.pb.js $M/mk.pb.js $M/fm.pb.js $T/hb/
cp $T/hb/* $T/ha/; cp $M/former_member_record.pb.js $T/ha/
for v in before after; do
  mkdir -p $T/$v/pb_data
  sudo sqlite3 -readonly /opt/pocketbase/pb_data/data.db ".backup $T/$v/pb_data/data.db"
  sudo cp -r /opt/pocketbase/pb_migrations $T/$v/
done
sudo chown -R ubuntu $T
cp $M/1794800000_former_members.js $T/after/pb_migrations/
/opt/pocketbase/pocketbase migrate up --dir=$T/after/pb_data --migrationsDir=$T/after/pb_migrations --hooksDir=$T/hb 2>&1 | tail -2
RULES="select name, listRule, viewRule from _collections where name in ('conversations','messages','message_media') order by name"
echo "##### D-5 counts (read-only, before copy)"
sqlite3 -readonly $T/before/pb_data/data.db "
select 'former pairs (own key rows, no member row)', count(*) from (select distinct k.conversation_id, k.user_id from group_keys k
  where not exists (select 1 from conversation_members m where m.conversation_id = k.conversation_id and m.user_id = k.user_id));
select 'of those, back-fillable (newer version for someone else)', count(*) from (select k.conversation_id, k.user_id, max(k.key_version) v from group_keys k
  where not exists (select 1 from conversation_members m where m.conversation_id = k.conversation_id and m.user_id = k.user_id)
  group by 1, 2) f where exists (select 1 from group_keys n where n.conversation_id = f.conversation_id and n.key_version > f.v);
select 'former pairs in DMs', count(*) from (select distinct k.conversation_id, k.user_id from group_keys k join conversations c on c.id = k.conversation_id
  where c.type != 'group' and not exists (select 1 from conversation_members m where m.conversation_id = k.conversation_id and m.user_id = k.user_id));"
nohup /opt/pocketbase/pocketbase serve --http=127.0.0.1:8098 --dir=$T/before/pb_data --migrationsDir=$T/before/pb_migrations --hooksDir=$T/hb >$T/b.log 2>&1 & P1=$!
nohup /opt/pocketbase/pocketbase serve --http=127.0.0.1:8099 --dir=$T/after/pb_data --migrationsDir=$T/after/pb_migrations --hooksDir=$T/ha >$T/a.log 2>&1 & P2=$!
sleep 4
set +e
echo "##### F table AFTER";  timeout 400 python3 $M/former_request_table.py 8099 2>&1 | tail -30
echo "##### F table BEFORE"; timeout 400 python3 $M/former_request_table.py 8098 2>&1 | tail -30
echo "##### F19 T1-T16 BEFORE"; timeout 300 python3 $M/rules_request_table.py 8098 $T/before/pb_data/data.db 2>&1 | tail -25 > $T/tb.txt; cat $T/tb.txt
echo "##### F19 T1-T16 AFTER";  timeout 300 python3 $M/rules_request_table.py 8099 $T/after/pb_data/data.db 2>&1 | tail -25 > $T/ta.txt; cat $T/ta.txt
echo "##### F19 U/V BEFORE"; timeout 300 python3 $M/membership_request_table.py 8098 2>&1 | tail -40 > $T/ub.txt; cat $T/ub.txt
echo "##### F19 U/V AFTER";  timeout 300 python3 $M/membership_request_table.py 8099 2>&1 | tail -40 > $T/ua.txt; cat $T/ua.txt
echo "##### F19 diffs (timing lines excluded)"
diff <(grep -v '^time\|^V9' $T/tb.txt) <(grep -v '^time\|^V9' $T/ta.txt) && echo "T1-T16 identical"
diff <(grep -v '^V9' $T/ub.txt) <(grep -v '^V9' $T/ua.txt) && echo "U/V identical"
kill $P1 $P2; sleep 1
echo "##### rollback on the after copy"
yes | /opt/pocketbase/pocketbase migrate down 1 --dir=$T/after/pb_data --migrationsDir=$T/after/pb_migrations --hooksDir=$T/hb 2>&1 | tail -2
sqlite3 -readonly $T/after/pb_data/data.db "$RULES; select 'former_members exists after down', count(*) from _collections where name='former_members'" > $T/down.txt
sqlite3 -readonly $T/before/pb_data/data.db "$RULES; select 'former_members exists after down', 0" > $T/orig.txt
diff $T/down.txt $T/orig.txt && echo "rules after down == original, collection gone"
echo "##### errors in logs"; grep -i "error\|panic\|exception\|former_members\]" $T/a.log $T/b.log | head -10
rm -rf $T $M
