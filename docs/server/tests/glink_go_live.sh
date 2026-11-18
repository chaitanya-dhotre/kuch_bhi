# google-link-and-push.md go-live. Run on the VM as ubuntu, files scp'd to /tmp/gl first:
#   google_auth.pb.js fcm_token_unique.pb.js 1794830000_users_email_private.js
set -e
P=/opt/pocketbase; BK=/home/ubuntu/pb_backups; S=20261118-google-link-pre
sudo sqlite3 -readonly $P/pb_data/data.db ".backup $BK/data.db.$S"
sudo cp -a $P/pb_hooks $BK/pb_hooks.$S
echo "##### backups"; ls -la $BK | grep $S
sudo install -o pocketbase -g pocketbase -m 644 /tmp/gl/google_auth.pb.js /tmp/gl/fcm_token_unique.pb.js $P/pb_hooks/
sudo install -o pocketbase -g pocketbase -m 644 /tmp/gl/1794830000_users_email_private.js $P/pb_migrations/
sudo rm $P/pb_hooks/test_b64.js   # D-5: dead file (not .pb.js); a copy stays in the hooks backup
sudo systemctl restart pocketbase; sleep 4
echo "##### service: $(systemctl is-active pocketbase)"
echo "##### migration applied: $(sudo sqlite3 -readonly $P/pb_data/data.db "select count(*) from _migrations where file='1794830000_users_email_private.js'")"
echo "##### emailVisibility on: $(sudo sqlite3 -readonly $P/pb_data/data.db 'select count(*) from users where emailVisibility=1')"
echo "##### hooks now"; ls $P/pb_hooks
echo "##### errors since restart"; sudo journalctl -u pocketbase --since "-1 min" --no-pager | grep -i "error\|panic\|exception" | head -5
rm -rf /tmp/gl
# Rollback: sudo cp -a $BK/pb_hooks.$S/. $P/pb_hooks/ && sudo rm $P/pb_hooks/fcm_token_unique.pb.js && sudo systemctl restart pocketbase
# (the emailVisibility change has no down step; flip the one row back by hand if ever needed)
