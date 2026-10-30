# Sheets & overlays: one chrome, one picker, one opener, one confirm dialog (acceptance checklist, Page 8)

Date: 2026-10-29. Visual ground truth: **`docs/design/pages/sheets.html`** (sections S1–S15, numbered;
S1 = the inventory with what is in scope, S12 = which candidate features the app and PocketBase support
today, S15 = diff summary). Authority: `docs/design/00-foundation.md` (tokens/laws) →
`docs/design/10-registry.md` (shared pieces) → this checklist. Page letters A–J are page-local. Line refs,
as of `7735099`: `mcm` = `lib/features/chat/widgets/message_context_menu.dart`, `rb` =
`lib/features/chat/widgets/reaction_bar.dart`, `hs` = `lib/features/home/screens/home_screen.dart`,
`afs` = `lib/features/home/screens/add_friend_screen.dart`, `frp` =
`lib/features/friend_requests/providers/friend_request_provider.dart`, `frs` =
`lib/features/friend_requests/screens/friend_requests_screen.dart`, `cg` =
`lib/features/groups/screens/create_group_screen.dart`, `cs` = `lib/features/chat/screens/chat_screen.dart`,
`mi` = `lib/features/chat/widgets/message_input.dart`, `gs` =
`lib/features/groups/screens/group_settings_screen.dart`, `md` =
`lib/features/media/screens/media_docs_screen.dart`, `ps` = `lib/features/profile/screens/profile_screen.dart`,
`ep` = `lib/features/profile/screens/edit_profile_screen.dart`, `at` = `lib/core/theme/app_theme.dart`.

**Starting point (audited 2026-10-29, trail grep).** 14 `showModalBottomSheet` call sites in 9 files and
8 `showDialog` call sites in 6 files. There is **no** `PopupMenu`, `showMenu`, `OverlayEntry`,
`Overlay.of`, `showGeneralDialog`, `DraggableScrollableSheet` or `showBottomSheet` in `lib/`. The full
in/out list is S1. Existing coverage: `test/offline/message_menu_offline_widget_test.dart` (message menu,
reads `ListTile.trailing` at `:100`), `test/registry_amendments_test.dart` (C4a/Home long-press keys
`:145-176`), `test/chat/reaction_bar_test.dart` (picker keys `:101-108`), `test/groups/add_members_sheet_test.dart`,
`test/groups/group_info_actions_test.dart` (member action sheet + dialogs), `test/chat/disappearing_dialog_test.dart`,
`test/profile/profile_screen_test.dart` / `edit_profile_screen_test.dart` (sign-out and discard dialogs). No
test covers the new-chat sheet, the add-friend sheet, the chat ⋮ menu, attach/quality, who-reacted or
the voice sheet.

**Smells, confirmed (not assumed).**
1. Add friend opens from **4 buttons through 3 copies of the opener**: `hs:543` (`_showAddFriend`, used by
   the FAB sheet row `hs:507` and the empty state `hs:456`), `frs:374` (empty state `frs:224`), `cg:396`
   (empty state `cg:539`). Each does `reset()` + its own `showModalBottomSheet`; Home passes radius 20,
   the others fall back to the theme's 24. `AddFriendSheet` itself is already one widget.
2. The **emoji list and the grid picker exist twice**: `_reactionEmojis` (32) at `mcm:17` and `rb:14`;
   pickers at `mcm:706` (keys `message-menu-reaction-picker` / `message-menu-picker-$emoji`, 90% height)
   and `rb:295` (keys `reaction-picker` / `reaction-picker-$emoji`, shrink-wrapped). No test uses the
   `mcm` keys; `reaction_bar_test.dart:101-108` uses the `rb` keys.

**Routing.** Claude end to end (spec, implementation, grading); Omnirush down until 2026-11-02 17:30
IST. If phase 2 starts after that time, the optimiser routes it (this checklist + `sheets.html` are the
brief). The grading pass is a fresh-context reviewer (subagent or `/code-review`), never the implementer.

**Pass criteria (page complete when):** all MUSTs ✓ · `flutter analyze` 0 errors · `flutter test`
green (baseline **505/505**, plus the new tests, with no existing test edited to pass) · test-gate
files below green · `git diff --check` clean (and no trailing whitespace in new files) ·
forbidden-pattern grep over the sheet files (A11) empty · `trail check` clean · frozen-method diff vs
HEAD unchanged · fresh-context review with no open BLOCK · device captures light + dark (+ AMOLED for
the chrome and one dialog) of: message menu (online + offline), the reaction picker, who reacted, new
chat, add friend (empty, found, sent, offline, scan), chat ⋮ menu, attach + quality, voice sheet, one
destructive dialog · user device PASS (no commit without it).

**Spec status: user PASS 2026-10-29; every deferred decision = its default** (decision 12: no live
PocketBase read). Deferred decisions at the bottom.

**Server facts.** No live PocketBase read was made. Everything below is from the repo; the two things
only the server can answer are decision 12.

**Status key:** `[x]` implemented AND verified by code/tests or recorded device evidence;
`[ ]` pending, partial, or blocked.

---

## ⛔ Frozen (read first: a breach here is an automatic FAIL)

