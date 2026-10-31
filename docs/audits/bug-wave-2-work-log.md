# Bug wave 2: work log (2026-10-31)

The rest of `docs/audits/2026-10-30-bugs.md` in scope: §4, §6, §5 (top-10 row 8), §7.1, §3.1.
Claude did this end to end (Omnirush down; races, lifecycle and the pipeline timeout are Claude work).
Status: **user device PASS 2026-10-31 (rounds 1–2 fixes + store change included); committed.**

## Confirmed in code first

| § | Today | Root cause / what changed since the audit |
|---|---|---|
| 4.1 voice | confirmed | `_loadAndPlay` re-read the cached `null` on every tap. |
| 4.2 doc bubble | confirmed | error/`null` drew `_errorTile()` with no tap; toast was `Could not open file: $e`. |
| 4.3 image/video | confirmed | error/`null` placeholders had no gesture, so the viewer (the only self-healing path) was unreachable. |
| 4.4 Docs list | confirmed | `_openDoc` re-read the cached `null`; same `$e` toast. |
| 4.5 link previews | confirmed | plain family, `fetch` returns `null` on any failure, cached for good. |
| 4.6 undecryptable count | **skipped** | needs a local Drift failure; a reconnect does not help it. Left as is. |
| 5.1 / 5.2 / 5.4 | confirmed | four Media & Docs tabs + Starred `Text('Error: $e')`, two `Could not open file: $e` SnackBars. `message_input.dart` sites were already fixed in wave 1. |
| 5.3 backup screen | **gone** | the key-backup rewrite (`335b5d5`) uses `backupErrorCopy`; no raw text left. |
| 3.1 backup screen | **partly still true** | the `restorePrivateKey` paths are now guarded, but `_restoreHistory`'s `onProgress` called `setState` with no `mounted` check, and the `ref.invalidate(encryptionSyncProvider)` after the 1–3 min sync used a dead `ref` ("Cannot use ref after the widget was disposed", found by the new test). |
| 6.1 media download | confirmed | `http.get` with no bound; the record lookup (`getFirstListItem`) before it was unbounded too. |
| 6.2 Media & Docs page | confirmed | `getList` with no bound. |
| 6.3 history load-more | **already fixed** | wave 1 bounded `loadMoreMessages`. |
| 6.4 open chat from Home | confirmed | `_openChat` awaited `getOrCreateDirectConversation` (→ `_syncConversations`) with no bound and no busy state; a second tap fired a second sync. |
| 6.5 sign-in tail | partly | the FCM `users.update` was unbounded. The `getOne` / `updatePublicKey` calls sit in `_initEncryptionKeys` (key code, frozen), so they are left. |
| 6.6 starred fetch | confirmed | `getList` unbounded; its catch already falls back to local stars. |
| 7.1 friend code | confirmed | `copyWith(clearError: true, searchError: …)`: the flag wins. |

## Fix

- **One shared reconnect hook** (`connectivity_signal.dart` `invalidateOnReconnect(ref)`): a plain family that resolved to nothing re-runs on the next offline → online flip. Used by `mediaFileProvider` (only when the result is `null`) and `linkPreviewServiceProvider` (same). The media store already drains queued blobs on reconnect; this makes the cached `null` notice.
- **`MediaRetry`** (`lib/features/chat/widgets/media_retry.dart`): the empty-load placeholder for photo, video and document bubbles. Online: icon + "Tap to retry", tap invalidates `mediaFileProvider` for that ref. Offline: the icon dims once (.38) and the caption is `kOfflineActionHint`; the tap does nothing (reconnect re-runs it). One Semantics node: "Photo didn't load. Tap to retry", button, enabled = online. A decode error (`Image.file` errorBuilder) keeps the plain broken icon: a retry would not help there.
- **Voice bubble**: `_loadAndPlay` drops a cached failure/`null` before reading. With an error and offline, the button dims (.38), is disabled, and the duration line shows the hint.
- **Media & Docs**: the four tabs' errors are `_LoadFailed`: "Couldn't load this chat's media." + Retry (invalidates that tab's `mediaPageProvider`); offline the Retry dims with the hint. `_openDoc` drops a cached failure before reading; its toast is `showToast(…, "Couldn't open the file. Try again.", error: true)`. Same toast copy in the doc bubble.
- **Starred**: R7 `EmptyState` "Couldn't load starred messages." + Retry. No mascot: it overflowed at 200% text on 360dp.
- **Timeouts, 8s, on the network call only**:
  - `media_blob_store.dart` (pipeline, frozen apart from this): the download is now `send(...).timeout(8s)` for the headers plus `stream.timeout(8s)` on the body. **This is a stall bound, not a total bound**, on purpose: files reach 100 MB (`maxFileSizeMb`), and a flat 8s on `get` would turn every large video on a slow link into a permanent "unavailable". The record lookup gets the same `.timeout(8s)`. Both throw into the existing catch, so a stall ends `queued` (auto-resumed on reconnect), never `failed`. Function-level diff: only the download statement and `_lookupRecord`'s call changed; decrypt, verify, key and state writes are untouched.
  - `media_gallery_service.dart`: `getList(...).timeout(8s)` → the tab's error state.
  - `getStarredMessages`: `getList(...).timeout(8s)` → the existing local-stars fallback.
  - `auth_repository_impl.dart` `_saveSession`: the FCM `users.update` gets `.timeout(kAuthNetworkTimeout)` inside its existing catch.
  - Home `_openChat`: `.timeout(8s)` on the awaited repository call. This bounds the **wait**, not the sync: Dart's `timeout` does not cancel, so `_syncConversations` (which touches membership and key-rotation scheduling) finishes in the background and lands in Drift, and the next tap finds the chat locally. Bounding the `getList`s inside `_syncConversations` instead would have changed resync and the restore history sync too.
