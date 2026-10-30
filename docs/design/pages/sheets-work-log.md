# Sheets & overlays (one chrome, one picker, one opener, one confirm dialog) — implementation work log

Date: 2026-10-30.
Scope: Page 8, checklist `docs/design/pages/sheets.md` (A–J, registry R19/R20/C12/C13, C4/C4a
amendment, theme row), board `sheets.html` (S1–S15). Routed to Claude end to end (Omnirush down
until 2026-11-02 17:30 IST); no handoff brief. K1–K4 (S14) not touched. No live PocketBase read
(decision 12).

## Status

| Step | Result |
|---|---|
| Spec + checklist | user PASS 2026-10-29, every deferred decision = its default |
| Implementation | DONE 2026-10-30 by Claude, every MUST and SHOULD in A–J |
| Gates | `flutter test` **573/573**, run twice (baseline 505 + **68** new: 66 at implementation + 2 from review fixes) · `flutter analyze` 0 errors; vs a HEAD snapshot, no new warning or info in any changed or new file · `git diff --check` clean, no trailing whitespace in new files · A11 grep gate RED twice (planted `showModalBottomSheet` in `media_docs_screen.dart`; planted `$e` in `add_friend_screen.dart`) then GREEN · A11 shell grep empty · `trail check`: 3 keyword-match conflicts on the new registry rows, none real (see below) · frozen-method diff vs HEAD: **37/37** pieces byte-identical |
| Independent review | fresh-context reviewer subagent, two passes (the first stopped at the usage limit): **FAIL → fixed**. 1 BLOCK + 3 SHOULD fixed, each proven RED with the fix reverted, then GREEN; 5 NITs: 2 fixed, 3 recorded |
| Device check | round 1 (2026-10-30): **FAIL → fixed** (4 Page 8 bugs + 1 voice-bubble bug, see below; tests 578/578); round 2 (2026-10-30): **PASS**. One small fix after it: switching to **Scan QR** now drops the keyboard (the code field kept focus); test RED then GREEN, suite **579/579** |
| Commit | one commit after the round 2 PASS: with `sheets.html`, `sheets.md`, this log, the registry rows, the six untracked learnings (`2026-10-29-choosing-high-quality-for-a-photo-chaitanya.md`, `2026-10-29-reading-a-qr-from-a-photo-chaitanya.md`, `2026-10-29-a-sheet-row-s-offline-hint-chaitanya.md`, `2026-10-29-a-media-download-that-failed-stays-chaitanya.md`, `2026-10-30-never-await-an-audio-player-s-chaitanya.md`, `2026-10-30-a-toast-shown-while-a-bottom-chaitanya.md`) and the implementation |

## What changed

- **NEW `lib/core/widgets/app_sheet.dart` (R19)**: `showAppSheet` (the only
  `showModalBottomSheet`; reduced motion = `AnimationStyle.noAnimation`), `AppSheetChrome`
  (C4a's `_ContextSheetChrome` promoted: handle, title + `titleAction`, `header` + divider,
  `children` or `body`, keyboard inset, 90% cap), `SheetActionRow` (`_menuActionTile` promoted,
  still a `ListTile`).
- **NEW `lib/core/widgets/app_dialog.dart` (R20)**: `showConfirmDialog`. Callers: delete message,
  remove member, leave group (next-admin line kept), sign out, discard changes (**Keep editing** /
  **Discard**, not destructive).
- **NEW `lib/features/chat/widgets/reaction_picker.dart` (C12)**: `kReactionEmojis` (today's 32,
  same order), `kQuickReactions`, `showReactionPicker`. Both `_reactionEmojis` lists and both grids
  deleted; the menu ＋ and the bubble ＋ chip call it and keep their own write.
- **NEW `lib/features/chat/widgets/attach_sheets.dart`**: `showAttachSourceSheet` /
  `showMediaQualitySheet` (titles **Attach**, **Photo quality** / **Video quality**; subtitles carry
  `AppConstants.retention*Days`, decision 2). Each pops with its own sheet context.
- **Theme** (`app_theme.dart`): `bottomSheetTheme` radiusLg + no tint; `dialogTheme` no tint +
  title 20/26 w700 ink + content 15/22 ink. `tokens.dart`: `radiusPill = 999` (foundation §4).
- **Message menu** (`message_context_menu.dart`): both sheets on R19; quick row = 5 emoji in 48
  `surface2` circles + 48 ＋ (**More reactions**); preview name 15/22 w600, preview 13/18, min
  height instead of a fixed 20; delete rows destructive; Copy / pin limit → R5; `_confirmDelete` →
  R20. C4a divider only with a header; `showActionSheet(haptic:)`.
