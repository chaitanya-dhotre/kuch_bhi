---
title: "Leaving the restore screen before the download ends must re-check the key status first, or the router sends you straight back"
author: Chaitanya
date: 2026-11-14
branch: main
cost: { minutes: 21, tokens: 122100 }
id: l-365e4ade
scope: repo
status: active
src: agent
touches:
  - docs/design/pages/group-key-restore-work-log.md
  - docs/design/pages/group-key-restore.md
  - docs/design/pages/history-sync-work-log.md
  - docs/design/pages/history-sync.md
  - docs/design/pages/restore-rev2-work-log.md
  - docs/design/pages/restore-rev2.md
  - lib/domain/repositories/message_repository.dart
  - lib/features/auth/screens/backup_pin_screen.dart
  - lib/infrastructure/repositories/message_repository_impl.dart
  - lib/services/encryption_service.dart
---

## Decided
Finish later (restore rev 2, device round 1, 2026-11-14) went Home and was redirected back to the restore screen on every tap. The router's key-sync gate still held "needs restore" from before the key came back, and the restore screen only re-checks it when the download ends. Finish later now invalidates the key-sync check first, then goes Home: the key is on the phone, so the check answers key ok (the splash shows while it loads), and the download keeps running without the screen.

## Watch out
Any new way off the restore screen before the sync finishes (a skip, a back gesture, a timeout) needs the same re-check, or it bounces.
Widget tests with a bare GoRouter never see this: the bug only shows with the gate's redirect. The restore overlay test now has a redirect that applies the gate's rule (a settled needs-restore sends /home back) plus a key-sync override (needs restore, then key ok); it fails without the fix.

In the code: lib/features/auth/screens/backup_pin_screen.dart `onFinishLater` (`ref.invalidate(encryptionSyncProvider)` then `context.go(AppRoutes.home)`); router rule in lib/core/router/app_router.dart `SyncRouteGate.redirect`; test `rev2 gate 5` with `gateHome: true` in test/auth/restore_overlay_test.dart. Device evidence: Redmi log 11:11:05–11:11:19, `location: /home` → `/backup-pin/restore` about 20 times.
