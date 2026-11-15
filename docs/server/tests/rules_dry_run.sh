set -e
T=/tmp/pbtest; rm -rf $T; mkdir -p $T/hooks
cp /tmp/rt/tok.pb.js $T/hooks/
for v in before after; do
  mkdir -p $T/$v/pb_data
  sudo sqlite3 -readonly /opt/pocketbase/pb_data/data.db ".backup $T/$v/pb_data/data.db"
  sudo cp -r /opt/pocketbase/pb_migrations $T/$v/
done
sudo chown -R ubuntu $T
cp /tmp/rt/1794700100_updated_rules_scope.js $T/after/pb_migrations/
/opt/pocketbase/pocketbase migrate up --dir=$T/after/pb_data --migrationsDir=$T/after/pb_migrations --hooksDir=$T/hooks 2>&1 | tail -2
nohup /opt/pocketbase/pocketbase serve --http=127.0.0.1:8098 --dir=$T/before/pb_data --migrationsDir=$T/before/pb_migrations --hooksDir=$T/hooks >$T/b.log 2>&1 & P1=$!
nohup /opt/pocketbase/pocketbase serve --http=127.0.0.1:8099 --dir=$T/after/pb_data --migrationsDir=$T/after/pb_migrations --hooksDir=$T/hooks >$T/a.log 2>&1 & P2=$!
sleep 4
set +e
echo "##### BEFORE"; timeout 150 python3 /tmp/rt/t.py 8098 $T/before/pb_data/data.db 2>&1 | tail -30
echo "##### AFTER";  timeout 150 python3 /tmp/rt/t.py 8099 $T/after/pb_data/data.db 2>&1 | tail -30
kill $P1 $P2; sleep 1
echo "##### S-4 counts (live copy, untouched)"
sudo sqlite3 -readonly /opt/pocketbase/pb_data/data.db "select 'receipts total', count(*) from message_receipts; select 'receipts whose recipient is not a member of that chat', count(*) from message_receipts r where not exists(select 1 from conversation_members m where m.conversation_id=r.conversation_id and m.user_id=r.recipient_id); select 'receipts where recipient is the sender', count(*) from message_receipts r join messages x on x.id=r.message_id where x.sender_id=r.recipient_id; select 'stars by non-members', count(*) from starred_messages s where not exists(select 1 from conversation_members m where m.conversation_id=s.conversation_id and m.user_id=s.user_id); select 'delete-for-me by non-members', count(*) from deleted_messages_for_me s where not exists(select 1 from conversation_members m where m.conversation_id=s.conversation_id and m.user_id=s.user_id); select 'media rows whose chat differs from the message chat', count(*) from message_media a join messages x on x.id=a.message_id where x.conversation_id!=a.conversation_id; select 'polls', count(*) from polls;"
grep -i "error\|panic" $T/a.log | head -5
rm -rf $T /tmp/rt