- **Who reacted** (`reaction_bar.dart`): opens at once; the query moved verbatim into
  `reactionDetailProvider` (auto-dispose family on `(messageServerId, emoji)`, 8s on `getList`
  only); 3 R11 skeleton rows / rows with R1 / R12 banner + Retry. `_ReactionAvatar` deleted.
  **Remove** = R3 text (ink); offline it gets one 38% dim and the sheet one hint.
- **Chat ⋮** (`chat_screen.dart`): C4a, no header, sentence case, trailing
  `disappearingDurationLabel`; each callback body is today's.
- **Attach** (`message_input.dart`): only the picker call expressions in `_onAttachPressed`
  changed; `_showSourcePicker` / `_showQualityPicker` deleted.
- **Voice sheet** (`media_docs_screen.dart`): R19 chrome; mic in a 48 `surface2` well; 56 accent
  play/pause disc (semantics **Play** / **Pause**); R3a in a `surface2` disc while loading; failure
  → **Couldn't load this voice message.** + **Try again** (re-runs `_init`); times 13/18 tabular;
  total = player duration, else the passed string.
- **Group info** (`group_settings_screen.dart`): R20 for remove / leave; `_RenameDialog` keeps its
  widget, gets R13 and loses its own bg/tint/shape; `_AddMembersSheet` on `AppSheetChrome(title,
  titleAction, body)`.
- **Add a friend** (`add_friend_screen.dart`): C13 `showAddFriendSheet`; R19 title; token tabs
  (15 w600, ink / inkSoft, 3px accent indicator, 48 tall); R13 field with helper and the
  notifier's error line; 48×56 accent search button (semantics **Search**, R3a on `surface2` while
  searching); R1 found card; R3 primary **Send friend request** (`busy`); sent state + R3 secondary
  **Done**; decision 3 lines; offline dim + one hint, field still types, a scan only fills the
  field; camera-refused card; R5 toasts. Home's `_showAddFriend`, `_NewChatSheetRow` and the
  Requests / Create Group `_openAddFriend` copies now go through C13.
- **New chat** (`home_screen.dart`): R19 title **New chat**, two `SheetActionRow`s.
- **Notifier** (`friend_request_provider.dart`, the one sanctioned logic edit): 8s on
  `findUserByCode` and `sendRequest` only; send failure copy **Couldn't send the request. Try
  again.**; search failure now also `debugPrint`s its detail.

## Decisions taken while building

- **E10 controller**: no `MobileScannerController` is made for a gallery pick; the tab calls
  `MobileScannerPlatform.instance.analyzeImage`. In mobile_scanner 6.0.11
  `MobileScannerController.dispose()` calls `MobileScannerPlatform.instance.dispose()`, which
  would stop the live camera on the same tab after a "no QR in that photo". Nothing is created,
  so nothing leaks.
- `SheetActionRow(key:)` puts the key on its `ListTile` (lint ignored with a reason): existing tests
  read the tile by key (`tester.widget<ListTile>(find.byKey(...))`).
- The disabled-row hint uses `TextWidthBasis.longestLine`: at 200% a wrapped hint otherwise claims
  the full tile width and `ListTile` asserts ("Trailing widget consumes the entire tile width").
- Emoji glyphs in fixed 48 circles / picker cells use `TextScaler.noScaling` (scaling only clips
  them); their semantics label is the emoji.
- Busy states on accent buttons (search, gallery) swap the fill to `surface2`: R3a's ring is accent
  and would vanish on an accent fill.
- `_onAttachPressed`: the quality calls became `mounted ? await showMediaQualitySheet(context, …)
  : null` (the switch is frozen; this keeps it to the call expression and clears
  `use_build_context_synchronously`).
- Who-reacted **Remove** offline = `IgnorePointer` + `Opacity(0.38)` (the P4 reaction-row pattern
  in the same file); add-friend buttons offline = `Opacity(0.38)` + disabled (page 7 `OfflineDim`).
- The send failure shows in the field's R13 error line (S6 "no match / send failed" state); it is
  the error of the action the sheet started.
- `media_docs_screen.dart` `_init`: one added line (`_failed = true` in its `catch`); download and
  playback lines unchanged.

## Tests: 505 + 68 = 573