Out of scope and frozen: **what each sheet starts.** `lib/infrastructure/repositories/message_repository_impl.dart`
(whole file: `addReaction`, `removeReaction`, `togglePin`, `toggleStar`, `deleteMessage`),
`friend_repository_impl.dart` (whole file), `lib/services/media_upload_service.dart` (whole file),
`MessageInput._onAttachPressed` (except the two picker call expressions, G1), `_sendImage`, `_sendVideo`,
`_sendDocument`, `groupAdminProvider` (`remove`, `leave`, `sendInvites`, `inviteStatuses`, rotation),
`_GroupSettingsScreenState._guard` and everything after each dialog returns in `_confirmRemove` /
`_confirmLeave` / `_rename`, `AuthNotifier.signOut`, `showDisappearingDialog`'s write,
`mediaFileProvider`, `ChatScreen._jumpToMessage` / `_openConversationInfo`, every callback body in
`_ContextSheet` (reply, select, copy, star, pin, delete ×2, reactions) except the toast and dialog swaps
(B2, B3), `backup_pin_screen.dart` (whole file), E2E and key code anywhere.

When a file holding any of these is edited (`mcm`, `mi`, `cs`, `gs`, `ps`, `ep`, `md`, `hs`, `rb`,
`frp`), the frozen methods in it are diffed against HEAD **at function level** and must be
byte-identical. The one lesson-driven logic edit is `AddFriendNotifier.searchByCode` / `sendRequest`
(`frp:557-601`: no `$e`, 8s bound on the network call only). Read for context only, do not re-solve:

- `.trail/learnings/2026-10-28-group-screens-amber-and-red-text-chaitanya.md` (amber/red contrast; remove/leave never retry)
- `.trail/learnings/2026-10-29-one-device-rotates-a-group-s-chaitanya.md`
- `.trail/learnings/2026-10-29-never-refresh-the-signed-in-user-chaitanya.md`
- `.trail/learnings/2026-10-29-restore-is-skipped-when-message-sync-chaitanya.md` (decrypting reads the device key only)
- `.trail/learnings/2026-10-29-a-settings-row-s-trailing-value-chaitanya.md` (Flexible trailing values)

## A. One sheet chrome (R19), laws, grep-gated hygiene (S2)

- [ ] **A1 MUST** NEW `lib/core/widgets/app_sheet.dart` with `showAppSheet<T>({required context,
  required WidgetBuilder builder, bool useRootNavigator = false})`: `isScrollControlled: true`,
  `useSafeArea: true`, `backgroundColor: t.surface`, no surface tint, `showDragHandle: false`, no
  `shape:` (the theme owns it, A4). It is the **only** `showModalBottomSheet` in `lib/` (gate, A11). The
  message menu and C4a keep `useRootNavigator: true` (today `mcm:106, :143`); every other sheet keeps
  today's (default) navigator.
- [ ] **A2 MUST** `AppSheetChrome` in the same file = `_ContextSheetChrome` (`mcm:303-363`) promoted:
  handle 36×4 `t.line` radius 2, 8 from the top and 12 below, in `ExcludeSemantics`, `handleKey`
  parameter (existing keys kept); optional `title` (h2 20/26 w700 ink, `Semantics(header: true)`, wraps)
  with an optional trailing `titleAction` widget; optional `header` (the preview row); then the body.
  16 side padding; bottom 16 + `viewInsets.bottom` inside `SafeArea(top: false)`; max height 90% of
  (screen − keyboard). Two body modes: `children` (the chrome scrolls them) or `body` (a `Flexible`
  that scrolls itself; handle and title stay put).
- [ ] **A3 MUST** `SheetActionRow` in the same file = `_menuActionTile` (`mcm:365-402`) promoted, **still
  a `ListTile`** (`message_menu_offline_widget_test.dart:91-100` reads `ListTile.trailing`): min height 52,
  leading icon 24 `inkSoft`, label 15/22 w600 ink, optional `subtitle` 13/18 inkSoft, optional trailing
  value 13/18 inkSoft wrapped `Flexible` + end-aligned (settings-row learning). `destructive` → error
  icon + ink label (C4b). `enabled: false` → icon + label in one `Opacity(0.38)`, trailing = the
  `kOfflineActionHint` text 13/18 inkSoft **not** dimmed, semantics not-enabled.
- [ ] **A4 MUST** One sheet radius: `bottomSheetTheme` (`at:91-95`) uses `WarmPopTokens.radiusLg`
  (today literal 24, decision 9) and `surfaceTintColor: Colors.transparent`; every per-call `shape:` on a
  sheet is deleted.
- [ ] **A5 MUST** C3 in the sheet and dialog code this page touches: colours only via `context.t.*`,
  radii only via `WarmPopTokens`. Today: `colorScheme.outline.withValues(alpha: 0.3)` handles (`mcm:349`,
  `afs:61-63`), `surfaceContainerHighest` (`mcm:525`, `afs:190`), `colorScheme.error` (`mcm:674`, `afs:178`),
  `onSurface.withValues(alpha: 0.5)` (`afs:228-230`), `success.withValues(alpha: 0.1)` (`afs:268`),
  `Theme.of(context).textTheme.titleLarge` (`afs:71`), radius literals 12/20 (`afs`, `hs:485, :550`, `rb:220`).
- [ ] **A6 MUST** C4: no accent-, error- or success-coloured `Text`, no accent icon on `surface`.
  Today: delete-row labels (`mcm:628, :645`), dialog **Delete** (`mcm:674`), reaction **Remove** (`rb:254`),
  who-reacted initial (`rb:355`), add-friend search error (`afs:178`), found-user initial (`afs:207`),
  **Request sent** line (`afs:284`), voice mic + play icons (`md:519, :552`), Material `TabBar`'s
  default selected label (primary = accent).
