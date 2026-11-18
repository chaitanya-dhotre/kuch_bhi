# google-link-and-push.md dry run. Run on the VM as ubuntu, files scp'd to /tmp/gl first:
#   google_auth.pb.js fcm_token_unique.pb.js glink_stub.pb.js 1794830000_users_email_private.js glink_check.py
# A copy of live data + live hooks + the new hooks, on 127.0.0.1:8099. The live DB is only read.
set -e
T=/tmp/pbtest; M=/tmp/gl; rm -rf $T; mkdir -p $T/h $T/pb_data
sudo sqlite3 -readonly /opt/pocketbase/pb_data/data.db ".backup $T/pb_data/data.db"
sudo cp -r /opt/pocketbase/pb_migrations $T/
sudo cp /opt/pocketbase/pb_hooks/*.pb.js $T/h/
sudo chown -R ubuntu $T
echo "##### live google_auth equals the repo base (diff must be empty apart from the F23/F24 lines)"
diff $T/h/google_auth.pb.js $M/google_auth.pb.js || true
cp $M/google_auth.pb.js $M/fcm_token_unique.pb.js $M/glink_stub.pb.js $T/h/
sed -i 's#https://oauth2.googleapis.com/tokeninfo#http://127.0.0.1:8099/stub-tokeninfo#' $T/h/google_auth.pb.js
grep -c "127.0.0.1:8099/stub-tokeninfo" $T/h/google_auth.pb.js | grep -qx 1 || { echo "stub swap failed"; rm -rf $T $M; exit 1; }
echo "##### F24 before: emailVisibility on = $(sqlite3 -readonly $T/pb_data/data.db 'select count(*) from users where emailVisibility=1')"
cp $M/1794830000_users_email_private.js $T/pb_migrations/
/opt/pocketbase/pocketbase migrate up --dir=$T/pb_data --migrationsDir=$T/pb_migrations --hooksDir=$T/h 2>&1 | tail -1
echo "##### F24 after migrate: emailVisibility on = $(sqlite3 -readonly $T/pb_data/data.db 'select count(*) from users where emailVisibility=1')"
nohup /opt/pocketbase/pocketbase serve --http=127.0.0.1:8099 --dir=$T/pb_data --migrationsDir=$T/pb_migrations --hooksDir=$T/h >$T/a.log 2>&1 & P=$!
sleep 4
set +e
timeout 120 python3 -I $M/glink_check.py 8099 $T/pb_data/data.db
kill $P; sleep 1
echo "##### hook log lines"; grep -i "GAuth\|fcm-unique" $T/a.log | grep -v "OK:" | head -5
echo "##### errors in log"; grep -i "error\|panic\|exception" $T/a.log | head -10
rm -rf $T $M
