---
title: "The server's real backup is a nightly encrypted copy to Google Drive, not PocketBase's own backups folder"
author: Chaitanya
date: 2026-11-18
branch: main
cost: { minutes: 3, tokens: 25885 }
id: l-8e77735c
scope: repo
status: active
src: agent
touches:
  - docs/audits/2026-11-16-security-cloudflare-skill.md
  - test/offline/leave_rotation_test.dart
  - docs/design/pages/google-link-and-push.md
  - docs/server/hooks/fcm_token_unique.pb.js
  - docs/server/hooks/google_auth.pb.js
  - docs/server/migrations/1794830000_users_email_private.js
  - docs/server/tests/glink_check.py
  - docs/server/tests/glink_dry_run.sh
  - docs/server/tests/glink_go_live.sh
  - docs/server/tests/glink_stub.pb.js
---

## Decided
The live server is backed up by a root cron job set up by the user (2026-10-20). Every night it takes a safe SQLite copy of the database plus the hooks, migrations, nginx and systemd config, and sends them to an encrypted Google Drive folder that keeps 14 days of history. Media files go to Drive as a mirror, so a file deleted on the server is also gone from Drive by the next night. Healthchecks.io gets a ping only when every step succeeded. Checked 2026-11-18: daily copies were present, and last night's copy restored and passed an integrity check.

## Tried and ruled out
Judging backups by PocketBase's own backups folder (pb_data/backups): it is empty on purpose, and reading it led to a wrong "no scheduled backup" report. An older ubuntu-user tar job had been writing empty files since Aug 2026, when the data folder became readable only by pocketbase. It was removed on 2026-11-18 with the user's yes, and its 6.5 GB of unencrypted old copies were deleted.

## Watch out
- The `-pre` copies in /home/ubuntu/pb_backups sit on the same disk as the live data. They are rollback points for live changes, not backups.
- If the Drive token expires (happened once, 2026-10-19), the job fails and only the Healthchecks alert tells you.
- To test a restore, copy a day's folder from the encrypted Drive remote into a temp folder, gunzip it and run an integrity check. Delete the temp copy afterwards.

In the code:
- Job: `/etc/cron.d/pb-backup` runs `/usr/local/bin/pb-backup.sh` at 22:00 UTC.
- Log: `/var/log/pb-backup.log`.
- Database and config: `rclone` remote `gcrypt:daily/<date>`, a crypt remote over `gdrive:vm-backups`.
- Media: `gcrypt:storage`.