- [ ] **A7 MUST** Type scale only (foundation §3): actions/labels 15 w600, titles h2 20/26 w700 (sheet) or
  `pageTitleStyle` (dialog), names 15–16 w600, captions 13/18. Gone: 13.5 (`mcm:284, :384`, `hs:948`),
  12 (`mcm:234`, `md:539-540`), 18 w600 (`rb:230`), 16 w600 quality title (`mi:461`).
- [ ] **A8 MUST** R5 toasts only, no `SnackBar(` in the sheet code: Copy (`mcm:570`), pin limit
  (`mcm:603`), QR not found (`afs:329`), QR read error (`afs:339`).
- [ ] **A9 MUST** No `$e` / `e.toString()` in user-visible text: `afs:339` (**Could not read QR: $e**),
  `frp:598` (**Failed to send request: $e**). Detail goes to `debugPrint` only.
- [ ] **A10 MUST** No lone `CircularProgressIndicator` in sheets: R3's own `busy`, or R3a
  `BusySpinner` (`afs:163, :249, :375`, `md:545`).
- [ ] **A11 MUST** Grep gate (Test gates): `showModalBottomSheet` appears only in
  `lib/core/widgets/app_sheet.dart`; `AddFriendSheet(` only in `afs`; the emoji list literal only in
  `reaction_picker.dart`; and over the sheet files (`app_sheet.dart`, `app_dialog.dart`,
  `reaction_picker.dart`, `attach_sheets.dart`, `mcm`, `afs`) none of: `colorScheme`, `withValues(alpha`,
  `textTheme`, `surfaceContainerHighest`, `CircularProgressIndicator`, `SnackBar(`, `fontSize: 13.5`,
  `fontSize: 12`, `(Border|Radius).circular(<digit>`, `$e` / `e.toString()` outside `debugPrint(` lines.
- [ ] **A12 SHOULD** Reduced motion: `showAppSheet` passes `sheetAnimationStyle: AnimationStyle.noAnimation`
  when `MediaQuery.disableAnimationsOf(context)` (decision 8).
- [ ] **A13 MUST** Every sheet in S1 marked IN or REF goes through `showAppSheet` + `AppSheetChrome`
  (rows via `SheetActionRow` where it has rows). Listed per sheet in B–I.

## B. Message long-press menu (C4) (S3)

- [ ] **B1 MUST** `_ContextSheet` builds on `AppSheetChrome` + `SheetActionRow`; keys unchanged
  (`message-context-menu`, `message-menu-handle`, `message-menu-preview`, `-preview-sender`,
  `-preview-body`, `-reaction-row`, `-reply`, `-select`, `-copy`, `-star`, `-pin`, `-delete-me`, `-delete-all`).
- [ ] **B2 MUST** **Delete for me** / **Delete for everyone** are `destructive` (error icon + ink label;
  today `color: t.error` on both, `mcm:628, :645`). **Copy** → `showToast(context, 'Copied')`; the pin limit
  → `showToast(context, e.message, error: true)` (the repository's own copy, **You can pin up to 3
  messages.**). These are the only edits inside the callbacks.
- [ ] **B3 MUST** `_confirmDelete` becomes `showConfirmDialog(destructive: true, title: 'Delete message?',
  body: <today's two strings>, confirmLabel: 'Delete', confirmIcon: Icons.delete_outline)`.
- [ ] **B4 MUST** Preview row: name 15/22 w600 ink, preview 13/18 inkSoft one line; the fixed
  `SizedBox(height: 20)` (`mcm:290`) becomes a minimum height so 200% text is not clipped.
- [ ] **B5 MUST** Reaction circles 48×48 (tap floor; today 46) on `t.surface2`; the ＋ circle on
  `t.surface` + 1px `t.line` with an `inkSoft` glyph, semantics **More reactions**; it opens C12 (C1).
  Offline: the row's one 38% dim + the hint stay as they are (P4 ruling, `reaction_bar_test`/menu tests).
- [ ] **B6 MUST** The quick row shows decision 11's set (default: `kQuickReactions = ['👍', '❤️', '😂', '😮', '😢']`, declared next to `kReactionEmojis` in `reaction_picker.dart`, + ＋).
- [ ] **B7 MUST** P4 per-row hints stay (`Pin`, `Delete for everyone` show **Available online** as their
  `ListTile.trailing`), now via `SheetActionRow`'s disabled state.

## C. Reactions: one picker (C12) and who reacted (S4)

- [ ] **C1 MUST** NEW `lib/features/chat/widgets/reaction_picker.dart`: `const kReactionEmojis` (today's
  32, same order) and `Future<String?> showReactionPicker(BuildContext context)` via `showAppSheet` +
  `AppSheetChrome(title: 'Add a reaction', body: grid)`. Grid = max-extent cells ≥48 (6 across at 360dp),
  each cell an `InkResponse` button with semantics label = the emoji. Keys `reaction-picker` (the grid) and
  `reaction-picker-$emoji`. Both `_showReactionPicker` (`mcm:706`) and `_ReactionAddChip._showPicker`
  (`rb:295`) call it; what they do with the result is unchanged. Both `_reactionEmojis` lists are deleted.
