# Share into the app (12.1): phase 2 work log

Date: 2026-11-02. Spec: `share-in.md` (user PASS 2026-11-02, decisions 1–22 at default). Implementer: Claude
(decision 22). **User device PASS 2026-11-02 (all 17 items).**

## Baseline

`flutter test` at `5580d1e`, clean `lib/` + `test/`: **899/900**. The one failure is the known load flake
`send_fetch_char_test.dart` "send persists optimistic pending row before the network ack" (passes alone).

## Where the gates ran

A sibling session ("multi-select that works") was editing `chat_screen.dart`, `album_screen.dart`,
`message_bubble.dart` and the repository files in the same checkout at the same time, and its half-written code did not
compile. So every gate below ran in a detached scratch worktree at `5580d1e` holding **only this change** (my files
copied in; for `chat_screen.dart`, HEAD plus my two hunks). The shared checkout's branch was never switched. At commit
time both sessions' hunks in `chat_screen.dart` must be staged apart.

## Gates

| Gate | Result |
|---|---|
| K1 grep gate `share-in` (inside `main()`) | **RED** with a planted `debugPrint('[Share] send check failed: $e ${conv.name}')` → `shared detail in debugPrint(...)`; reverted → **GREEN** (36/36 in the file) |
| `test/share/share_payload_test.dart` | 10/10 |
| `test/share/share_in_service_test.dart` | 10/10 |
| `test/share/share_target_screen_test.dart` | 14/14 (after review) |
| `test/chat/message_input_share_test.dart` | 10/10 (after review) |
| Full `flutter test` | On `a9d40e1` (multi-select landed): **976/976** before commit. First run 943/943. **After the review fixes: 945/945 = baseline 900 + 45 new.** No existing test edited (the flake passed both runs). |
| `flutter analyze` | 0 errors; no warnings in touched files |
| `flutter build apk --debug` | ✓ `app-debug.apk` |
| `git diff --check` | clean |
| Function-level frozen diff | `message_input.dart`: additions only (imports, end of `initState`, new `didUpdateWidget`, new share block above Image sharing); every pre-existing method byte-identical. `MainActivity.kt`: additions only; the clipboard handler is byte-identical. `chat_screen.dart`: only the `canSendIn` extraction (same values, one call; the now-unused `isMeAdmin` local removed). |
| `trail check` | 1 hit, a false positive: `MainActivity.kt:63` "brings back flutter set copy" against the recovery-key clipboard learning (Flutter's `Clipboard.setData`). The line is the share channel's comment ("a copy only after a chat is picked"); no clipboard code changed. Say so in the commit message. |

## Choices made in phase 2 (inside the spec, recorded for review)

1. **D9 replacement = pop, then push.** The picker is a pageless `MaterialPageRoute` on go_router's root navigator, so
   go_router's `pushReplacement` can't replace it. The picker pops with the chosen `Conversation`; the service then
   `router.push(chat, extra: conv)`, unless that chat is already the go_router top (then it only pops). Back from the
   chat lands where Back from the picker would have.
2. **All known-too-big at arrival → no picker.** A share whose every item has a known size over 100 MB (and no text)
   gets **Too big to send. The limit is 100 MB.** instead of a picker (S6's table shows a "1 video" summary for that
   row; opening a picker that can only fail seemed worse). Partly too big: the left-out toast shows after the tap.
3. **One left-out toast.** If both too-big and unreadable items were left out, only the too-big toast shows
   (`showToast` replaces the previous one).
4. **TalkBack bar.** `pageAppBar` takes the title as a string, so the bar reads **Send to** (header) and then the
   summary as the next node, rather than one "Send to, 3 photos and 2 videos" node.
5. **Group send rule settles late.** A group chat's composer starts with `canSendMessages` false (members and key
   readiness are streams). The composer holds the share and runs it when the rule turns true (a self-cancelling 500 ms
   check, no dispose hook); if it is still false after 15 s it drops the share, deletes its folders and shows **You can't send messages in this
   chat.** The picker's own D6 check reads the repo directly (`watchGroupMembers().first`, `hasUsableKey`, 3 s cap,
   no autoDispose provider awaited) and allows on a timeout, leaving the composer as the backstop.
6. **Service start** is one line in `app.dart`'s first post-frame callback (not listed in the spec's unfrozen files;
   nothing else there changed). It clears `share_in/`, then calls `takeShare`.
7. **Logout** drops a waiting share (auth goes from signed in to signed out) and `wipeMediaCache` deletes
   `share_in/` next to `media_clear/`.

## Review (fresh-context reviewer, 2026-11-02): 1 BLOCK, 3 SHOULD, 5 NIT. All fixed except where noted

| # | Finding | Fix |
|---|---|---|
| 1 BLOCK | A share run in a chat that already had a send in flight (or the editor open) bumped the upload generation and silently cancelled that send. | The composer holds the share while it is busy (recording, voice send, album prep, any upload) or not the top route; a 500 ms self-cancelling timer runs it once idle. Test: a page over the chat holds it. |
| 2 SHOULD | A second tap during the picker's group send check started a second copy loop that could wipe the first loop's handed-off files. | `_picking` guard from the tap to the hand-off. Test: double tap → one loop, no clear after hand-off. |
| 3 SHOULD | A recreated activity (process death under the camera, or a config change outside `configChanges`, e.g. bold text) replayed the old SEND without `LAUNCHED_FROM_HISTORY`. | `onCreate`: `savedInstanceState != null` → intent = plain `MAIN`. Device-only. |
| 4 SHOULD | Any URI scheme accepted ("Dirty Stream"): a hostile app could share `file:///data/data/com.chai.kuch_bhi/...` and one tap would send a private file. | Only `content://`; authorities starting with our package refused, except share_plus's `<pkg>.flutter.share_provider` (device item 15). Checked in `describeItem` and again in `copyShared`. Device-only. |
| 5 NIT | `take(120)` counted UTF-16 units: long non-Latin names could exceed ext4's 255 bytes, split a surrogate, or lose the extension. | `safeName`: ≤120 characters and ≤200 UTF-8 bytes, cut on a whole code point, extension kept. |
| 6 NIT | `debugPrint('[Share] media part failed: $e')` could print a `share_in/<n>/<name>` path. | Prints `e.runtimeType`. Not changed (frozen): `rep:1697` logs a document's file path, as the in-app Document pick already does. |
| 7 NIT | A handed-off share whose chat never opened survived logout. | Logout also invalidates `chatShareProvider`. |
| 8 NIT | One `try` around both wipe folders. | One `try` per folder. |
| 9 NIT | 5 s backstop could drop a share on a slow key fetch. | 15 s. |

Re-gates after the fixes: analyze 0 errors · full suite 945/945 · `flutter build apk --debug` ✓ · `git diff --check` clean
· frozen diff still additions-only in `message_input.dart` / `MainActivity.kt` (a `dart format` run had reflowed two
frozen lines; restored byte-for-byte). No open BLOCK.
