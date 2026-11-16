# membership-rules.md dry run. Run on the VM as ubuntu, files scp'd to /tmp/mt first:
#   tok.pb.js mk.pb.js user_fields_unhide.pb.js 1794790000_updated_membership_presence.js membership_request_table.py
# "before" = live copy + live key_backup_hide.pb.js; "after" = migration + new hook, NO key_backup_hide.
# Nothing live is changed: the live DB is only read (.backup / -readonly).
set -e
T=/tmp/pbtest; M=/tmp/mt; rm -rf $T; mkdir -p $T/hb $T/ha
cp $M/tok.pb.js $M/mk.pb.js $T/hb/; cp $M/tok.pb.js $M/mk.pb.js $M/user_fields_unhide.pb.js $T/ha/
sudo cp /opt/pocketbase/pb_hooks/key_backup_hide.pb.js $T/hb/
for v in before after; do
  mkdir -p $T/$v/pb_data
  sudo sqlite3 -readonly /opt/pocketbase/pb_data/data.db ".backup $T/$v/pb_data/data.db"
  sudo cp -r /opt/pocketbase/pb_migrations $T/$v/
done
sudo chown -R ubuntu $T
cp $M/1794790000_updated_membership_presence.js $T/after/pb_migrations/
/opt/pocketbase/pocketbase migrate up --dir=$T/after/pb_data --migrationsDir=$T/after/pb_migrations --hooksDir=$T/ha 2>&1 | tail -2
echo "##### hidden flags after migrate"
sqlite3 -readonly $T/after/pb_data/data.db "select json_extract(f.value,'\$.name'), json_extract(f.value,'\$.hidden') from _collections c, json_each(c.fields) f where c.name='users' and json_extract(f.value,'\$.hidden')=1"
nohup /opt/pocketbase/pocketbase serve --http=127.0.0.1:8098 --dir=$T/before/pb_data --migrationsDir=$T/before/pb_migrations --hooksDir=$T/hb >$T/b.log 2>&1 & P1=$!
nohup /opt/pocketbase/pocketbase serve --http=127.0.0.1:8099 --dir=$T/after/pb_data --migrationsDir=$T/after/pb_migrations --hooksDir=$T/ha >$T/a.log 2>&1 & P2=$!
sleep 4
set +e
echo "##### BEFORE"; timeout 200 python3 $M/membership_request_table.py 8098 2>&1 | tail -40
echo "##### AFTER";  timeout 200 python3 $M/membership_request_table.py 8099 2>&1 | tail -40
kill $P1 $P2; sleep 1
echo "##### rollback on the after copy"
yes | /opt/pocketbase/pocketbase migrate down 1 --dir=$T/after/pb_data --migrationsDir=$T/after/pb_migrations --hooksDir=$T/hb 2>&1 | tail -2
sqlite3 -readonly $T/after/pb_data/data.db "select 'hidden users fields after down', count(*) from _collections c, json_each(c.fields) f where c.name='users' and json_extract(f.value,'\$.hidden')=1 and json_extract(f.value,'\$.name') in ('current_chat','typing_in','fcm_token','private_key_encrypted','private_key_salt'); select name, md5 from (select name, createRule||'|'||updateRule as md5 from _collections where name in ('conversation_members','group_invites'))" > $T/down.txt
sqlite3 -readonly $T/before/pb_data/data.db "select 'hidden users fields before', count(*) from _collections c, json_each(c.fields) f where c.name='users' and json_extract(f.value,'\$.hidden')=1 and json_extract(f.value,'\$.name') in ('current_chat','typing_in','fcm_token','private_key_encrypted','private_key_salt'); select name, createRule||'|'||updateRule from _collections where name in ('conversation_members','group_invites')" > $T/orig.txt
head -1 $T/down.txt; head -1 $T/orig.txt; diff <(tail -n +2 $T/down.txt) <(tail -n +2 $T/orig.txt) && echo "rules after down == original"
echo "##### read-only counts (live, untouched)"
sudo sqlite3 -readonly /opt/pocketbase/pb_data/data.db "
select 'member row older than its chat', count(*) from conversation_members m join conversations c on c.id = m.conversation_id where m.created < c.created;
select 'group member, not creator, no invite, joined > 10 min after the chat', count(*) from conversation_members m join conversations c on c.id = m.conversation_id where c.type = 'group' and m.user_id != c.created_by and not exists (select 1 from group_invites i where i.conversation_id = m.conversation_id and i.invited_user_id = m.user_id) and julianday(m.created) - julianday(c.created) > 10.0/1440;
select 'admins who joined by invite', count(*) from conversation_members m join group_invites i on i.conversation_id = m.conversation_id and i.invited_user_id = m.user_id where m.role = 'admin';
select 'users still on a v1 backup blob', count(*) from users where private_key_encrypted != '' and private_key_encrypted not like 'v2:%';"
echo "##### errors in logs"; grep -i "error\|panic\|exception" $T/a.log $T/b.log | head -10
rm -rf $T $M