- **Home busy state**: the tapped friend's subtitle reads "Opening chat…" and the tile ignores taps; a second tap anywhere is ignored until the open ends.
- **Backup screen (§3.1)**: `onProgress` returns early when unmounted; `_restoreHistory` takes `ProviderScope.containerOf(context)` up front and invalidates `encryptionSyncProvider` through it, so the router's re-check still happens after the screen is gone.
- **Friend code (§7.1)**: `clearError: true` dropped from the short-code call.

## Tests (+27, RED then GREEN)

RED was run in an isolated `git archive HEAD` copy with only the new tests (and the new helper) copied in, so the shared folder was never swapped.

| Test | RED at HEAD |
|---|---|
| `test/media/media_retry_test.dart` photo / video / document bubble: "Tap to retry", getSemantics label + button + enabled, tap re-fetches (×3, 360dp 200%) | no "Tap to retry" |
| same: offline photo: one .38 dim, hint, tap does nothing | no hint |
| same: a blob the store marked failed shows "No longer available", not a button; tap does nothing (review SHOULD 1) | no such state |
| same: voice: the tap after a failure re-fetches; offline dims, disabled semantics, hint | fetched 1, expected 2 |
| same: Media & Docs failed tab: plain copy, no `Exception`/`Error:`, Retry reloads (200%) | `Error: …` shown |
| same: offline tab Retry dims with the hint | no hint |
| same: Docs list: empty doc → plain toast; the next tap re-fetches | `$e` toast, 1 fetch |
| same: `invalidateOnReconnect` re-runs only on offline → online | compile-RED (new helper) |
| same: link preview: a `null` is re-read after reconnect | no reload |
| `test/offline/media_stall_test.dart`: header stall, mid-body stall and record-lookup stall each end `queued` in < 12s (real store, MockClient) | see below |
| same: Media & Docs page throws `TimeoutException`; starred falls back to the local star in < 12s | see below |
| `test/home/open_chat_busy_test.dart`: "Opening chat…", two taps → one call, toast after 8s (360dp 200%) | see below |
| `test/home/friend_code_error_test.dart`: 4-char code → the message | see below |
| `test/auth/restore_overlay_test.dart` (one test appended inside `main()`): progress + completion after the screen is gone throw nothing | see below |
| `test/chat/starred_error_test.dart`: plain copy, Retry reloads (360dp 200%) | see below |
| `test/grep_gates_test.dart` "bug wave 2" (inside `main()`): no `Text(`/`SnackBar(`/`showToast(`/`errorText:` interpolating `$e`/`$err`/`$error`/`.toString()` anywhere in `lib/` (debugPrint lines dropped); `mediaFileProvider` wires the reconnect hook; the FCM write is bounded | see below |

## Gates

