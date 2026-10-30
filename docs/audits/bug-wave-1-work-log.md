# Bug wave 1: work log (2026-10-30)

Top three items from `docs/audits/2026-10-30-bugs.md` (§1.1–1.3). Claude did this end to end.
Status: **gates green, review done, waiting for the user's device PASS. Nothing committed.**

## Confirmed in code first

| § | Confirmed | Root cause |
|---|---|---|
| 1.1 | yes | `SendMessageNotifier.send` swallowed every throw. The composer cleared before the call and `onSend` was `void`. Every throw in `sendMessage` (`_assertCanSend`, `_computeExpiry`, the drift txn) happens **before** the row and outbox op land, because they are one transaction. Offline sends never throw: they queue as pending bubbles. So a "failed bubble" would be wrong (no row exists, and for a removed member there must not be one). The fix gives the text back. |
| 1.2 | yes | `SendMediaMessageNotifier.send` swallowed too, so the four composer catches (voice/doc/image/video) could only fire for compress or thumbnail errors. `sendMediaMessage` throws only before its optimistic row (upload is `unawaited`, and upload failures mark the bubble). |
| 1.3 | yes | `loadMoreMessages` swallowed every failure, so `_loadMore` always did `_offset += 40`. On the next scroll `loaded < _offset` set `_historyExhausted`. One failed page = "beginning of chat" plus a 40-message hole. `getList` was also unbounded (§6.3). |

## Fix

- `chat_provider.dart`: both send notifiers `rethrow` after the debugPrint (busy flag still resets in `finally`).
- `message_input.dart`: `onSend` is now `FutureOr<void> Function(String)`, so existing `void` callers still compile. `_send` captures the reply, calls `onSend` (before clearing the reply, since chat_screen reads it inside `onSend`), clears the box, then awaits. On failure: restore the text if the box is still empty, set the reply back with `??=`, and show the toast "Couldn't send. Try again.". The four media catches now use `showToast(error: true)` with fixed copy and no `$e`. Voice keeps its recorded preview on failure so it can be resent; the reset moved into the success path.
- `chat_screen.dart`: `onSend` returns the send future. `_loadMore` only advances the offset after the page succeeds. On failure it sets `_historyLoadFailed`, `_onScroll` stops auto-loading (no refetch on every scroll tick), and `HistoryLoadFailedRow` appears under the top progress bar. Retry refetches the same page. Offline, Retry sits in a single `Opacity(.38)`, disabled, with `kOfflineActionHint`.
- `message_repository_impl.dart` `loadMoreMessages`: `.timeout(8s)` on the `getList` only, and every failure is logged and rethrown. The interface doc says it throws. A missing group key is not a failure: the rows land `key_missing` (the same always-commit as the main fetch) and heal when the key arrives. Without that, a keyless group would fail every Retry forever (review SHOULD 1).
- "Retry invalidates the cached provider first": does not apply here. The page writes into drift and `messagesProvider` is a drift stream, so no provider caches a failure.

## Tests (+9, RED then GREEN)

| Test | RED proof |
|---|---|
| `test/chat/send_failure_test.dart`: text notifier rethrows + busy resets; media notifier rethrows | RED at HEAD ("Actual: Future<void>", swallowed) |
| same file: failed send restores the text + toast (keyboard submit; the button tap misses in the bare test layout, so the test uses the same `_send` path) | RED with HEAD `message_input.dart` + `chat_screen.dart` swapped in |
| `test/offline/load_more_failure_test.dart`: failed page throws; stalled page throws `TimeoutException` in under 12s | both RED with HEAD `message_repository_impl.dart` swapped in |
| same file: a page without the group key lands as `key_missing` and does not throw | RED before the review fix (threw MissingKeyException) |
| same file: `HistoryLoadFailedRow` online Retry; offline single .38 dim + hint, tap does nothing | new widget (compile-RED before) |
| `grep_gates_test.dart` "bug wave 1" (inside `main()`): no `$e` / `Failed to send` text in message_input; both notifiers rethrow; `_offset += 40` sits inside the try before `catch … _historyLoadFailed = true`; `_onScroll` skips while failed; the row is wired | RED at HEAD (`$e` present; offset regex checked directly: HEAD no match, now match) |

## Gates

- `flutter test`: **666/666** (baseline 657 + 9). No existing test changed. One gate test appended inside `main()`.
- `flutter analyze`: 0 errors (all pre-existing infos/warnings, none on changed lines).
- `git diff --check`: clean. `trail check`: no conflicts.
- Frozen code: the only `message_repository_impl.dart` hunk is inside `loadMoreMessages`. No change to encryption, keys, decrypt or the upload pipeline (`_uploadMediaMessage` untouched).

## Independent review (fresh-context agent, 2026-10-30)

**PASS-with-SHOULDs**, no BLOCK. It confirmed: no duplicate send on restore (every throw comes before the txn), the frozen areas are untouched, there are no other callers, and `mounted` is checked after every await.
- SHOULD 1, a missing key failed the whole page: **fixed** (see Fix) + test.
- SHOULD 2, the offset gate also matched the old code: **fixed**. The regex is anchored to the try/catch, and a scroll-gate assert was added.
- SHOULD 3, no widget test for keeping the voice preview / the media toasts: **not done**. Reaching the preview needs the `record` plugin, and the doc path needs `file_picker`. Covered by device check 2–3; the notifier rethrow is unit-tested.
- NITs, left as they are: (a) if the user types new text during the in-flight send and the send then fails, the old text is not restored; the toast still shows, and the window is milliseconds of local work. (b) A removed member sees the generic toast, and the composer hides once membership refreshes. (c) The key/conversation calls after `getList` in `loadMoreMessages` are unbounded. That predates this change and sits in §6 timeouts, out of scope. (d) The 8s test costs 8s of suite time.

## Device check (user)

1. Airplane mode on, send a text: it appears as a pending bubble (clock tick) and sends when you go back online. The composer clears.
2. Airplane mode on, record and send a voice note: a bubble appears and turns **failed**. The upload pipeline marks offline uploads failed instead of queuing them, and that code is frozen, so it is noted, not changed. The point to check: it is never silent, and the preview row does not just vanish.
3. Airplane mode on, attach a document: same as 2.
4. In a group you were removed from (or the race case, if you can reproduce it), send a text: the text comes back in the box with the toast "Couldn't send. Try again.", and the reply quote stays.
5. Open a long chat, scroll up, and cut the network while older messages are loading: within 8s the bar stops and "Couldn't load older messages." shows with Retry dimmed and "Available online". No "beginning of your chat" marker.
6. Network back, tap Retry: the same older page loads (no gap in dates) and scrolling further keeps paging.
7. Scroll to the real start of a short chat online: the "beginning of your chat" marker still appears.

## Out of scope (untouched)

§4 cached-failure bubbles, §6 other timeouts, §3.1 PIN screen, §7.1 friend code, dead-code audit, security §8.2.
