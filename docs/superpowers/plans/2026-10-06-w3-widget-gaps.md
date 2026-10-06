# W3 Widget Gaps — Font Selector + Mascot Tier-1 + Placements Implementation Plan

> **STATUS: PARKED (2026-10-06)** — offline-first architecture runs first (see `docs/backlog.md` §0). Resume from Task 1 when unparked; T2 (Tier-1 rig) must run before chat restructure (mascot C4 depends on it).

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the two Phase-B scope stragglers plus the spec's mascot placement list: user-selectable font (P11 Jakarta), Capybara Tier-1 interactions (squash-on-tap, success bounce), and mascot in profile header + status banner.

**Architecture:** Clone the proven theme-persistence pattern (Drift `AppSettingsTable` via `settingsDao`) for a font setting; thread `fontFamily` through the existing `warmPopLight/warmPopDark` builders into `MaterialApp` so one provider rebuild repaints the whole app. Extend the existing `Capybara` rig with two animation controllers (squash, celebrate) driven by a tap gesture and a `celebrateTick` counter param. Placements are call-site composition of the already-approved `Capybara` widget — no new components.

**Tech Stack:** Flutter, Riverpod `StreamProvider`, Drift `settingsDao` (existing table), Warm Pop tokens, existing `Capybara` rig (`lib/features/mascot/capybara.dart`).

**Spec:** `docs/superpowers/specs/2026-10-05-w3-warm-pop-design-system.md` (binding authority) — P11 typography, Mascot system, Screens "Used in" list.

## Skills (execution MUST load before Task 1)

- **`superpowers:executing-plans`** — native/inline workflow: task loop, ledger, rulings, completion contract, final review dispatch.
- **`superpowers:test-driven-development`** — governs every step: failing test first, watch RED, minimal code, watch GREEN.
- **`superpowers:verification-before-completion`** — per-task completion contract (tests ran + output read + Expected compared).
- **`superpowers:systematic-debugging`** — on any step output mismatch (code wrong vs plan wrong).
- **`superpowers:requesting-code-review`** — final whole-branch fresh review after Task 3, before finishing menu.
- **`.claude/skills/impeccable`** (project) — `impeccable detect` on every device capture presented for PASS.
- **`projectSettings:taste`** — anti-slop discipline for font-radio UI + mascot placements (no default-y additions, no palette drift).

## Global Constraints

- No commit until user PASS (batch rule); commits end `Co-Authored-By: Claude Code <noreply@anthropic.com>`.
- `flutter analyze` 0 errors + `flutter test` green after every task.
- TDD: failing test first, watch it fail, minimal code, watch it pass. Grep gates for wiring, widget tests for behavior.
- No violet/purple/indigo anywhere in `lib/` (gate 8 enforces).
- Screens may not hardcode color — `context.t` / `WarmPopTokens` only; components in `lib/core/widgets/` too.
- Rule 4: no changes to provider reads/wiring inside screens except the new font provider watch in `app.dart` (presentation-only theme input).
- System font is the default (P11): `fontFamily` stays `null` unless Jakarta selected. Jakarta family name in pubspec = `PlusJakartaSans`.
- Reduced-motion: mascot animations must park under `MediaQuery.disableAnimationsOf(context)` (existing rig behavior, keep for new controllers).
- Mockup gate waived for this mini-plan (component deltas, not screen batches) — device captures + user PASS per commit instead. Ruling recorded in ledger at start.
- Ledger: `.superpowers/sdd/2026-10-06-w3-widget-gaps/progress.md` (task-start/task-done scripts per task).

## Review Focus

- Font switch at runtime: one `settingsDao` write must repaint every screen (chat bubbles, settings, auth) without restart — stream → `app.dart` rebuild path, not cached ThemeData.
- AMOLED + font compose: `warmPopDark(amoled: true, fontFamily: ...)` must apply both (dark builder takes two optional params).
- Reduced-motion: squash/bounce never animate and timers/controllers dispose cleanly (existing blink timer pattern; leak = zombie animation after route pop).
- Status banner leading mascot: `Expanded` text + fixed-size leading must not overflow the ~48px strip on narrow widths; banner still renders without mascot (call-site optional).
- Profile header placement: centered column survives narrow width; mascot constant palette legible in light AND dark (mascot palette is theme-invariant by spec).

---

### Task 1: Font selector (provider + settings UI + theme threading)

