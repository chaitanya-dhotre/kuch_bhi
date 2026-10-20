Dict: S=status D=done P=proof R=remaining N=constraint

S=Home redesign implemented. No commit created.

D=changed:

- `lib/features/home/screens/home_screen.dart`
    - App bar, badge clamp, profile avatar, search/filter, sections/counts.
    - Pin/presence/unread tile states.
    - Group sender prefixes; L1–L5 preview/predecrypt preserved.
    - Conversation long-press actions: pin, mark read, info.
    - FAB, new-chat sheet, backup banner, offline/error/empty/loading states.
    - Refresh invalidates conversations + friendships.
    - Reduced-motion handling and contrast fallback.
- `lib/features/home/widgets/home_search_bar.dart`
- `lib/core/widgets/chat_tile.dart`
- `lib/core/widgets/app_badge.dart`
- `lib/core/widgets/app_avatar.dart`
- `lib/core/widgets/skeleton.dart`
- `lib/features/chat/widgets/message_context_menu.dart`
    - Added reusable conversation-menu action API.
- `docs/design/10-registry.md`
- `docs/design/pages/home.md`
    - Completed items ticked.
- `test/home_search_test.dart`
- `test/chat_tile_test.dart`
- `test/registry_amendments_test.dart`

P=proof:

- Full suite: `248` tests passed.
- Targeted Home/preview/predecrypt/menu gates: passed.
- `flutter analyze`: exit 0; 97 existing info/warning diagnostics remain, no analyzer errors.
- `git diff --check`: passed.
- L5 static check: raw `Listener(onPointerDown)` preserved; no tile `GestureDetector.onTapDown`.
- Flutter SDK used: `/home/chaitanyadhotre/development/flutter/bin/flutter`.

R=remaining:

- `H6 SHOULD`: partial friend-error banner not fully closed.
- `H7 SHOULD`: pin row move animation not implemented.
- `I4 MUST`: font-scale 1.3 device capture not run.
- M52/Redmi device captures and manual TAPDOWN log verification not available in this environment.

N=worktree already contained unrelated modifications; preserved. No commit or destructive action performed.


S=done. Home user/group rows now render as separate bubbles.

D=change:

- `lib/features/home/screens/home_screen.dart`
- Added Home-only tile inset: `12dp` left/right.
- Added `10dp` vertical gap between rows.
- Preserved tile behavior, navigation, semantics, preview, and predecrypt logic.

P=proof:

- Emulator tested: `emulator-5554`.
- Build/install/launch passed with fake data.
- Visual inspection passed: separate rounded cards, page background visible between rows.
- Targeted tests passed: `7`.
- `git diff --check` passed.
- Isolated `test/offline/send_fetch_char_test.dart`: passed.

R=full-suite note:

- One full-suite run had 1 unrelated timing failure:
    - `send_fetch_char_test.dart`
    - optimistic row observed before async insert completed.
- No unrelated code changed.

N=no commit.

S=done.

D=adjusted `lib/core/widgets/chat_tile.dart`:

- Reduced vertical padding by 4dp total.
- Preserved horizontal spacing and bubble separation.
- Kept radius at `WarmPopTokens.radiusMd` = `16dp`.
- Curve matches `home.html` tile radius and shared Warm Pop surfaces.

P=verified:

- Targeted tests: `7 passed`.
- Emulator build/install/launch: passed on `emulator-5554`.
- Screenshot inspection: bubbles are shorter, still separated, curves consistent.
- `git diff --check`: passed.

N=no commit.

S=review pass 3 (2026-10-20, Claude): full home verification vs checklist — see
`chat-work-log.md` § Review pass 3 (shared log, both pages).

D=home line reopened: **D5** group sender prefix (`Flexible(flex: 0)` unbounded → row overflow
+ zero-width preview; probe-confirmed, no test). **I4** font-1.3 CAPTURED and ticked
(`captures/home-redmi-font-1.3.png`). H6 stays open: banner is unreachable dead code
(`friendsHasError` can't be true with non-empty list). H7 unchanged (SHOULD).

P=248/248 + analyze 0 + L5 live (TAPDOWN conv=d8zam3bst08ybzt) + device light/dark/font-1.3
all verified this pass.

N=no commit; fix list F1–F11 gates PASS.

S=review pass 4 complete (2026-10-20).

D=closed:

- Group sender prefix remains bounded and ellipsized; preview keys/contracts preserved.
- ChatTile uses one composed semantics node; dark accentSoft avatar initials meet 4.5:1.
- Pinned counter is normalized before render.
- H6 friend-error banner is reachable with retained stale friend data via `valueOrNull`.
- Shared Skeleton motion/duration fixes and chat loading convergence are recorded in the chat log.

P=proof: full suite **257/257**, analyzer 0 errors, emulator-5554 debug build/install/launch,
and Home screenshot inspection passed. H7 pin-row move animation remains open; no commit.