- [ ] **C2 MUST** Who reacted opens **at once** (today it fetches first, `rb:177-213`, then opens).
  The existing query (same `filter`, `expand: 'user_id'`, `perPage: 50`, same name/avatar resolution) moves
  verbatim into an auto-dispose `FutureProvider.family` in `rb`, with `.timeout(8s)` on the `getList`
  call only. Loading = 3 R11 skeleton rows (40 disc + 14 bar); data = scrollable rows (R1 `AppAvatar`
  40, name 16/22 w600, **You** caption 13/18 for mine); error or timeout = R12 `StatusBanner(message:
  "Couldn't load reactions.", onRetry: invalidate)`. Title row: `<emoji> N reaction(s)` (h2).
- [ ] **C3 MUST** `_ReactionAvatar` (`rb:339-376`, amber initial) is replaced by R1 `AppAvatar(url:,
  initials: initialsOf(name), radius: 20)`; keys `reaction-detail-user-$uid` / `reaction-detail-avatar-$uid` kept.
- [ ] **C4 MUST** **Remove** (my row) is an R3 text button in ink (today error red, `rb:254`); offline it
  gets the one 38% dim and the sheet shows one hint. Its write + invalidate + pop are unchanged.

## D. Dialogs: one confirm dialog (R20) + the dialog theme (S11)

- [ ] **D1 MUST** NEW `lib/core/widgets/app_dialog.dart`: `Future<bool> showConfirmDialog({required
  context, required String title, required String body, required String confirmLabel, String cancelLabel
  = 'Cancel', IconData? confirmIcon, bool destructive = false})`. `AlertDialog` on `t.surface`, no tint,
  `radiusXl`; title `pageTitleStyle` (R14); body 15/22 ink; actions R3 text (cancel → `false`) + R3
  secondary (confirm → `true`; `destructive` → `confirmIcon` in `t.error` + ink label); barrier tap → `false`.
- [ ] **D2 MUST** Callers, each keeping its copy, its icon and everything after it (frozen): delete message
  (B3), remove member (`gs:234`), leave group incl. the next-admin line (`gs:280`), sign out (`ps:97`),
  discard changes (`ep:145`, not destructive: **Keep editing** / **Discard**).
- [ ] **D3 MUST** `dialogTheme` (`at:86-90`) gains `surfaceTintColor: Colors.transparent`,
  `titleTextStyle` 20/26 w700 ink and `contentTextStyle` 15/22 ink, so C11, the rename dialog and Backup
  PIN's frozen dialog match with no per-site styling (Backup PIN: theme effect only, file untouched).
- [ ] **D4 MUST** `_RenameDialog` (`gs:1680`) keeps its own widget (it owns its controller, `gs:1673`)
  and gets R13 `appFieldDecoration(label: 'Group name', hint: 'Enter group name…')` with the 50 counter;
  its explicit `backgroundColor`/`surfaceTintColor`/`shape` go (theme, D3).
- [ ] **D5 MUST** Titles and buttons per decision 1 (default: page 4's accepted strings stay: **Remove from
  Group**, **Leave Group?**, **Edit Group Name**).

## E. New chat + add a friend (S5, S6)

- [ ] **E1 MUST** `_showNewChatSheet` (`hs:480`) → `showAppSheet` + `AppSheetChrome(title: 'New chat')`
  (decision 7) + two `SheetActionRow`s **Add a friend** / **New group** (decision 1); `_NewChatSheetRow`
  (`hs:927-955`) is deleted. Taps do what they do today. No offline dim (neither row needs the network to open).
- [ ] **E2 MUST** ONE opener `void showAddFriendSheet(BuildContext context, WidgetRef ref)` in `afs`:
  `ref.read(addFriendProvider.notifier).reset()` then `showAppSheet(builder: (_) => const AddFriendSheet())`.
  All four buttons call it; `_showAddFriend` (`hs:543`), `_openAddFriend` (`frs:374`, `cg:396`) are deleted.
  The empty-state button labels in `frs`/`cg`/`hs` are not this page (they are tested: `requests_screen_test.dart:189`,
  `create_group_screen_test.dart:219`).
- [ ] **E3 MUST** `AddFriendSheet` on `AppSheetChrome(title: 'Add a friend', body: …)` (today
  `titleLarge`, `afs:71`); its own handle, max-height and inset code (`afs:43-66`) go.
- [ ] **E4 MUST** Tabs **Friend code** / **Scan QR**: 48 tall, label 15 w600, selected ink, unselected
  inkSoft, 3px accent indicator (fill), divider `t.line`. No accent text.
- [ ] **E5 MUST** Code field = R13 (`label: 'Friend code'`, `hint: 'e.g. CHAI42'`, helper **Six letters or
  numbers, from your friend's profile.**, the notifier's `searchError` as the R13 error line: ink + error
  icon); input formatters, `maxLength: 6`, uppercase and submit unchanged. Search button: accent-filled
  48×56, `radiusMd`, onAccent icon, semantics **Search**, R3a while `isSearching`.
- [ ] **E6 MUST** Found card: `surface2`, `radiusMd`, R1 `AppAvatar` radius 28 (`accentSoft` flag, ink
  initial), name 16/22 w600, `@username` 13/18 inkSoft; **Send friend request** = R3 primary, expanded,
  `busy: isSendingRequest`.
- [ ] **E7 MUST** Sent state: `check_circle_outline` 36 in `t.success` (icon only), **Request sent to
  <name>.** 16/22 w600 ink, **They'll show up in your chats once they accept.** 13/18 inkSoft, and R3
  secondary **Done** that pops the sheet (decision 4).
- [ ] **E8 MUST** Offline (`isOnlineProvider`): the search button and **Send friend request** get one 38%
  dim and are disabled; one **Available online** hint under them; the field still types; the Scan tab still
  scans, but a scanned code fills the field without searching while offline.