| File | New tests |
|---|---|
| `test/core/app_sheet_test.dart` | 12 |
| `test/media/voice_sheet_test.dart` | 1 (review BLOCK) |
| `test/core/app_dialog_test.dart` | 8 |
| `test/chat/reaction_picker_test.dart` | 5 |
| `test/chat/reaction_detail_sheet_test.dart` | 7 (incl. the real query vs a silent PocketBase, gives up at 8s; +1 review SHOULD 2) |
| `test/chat/message_menu_sheet_test.dart` | 8 |
| `test/home/add_friend_sheet_test.dart` | 10 |
| `test/home/add_friend_openers_test.dart` | 2 |
| `test/chat/attach_sheets_test.dart` | 14 |
| `test/grep_gates_test.dart` (page-8 gate, inside `main()`) | 1 |

Helper (no tests): `test/core/sheet_harness.dart` (`SheetLauncher`, `pumpHost` with 360×640 ×
200%, `largeTextFonts` = system + `PlusJakartaSans`, `paintedColor`, `expectNoTextIn`).
Existing tests edited: **none** (`git diff --stat HEAD -- test` = only the new gate in
`grep_gates_test.dart`). The 11 named existing files pass unedited (119 tests).

## Grep gate RED → GREEN

1. RED: appended `// planted: showModalBottomSheet(context: c, builder: b);` to
   `media_docs_screen.dart` → `showModalBottomSheet outside lib/core/widgets/app_sheet.dart`.
2. RED: appended `String planted(Object e) => 'Failed: $e';` to `add_friend_screen.dart` →
   `$e in lib/features/home/screens/add_friend_screen.dart`.
3. Both files restored (`cmp` against the copies) → GREEN.

## Frozen-method diff (function level, vs HEAD)

Script in the session scratchpad. Whole files unchanged: `message_repository_impl.dart`,
`friend_repository_impl.dart`, `media_upload_service.dart`, `backup_pin_screen.dart`,
`group_admin_provider.dart`, `auth_provider.dart`, `disappearing_dialog.dart`,
`chat_provider.dart`, `encryption_service.dart`. Identical at function level: `_onAttachPressed`
(only the sanctioned picker swaps), `_sendImage`, `_sendVideo`, `_sendDocument`,
`_jumpToMessage`, `_openConversationInfo`, `_guard`, post-dialog code of `_confirmRemove` /
`_confirmLeave` / `_rename` / `_confirmSignOut` / `_onPopBlocked`, `_confirmLeave`'s next-admin
rule, `_AddMembersSheet._send`, `_afterAction`, every `_ContextSheet` callback (reply, select, copy,
star, pin, delete ×2, quick reaction, picker result; only the R5 / destructive swaps), the
reaction chip write, the add-chip result handling, who-reacted Remove (write + invalidate + pop),
and everything in `friend_request_provider.dart` outside `searchByCode` / `sendRequest`.
**37/37**, re-run after the review fixes (who-reacted Remove compared with the sanctioned
`ref` → captured container swap, review SHOULD 2).

## Review findings and fixes

Reviewer: fresh-context general-purpose subagent over `git diff HEAD -- lib test` against
`sheets.md`. Pass 1 stopped at the usage limit (no verdict); pass 2 finished the remaining files
and ran the suite. **Verdict: FAIL → fixed.** Every fix below was proven RED (fix reverted, the
new assertion fails) and then GREEN, with files restored by `cmp`.

| # | Sev | Finding | Outcome |
|---|---|---|---|
| 1 | BLOCK | H3: voice **Try again** could never succeed: `mediaFileProvider` is a plain (not auto-dispose) family, so `_init` re-read the cached `null` | Fixed: `_retry` invalidates `mediaFileProvider(MediaRef(…))` before `_init` (the provider stays frozen). Test `test/media/voice_sheet_test.dart`: RED `Expected: <2> Actual: <1>` fetches, GREEN with the fix |
| 2 | SHOULD | J2/J3: `Semantics(excludeSemantics: true)` buttons had no tap action (picker cells, the 5 quick emoji + ＋, add-friend **Search**) | Fixed: `onTap:` on each Semantics. Tests now assert `hasTapAction` (picker, menu, add-friend; Search offline `hasTapAction: false`); all three RED without the fix |
| 3 | SHOULD | Same, the voice play/pause disc (pass 2) | Fixed the same way. Device check (the disc needs a real player) |
| 4 | SHOULD | C4: who-reacted **Remove** used the sheet's `ref` after the await; swipe the sheet away mid-write → `Cannot use "ref" after the widget was disposed`, invalidate skipped | Fixed: `ProviderScope.containerOf(context)` captured before the await, used for the read and the invalidate. Test "Remove, then the sheet is swiped away mid-write…": RED without the fix, GREEN with it |
| 5 | NIT | The emoji-list gate matched one entry (`'🫡'`) | Fixed: any of `🫡 🫠 🫶 🥹 💎` outside `reaction_picker.dart` fails |
| 6 | NIT | Voice error line not centred when wrapped | Fixed: `textAlign: center` |
| 7 | NIT | Who-reacted Retry shows no loading (Riverpod keeps the error up during refresh) | Not fixed: the banner goes away when the re-read lands; a spinner would be new UI beyond C2 |
| 8 | NIT | `SheetActionRow` label is `Expanded` beside a `Flexible` value, so the label is capped at half the row | Not fixed: this is the settings-row learning's sanctioned layout (wraps, never overflows) |
| 9 | NIT | A send that timed out at 8s may have reached the server; the copy invites a retry (possible duplicate pending request) | Not fixed: K3 / decision 12 (server rule unknown), accepted at spec time |