**Files:**
- Create: `lib/features/settings/providers/font_provider.dart`
- Modify: `lib/core/theme/app_theme.dart:4,8,26,45` (`_build` gains `String? fontFamily`; P11 comment updated)
- Modify: `lib/app.dart:75-95` (watch font provider, pass into all three theme constructions)
- Modify: `lib/features/settings/screens/settings_screen.dart` (APPEARANCE section, after theme radios)
- Test: `test/font_provider_test.dart`, `test/grep_gates_test.dart` (gate 11)
- Test host: uses existing Drift `AppDatabase` pattern from `test/theme_tokens_test.dart` (no DB needed — enum + ThemeData only)

**Interfaces:**
- Consumes: `appDatabaseProvider`, `settingsDao.watchSetting/setSetting` (same contract as `theme_provider.dart`), `warmPopLight/warmPopDark`.
- Produces: `AppFont {system, jakarta}`, `fontFamilyProvider` (`StreamProvider<AppFont>`), `fontControllerProvider` → `FontController.setFont(AppFont)`; `warmPopLight({String? fontFamily})`, `warmPopDark({bool amoled = false, String? fontFamily})`.

- [ ] **Step 1: Write the failing tests**

`test/font_provider_test.dart`:

```dart
// P11 font selection: enum round-trip + ThemeData threading (RED until
// font_provider.dart and the fontFamily param exist).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/features/settings/providers/font_provider.dart';

void main() {
  test('AppFont storage round-trip defaults to system', () {
    expect(AppFontX.fromStorage(null), AppFont.system);
    expect(AppFontX.fromStorage('garbage'), AppFont.system);
    expect(AppFontX.fromStorage('jakarta'), AppFont.jakarta);
    expect(AppFont.jakarta.storageValue, 'jakarta');
    expect(AppFont.system.label, 'System default');
    expect(AppFont.jakarta.label, 'Plus Jakarta Sans');
  });

  test('warmPop builders thread fontFamily into ThemeData', () {
    final light = warmPopLight(fontFamily: 'PlusJakartaSans');
    expect(light.textTheme.bodyMedium?.fontFamily, 'PlusJakartaSans');
    expect(warmPopLight().textTheme.bodyMedium?.fontFamily, isNull,
        reason: 'P11 system default');

    final amoled =
        warmPopDark(amoled: true, fontFamily: 'PlusJakartaSans');
    expect(amoled.textTheme.bodyMedium?.fontFamily, 'PlusJakartaSans');
  });
}
```

Append gate 11 to `test/grep_gates_test.dart`:

```dart
  // Gate 11: font selection must be provider-driven end to end.
  test('font selector wired: settings UI + app theme watch the provider', () {
    final settings = File('lib/features/settings/screens/settings_screen.dart')
        .readAsStringSync();
    expect(settings.contains('fontControllerProvider'), isTrue,
        reason: 'settings writes via controller');
    expect(settings.contains('AppFont.values'), isTrue,
        reason: 'font options listed');
    final app = File('lib/app.dart').readAsStringSync();
    expect(app.contains('fontFamilyProvider'), isTrue,
        reason: 'app.dart must watch the font stream');
    expect(app.contains('fontFamily:'), isTrue);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/font_provider_test.dart test/grep_gates_test.dart 2>&1 | tail -15`
Expected: RED — compile error `font_provider.dart` doesn't exist + `fontFamily` named param not defined; gate 11 fails (no `fontControllerProvider` string).

- [ ] **Step 3: Create `font_provider.dart`** (clone `theme_provider.dart` shape exactly):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database/app_database.dart';

/// P11: system font default; Plus Jakarta Sans optional.
enum AppFont { system, jakarta }

const _kFontKey = 'app_font';

extension AppFontX on AppFont {
  String get storageValue => name;

  static AppFont fromStorage(String? v) {
    return AppFont.values.firstWhere(
      (e) => e.name == v,
      orElse: () => AppFont.system,
    );
  }

  String get label => switch (this) {
        AppFont.system  => 'System default',
        AppFont.jakarta => 'Plus Jakarta Sans',
      };

  IconData get icon => switch (this) {
        AppFont.system  => Icons.font_download_outlined,
        AppFont.jakarta => Icons.title,
      };
}