- `flutter test`: **738/738** (baseline 711 + 27). No existing test changed; one test appended inside `main()` of `restore_overlay_test.dart`, one gate inside `main()` of `grep_gates_test.dart`.
- `flutter analyze`: 0 errors; nothing new on changed lines (the one info in `media_blob_store.dart` is the old `baseUrl` deprecation on an untouched line).
- `git diff --check`: clean. `trail check`: no conflicts (20 "worth a look", all on doc files).
- Frozen code: `media_blob_store.dart` changes only the download statement and `_lookupRecord`'s call (timeouts). No change to decrypt, keys, upload or `_initEncryptionKeys`.
- Known, not this change: Home already overflows at 200% text on 360dp before any tap (tracked apart); the open-chat test drains that one exception before tapping.
- Learning saved: `.trail/learnings/2026-10-30-a-media-download-gives-up-after-chaitanya.md` (commit with the change).

## Independent review (fresh-context agent, 2026-10-31)

**PASS-with-SHOULDs**, no BLOCK. It confirmed: the blob-store diff is only the two timeouts; a stall ends `queued` and leaves no `.part` file (the body is buffered before the write); `Response.bytes` loses nothing used later; all callers reach `_restoreHistory` while mounted; `searchByCode` was the only clear-flag conflict; `invalidateOnReconnect` cannot loop.
- SHOULD 1, a terminal (`failed`) blob was offered "Tap to retry", and every viewed ref re-ran on each reconnect (2 PB lookups each for a record-404): **fixed**. `mediaFileProvider` hooks reconnect only when the row is not `failed`; `MediaRetry` reads `mediaBlobStatusProvider` and shows "No longer available" (not a button, no dim) for expired / dead link / can't decrypt; its tap also invalidates the status. A record that never landed stays `queued` (the store's own choice), so it keeps its retry. + test.
- SHOULD 2, a header stall left the late socket open (`timeout` does not cancel `send`): **fixed**. The download is an `http.AbortableRequest`; both stall timeouts complete its abort trigger before throwing. Still only the network statement.
- NIT 1, a tap during an in-flight reload restarted it: **fixed** (`!cached.isLoading` in the voice bubble and `_openDoc`).
- NIT 3, a page with no `<title>` was re-fetched from the third-party site on every reconnect: **fixed**. `fetch` rethrows `DioException`; only that transport failure hooks reconnect; a no-title `null` is final.
- NIT 6, gate names: **widened** to `e|e2|ex|err|error|exception`. The `[^;]` window still stops at an inline closure's `;`; nothing like that exists in `lib/` today.
- Left as they are: NIT 2 (the viewer can invalidate during an old body's 45s wait, so one extra reload on the next flip; harmless, Riverpod 2.6 has no `ref.mounted`), NIT 4 (Home keeps its SnackBar: the dead-code audit owns toast/SnackBar sites; after the 8s bound a re-tap can start a second sync, an existing pattern), NIT 5 (Starred Retry works offline from local stars, so no dim).
- Also found by the §3.1 test, beyond the audit: the dead `ref` after the restore sync (see Fix). The trail learning about the stall bound is saved (see Gates).

## Device round 1 (user, 2026-10-31): expired media

**Finding:** 3-month-old photos and documents in the Avium chat showed an endless shimmer, then (after the 45s wait) "Tap to retry" that could never work. Everything else passed.
**Cause (read from the Samsung's local DB, no server access):** every stuck item was `queued`, none `failed`. The server purges expired media *records*, and a purged record answers 404, which the store files as "not landed yet" (queued), the same as the upload race. So the review's SHOULD 1 fix (terminal = `failed`) never applied to them. All stuck rows were 21 July – 1 Aug (photo, document ×3, voice); one photo from 25 Sept (36 days) is also queued.
**Fix:** `isPastRetention(type, createdAt)` in `media_utils.dart`: older than the longest retention for that type at any quality (photo 60, video 30, voice 60, document 60 days) + 1 day of slack means the server copy is purged for sure. The four bubbles check it first and show the existing expired placeholder (timer icon) without watching `mediaFileProvider`, so there is no download, no 45s wait and no retry. The store stays frozen.
**Limit:** a photo past 30 days but under 60 may be an expired High-quality one; the receiver can't know the quality, so it keeps the wait and the retry (the 25 Sept photo). A downloaded file past the longest retention also turns into the expired placeholder, which matches what the server and the badge already say.
**Tests (+5):** each bubble type 90 days old shows the timer icon, never fetches, no retry, no overflow at 360dp 200% (RED at HEAD ×4); `isPastRetention` boundaries.
**Not changed (frozen store):** the store's reconnect drain still re-requests every queued blob, purged ones included (one record lookup each per reconnect).

## Device round 2 (user, 2026-10-31, Redmi, light theme)

1. **"Media expired" misaligned:** in full-width voice and document bubbles the icon-over-text sat centred, and on the own amber bubble it was grey at 50% (unreadable). **Fix:** `ExpiredPlaceholder` gains `inline` (a left row like a document row, 13px) and `ink`; voice and document use the row; every own-bubble expired mark (photo, video, voice, document) uses `onAccent @70%`, the same ink as the document retry tile. Test (+2, own/theirs): icon and copy share one row starting at the bubble edge; ink = onAccent .70 on own, inkSoft on theirs. RED against round 1's centred column.
2. **Two photos from 24/25 Sept shimmered for a while, then "Tap to retry":** both are `queued` on the Redmi (no server record answered), while a photo sent minutes later on 25 Sept is `ready`. They are 37 days old, under the 60-day photo maximum, so the age rule cannot call them expired (they may be High quality, 30 days, or an upload that never finished). The "while" was the provider's 45s wait for a just-sent upload's record. **Fix (provider, not the store):** `mediaFileProvider` reads the message's `createdAt` first; older than 10 minutes, or a blob already `failed`, skips the 45s wait (and does not subscribe to `mediaChanges`). Test (+1, real repository + store, record list empty): resolves null in < 10s; RED with HEAD's provider (timed out at 20s).
**Store change (user OK, 2026-10-31):** in `_runPipeline`, a record 404 on a message **over a day old** is now `failed` / `dead_link` instead of `queued`, so the bubble shows "No longer available" (via `mediaBlobStatusProvider`) and the reconnect drain stops re-requesting it. A day, not the provider's 10 minutes, because `failed` is permanent (the store never retries it) and a large upload on a slow link can take longer than 10 minutes; nothing uploads a day late (offline media uploads fail rather than queue). A message with no local row stays `queued`. Existing stuck rows heal on their next request (they are `queued`, so the pipeline runs again). Test (+1): 37 days old → failed/dead_link, 1 minute old → still queued; RED against HEAD's store. The 6 existing store tests pass unchanged. Frozen-file diff now: the two timeouts and this one branch in the record-404 path; decrypt, verify, key and write paths untouched.

## Device check (user)

Round 2 re-check: open the Avium chat again. The July photos, documents and voice note show the timer "expired" placeholder at once, with no shimmer and no "Tap to retry". Then the 200% text pass on the screens below.

Use a 360dp-ish phone with 200% text for 3, 4, 6 and 8 if you can.

1. Airplane mode on, open a chat with a voice note you have never played, tap play: after the wait it shows the red error. Tap again while offline: the button is dimmed and "Available online" replaces the duration; nothing happens. Airplane off, tap: it plays.
2. Same for a document you never opened: the bubble shows "Tap to retry" online, or a dimmed icon with "Available online" offline. Turn the network back on and wait: it loads by itself. Tap a document bubble that did load: it opens; if the open fails you see "Couldn't open the file. Try again." (no `Exception`).
3. Same for a photo and a video you never loaded: grey placeholder with "Tap to retry" (online) or the dimmed icon and "Available online" (offline). Back online it fills in by itself; a tap online also reloads it.
4. Media & Docs, airplane on, open the chat's Media & Docs: each tab shows "Couldn't load this chat's media." with Retry dimmed and "Available online". Airplane off, Retry: the tab loads. In Docs, a document never downloaded, offline: after the wait, "Couldn't open the file. Try again."; online, tap again: it opens.
5. A photo whose server copy expired (an old High-quality photo, if you have one): "No longer available", no retry, tapping does nothing.
6. Stalled network (Wi-Fi connected but with no internet, e.g. a hotspot with mobile data off): open Media & Docs. Within about 8s the spinner becomes the error state. A photo in a chat stops shimmering within about 8s of its download stalling (plus the existing 45s wait for a record that never landed).
7. On the same stalled network, tap a friend on Home who has no chat yet: the tile says "Opening chat…", more taps do nothing, and after about 8s "Chat is not ready yet. Try again in a moment." shows.
8. Add friend → enter a 5-character code → Search: "Friend code must be exactly 6 characters." shows.
9. Starred messages: still lists your stars offline (no `Error:` text anywhere).
10. Restore on a fresh install (if you can face it): the sync still reaches Home as before.