Reviewer confirmed independently: deviation (a) (mobile_scanner dispose stops the camera),
deviations (b)–(g); E9 bound placement; B2 callback swaps only; F1/F2, G1/G2, E1/E2, D2, D4, D5,
I1, H1/H2; `_guard` and `_rename` absent from the diff, the post-dialog code of
`_confirmRemove` / `_confirmLeave` identical; the A11 gate is inside `main()` and covers every
listed pattern; every Test-gate item has a matching test; `git diff --stat HEAD -- test` = only
the new gate. Not verified by the reviewer: device-only items, and the RED proofs (taken from
the implementer).

**`trail check` conflicts (3, all keyword matches on the new registry rows, none real):**
R19's "trailing value Flexible + end-aligned" is what the settings-row learning *decided*;
"action value" matches an unrelated refresh-race learning; R20 lists "remove member, leave
group" as dialog callers and adds no UI guard (the group-rotation learning's ruled-out item).
The commit message should say so.

## Device check round 1 (2026-10-30): findings and fixes

Each fix has a test proven RED without it, then GREEN, except the voice spinner (needs a fake audio
platform; device check 10 and 12 cover it). Totals after: `flutter test` **578/578** (573 + 5),
`flutter analyze` 0 errors (83 infos/warnings, unchanged), `git diff --check` clean, frozen 37/37.

| # | You saw | Cause | Fix | Test |
|---|---|---|---|---|
| 1 | Gallery photo without a QR: no toast, camera keeps running | R5 toasts go to the root `Scaffold`, which sits under the sheet; the QR tab is the only place that toasts while its sheet stays open | the QR tab gets its own `ScaffoldMessenger` + a transparent `IgnorePointer` `Scaffold` (taps reach the gallery button). Not done in `showAppSheet`: Copy and group invites toast as their sheet closes, and a sheet-wide messenger would hide those | `add_friend_sheet_test`: the SnackBar is inside the sheet; the gallery button still hit-tests |
| 2 | Long-press media: preview loads forever | pre-existing (HEAD too): the header used `MessageBodyText`, and media has no text body, so its placeholder never resolves | non-text messages show `conversationPreviewLabel(type)` (📷 Photo, 🎬 Video, 🎤 Voice message, 📎 Document), same key | `message_menu_sheet_test` |
| 3 | My own messages say "Unknown" | pre-existing: the bubble passes no name for my messages | header name = **You** when `isMine` | `message_menu_sheet_test` |
| 4 | Long-press a reaction chip: **Couldn't load reactions.** online | pre-existing, hidden: `user_id` is a single relation, so the SDK returns the expand as a plain `Map`, and `.getStringValue` on a `Map` throws. HEAD swallowed it (`catch (_) {}`), so the old sheet was always empty; the new error state made it visible | read `expand.user_id.display_name` / `.avatar` by dot path (no SDK import in a widget, the network grep gate) | `reaction_detail_sheet_test` with a real PocketBase JSON answer |
| 5 | Reactions vanish offline, come back only after reopening the chat | pre-existing: the repository answers `[]` on a network failure, so a bar rebuilt offline showed nothing, and nothing re-read on reconnect | `ReactionBar` keeps the last known set per message and shows it when an offline read is empty; it re-reads `reactionsProvider` on offline → online, with `skipLoadingOnReload` so the chips don't blink. Lives in `reaction_bar.dart`, because `chat_provider.dart` is frozen | `reaction_detail_sheet_test`: offline remount keeps the chip; reconnect re-reads (each half RED alone) |
| 6 | Voice note: spinner for the whole clip, never a pause icon | `await _player.play()` completes only when playback stops, so `_loading` stayed true. In the chat bubble (`voice_message_bubble.dart`) and the same line in the Page 8 voice sheet | `unawaited(_player.play())` in both | none (device) |

