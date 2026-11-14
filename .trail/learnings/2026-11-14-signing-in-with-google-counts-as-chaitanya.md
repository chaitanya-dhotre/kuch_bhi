---
title: "Signing in with Google counts as a short app switch, so on a fresh install the quick resume catch-up downloads every chat next to the restore"
author: Chaitanya
date: 2026-11-14
branch: main
cost: { minutes: 8, tokens: 141479 }
id: l-5138bf48
scope: repo
status: active
src: agent
touches:
  - docs/design/pages/restore-resume-overlap.md
  - lib/infrastructure/repositories/message_repository_impl.dart
---

## Decided
Found 2026-11-14 (restore-resume-overlap spec, user PASS all defaults, build pending). The Google account picker takes the app to the background, so coming back is a resume under 60 s: the light path. The light path picks its chats from the newest stored message; a fresh install has none, so it falls back to every membership and backfills all chats 3 at a time, right next to the restore's own download (Redmi chats 1-3 took 5-7 s instead of ~2 s). App switches on the recovery-key screen (no device key pair yet) start conversation passes that the restore's own pass then waits behind (M52 ~3 s).
Fix chosen: while the history sync runs, or while there is no device key pair, a resume only reconnects SSE and does local work (retry queued sends, join emits, preview prewarm); a backfill already running stops between chunks once the sync starts; chats the sync had already finished before a deferred resume get one refetch after the sync.

## Tried and ruled out
Running the light-path delta query after the sync instead of tracking finished chats: during a sync rows land out of time order, so the newest-stored-message watermark can sit above a message missed in an earlier chat, and that message is skipped.

## Watch out
Never skip the SSE reconnect on resume, even during the restore: Android drops the socket in the background and SSE does not replay. After Finish later the user is on Home while the sync still runs, so retrying queued sends must stay in the deferred resume.

In the code: `_resyncRun`, `_deltaBackfillTargets` (watermark null -> all memberships), `_backfillTargets`, `_historySyncRunning` in lib/infrastructure/repositories/message_repository_impl.dart; app.dart resume hook; spec docs/design/pages/restore-resume-overlap.md.