/// Reactive font choice, persisted in Drift (AppSettingsTable).
final fontFamilyProvider = StreamProvider<AppFont>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.settingsDao
      .watchSetting(_kFontKey)
      .map(AppFontX.fromStorage);
});

final fontControllerProvider = Provider<FontController>((ref) {
  return FontController(ref.read(appDatabaseProvider));
});

class FontController {
  FontController(this._db);
  final AppDatabase _db;

  Future<void> setFont(AppFont font) =>
      _db.settingsDao.setSetting(_kFontKey, font.storageValue);
}
```

- [ ] **Step 4: Thread `fontFamily` through the theme builders**

`app_theme.dart` — signatures and `_build` (current lines 4, 8, 26, 45):

```dart
ThemeData warmPopLight({String? fontFamily}) =>
    _build(ColorTokens.light, Brightness.light, fontFamily);

ThemeData warmPopDark({bool amoled = false, String? fontFamily}) =>
    _build(ColorTokens.dark, Brightness.dark, fontFamily, amoled: amoled);

ThemeData _build(
  ColorTokens c,
  Brightness brightness,
  String? fontFamily, {
  bool amoled = false,
}) {
```

(keep the rest of `_build` body as-is; pass `fontFamily: fontFamily,` to the `ThemeData(...)` constructor and replace the line-45 comment with `// P11: system default — fontFamily null unless Jakarta selected.`)

- [ ] **Step 5: Watch the provider in `app.dart`**

Inside the existing `build` (after `themeMode` watch):

```dart
final font = ref.watch(fontFamilyProvider).valueOrNull ?? AppFont.system;
final String? fontFamily =
    font == AppFont.jakarta ? 'PlusJakartaSans' : null;
```

and: `theme: warmPopLight(fontFamily: fontFamily)`, `warmPopDark(amoled: true, fontFamily: fontFamily)`, `warmPopDark(fontFamily: fontFamily)`; add import for `font_provider.dart`.

- [ ] **Step 6: Settings UI — font radios in APPEARANCE**

In `settings_screen.dart`, after the theme-radio `for` loop (after its trailing `const SizedBox(height: 8);`), add:

```dart
          // P11 font selector — same radio pattern as theme.
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 6),
            child: Text(
              'FONT',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: .08,
                color: t.accent,
              ),
            ),
          ),
          for (final font in AppFont.values) ...[
            RadioListTile<AppFont>(
              value: font,
              groupValue: currentFont,
              onChanged: (v) {
                if (v != null) {
                  ref.read(fontControllerProvider).setFont(v);
                }
              },
              secondary: Icon(font.icon, color: t.inkSoft, size: 20),
              controlAffinity: ListTileControlAffinity.trailing,
              title: Text(font.label,
                  style: const TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w600)),
              activeColor: t.accent,
              tileColor: t.surface,
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(WarmPopTokens.radiusMd),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            ),
            const SizedBox(height: 8),
          ],
```

Declare next to the existing `current` theme watch: `final currentFont = ref.watch(fontFamilyProvider).valueOrNull ?? AppFont.system;` + imports (`font_provider.dart`).

- [ ] **Step 7: Run tests to verify they pass**

Run: `flutter test test/font_provider_test.dart test/grep_gates_test.dart 2>&1 | tail -8`
Expected: PASS — round-trip + theme threading + gate 11 green.

- [ ] **Step 8: Full verification**

Run: `flutter analyze 2>&1 | grep -c "error •" && flutter test 2>&1 | tail -1`
Expected: `0` errors, `All tests passed` (suite grows by ≥3).

- [ ] **Step 9: Device proof + commit (STOP for PASS)**

`flutter run -d emulator-5554` → Settings → APPEARANCE → toggle FONT rows light + dark → capture `gap_font_settings_light.png`, `gap_font_settings_dark.png`, plus one chat screen in Jakarta (`gap_font_chat_jakarta.png`); Read-verify each; present → **STOP until user PASS** → then commit `[W3 Widget Gaps] Font selector — P11 Jakarta toggle on Drift settings`.

---

### Task 2: Capybara Tier-1 interactions (squash-on-tap + success bounce)

**Files:**
- Modify: `lib/features/mascot/capybara.dart`
- Test: `test/capybara_rig_test.dart` (append — file already covers idle/blink/reduced-motion)

**Interfaces:**
- Consumes: existing `_idle` controller pattern, `WarmPopTokens.mascotBreathe`, `MediaQuery.disableAnimationsOf`.
- Produces: `Capybara({..., int celebrateTick = 0})` — tap anywhere on the mascot plays a squash dip; incrementing `celebrateTick` plays one success bounce. Both park under reduced-motion.

- [ ] **Step 1: Write the failing tests** (append to `test/capybara_rig_test.dart`):

```dart
  testWidgets('squash-on-tap: scale dips below 1 mid-animation',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: Capybara())),
    ));
    final scaleFinder = find.byKey(const ValueKey('capy-scale'));
    expect(tester.widget<Transform>(scaleFinder).transform, Matrix4.identity());

    await tester.tap(scaleFinder);
    await tester.pump(const Duration(milliseconds: 60));
    final mid = tester.widget<Transform>(scaleFinder).transform;
    expect(mid.getMaxScaleOnAxis(), lessThan(1.0));

    await tester.pumpAndSettle();
    expect(tester.widget<Transform>(scaleFinder).transform,
        Matrix4.identity(), reason: 'settles back to rest');
  });

  testWidgets('celebrateTick increment plays one bounce (scale > 1)',
      (tester) async {
    var tick = 0;
    Widget build() => MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Capybara(celebrateTick: tick),
                    ElevatedButton(
                      onPressed: () => setState(() => tick++),
                      child: const Text('go'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
    await tester.pumpWidget(build());
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 60));
    final mid = tester
        .widget<Transform>(find.byKey(const ValueKey('capy-scale')))
        .transform;
    expect(mid.getMaxScaleOnAxis(), greaterThan(1.0));
    await tester.pumpAndSettle();
  });

  testWidgets('reduced motion: tap parks squash at rest scale',
      (tester) async {
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: const MaterialApp(
        home: Scaffold(body: Center(child: Capybara())),
      ),
    ));
    final scaleFinder = find.byKey(const ValueKey('capy-scale'));
    await tester.tap(scaleFinder);
    await tester.pump(const Duration(milliseconds: 60));
    expect(
        tester.widget<Transform>(scaleFinder).transform, Matrix4.identity());
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/capybara_rig_test.dart 2>&1 | tail -12`
Expected: RED — `capy-scale` key not found (`Finder: find.byKey(ValueKey('capy-scale'))`), all three new tests fail; existing idle/blink tests still pass.

- [ ] **Step 3: Implement in `capybara.dart`**

Add fields + controllers (same vsync/dispose discipline as `_idle`):

```dart
  /// Tier-1 squash-on-tap + success bounce (spec Mascot system).
  late final AnimationController _squash = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 240));
  late final AnimationController _bounce = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 360));

  void _onTap() {
    if (MediaQuery.disableAnimationsOf(context)) return;
    _squash.forward(from: 0);
  }
```

`didUpdateWidget`: `if (widget.celebrateTick != old.celebrateTick && widget.celebrateTick > 0 && !MediaQuery.disableAnimationsOf(context)) _bounce.forward(from: 0);`

Dispose both in `dispose()`. New param on the widget: `this.celebrateTick = 0` (doc: "increment to play one success bounce").

Build (wrap existing content):

```dart
    return RepaintBoundary(
      child: GestureDetector(
        onTap: _onTap,
        child: AnimatedBuilder(
          animation: Listenable.merge([_idle, _squash, _bounce]),
          builder: (context, _) {
            // dip on squash, rise on bounce, sine-shaped so both settle at 1
            final squash = sin(_squash.value * pi) * 0.12;
            final bounce = sin(_bounce.value * pi) * 0.12;
            final scale = 1.0 - squash + bounce;
            return Transform.scale(
              key: const ValueKey('capy-scale'),
              scale: scale,
              child: CustomPaint(
                size: widget.size,
                painter: CapybaraPainter(
                  mood: widget.mood,
                  blink: _blink,
                  breathe: _idle.value,
                  showKey: widget.showKey,
                ),
              ),
            );
          },
        ),
      ),
    );
```

(`import 'dart:math';` for `sin`/`pi`. Tap target grows to the paint size — acceptable; the widget is decorative.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/capybara_rig_test.dart 2>&1 | tail -6`
Expected: PASS — old idle/blink/reduced-motion tests + 3 new ones green.

- [ ] **Step 5: Full verification + STOP for PASS**

`flutter analyze` 0 errors, `flutter test` full green. Device: tap mascot in an EmptyState (or login) → capture squash mid-animation is timing-flaky; proof = `pumpAndSettle` tests + a steady-state tap capture; present test evidence → **STOP until PASS** → commit `[W3 Widget Gaps] Capybara Tier-1 — squash-on-tap + success bounce`.

---

### Task 3: Mascot placements — profile header + status banner

**Files:**
- Modify: `lib/features/profile/screens/profile_screen.dart` (header column, after `@username`)
- Modify: `lib/features/home/screens/home_screen.dart` (the `StatusBanner(` call site — add `leading:`)
- Test: `test/grep_gates_test.dart` (gate 12) + widget test in `test/widgets_batch2_test.dart` style if a standalone banner test exists; else append to `test/capybara_rig_test.dart`

**Interfaces:**
- Consumes: `Capybara` (Task 2 shape), `StatusBanner({message, leading, onRetry})` existing slot, profile header column at `profile_screen.dart:44-75`.
- Produces: no new APIs — composition only.

- [ ] **Step 1: Write the failing tests**

Append gate 12:

```dart
  // Gate 12: spec "Used in" placements wired (profile header + status banner).
  test('mascot placements: profile header + status banner leading', () {
    final profile =
        File('lib/features/profile/screens/profile_screen.dart').readAsStringSync();
    expect(profile.contains('Capybara('), isTrue,
        reason: 'spec: mascot used in profile header');
    final home = File('lib/features/home/screens/home_screen.dart')
        .readAsStringSync();
    expect(home.contains('StatusBanner('), isTrue);
    expect(home.contains('Capybara('), isTrue,
        reason: 'spec: mascot used as status-banner leading (composition '
            'proven by the widget test below)');
  });
```

Plus behavior test — append to `test/capybara_rig_test.dart` (banner renders leading without overflow):

```dart
  testWidgets('StatusBanner renders mascot leading without overflow',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: warmPopLight(),
      home: const Scaffold(
        body: StatusBanner(
          message: 'Offline — messages will send later',
          leading: Capybara(size: Size(40, 34)),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.byType(Capybara), findsOneWidget);
    expect(find.text('Offline — messages will send later'), findsOneWidget);
  });
```

(import `status_banner.dart` + `capybara.dart` + `warmPopLight` into the chosen test file.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/grep_gates_test.dart 2>&1 | tail -8`
Expected: gate 12 RED (no `Capybara(` in profile yet); banner test may pass already (leading slot exists) — gate is the RED driver for the wiring.

- [ ] **Step 3: Profile header placement**

After the `@${user.username}` Text block in the header Column (`profile_screen.dart` ~line 70), add:

```dart
            const SizedBox(height: 12),
            const Center(
              child: Capybara(size: Size(96, 82)),
            ),
```

plus import — profile is at `lib/features/profile/screens/`, so relative: `import '../../mascot/capybara.dart';` (canonical shape proven by `empty_state.dart:3`). Banner widget test in `capybara_rig_test.dart` needs two extra imports: `package:kuch_bhi/core/theme/app_theme.dart` (for `warmPopLight` — `context.t` throws on default MaterialApp theme) and `package:kuch_bhi/core/widgets/status_banner.dart`.

- [ ] **Step 4: Status banner placement**

At the `StatusBanner(` call in `home_screen.dart` (line 159), add:

```dart
          leading: const Capybara(size: Size(40, 34)),
```

(adjust indent to the call site; import Capybara). Banner strip grows ~10px taller — acceptable; `Expanded(message)` already tolerates leading.

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/grep_gates_test.dart test/capybara_rig_test.dart 2>&1 | tail -6`
Expected: PASS.

- [ ] **Step 6: Full verification + device proof + STOP for PASS**

`flutter analyze` 0 errors, full `flutter test` green. Device captures: Profile light + dark (`gap_profile_mascot_light.png`, `gap_profile_mascot_dark.png`); status banner only appears offline — trigger airplane mode OR verify via the widget test (ruling: widget-test proof accepted if banner is unreachable on emulator). Present → **STOP until PASS** → commit `[W3 Widget Gaps] Mascot placements — profile header + status banner leading`.

---

**End state:** ≤3 commits, suite ≥74 green, analyze 0, no purple, P11 font live, Tier-1 mascot interactions live, spec "Used in" list complete (minus nonexistent splash). Then Phase C (frame drops + D5).