Sent to separate sessions (outside this page, or in code it must not touch): an offline media send
that never retries; GIF → JPEG on compression; pixelated thumbnails (full-size trial); and 200%
text overflows on the Home list rows and the chat app bar's "Last seen".

## Known limits / follow-ups (outside this page)

- **Offline reactions (user, round 2):** reactions should work like the rest of an offline-first
  app: show at once, sync on reconnect, and survive a cold start offline. Today they are
  network-only. There is no drift table, no outbox op, and `reactionsProvider` reads PocketBase
  directly, so the menu dims them with **Available online** (P4). The in-memory last-set in
  `ReactionBar` covers one run only. Needs a reactions table plus outbox add/remove ops in
  `message_repository_impl.dart`, which was frozen here.
- **Offline banner (user, round 2):** "You're offline…" everywhere is too loud for an offline-first
  app; kept for now, revisit in the mascot pass (page 10).
- **Media (user, round 2):** GIF → JPEG, pixelated thumbnails (try full size), offline media send
  that never retries → the media phase (page 9).

- `AddFriendNotifier.searchByCode`: the **Friend code must be exactly 6 characters.** error never
  shows, because `copyWith(clearError: true, searchError: …)` lets `clearError` win. Found while
  writing the openers test; the notifier is frozen beyond the 8s / `$e` edit.
- Raw SnackBars outside this page remain (composer send failures with `$e`, media viewer, chat
  search); not in A8's list.
- K1–K4 (S14) unchanged.
- **Pre-existing flaky tests (not this page):** `test/offline/send_fetch_char_test.dart` ("send
  persists optimistic pending row before the network ack") and `test/offline/outbox_core_test.dart`
  ("own-message enqueue is complete while network hangs") wait a fixed 50ms of real time; under
  load they fail about 1 run in 3–6. Reproduced on a clean HEAD (`7735099`) snapshot: 2 of 6
  `flutter test test/offline` runs failed with neither file touched. The full suite here was green
  twice in a row (573/573).

## Device check (you do every real send)

From `sheets.md`:

1. Long-press a message (light, dark, AMOLED): handle, preview, 5 emoji + ＋, rows; both delete rows
   have a red icon and an ink label; **Copy** → toast **Copied**.
2. Same, airplane mode: emoji row and **Pin** / **Delete for everyone** dimmed with **Available online**.
3. ＋ in the menu and ＋ on a bubble open the same picker; picking reacts (you send it).
4. Long-press a reaction chip: the sheet opens at once with skeletons, then **names** (round 1 showed
   the error online); airplane mode →
   the banner + Retry; back online → Retry fills it; **Remove** on yours.
5. FAB → **New chat** → **Add a friend**: tabs, field, search a real friend code, **Send friend
   request** (you send it), **Done**. Airplane mode: search dimmed + hint, field types.
6. **Scan QR**: deny camera → the Camera unavailable card; allow → scan a profile QR; gallery → a
   photo without a QR → toast **No QR code in that photo.** shown over the sheet (and the camera
   keeps running).
7. Requests empty state and Create Group empty state → the same Add a friend sheet, fresh.
8. Chat ⋮ in a group and in a 1:1: rows, **Disappearing messages** value, each row opens what it opened.
9. Attach → each source; a photo → **Photo quality** with days; send one (you send it); a video →
   **Video quality**.
10. Media & docs → a voice note: disc plays/pauses; airplane mode on an uncached note → error +
    **Try again**.
11. Delete for everyone → the dialog (red icon, ink **Delete**); Leave group / Remove member / Sign
    out / Discard changes look the same; rename group shows the R13 field.
12. Settings → large text (max) + Plus Jakarta Sans: message menu, add friend, attach, a dialog:
    nothing clipped, sheets scroll.
13. With the keyboard up in Add a friend: the field and button stay above it.
14. Round 1 re-checks: long-press a photo, a video and a voice note: the header says **📷 Photo** /
    **🎬 Video** / **🎤 Voice message**, and your own messages say **You**. Turn airplane mode on in a
    chat with reactions: the chips stay (dimmed); off again: they stay, with no reopen. Play a voice
    note in the chat: the spinner turns into a pause icon within a second.