- [ ] **E9 MUST** `frp:557-601`: `findUserByCode(...)` and `sendRequest(user.id)` each get `.timeout(const
  Duration(seconds: 8))` on that call only; a timeout lands in the existing `catch` (search: **Search
  failed. Check your connection.**; send: **Couldn't send the request. Try again.**). `debugPrint` keeps
  the detail. Nothing else in the notifier changes.
- [ ] **E10 MUST** Scan tab: `MobileScanner(errorBuilder:)` shows the S6 card (**Camera unavailable** /
  **Allow camera access in system settings, or pick a photo of the code.**), never the package's raw error;
  the idle placeholder icon is inkSoft on `surface2`, `radiusMd`; the gallery button = accent fill +
  onAccent icon, 48, `radiusMd`, tooltip **Pick a photo of a QR code**, R3a while picking. Toasts: **No QR
  code in that photo.** / **Couldn't read that photo.** (R5, error). The `MobileScannerController` made for
  `analyzeImage` is disposed after use (`afs:325`).
- [ ] **E11 MUST** Decision 3 (default: a found user who is you shows **That's your code.** and no button;
  one already in `friendshipsProvider` shows **You're already friends.** and no button; both lines 13/18
  inkSoft; local data only, no new server call).

## F. Chat ⋮ menu → C4a (S7)

- [ ] **F1 MUST** `_showChatMenu` (`cs:993`) keeps its DB read, then calls `showActionSheet(context:,
  actions:)` with no header (decision 10): **Media and docs**, **Starred messages**, **Group info**
  (groups only), **Disappearing messages** (trailing `disappearingDurationLabel(...)`). Each callback body is
  today's (the `Navigator.pop(sheetContext)` becomes C4a's own pop).
- [ ] **F2 MUST** C4a draws its divider only when a `header` is given (today always, `mcm:217`).

## G. Attach + quality (S8)

- [ ] **G1 MUST** NEW `lib/features/chat/widgets/attach_sheets.dart`: `Future<String?>
  showAttachSourceSheet(BuildContext)` (title **Attach**; rows **Take a photo** / **Photo library** /
  **Record a video** / **Video library** / **Document**) and `Future<String?> showMediaQualitySheet(BuildContext,
  {required bool isVideo})` (title **Photo quality** / **Video quality**; rows **Normal** / **High** with
  subtitles). Same return strings as today; each pops with its **own** sheet context (today the
  `MessageInput` context, `mi:414-434, :470-476`). `_showSourcePicker` / `_showQualityPicker` are deleted;
  `_onAttachPressed` changes only in those two call expressions.
- [ ] **G2 MUST** Quality subtitles: today's (`60% quality, up to 1280px` / `90% quality, up to 2560px` /
  `720p` / `1080p`) plus decision 2's retention, built from `AppConstants.retention*Days`, never literals.

## H. Voice note sheet (S10)

- [ ] **H1 MUST** `_playInSheet` (`md:419`) → `showAppSheet` + `AppSheetChrome(children: …)`.
- [ ] **H2 MUST** Mic in a 48 `surface2` well (`radiusMd`), icon inkSoft (today 40 amber); title **Voice
  message** 16/22 w600; progress = accent on `surface2`, 4 tall, `radiusPill`; times 13/18 inkSoft with
  tabular figures (today 12); total = the player's duration, falling back to the passed `duration` string.
- [ ] **H3 MUST** Play / pause = 56 accent disc, onAccent glyph, semantics **Play** / **Pause**; loading = R3a
  in a 56 `surface2` disc; failure (today swallowed, `md:492`) = **Couldn't load this voice message.** 13/18
  inkSoft + R3 text **Try again** that re-runs `_init`. The playback and download code is unchanged.

## I. Page 4's sheets (S9)

- [ ] **I1 MUST** `_AddMembersSheet` (`gs:1208`) on `AppSheetChrome(title: 'Add to group', titleAction:
  AppButton(Invite N), body: …)`; its own `Container`/handle/`SafeArea`/inset/`ConstrainedBox` (`gs:1301-1330`)
  go. Search, skeleton, banner, empty state, `_send` unchanged; `add_members_sheet_test.dart` green unedited.
- [ ] **I2 MUST** `_ActionSheet` (C4a) and `_ContextSheet` share `AppSheetChrome` + `SheetActionRow`; keys
  `action-sheet`, `action-sheet-handle`, `conversation-context-menu`, `conversation-menu-handle`,
  `conversation-menu-preview(-avatar|-name)`, `conversation-menu-action-$i` unchanged.

## J. A11y, large text, motion (S13)

- [ ] **J1 MUST** Every sheet and dialog this page touches at 360×640 with `textScaler: 2.0`, and again
  with Plus Jakarta Sans (R18's `PlusJakartaSans`), shows no overflow (tests below cover every one a test
  can pump; the rest are device checks).
- [ ] **J2 MUST** Semantics, asserted through `tester.getSemantics`: sheet titles are headers; the handle
  has no semantics node; disabled rows are not-enabled; emoji cells are buttons labelled by their emoji;
  search button **Search**; voice disc **Play** / **Pause** (device check).
- [ ] **J3 MUST** Tap targets ≥48 everywhere this page draws (reaction circles, emoji cells, search button,
  gallery button, voice disc, every row).
- [ ] **J4 SHOULD** A12 reduced motion.

## Registry amendments (same commit, L2)

