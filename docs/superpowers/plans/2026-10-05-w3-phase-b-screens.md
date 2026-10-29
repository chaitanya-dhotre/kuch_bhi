# W3 Phase B — Screen Rework (Warm Pop wiring) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every spec screen composes the Phase A component set on Warm Pop tokens — zero `AppColors`/hardcoded palette left in features, indigo/purple gone, Marigold live on Home/Chat/etc. in light + dark.

**Architecture:** Screens keep their provider/domain logic untouched (spec rule 4). Pure presentation swap: inline tiles migrate to `lib/core/widgets/` components, color reads migrate `AppColors.x` → `context.t.x` / `WarmPopTokens.x`. Ends with `AppColors` + `google_fonts` deleted (dead after migration).

**Tech Stack:** Flutter, Riverpod, Phase A token/component system (`lib/core/theme/tokens.dart`, `lib/core/widgets/`).

**Spec:** `docs/superpowers/specs/2026-10-05-w3-warm-pop-design-system.md` (binding authority)

## Global Constraints

- **AppColors → token map** (mechanical, whole-repo):
  | AppColors | Warm Pop |
  |---|---|
  | `primary` | `context.t.accent` (static: `WarmPopTokens.accent`) |
  | `primaryVariant` | `WarmPopTokens.accentPressed` |
  | `primaryLight` | `context.t.accentSoft` (light: `accentSoftLight`) |
  | `sentBubble` | `context.t.accent` |
  | `receivedBubbleLight` / `receivedBubbleDark` | `context.t.surface` |
  | `tickSent`/`tickDelivered` | `context.t.inkFaint` |
  | `tickRead` | `context.t.accent` |
  | `error`/`success`/`warning` | `context.t.error` / `t.success` / `WarmPopTokens.accent` (warning→accent) |
  | `Colors.purple`/`Colors.indigo` sender palette | hash name → `[WarmPopTokens.accent, WarmPopTokens.info, WarmPopTokens.success, WarmPopTokens.error, WarmPopTokens.keyGold]` (deterministic `name.hashCode % len`) |
  | `Color(0xFF1A1A2E)` and other old dark literals | `context.t.surface` / `t.bg` / `t.surface2` by role |
  | `Colors.grey*`, `black54`, `white60` text | `context.t.inkSoft` / `t.inkFaint` |
  | old radii `12/20` | `WarmPopTokens.radiusMd/lg` |
- White `Icon` on accent stays readable: `context.t.onAccent`.
- Screens read ONLY `context.t` / `WarmPopTokens` / `Theme.of` — no new color literals (grep-gated per task).
- Loading/empty/error branches adopt Phase A components: `CircularProgressIndicator`-only loaders → `Skeleton`, hardcoded empty copy → `EmptyState` (mascot slot), connectivity/key banners → `StatusBanner` (`rg -n "CircularProgressIndicator|No .* yet|Offline" lib/features` = the worklist per batch).
- `flutter analyze` 0 errors + `flutter test` green after every task.
- **No commit until user PASS** (spec gate 5): batches commit only after the user approves that batch's device pass. `Co-Authored-By: Claude Code <noreply@anthropic.com>`.
- **Mockup-first gate** (spec screens section): before wiring each batch, serve an HTML mockup on `http://127.0.0.1:8792/` and STOP for approval. Batch 1's gate is already satisfied by the approved `docs/mockups/2026-10-05-home-chat.html`.
- TDD for this plan = grep-gate tests written RED against `rg` output, plus widget tests for genuinely new widgets.
- **Deferred to Phase C** (do not scope in): frame-drop/DevTools work (spec §Frame-drop), D5 dev options (spec §D5).

## Review Focus

- Sent-bubble Marigold with `onAccent` text stays ≥3:1 in light AND dark (accent unchanged across themes; `onAccent` flips `#2A2520`/`#21260F`).
- Unread badge / FAB / section headers on Home must hit Marigold (`AppColors.primary` was indigo `#5E6AD2` — the visible Phase A smoke defect).
- Group-sender name colors: deterministic hash mapping must not collide into unreadable-on-bubble (names render on `t.surface`, palette entries are all dark-enough except none — accent `#EFA00B` on white is a label, not body text; keep labels ≥ w600 12px).
- Migration must not touch provider reads inside screens (rule 4 regression): diff must show no changes to `ref.read`/provider wiring.
- `google_fonts` removal: confirm no import survives, `pubspec` cleaned, `pub get` green.

---

### Task 1: ChatTile component

**Files:**
- Create: `lib/core/widgets/chat_tile.dart`
- Test: `test/chat_tile_test.dart`

