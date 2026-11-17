# Rule-shape timing on one copy (after migration + hook). VM, files in /tmp/fm. Live DB only read.
set -e
T=/tmp/pbtest; M=/tmp/fm; rm -rf $T; mkdir -p $T/h $T/pb_data
sudo cp /opt/pocketbase/pb_hooks/user_fields_unhide.pb.js $T/h/
cp $M/tok.pb.js $M/mk.pb.js $M/fm.pb.js $M/former_member_record.pb.js $T/h/
sudo sqlite3 -readonly /opt/pocketbase/pb_data/data.db ".backup $T/pb_data/data.db"
sudo cp -r /opt/pocketbase/pb_migrations $T/; sudo chown -R ubuntu $T
cp $M/1794800000_former_members.js $T/pb_migrations/
/opt/pocketbase/pocketbase migrate up --dir=$T/pb_data --migrationsDir=$T/pb_migrations --hooksDir=$T/h 2>&1 | tail -1
nohup /opt/pocketbase/pocketbase serve --http=127.0.0.1:8099 --dir=$T/pb_data --migrationsDir=$T/pb_migrations --hooksDir=$T/h >$T/a.log 2>&1 & P=$!
sleep 4; set +e
timeout 900 python3 $M/former_rule_timing.py 8099 2>&1 | tail -20
kill $P; sleep 1; grep -i "error\|panic" $T/a.log | head -5
rm -rf $T $M