| ID | Amendment |
|---|---|
| R19 | `showAppSheet<T>` + `AppSheetChrome` + `SheetActionRow` in NEW `lib/core/widgets/app_sheet.dart`: the only way to open a sheet; C4a's private `_ContextSheetChrome` / `_menuActionTile`, promoted (A1–A3). Used by every sheet in the app. |
| R20 | `showConfirmDialog(...) → Future<bool>` in NEW `lib/core/widgets/app_dialog.dart` (D1). Used by delete message, remove member, leave group, sign out, discard changes. |
| C4 / C4a | amendment: built on R19; C4a's divider only with a header (F2); the chat ⋮ menu is a C4a caller (F1). |
| C12 | `kReactionEmojis` + `showReactionPicker(context) → Future<String?>` in NEW `lib/features/chat/widgets/reaction_picker.dart`: the ONE emoji list and picker (C1). |
| C13 | `showAddFriendSheet(context, ref)` in `lib/features/home/screens/add_friend_screen.dart`: the ONE way to open Add a friend (E2). |
| Theme | `bottomSheetTheme` radius `radiusLg` + no tint; `dialogTheme` no tint + title/content styles (A4, D3). Foundation §7 "Sheet" and "Dialog" now point at R19 / R20. |

## Test gates (mandatory)

Screen tests use fakes and an overridden `isOnlineProvider`; no platform channels, no real network.
Semantics via `tester.getSemantics`, not by finding `Semantics` widgets. Every test that checks large
text pumps at 360×640 with `textScaler 2.0` AND once with `fontFamily: 'PlusJakartaSans'` in the theme.

- [ ] NEW `test/core/app_sheet_test.dart`: `showAppSheet` opens on `t.surface` with radius `radiusLg` (from
  the theme) · handle 36×4 in `t.line`, no semantics node · title is a header and wraps at 200% · row
  label 15 w600 ink · `destructive` → icon `t.error`, label `t.ink` · disabled → one `Opacity(0.38)` over
  icon + label, trailing **Available online** not inside it, not-enabled in semantics · trailing value wraps
  at 360×200% (no overflow) · the keyboard inset lifts the content (pump with `viewInsets`) · 30 rows
  scroll inside 90% height · divider only with a header.
- [ ] NEW `test/core/app_dialog_test.dart`: confirm → `true`, cancel → `false`, barrier → `false` ·
  destructive icon `t.error` + label ink · title style 20 w700 · 360×200% + Jakarta no overflow.
- [ ] NEW `test/chat/reaction_picker_test.dart`: `kReactionEmojis.length == 32` and its order · picking
  returns the emoji, dismiss returns `null` · cells ≥48 at 360dp · the message menu's ＋ opens the widget
  keyed `reaction-picker` (same as the bubble chip) · cells are buttons labelled by their emoji.
- [ ] NEW `test/chat/reaction_detail_sheet_test.dart` (override the new provider): sheet visible on the
  first frame with 3 skeleton rows · data → rows with R1 avatars, **You** on mine · error → **Couldn't load
  reactions.** + Retry re-reads · the provider times out after 8s with a never-answering fake (fake async) ·
  **Remove** label is ink · offline → Remove dimmed + one hint.
- [ ] NEW `test/chat/message_menu_sheet_test.dart`: delete rows' icon `t.error` and label `t.ink` · **Copy**
  shows the R5 toast **Copied** (no `SnackBar` built outside R5) · **Delete for me** opens the R20 dialog
  **Delete message?**; Cancel leaves the message; quick row = decision 11's set + ＋ · 360×200% + Jakarta.
- [ ] NEW `test/home/add_friend_sheet_test.dart` (fake `friendRepositoryProvider`): title **Add a friend** is a
  header · search → found card + R3 primary · send → sent state + **Done** pops · send throws → **Couldn't send
  the request. Try again.** and no `Exception`/`$` in any text · send never answers → that copy after 8s ·
  search never answers → **Search failed. Check your connection.** after 8s · offline → search + send
  dimmed, one hint, field still accepts text · decision 3 lines · no `Text` in `t.accent`/`t.error`/`t.success`
  · 360×200% + Jakarta (empty, found, sent).
- [ ] NEW `test/home/add_friend_openers_test.dart`: the Requests and Create Group empty-state buttons each
  open `AddFriendSheet` with a reset state (a stale `searchError` from before is gone).
- [ ] NEW `test/chat/attach_sheets_test.dart`: each source row returns its string · Normal/High return
  `'normal'`/`'high'` · subtitles carry `AppConstants` retention days for photo and video · 360×200% + Jakarta.
- [ ] `test/grep_gates_test.dart`: NEW test **inside `main()`** for A11. Prove it RED once (break it
  locally, e.g. a stray `showModalBottomSheet` in a feature file), then GREEN; record both in the work log.
- [ ] Existing tests stay green **unedited**: `message_menu_offline_widget_test.dart`,
  `registry_amendments_test.dart`, `reaction_bar_test.dart`, `add_members_sheet_test.dart`,
  `group_info_actions_test.dart`, `group_info_screen_test.dart`, `disappearing_dialog_test.dart`,
  `profile_screen_test.dart`, `edit_profile_screen_test.dart`, `create_group_screen_test.dart`,
  `requests_screen_test.dart`. If decision 1 goes the other way, the string-only edits it needs are listed
  line by line in the work log, nothing else.
- [ ] Count: the work log records **505 + N = total**, N = tests added, and the suite total matches.
- [ ] Function-level diff vs HEAD of every frozen method in an edited file (see ⛔): empty.
- [ ] Full suite green · analyze 0 errors · `git diff --check` clean · `trail check` clean.

