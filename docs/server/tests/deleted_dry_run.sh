# delete-everyone-leftovers.md §5 dry run. Run on the VM as ubuntu, files scp'd to /tmp/del first:
#   tok.pb.js mk.pb.js delete_everyone_purge.pb.js 1794820000_updated_media_hide_deleted.js
#   1794820100_cleanup_deleted_for_everyone.js deleted_request_table.py
# "before" = live copy + live hooks; "after" = live copy + both migrations + the new hook. The cron
# and push hooks are left out. Nothing live is changed: the live DB and storage are only read.
set -e
T=/tmp/pbtest; M=/tmp/del; L=/opt/pocketbase/pb_hooks; rm -rf $T; mkdir -p $T/hb $T/ha
sudo cp $L/disappearing_stamp.pb.js $L/former_member_record.pb.js $L/user_fields_unhide.pb.js $T/hb/
for v in before after; do
  mkdir -p $T/$v/pb_data
  sudo sqlite3 -readonly /opt/pocketbase/pb_data/data.db ".backup $T/$v/pb_data/data.db"
  sudo cp -r /opt/pocketbase/pb_migrations $T/$v/
done
DB=$T/after/pb_data/data.db
MMC=$(sudo sqlite3 -readonly $DB "select id from _collections where name='message_media'")
IDS=$(sudo sqlite3 -readonly $DB "select mm.id from message_media mm join messages m on m.id = mm.message_id where m.is_deleted_for_everyone = 1")
# the flagged messages' media folders go into the after copy, so the cleanup's file removal shows
sudo mkdir -p $T/after/pb_data/storage/$MMC
for i in $IDS; do sudo cp -r /opt/pocketbase/pb_data/storage/$MMC/$i $T/after/pb_data/storage/$MMC/; done
sudo chown -R ubuntu $T
cp $M/tok.pb.js $M/mk.pb.js $T/hb/; cp $T/hb/* $T/ha/; cp $M/delete_everyone_purge.pb.js $T/ha/
folders() { n=0; for i in $IDS; do [ -d $T/after/pb_data/storage/$MMC/$i ] && n=$((n+1)); done; echo "flagged media folders on disk: $n"; }
COUNTS="
select 'flagged messages', count(*) from messages where is_deleted_for_everyone = 1;
select 'flagged with body or iv', count(*) from messages where is_deleted_for_everyone = 1 and (encrypted_body != '' or iv != '');
select 'flagged with a preview', count(*) from messages where is_deleted_for_everyone = 1 and reply_preview != '';
select 'media rows of flagged', count(*) from message_media mm join messages m on m.id = mm.message_id where m.is_deleted_for_everyone = 1;
select 'previews non-empty', count(*) from messages where reply_preview != '';
select 'previews quoting flagged', count(*) from messages r where r.reply_preview != '' and r.reply_to_id in (select id from messages where is_deleted_for_everyone = 1);
select 'unflagged with a body', count(*) from messages where is_deleted_for_everyone = 0 and encrypted_body != '';
select 'messages total', count(*) from messages;
select 'media total', count(*) from message_media;"
echo "##### counts BEFORE (copy of live)"; sqlite3 -readonly $DB "$COUNTS"; folders
echo "##### migrate up (after copy)"
cp $M/1794820000_updated_media_hide_deleted.js $M/1794820100_cleanup_deleted_for_everyone.js $T/after/pb_migrations/
/opt/pocketbase/pocketbase migrate up --dir=$T/after/pb_data --migrationsDir=$T/after/pb_migrations --hooksDir=$T/hb 2>&1 | tail -4
sleep 1
APPLIED=$(sqlite3 -readonly $DB "select count(*) from _migrations where file like '17948201%' or file like '17948200%'")
echo "##### our migrations applied: $APPLIED"; [ "$APPLIED" = 2 ] || { rm -rf $T $M; exit 1; }
echo "##### counts AFTER"; sqlite3 -readonly $DB "$COUNTS"; folders
echo "##### message_media rules after"; sqlite3 -readonly $DB "select listRule = viewRule, substr(listRule, -48), createRule from _collections where name = 'message_media'"
REAL=$(sqlite3 -readonly $DB "select cm.user_id from conversation_members cm join message_media mm on mm.conversation_id = cm.conversation_id group by cm.user_id order by count(*) desc limit 1")
echo "##### the real member with most media: chats' flagged media rows on the before copy"
sqlite3 -readonly $T/before/pb_data/data.db "select count(*) from message_media mm join messages m on m.id = mm.message_id join conversation_members cm on cm.conversation_id = mm.conversation_id and cm.user_id = '$REAL' where m.is_deleted_for_everyone = 1 and (m.expires_at = '' or m.expires_at > strftime('%Y-%m-%d %H:%M:%fZ','now'))"
nohup /opt/pocketbase/pocketbase serve --http=127.0.0.1:8098 --dir=$T/before/pb_data --migrationsDir=$T/before/pb_migrations --hooksDir=$T/hb >$T/b.log 2>&1 & P1=$!
nohup /opt/pocketbase/pocketbase serve --http=127.0.0.1:8099 --dir=$T/after/pb_data --migrationsDir=$T/after/pb_migrations --hooksDir=$T/ha >$T/a.log 2>&1 & P2=$!
sleep 4
set +e
echo "##### D table BEFORE (live rules, no hook)"; timeout 300 python3 $M/deleted_request_table.py 8098 $REAL 2>&1 | tail -20
echo "##### D table AFTER (new rules + hook)";    timeout 300 python3 $M/deleted_request_table.py 8099 $REAL 2>&1 | tail -20
kill $P1 $P2; sleep 1
echo "##### rollback on the after copy (down 2: cleanup no-op, then rules)"
yes | /opt/pocketbase/pocketbase migrate down 2 --dir=$T/after/pb_data --migrationsDir=$T/after/pb_migrations --hooksDir=$T/hb 2>&1 | tail -3
RULES="select listRule, viewRule, createRule, updateRule, deleteRule from _collections where name = 'message_media'"
sqlite3 -readonly $DB "$RULES" > $T/down.txt; sqlite3 -readonly $T/before/pb_data/data.db "$RULES" > $T/orig.txt
diff $T/down.txt $T/orig.txt && echo "message_media rules after down == original"
sqlite3 -readonly $DB "select 'our migrations left in _migrations', count(*) from _migrations where file like '179482%'"
echo "##### errors in logs"; grep -i "error\|panic\|exception\|purge failed" $T/a.log $T/b.log | head -10
rm -rf $T $M
