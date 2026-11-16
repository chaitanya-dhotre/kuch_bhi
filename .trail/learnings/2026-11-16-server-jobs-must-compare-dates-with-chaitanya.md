---
title: "Server jobs must compare dates with the server's own now, because stored dates use a space where a JavaScript date string uses T"
author: Chaitanya
date: 2026-11-16
branch: main
cost: { minutes: 3, tokens: 549765 }
id: l-65025c6a
scope: repo
status: active
src: agent
touches:
  - lib/core/widgets/app_field.dart
  - lib/core/widgets/app_toast.dart
  - lib/features/auth/screens/backup_pin_screen.dart
  - lib/features/auth/screens/forgot_password_screen.dart
  - lib/features/media/screens/media_docs_screen.dart
  - lib/features/share/share_target_screen.dart
  - lib/features/starred_messages/screens/starred_messages_screen.dart
  - test/core/motion_tokens_test.dart
  - test/design/calm_rest_part4_test.dart
  - lib/core/widgets/change_motion.dart
---

## Decided
The media expiry cron now filters with `expires_at <= @now` (fixed live 2026-11-16, user go-ahead), the same fix the disappearing-messages cron got on 2026-11-05.

## Tried and ruled out
- Binding `new Date().toISOString()` as a filter parameter (the old code): PocketBase stores dates as `2026-11-16 19:31:18.000Z` and the bound value reads `2026-11-16T16:31:22.556Z`. The compare is text, and a space sorts before `T`, so every row due later the same UTC day matched and was deleted up to about 22 hours early.

## Watch out
- Any hook or cron that compares a date column with a time computed in JavaScript has this bug. Use `@now`, or format the value with a space (`.replace("T", " ")`) as the 90-day cutoff in the disappearing cron does.
- Media the old job deleted early is gone (the nightly logs show 2, 2 and 1 deletions on Nov 14–16; which were early is unknown).
- Test a date filter by inserting rows due a few hours later the same day; rows days away never show the bug.

In the code:
- live hook: /opt/pocketbase/pb_hooks/media_expiry.pb.js; repo copy docs/server/hooks/media_expiry.pb.js
- backup: /home/ubuntu/pb_backups/pb_hooks.20261116-media-expiry-pre
- dry run: a throwaway route on a database copy ran both filters with one row due in 3 h and one expired 1 h ago: old 2, new 1