## Device check list (phase 2, M52 if connected, else Redmi S2; you do every real send)

1. Long-press a message (light, dark, AMOLED): handle, preview, 5 emoji + ＋, rows; both delete rows have a
   red icon and a dark/light ink label; **Copy** → toast **Copied**.
2. Same, airplane mode: emoji row and **Pin** / **Delete for everyone** dimmed with **Available online**.
3. ＋ in the menu and ＋ on a bubble open the same picker; picking reacts (you send it).
4. Long-press a reaction chip: the sheet opens at once with skeletons, then names; airplane mode → the
   banner + Retry; back online → Retry fills it; **Remove** on yours.
5. FAB → **New chat** → **Add a friend**: tabs, field, search a real friend code, **Send friend request**
   (you send it), **Done**. Airplane mode: search dimmed + hint, field types.
6. **Scan QR**: deny camera → the Camera unavailable card; allow → scan a profile QR; gallery → a photo
   without a QR → toast **No QR code in that photo.**
7. Requests empty state and Create Group empty state → the same Add a friend sheet, fresh.
8. Chat ⋮ in a group and in a 1:1: rows, **Disappearing messages** value, each row opens what it opened.
9. Attach → each source; a photo → **Photo quality** with days; send one (you send it); a video → **Video quality**.
10. Media & docs → a voice note: disc plays/pauses; airplane mode on an uncached note → error + **Try again**.
11. Delete for everyone → the dialog (red icon, ink **Delete**); Leave group / Remove member / Sign out /
    Discard changes look the same; rename group shows the R13 field.
12. Settings → large text (max) + Plus Jakarta Sans: message menu, add friend, attach, a dialog: nothing
    clipped, sheets scroll.
13. With the keyboard up in Add a friend: the field and button stay above it.

## Out of scope (do NOT build on this page)