**Interfaces:**
- Consumes: `AppAvatar`, `AppBadge`, `context.t`, `WarmPopTokens.radiusMd`.
- Produces: `ChatTile({required this.title, required this.subtitle, this.avatar, this.time, this.unreadCount = 0, this.onTap, this.onLongPress, this.isGroup = false})` — Task 2 wires Home to it.

- [ ] **Step 1: Write the failing widget tests**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/core/widgets/chat_tile.dart';

Widget host(Widget child) => MaterialApp(
    theme: warmPopLight(), home: Scaffold(body: ListView(children: [child])));

void main() {
  testWidgets('ChatTile renders title/subtime/time, badge only when unread',
      (tester) async {
    await tester.pumpWidget(host(const ChatTile(
        title: 'Aarav', subtitle: 'See you at 8', time: '13:33')));
    expect(find.text('Aarav'), findsOneWidget);
    expect(find.text('See you at 8'), findsOneWidget);
    expect(find.text('13:33'), findsOneWidget);
    expect(find.byType(ListTile), findsOneWidget);
    await tester.pumpWidget(host(const ChatTile(
        title: 'Design Squad', subtitle: 'hi', unreadCount: 3)));
    expect(find.text('3'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ChatTile runs onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(host(ChatTile(
        title: 'A', subtitle: 's', onTap: () => tapped = true)));
    await tester.tap(find.byType(ListTile));
    expect(tapped, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/chat_tile_test.dart 2>&1 | tail -5`
Expected: FAIL — `Target of URI doesn't exist: 'package:kuch_bhi/core/widgets/chat_tile.dart'`

- [ ] **Step 3: Implement ChatTile**

Mirror the approved mockup row (`.row`): 40px avatar (reuse `AppAvatar` with letter fallback tinted `accentSoft`/`accent`), title `w700/14.5→15`, subtitle `13 inkSoft` ellipsis, time `11 inkFaint`, trailing `AppBadge(count: unreadCount)`, container `surface` + `radiusMd` + padding 12. Group rows pass `isGroup: true` to show the group glyph under the avatar (as Home does today). Accept `subtitleColor` override for online-green (`t.success`).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/chat_tile_test.dart 2>&1 | tail -3`
Expected: PASS 2/2

- [ ] **Step 5: Commit gate deferred** — no commit (batch commit after user PASS, Task 3).

### Task 2: Home screen migration

**Files:**
- Modify: `lib/features/home/screens/home_screen.dart` (541 lines — all color sites)
- Modify: `lib/features/home/screens/add_friend_screen.dart`
- Test: `test/grep_gates_test.dart` (create; RED first)

**Interfaces:**
- Consumes: `ChatTile` (Task 1), `SectionHeader`, `SearchField`, `AppBadge` — all Phase A.
- Produces: home with zero `AppColors`; grep-gate file other tasks extend.

- [ ] **Step 1: Write the failing grep-gate test**

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home screens carry no AppColors / old indigo palette', () {
    for (final f in [
      'lib/features/home/screens/home_screen.dart',
      'lib/features/home/screens/add_friend_screen.dart',
    ]) {
      final src = File(f).readAsStringSync();
      expect(src.contains('AppColors'), isFalse, reason: f);
      expect(RegExp(r'5E6AD2|EEF0FB').hasMatch(src), isFalse, reason: f);
    }
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/grep_gates_test.dart 2>&1 | tail -5`
Expected: FAIL — `home_screen.dart` contains `AppColors`

- [ ] **Step 3: Migrate home**

- Apply the Global Constraints map site-by-site (`rg -n "AppColors|Color\(0x|Colors\." lib/features/home/` is the worklist).
- Replace inline `_ConversationTile`/`_FriendsTile` leading+title+subtitle+trailing composition with `ChatTile` (keep ALL existing `ref.read`/navigation logic byte-identical — review focus #4).
- `_SectionHeader` here → delete, use core `SectionHeader` (same label style).
- FAB: `backgroundColor: context.t.accent`, icon `context.t.onAccent`, extended icon glyph unchanged.
- Requests preview rows: `AppBadge` already exists — wire counts through it.
- Add-friend sheet: map its `primary`/`primaryLight` per table.

- [ ] **Step 4: Run gate + suite**

Run: `flutter test test/grep_gates_test.dart test/chat_tile_test.dart 2>&1 | tail -3 && flutter analyze 2>&1 | tail -1`
Expected: gates PASS; analyze 0 errors (warnings unchanged ≤32 pre-existing)

- [ ] **Step 5: Commit gate deferred** — batch commit after user PASS (Task 3).

### Task 3: Chat screen migration (bubble + composer + screen) + Batch 1 device PASS

**Files:**
- Modify: `lib/features/chat/widgets/message_bubble.dart` (492)
- Modify: `lib/features/chat/widgets/message_input.dart` (composer)
- Modify: `lib/features/chat/screens/chat_screen.dart` (811)
- Modify: `lib/features/chat/widgets/{image,video,voice,document}_message_bubble.dart`, `reply_quote.dart`, `reaction_bar.dart`, `message_context_menu.dart`, `swipe_to_reply.dart`, `pinned_message_banner.dart`, `link_preview_card.dart`
- Test: extend `test/grep_gates_test.dart`

**Interfaces:**
- Consumes: Phase A tokens; `AppColors.sentBubble` etc. per map.
- Produces: chat zero-`AppColors`; Batch 1 (Home+Chat) ready for user PASS.

- [ ] **Step 1: RED — extend grep gate**

Add to `grep_gates_test.dart`: same loop over `lib/features/chat/screens/chat_screen.dart`, `lib/features/chat/widgets/` (walk all `.dart` under that dir), asserting no `AppColors`, no `Colors.purple`, no `Colors.indigo`, no `5E6AD2`.
Run: `flutter test test/grep_gates_test.dart 2>&1 | tail -5` → FAIL.

- [ ] **Step 2: Migrate bubble palette**

In `message_bubble.dart` replace the `_nameColors = [Colors.purple, Colors.indigo, ...]` list with the token palette from the Global Constraints table (hash mapping, deterministic). Replace `AppColors.sentBubble` → `context.t.accent` with text `context.t.onAccent`; received → `context.t.surface` on `t.bg` chat background; ticks per map (`tickRead` → `t.accent`).

- [ ] **Step 3: Migrate composer**

`message_input.dart` worklist (`rg -n "AppColors|Color\(0x|Colors\." lib/features/chat/widgets/message_input.dart`): field bg `t.surface` + border `t.line`, send/mic FAB `t.accent` + `t.onAccent`, recording states `t.error`, hints `t.inkFaint`, radius → `radiusMd`/pill per mockup `.composer`/`.pill` (44px pill, 44px round send).

- [ ] **Step 4: Migrate chat screen + sibling widgets**

Same map across the listed files (App bars `t.surface`, chips `t.accentSoft`, sheets/dialogs already themed). Keep provider wiring untouched.

- [ ] **Step 5: GREEN — gates + suite**

Run: `flutter test 2>&1 | tail -2 && flutter analyze 2>&1 | grep -c "error •" || true`
Expected: all tests green (52 + new), 0 errors.

- [ ] **Step 6: PRESENT Batch 1 to user — hard gate**

Build+install on emulator (`flutter run -d emulator-5554`), screenshot Home + Chat light/dark via Marionette (adb `exec-out screencap -p` fallback). Report: indigo gone, Marigold live, sent bubbles Marigold both themes, gates green. **STOP until user PASS/edits.** On PASS: commit batch —
`git add lib test && git commit -m "[W3 Phase B] Batch 1 — Home + Chat on Warm Pop tokens (ChatTile, Marigold bubbles/FAB) ... Co-Authored-By: Claude Code <noreply@anthropic.com>"`.

### Task 4: Batch 2 mockup gate — Profile + Settings + About

**Files:**
- Create: `docs/mockups/2026-10-05-profile-settings.html`

**Interfaces:**
- Consumes: Phase A mockup file as style base; profile/settings screens (read-only).
- Produces: approved visual target for Task 5.

- [ ] **Step 1: Build the mockup**

Clone `docs/mockups/2026-10-05-home-chat.html` structure/tokens. Frames: **Light Profile** (avatar+name+@handle, Friend Code card `accentSoft` w/ Marigold code, Change-PIN button secondary style, QR card white with ink caption — fix the white-on-white defect), **Dark Settings** (APPEARANCE Marigold section header, radio rows, Backup PIN / About `SettingsTile`s), **Light About**. Zero em-dashes; impeccable-detect clean (`.claude/skills/impeccable/scripts/impeccable detect` from `docs/mockups/`).

- [ ] **Step 2: Serve + PRESENT — hard gate**

`nohup python3 -m http.server 8792 --directory docs/mockups >/dev/null 2>&1 &` → report `http://127.0.0.1:8792/2026-10-05-profile-settings.html`. **STOP until user approves or lists edits.**

### Task 5: Batch 2 wiring — Profile, Settings, About

**Files:**
- Modify: `lib/features/profile/screens/{profile,edit_profile,view_profile}_screen.dart`
- Modify: `lib/features/settings/screens/{settings,about}_screen.dart`
- Test: extend `test/grep_gates_test.dart`

- [ ] **Step 1: RED** — grep-gate the six files for `AppColors`/`Color(0x`/`Colors.` → FAIL.
- [ ] **Step 2: Migrate** per Global Constraints map. Profile: QR caption `t.inkSoft` on white card (fixes smoke defect); Friend Code card `t.accentSoft` bg + `t.accent` code text; `Sign Out` → `t.error`. Settings: rows → core `SettingsTile`/`SectionHeader`; About: tokens.
- [ ] **Step 3: GREEN** — gates + `flutter test` + analyze 0.
- [ ] **Step 4: PRESENT device pass (light+dark) — STOP for PASS.** On PASS: commit `[W3 Phase B] Batch 2 — Profile + Settings + About ...`.

### Task 6: Batch 3 mockup gate + wiring — Auth screens

**Files:**
- Create: `docs/mockups/2026-10-05-auth.html`
- Modify: `lib/features/auth/screens/{login,register,google_onboarding,forgot_password,backup_pin}_screen.dart`
- Test: extend `test/grep_gates_test.dart`

- [ ] **Step 1: Mockup** — frames: Light Login (Marigold primary button, warm inputs, Capybara empty-state-style slot at top), Dark Register, Light Backup-PIN. impeccable detect clean. Serve → **STOP for approval.**
- [ ] **Step 2: RED gate** on the five files → FAIL.
- [ ] **Step 3: Migrate** per map (inputs `t.surface`+`t.line`, buttons primary=`t.accent`/`t.onAccent`, links `t.accent`, errors `t.error`). Keep auth logic/providers untouched.
- [ ] **Step 4: GREEN** gates + suite + analyze.
- [ ] **Step 5: PRESENT device pass — STOP for PASS.** On PASS: commit `[W3 Phase B] Batch 3 — Auth screens ...`.

### Task 7: Batch 4 mockup gate + wiring — Requests + Groups

**Files:**
- Create: `docs/mockups/2026-10-05-requests-groups.html`
- Modify: `lib/features/friend_requests/screens/friend_requests_screen.dart`, `lib/features/groups/screens/{group_settings,create_group}_screen.dart`, `lib/features/home/screens/add_friend_screen.dart` (if residual)
- Test: extend `test/grep_gates_test.dart`

- [ ] **Step 1: Mockup** — frames: Light Requests (invite cards, Marigold Accept/secondary Decline per component set), Dark Group Info (member rows, leave in `t.error`). Serve → **STOP for approval.**
- [ ] **Step 2: RED gate** → FAIL.
- [ ] **Step 3: Migrate** per map; invite/member rows → `SettingsTile`/`ChatTile` patterns; buttons → core `AppButton`.
- [ ] **Step 4: GREEN** gates + suite + analyze.
- [ ] **Step 5: PRESENT device pass — STOP for PASS.** On PASS: commit `[W3 Phase B] Batch 4 — Requests + Groups ...`.

### Task 8: Long-tail sweep + AppColors removal

**Files:**
- Modify: remaining `rg -l AppColors lib` hits — media screens/widgets (`media_viewer`, `media_docs`, `expiry_badge`, `video_player`), `starred_messages`, `add_friend` remnants, `app_colors.dart` (delete), `pubspec.yaml` (drop `google_fonts` if unused)
- Test: final grep gate = repo-wide

- [ ] **Step 1: RED — repo-wide gate**

```dart
test('no AppColors remains in lib (except the file itself, deleted)', () {
  final hits = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => File(f).readAsStringSync().contains('AppColors'));
  expect(hits.map((f) => f.path), isEmpty);
});
```
Run → FAIL (34 files).

- [ ] **Step 2: Migrate remaining files** per map (one pass, mechanical).

- [ ] **Step 3: Delete `lib/core/constants/app_colors.dart`**; `rg google_fonts lib` → empty → drop dep from `pubspec.yaml`, `flutter pub get`.

- [ ] **Step 4: GREEN** — full suite + analyze 0 + `dart run tool/export_tokens.dart` still clean.

- [ ] **Step 5: PRESENT final device sweep (light/dark × Home/Chat/Login/Settings/Group, emulator) — STOP for PASS.** On PASS: final commit `[W3 Phase B] Long-tail sweep — AppColors removed, google_fonts dropped ...`.

**End state:** 5 commits max (one per PASSed batch + sweep), zero `AppColors`, Phase C (frame drops, D5) next.
