# Restore and resume overlap: work log

Status: **device PASS 2026-11-14** (logs + your word on items 3 and 4), not committed.

Spec: `docs/design/pages/restore-resume-overlap.md` (PASS 2026-11-14, all defaults:
D1 A, D2 same as D1 A, D3 stop at the next chunk, D4 A). Built 2026-11-14 by Claude in
the spec session. Not committed.

| | |
|---|---|
| Files | `lib/infrastructure/repositories/message_repository_impl.dart`, `lib/services/encryption_service.dart`, `test/offline/restore_rev2_test.dart` (new group "resume overlap", gates 1–7), `test/offline/short_resume_test.dart` (fixture: phone holds its key pair) |
| Gates | baseline `flutter test` **1296 pass, 2 fail** (taken first; the 2 are `send_fetch_char_test` "send persists optimistic pending row" and `server_created_watermark_test` C1a, from other sessions' uncommitted work in this checkout, not this build) → after: see "Suite after" below · 7 spec gates green · `flutter analyze` 0 errors · `trail check` no conflicts |
| Mutation checks | removing each guard fails its gate: sync guard (gates 1, 4), no-key guard (2), O2 stop (3), owed add (4), page-1 mark (4), sign-out clear (7) |

## What was built

- **O1** `_resyncRun`: after `_reconnect()`, `_myId()` and the unchanged preview prewarm, a
  resume checks `_historySyncRunning`, then `encryption.hasDeviceKeyPair()`. Either one →
  `[Msg] resync deferred — reason=sync|nokey path=light|full`, then only
  `_resumeLocalWork` (retry queued sends, join-emit retries) and return. No conversations
  pass, delta query, backfill, user-wide passes, prefetch or key-gap reconcile.
- `EncryptionService.hasDeviceKeyPair()`: `getPrivateKey() != null`, one secure-storage read.
- `_resumeLocalWork(myId)`: the two steps both paths already ended with, now shared by the
  light path, the full path and the two early returns.
- **O2** `_backfillTargets` returns `bool`: before each chunk of 3, if the sync is running,
  logs `[Msg] resync backfill stopped — history sync, left=<n>` and returns false; both
  resume paths then run only `_resumeLocalWork`.
- **O3** `syncAllHistory` clears `_historyFetched` at start and adds a chat once its key,
  receipts and page 1 are in. A `sync`-deferred resume adds that set to `_owedChats`. In the
  sync's `finally`, a non-empty owed set is taken, cleared, logged
  (`[Sync] owed catch-up chats=<n>`) and run through `_backfillTargets` unawaited. The
  identity-change listener clears `_owedChats` with the other per-user state.

### Deviations from the spec

- O3 step 1 says "chats it has finished". Built as "chats whose page 1 has been fetched":
  that also covers the chat being downloaded when the app went to the background (its page
  1 may predate a message sent meanwhile). A chat retried after a failure may get one
  extra refetch; it is idempotent.
- Gate 1 asks for "SSE re-subscribe +1" and "a queued text is retried". Not asserted: the
  harness's realtime connect never completes, so a second subscribe never reaches the
  wire, and the outbox is empty on a fresh install. Both calls are unchanged code that
  runs before / instead of the gate: `_reconnect()` stays the first line of `_resyncRun`,
  and every deferred return goes through `_resumeLocalWork`.
- `short_resume_test.dart`: its harness had no device key pair, so after O1 every resume
  there was deferred as `nokey`. Its 9 tests describe a signed-in phone, so they now build
  through `keyedHarness`, which creates the key pair the way `restore_rev2_test`'s `_fresh`
  does. No assertion changed.

## Suite after

Full `flutter test`: **1304 pass, 1 fail**, i.e. 1296 + 7 new + `server_created_watermark` passing
this time. The 1 failure is `send_fetch_char_test` "send persists optimistic pending row",
already failing in the baseline. Run alone with this build, both baseline failures pass
(5/5), so they are full-suite load flakes, not this change.

## Device run 1 (2026-11-14, build installed 13:36, logs read by Claude)

"Sync time" = `Full history sync starting` to `[Sync] total`. Logs:
the session scratchpad `m52.log`, `redmi.log` (not kept in the repo).

| # | Phone, run | From the logs | Verdict |
|---|---|---|---|
| 1 | Redmi 13:40 and 13:44 (two clean restores) | After sign-in only `resync deferred — reason=nokey` (1 and 2 lines); **no** `resync light — delta convs=` line; **no** `_fetchAndCacheMessages` between start and `[Sync] total`. During the 13:41 sync the only other lines are its own 15 group walks (one per group) and 19 DM key derivations. Chat 1: **1.95 s / 1.83 s** (run 1: 5–7 s for chats 1–3). Chats 2–3 (22 and 67 msgs) 3.4–3.7 s. Sync time **54.4 s** (work 52.6 s) and **60.1 s** (work 58.3 s), 18 chats, 567 msgs | **PASS on the overlap**: nothing runs next to the download any more. The total is **not** under run 1's 48.8 s: small chats take ~1.7–2.1 s each today with nothing beside them, so the difference is in the chats themselves (network or server that hour), not resume work |
| 2 | M52 13:42 and 13:44 | 3 and 2 `reason=nokey` lines on the key screen. The sync's `[Conv] sync`: `queued=0` (13:42); `queued=1` (13:44), behind a pass that **no resume started** (the background conversations pass after sign-in: its group-key prefetch logged `no device key pair (restore pending)` per group at 13:44:44). Chat 1 started **1.7 s / 2.6 s** after the start and finished 4.0 s / 5.4 s (run 1: started ~5.5 s, finished 8.0 s). 13:44 sync time **53.2 s** (work 50.6 s; run 1: 56.9 s and 62.7 s), 29 chats, 707 msgs | **PASS** (chat 1 under 5 s). The `queued=1` is the spec's "SSE / background passes still fold" item, not a resume |
| 3 | Redmi 13:47 | 5 × `resync deferred — reason=sync` during the download; after `[Sync] total` (13:50:07.264): `[Sync] owed catch-up chats=15`, then exactly 15 `_fetchAndCacheMessages`, 3 at a time, done by 13:50:13.7 (about 6.5 s, after Home) | **PASS** (you confirmed: the message showed on Home before the chat was opened) |
| 4 | Redmi 13:48 | `[Sync] offline: 13 chats left` 13:48:37; on Home a chat was opened 13:48:58 (`TAPDOWN`); connection back 13:49:17 (`[Outbox] Connectivity restored`); download carried on to `left=0`, `waitedMs=40250`. The `_fetchAndCacheMessages` lines during it are that open chat's own fetch and its 5 s poll while SSE was down (chat-open fetch is never gated, by design), not a resume | **PASS** (you confirmed: the message sent from Home went out once) |
| 5 | M52 after Home | shade-style returns 13:45:41, 13:47:00, 13:49:49: `path=light`, `delta convs=0`, no `deferred` line | PASS for the light half. **Not in the logs**: a return after more than a minute (`path=full`) on either phone |

Seen in passing (not changed): on the key screen the background conversations pass still runs its
group-key prefetch, which fails fast per group with `no device key pair (restore pending)` (G4).
No requests are wasted beyond the prefetch's own key-row read, if any.

## Device check list (you do every sign-in)

Test account pair from two-device testing, never your real chats. Release build,
`--split-per-abi` arm64. Log:
`adb logcat | grep -E "\[Sync\]|\[Conv\] sync|resync|group keys|_fetchAndCacheMessages"`.

1. Redmi on **mobile data**, clear app data, sign in **with Google**, restore. After
   sign-in: `resync deferred — reason=nokey`, and **no** `resync light — delta convs=`
   line. Between `Full history sync starting` and `[Sync] total`: **no**
   `_fetchAndCacheMessages` lines. Chats 1–3 about 2 s each; sync time under run 1's
   48.8 s.
2. M52 on **mobile data**, clear app data, sign in, switch to another app and back twice
   on the recovery-key screen, then Restore: one `reason=nokey` line per switch; the
   sync's `[Conv] sync` line has `queued=0`; chat 1 starts **under 5 s** after the start.
3. Redmi, clear data, restore; around chat 5 switch away for about 20 s while the M52
   sends a message into one of the first two chats: `reason=sync` on return; after
   `[Sync] total`, `[Sync] owed catch-up chats=` with a small number; on Home that chat
   shows the message and an unread count **before** you open it.
4. Redmi, clear data, restore; turn the hotspot off at about chat 5, tap Finish later,
   switch apps and back on Home, then send a message from Home and turn the hotspot on:
   the message goes out once; the download carries on and ends; no
   `_fetchAndCacheMessages` lines during it (until the owed catch-up after `[Sync] total`).
5. After any of the above, on Home: pull the notification shade and let go:
   `path=light` with `delta convs=0`; leave for over a minute and come back: `path=full`
   as before.