Everything in ⛔ · K1–K4 (S14) · new features listed as not offered in S12 · the reaction chips on bubbles
and their ＋ chip (page 1, bubble) · the composer and recording UI · Backup PIN (incl. its dialog's logic) ·
fullscreen media (page 9) · mascots (page 10) · the empty-state button copy on Home/Requests/Create Group.

---

## Diff vs current implementation

| # | Area | Today (file:line) | Spec | Checklist |
|---|---|---|---|---|
| 1 | Opening sheets | 14 hand-rolled `showModalBottomSheet` calls in 9 files | R19 `showAppSheet` only; grep gate | A1, A11 |
| 2 | Sheet radius | literal 20 (`hs:485, :550`, `rb:220`), `radiusLg` (6 sites), theme 24 (`at:94`) for 4 sites | theme `radiusLg`, no per-call shape | A4 |
| 3 | Handle | `colorScheme.outline@30%` (`mcm:349`, `afs:61-63`, 40 wide), `t.line` (`hs:498`, `gs:1325`), Material `showDragHandle` (`cs:1003`, `mi:401, :446`, `mcm:715`, `rb:298`), none (`rb`, `md`) | one handle, 36×4 `t.line`, no semantics | A2 |
| 4 | Titles | 18 w600 (`rb:230`), 16 w600 (`mi:461`), `titleLarge` (`afs:71`), 20 w700 (`gs:1337`), none elsewhere | h2 20/26 w700, header semantics | A2 |
| 5 | Rows | dense `ListTile` 13.5 (`mcm:384`, `hs:948`), default `ListTile` (`cs`, `mi`) | `SheetActionRow` 15/22 w600, min 52 | A3 |
| 6 | Destructive | red labels: delete rows `mcm:628, :645`; dialog **Delete** `mcm:674`; **Remove** `rb:254` | error icon + ink label | A6, B2, C4, D1 |
| 7 | Keyboard | add friend pads insets itself (`afs:45`); attach/quality/new chat ignore it (no field) | chrome owns it | A2 |
| 8 | Scroll | who reacted (`rb:224`), attach (`mi:408`) and quality don't scroll | chrome / body scrolls at 90% | A2, C2 |
| 9 | Toasts | raw SnackBar `mcm:570, :603`, `afs:329, :339` | R5 | A8 |
| 10 | `$e` | `afs:339`, `frp:598` | fixed copy; detail to `debugPrint` | A9, E9, E10 |
| 11 | Spinners | `CircularProgressIndicator` `afs:163, :249, :375`, `md:545` | R3 busy / R3a | A10 |
| 12 | Message menu offline | per-row hint + emoji row dim (P4) | kept, via `SheetActionRow` | B7 |
| 13 | Message menu preview | fixed height 20 `mcm:290`; 13.5 name | min height; 15 w600 | B4 |
| 14 | Reaction circles | 46, `surfaceContainerHighest` `mcm:520-525` | 48, `t.surface2` | B5 |
| 15 | Quick row | all 32 emoji, scrolling | decision 11 (default 👍 ❤️ 😂 😮 😢 + ＋) | B6 |
| 16 | Emoji list | declared twice `mcm:17`, `rb:14` | `kReactionEmojis` once | C1 |
| 17 | Picker | two grids, two key sets `mcm:706`, `rb:295` | `showReactionPicker` once | C1 |
| 18 | Who reacted | fetch then open; `catch (_) {}`; no scroll; no bound `rb:174-266` | open at once; skeleton / list / banner; 8s | C2 |
| 19 | Who-reacted avatar | `CircleAvatar` + amber initial `rb:339-376` | R1 | C3 |
| 20 | Delete dialog | Material defaults, red **Delete** `mcm:658-682` | R20 destructive | B3, D1 |
| 21 | Group dialogs | hand-built chrome ×3 `gs:240, :303, :1709` | R20 ×2 + theme; rename R13 | D2–D4 |
| 22 | Profile dialogs | hand-built chrome ×2 `ps:101`, `ep:150` | R20 | D2 |
| 23 | Dialog theme | bg + radius only `at:86-90` | + no tint, title/body styles | D3 |
| 24 | New chat | custom handle + `_NewChatSheetRow` 13.5 `hs:480-523, :927-955`; no title | R19, title **New chat** | E1 |
| 25 | Add-friend openers | 3 copies `hs:543`, `frs:374`, `cg:396` | `showAddFriendSheet` | E2 |
| 26 | Add-friend chrome | own handle, `titleLarge`, Material `TabBar` (amber label) | R19 + token tabs | E3, E4 |
| 27 | Add-friend field / buttons | `OutlineInputBorder(12)`, `FilledButton`s radius 12, inline spinners | R13, accent icon button, R3 primary | E5, E6 |
| 28 | Add-friend error / sent text | red error `afs:178`; green **Request sent …!** `afs:284` | R13 error line (ink); ink line + **Done** | E5, E7 |
| 29 | Add-friend offline | nothing; search spins then fails | one dim + one hint | E8 |
| 30 | Add-friend timeouts | none on `findUserByCode` / `sendRequest` | 8s on each call | E9 |
| 31 | QR tab | package's raw error widget; controller per pick never disposed `afs:325` | refused-camera card; dispose | E10 |
| 32 | Self / friend | can request yourself or a friend | decision 3 | E11 |
| 33 | Chat ⋮ menu | plain `ListTile`s + Material handle, Title Case `cs:1000-1069` | C4a, sentence case | F1 |
| 34 | C4a divider | always, even with no header `mcm:217` | only with a header | F2 |
| 35 | Attach / quality | private in `MessageInput`, pop with the input's context `mi:397-482` | `attach_sheets.dart`, own context, titles | G1 |
| 36 | Quality retention | hidden (High kept half as long) | shown from `AppConstants` (decision 2) | G2 |
| 37 | Voice sheet | amber mic + play icons, 12px times, lone spinner, silent failure `md:419-560` | well, disc, R3a, error + **Try again** | H1–H3 |
| 38 | Add to group chrome | own container/handle/inset `gs:1301-1330` | R19 title-with-action | I1 |
| 39 | Tests | none for 6 of the 14 sheets | 8 new files + a gate inside `main()` | Test gates |

---

### Deferred decisions (you decide at spec review; default = recommended)

Every candidate was checked against what the app and PocketBase support today (S12). Nothing below is
built unless its default stands or you pick it.

1. **Copy casing: sentence case for strings this page owns** (**Add a friend**, **New group**, **Media and
   docs**, **Starred messages**, **Photo library**, **Friend code**, **Send friend request** …); **page 4's
   accepted and tested strings stay** (**Make Admin**, **Remove Admin**, **Remove from Group**, **Leave
   Group(?)**, **Edit Group Name**) → zero existing-test edits. Alternative: sentence case everywhere, with
   ~20 string-only edits across `group_info_actions_test.dart` and `group_info_screen_test.dart`, each listed.
2. **Quality sheet says how long the server keeps it** (`· kept 60 days` / `· kept 30 days` for photos,
   `30` / `15` for video), read from `AppConstants`. Today High silently halves retention. Alternative:
   leave the subtitles as they are.
3. **Add friend: “That's your code.” / “You're already friends.” instead of the Send button**, from the
   current user id and `friendshipsProvider` (local, no new call). Alternative: leave it to the server
   (whose rule is unknown, decision 12).
4. **Sent state gets a Done button** that closes the sheet. Alternative: no button (swipe down / Back),
   or Done + **Add another** (resets the form).
5. **Who reacted keeps its PocketBase query in `reaction_bar.dart`** (moved verbatim into a provider so it
   can be bounded and tested); moving it behind `MessageRepository` (L4) is backlog K2. Alternative: move
   it now (adds a repository method; the repository file is otherwise frozen).
6. **Who reacted opens at once with skeletons** instead of after the fetch. Alternative: keep fetch-first
   but add a busy state on the chip.
7. **New-chat sheet gets the title “New chat”** (matches the FAB tooltip; gives screen readers a header).
   Alternative: no title.
8. **Reduced motion: sheets appear without the slide.** Alternative: keep Material's slide (≤250ms, within
   the ceiling).
9. **Sheet top radius = `radiusLg` 20** (what 9 of 14 sites use). Alternative: `radiusXl` 24 (the theme's
   current value).
10. **Chat ⋮ menu has no header.** Alternative: the conversation's avatar + name header (like Home
    long-press).
11. **Message menu quick row = 5 emoji (👍 ❤️ 😂 😮 😢) + ＋**; the full 32 stay in the picker.
    Today the row scrolls all 32 and ＋ shows the same 32 again. Alternative: keep all 32 in the row.
12. **No live PocketBase read for this page.** Two facts only the server knows: whether the
    `friend_requests` create rule rejects a request to yourself or a duplicate pending one (K3), and the
    Google hook's `friend_code` length (the sheet requires 6). Default: skip (decision 3 covers the first
    on the client; the second only matters if Google accounts get non-6 codes). Alternative: you approve a
    read-only look at both now.
