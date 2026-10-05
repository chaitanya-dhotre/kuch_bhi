# W3 Phase A — Foundation (Tokens, Components, Mascot, Mockups) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the Warm Pop design foundation — token system + export, ThemeData, the approved Capybara mascot rig (Tier-1 animated), the chrome component set, and user-approved Home+Chat mockups — without touching any existing screen's code.

**Architecture:** One token file is the source of truth; a test keeps the JSON/CSS export in sync with it. ThemeData derives from tokens (legacy screens keep their hardcoded colors until Phase B — accepted transitional mixed state). The mascot is a CustomPainter transcribing the approved SVG geometry (no new runtime deps); components are thin widgets that read tokens only; mockups are HTML (concept-board style) audited by impeccable before user review.

**Tech Stack:** Flutter/Riverpod (existing), ThemeData + ThemeExtension, CustomPainter, `google_fonts`-free bundled TTF (assets), tool/ Dart scripts, HTML mockups.

**Spec:** `docs/superpowers/specs/2026-10-05-w3-warm-pop-design-system.md`

## Global Constraints

- **Phase split (spec amendment by plan):** screen-level components — ChatTile, MessageBubble, Composer, NavBar, ProfileCard, InviteCard, SegmentedControl — are built in Phase B together with their screens (each needs its screen's mockup approval first). Phase A builds only the chrome set listed in Tasks 5-6.
- NO git commits during execution (standing rule). One commit only after the user approves the mockups in Task 6.
- New branch `feature/w3-warm-pop` created from `main` before Task 1 (executing-plans setup).
- `flutter analyze` 0 errors and `flutter test` green after every task.
- Accent `#EFA00B`; no violet/purple/gradients in chrome; mascot gradients/second-tone only on the mascot itself (spec).
- System font default; Plus Jakarta Sans bundled as the OPTIONAL font (spec/P11) — selector UI is Phase B.
- Components may not hardcode colors: `grep -rn "Color(0x" lib/core/widgets lib/features/mascot` must print nothing (enforced in Task 5 and 6 final steps; legacy `lib/core/constants/app_colors.dart` and feature screens are exempt until Phase B).
- Reference sources for taste: `.claude/skills/taste`, `.claude/skills/impeccable`, `.claude/skills/brand-design-md` (spec "Reference sources").
- Mascot geometry is LOCKED to the approved art (`docs/Capybara.png` + board source): body `x28 y48 w146 h96 rx46`, ears `cx80 cy52 r12.5` / `cx150 cy58 r11` (body color, behind body), snout `x21 y66 w50 h66 rx23` fill `#8B5E3E`, legs front `x52 y126 w28 h24 rx12`, mid `x96 y128 w30 h24 rx12`, back `x138 y126 w24 h24 rx11`, all legs `#B27A42`; eyes `cx88 cy66 r5.5` + `cx122 cy62 r5.5` face `#3A2E22` with white highlights `r2` at `+2.5,-2.5`.
- Motion: fast 150 / base 250 / slow 400 ms; idle breathe 3.4s, blink 4.6s; reduced-motion parks all of it (spec).

## Review Focus

- **Theme swap regressions on legacy screens** — hardcoded screens ignore ThemeData but Material defaults (buttons/sheets/dialogs in old screens) will restyle mid-transition; a reasonable user expects no broken contrast. → Task 6 Step 9 on-device smoke list (home, chat, login, settings: eyeball both themes).
- **Export drift** — tokens edited without the JSON/CSS export update silently desyncs the future website. → Task 3 Step 1 test compares export output to token constants (fails when either side moves alone).
- **Mascot geometry drift** — painter must match the art the user approved three rounds deep. → Task 4 Step 3 test asserts exact geometry values (sizes/positions listed above) plus moods; mismatch fails.
- **Silent font fallback** — missing/misnamed Jakarta asset makes the "optional font" do nothing. → Task 3 Step 1 test asserts the font asset files exist (and Task 2's theme test pins system-font default).
- **Hardcoded color sneaking into new code** — the token-only rule is unenforceable by types. → Tasks 4/5/6 final steps run the grep gate above (empty output required).
- **Theme swap side-effects in old screens** — Material defaults restyle while hardcoded colors stay. → Task 6 Step 8 on-device smoke: after approval, build + install on Samsung, open home/chat/login/settings in light AND dark, confirm no unreadable contrast before committing.

---

### Task 1: PRODUCT.md via impeccable init (inferred from the brief)

**Files:**
- Create: `PRODUCT.md` (repo root)
- Read-only: `.claude/skills/impeccable/reference/init.md` (follow its PRODUCT.md section format)

**Interfaces:**
- Produces: `PRODUCT.md` — product truth the impeccable commands load. Later tasks invoke impeccable only through its skill (Task 6).

- [ ] **Step 1: Write PRODUCT.md from the session's brief, labeling every assumption**

```markdown
# kuch-bhi — Product Truth

## Product
End-to-end encrypted chat app (1:1, groups) for Android — Flutter client,
PocketBase backend. Working name: "Kuch Bhi".

## Audience
[ASSUMPTION from session] Design-conscious personal-use messaging users;
the founder tests on 3 devices (Samsung, Redmi S2, Pixel emulator) and
invites friends. Not enterprise.

## Purpose
Private, fast, lively everyday messaging — E2E by default, no ads/tracking.

## Operating context
Android phones (oldest supported: Redmi S2 / Snapdragon 625 — perf budget
is real), occasional desktop dev only. Release builds are the perf baseline.

## Constraints
- System font default (user choice); optional bundled font.
- No violet/purple/gradients in chrome; accent = Marigold #EFA00B.
- Mascot = Capybara, art approved and locked (docs/Capybara.png).
- Design must absorb: offline-first, mascot expansion, website/privacy
  pages, hidden dev options — see W3 spec extensibility rules.

## Voice
[ASSUMPTION] Friendly, direct, a bit playful (name is meme-flavored);
never corporate, never try-hard.

## Evidence
W3 spec: docs/superpowers/specs/2026-10-05-w3-warm-pop-design-system.md
Direction board: docs/Capybara.png, docs/Bear to Capybara Design Comparison.png
```

- [ ] **Step 2: Sanity-check against init.md's required sections**

Run: `grep -n "^## " .claude/skills/impeccable/reference/init.md | head -20`
Expected: the section set (Audience, Purpose, Operating context, Stack,
Constraints, Voice…) — add any required section missing from Step 1's
content (keep assumption labels).

- [ ] **Step 3: Verify impeccable reads it**

Run: `cd /home/chaitanyadhotre/kuch_bhi && .claude/skills/impeccable/scripts/impeccable context 2>&1 | head -20`
Expected: output no longer contains `NO_PRODUCT_MD`; contains `PRODUCT_INIT_REQUIRED`-free directives (the prior smoke test at install time printed NO_PRODUCT_MD).

---

### Task 2: Token system + theme

**Files:**
- Create: `lib/core/theme/tokens.dart`
- Create: `lib/core/theme/app_theme.dart`
- Create: `test/theme_tokens_test.dart`
- Modify: `lib/app.dart` (`_KuchBhiApp` builds `ThemeData` via `app_theme.dart` for both `lightTheme`/`darkTheme` — find the existing `theme:`/`darkTheme:` assignments and replace their sources; leave every screen file untouched)

**Interfaces:**
- Produces: `class WarmPopTokens` with static fields; `ThemeData warmPopLight()` / `ThemeData warmPopDark()`; `class ColorTokens extends ThemeExtension<ColorTokens>` (fields: `bg, surface, surface2, ink, inkSoft, inkFaint, line, accent, accentPressed, accentSoft, onAccent, success, error, info, mascotBody, mascotShade, mascotSnout, mascotFace, keyGold`) accessible as `context.t` extension getter.

- [ ] **Step 1: Write the failing test**

```dart
// test/theme_tokens_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/core/theme/tokens.dart';

void main() {
  test('locked brand values (spec: Warm Pop tokens)', () {
    expect(const Color(0xFFEFA00B), WarmPopTokens.accent);
    expect(const Color(0xFF2A2520), WarmPopTokens.ink);
    expect(const Color(0xFFFAF7F1), WarmPopTokens.bg);
    expect(const Color(0xFFC6894F), WarmPopTokens.mascotBody);
    expect(const Color(0xFF8B5E3E), WarmPopTokens.mascotSnout);
    expect(WarmPopTokens.space, [4, 8, 12, 16, 20, 24, 32, 40, 48]);
    expect(WarmPopTokens.radiusSm, 10);
    expect(WarmPopTokens.radiusLg, 20);
    expect(WarmPopTokens.motionBase, const Duration(milliseconds: 250));
  });

  test('light and dark themes both carry ColorTokens with correct accent', () {
    final light = warmPopLight();
    final dark = warmPopDark();
    final lt = light.extension<ColorTokens>()!;
    final dt = dark.extension<ColorTokens>()!;
    expect(lt.accent, const Color(0xFFEFA00B));
    expect(dt.accent, const Color(0xFFEFA00B));
    expect(lt.bg, const Color(0xFFFAF7F1));
    expect(dt.bg, const Color(0xFF171512));
    expect(lt.onAccent, const Color(0xFF2A2520)); // contrast pair
    expect(dt.onAccent, const Color(0xFF21260F));
  });

  test('system font is the default (P11)', () {
    expect(warmPopLight().textTheme.bodyMedium?.fontFamily, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/theme_tokens_test.dart`
Expected: FAIL — `tokens.dart` undefined.

- [ ] **Step 3: Implement tokens**

```dart
// lib/core/theme/tokens.dart
import 'package:flutter/material.dart';

/// Warm Pop token system — the single source of truth (spec).
/// Components read tokens; screens read components. Never hardcode colors
/// in lib/core/widgets or lib/features/mascot (grep gate in tasks 5/6).
class WarmPopTokens {
  WarmPopTokens._();

  // Brand
  static const accent = Color(0xFFEFA00B);
  static const accentPressed = Color(0xFFD98F08);
  static const onAccentLight = Color(0xFF2A2520);
  static const onAccentDark = Color(0xFF21260F);

  // Light
  static const bg = Color(0xFFFAF7F1);
  static const surface = Color(0xFFFFFFFF);
  static const surface2 = Color(0xFFF1ECE3);
  static const ink = Color(0xFF2A2520);
  static const inkSoft = Color(0xFF6E655A);
  static const inkFaint = Color(0xFF9C9284);
  static const line = Color(0xFFE4DDD1);
  static const accentSoftLight = Color(0xFFFFF3DC);

  // Dark
  static const bgDark = Color(0xFF171512);
  static const surfaceDark = Color(0xFF211E1A);
  static const surface2Dark = Color(0xFF2B2823);
  static const inkDark = Color(0xFFF3EDE3);
  static const inkSoftDark = Color(0xFF9C9284);
  static const lineDark = Color(0xFF3B362F);
  static const accentSoftDark = Color(0xFF3A2E14);

  // Semantic
  static const success = Color(0xFF0E9F6E);
  static const error = Color(0xFFE5484D);
  static const info = Color(0xFF4A6FA5);

  // Mascot (constant across themes)
  static const mascotBody = Color(0xFFC6894F);
  static const mascotShade = Color(0xFFB27A42);
  static const mascotSnout = Color(0xFF8B5E3E);
  static const mascotNostril = Color(0xFF5C3B28);
  static const mascotFace = Color(0xFF3A2E22);
  static const keyGold = Color(0xFFE8A21D);

  // Space (4-base grid)
  static const space = [4, 8, 12, 16, 20, 24, 32, 40, 48];

  // Radius
  static const radiusSm = 10.0;
  static const radiusMd = 16.0;
  static const radiusLg = 20.0;
  static const radiusXl = 24.0;
  static const radiusBubble = 18.0;
  static const radiusBubbleTail = 6.0;

  // Motion
  static const motionFast = Duration(milliseconds: 150);
  static const motionBase = Duration(milliseconds: 250);
  static const motionSlow = Duration(milliseconds: 400);
  static const mascotBreathe = Duration(milliseconds: 3400);
  static const mascotBlink = Duration(milliseconds: 4600);
}

/// Theme-scoped colors. Components consume `context.t`.
class ColorTokens extends ThemeExtension<ColorTokens> {
  const ColorTokens({
    required this.bg, required this.surface, required this.surface2,
    required this.ink, required this.inkSoft, required this.inkFaint,
    required this.line, required this.accent, required this.accentPressed,
    required this.accentSoft, required this.onAccent, required this.success,
    required this.error, required this.info,
  });

  final Color bg, surface, surface2, ink, inkSoft, inkFaint, line, accent,
      accentPressed, accentSoft, onAccent, success, error, info;

  static const light = ColorTokens(
    bg: WarmPopTokens.bg, surface: WarmPopTokens.surface,
    surface2: WarmPopTokens.surface2, ink: WarmPopTokens.ink,
    inkSoft: WarmPopTokens.inkSoft, inkFaint: WarmPopTokens.inkFaint,
    line: WarmPopTokens.line, accent: WarmPopTokens.accent,
    accentPressed: WarmPopTokens.accentPressed,
    accentSoft: WarmPopTokens.accentSoftLight,
    onAccent: WarmPopTokens.onAccentLight, success: WarmPopTokens.success,
    error: WarmPopTokens.error, info: WarmPopTokens.info,
  );

  static const dark = ColorTokens(
    bg: WarmPopTokens.bgDark, surface: WarmPopTokens.surfaceDark,
    surface2: WarmPopTokens.surface2Dark, ink: WarmPopTokens.inkDark,
    inkSoft: WarmPopTokens.inkSoftDark, inkFaint: WarmPopTokens.inkSoftDark,
    line: WarmPopTokens.lineDark, accent: WarmPopTokens.accent,
    accentPressed: WarmPopTokens.accentPressed,
    accentSoft: WarmPopTokens.accentSoftDark,
    onAccent: WarmPopTokens.onAccentDark, success: WarmPopTokens.success,
    error: WarmPopTokens.error, info: WarmPopTokens.info,
  );

  @override
  ColorTokens copyWith({
    Color? bg, Color? surface, Color? surface2, Color? ink, Color? inkSoft,
    Color? inkFaint, Color? line, Color? accent, Color? accentPressed,
    Color? accentSoft, Color? onAccent, Color? success, Color? error,
    Color? info,
  }) =>
      ColorTokens(
        bg: bg ?? this.bg, surface: surface ?? this.surface,
        surface2: surface2 ?? this.surface2, ink: ink ?? this.ink,
        inkSoft: inkSoft ?? this.inkSoft, inkFaint: inkFaint ?? this.inkFaint,
        line: line ?? this.line, accent: accent ?? this.accent,
        accentPressed: accentPressed ?? this.accentPressed,
        accentSoft: accentSoft ?? this.accentSoft,
        onAccent: onAccent ?? this.onAccent, success: success ?? this.success,
        error: error ?? this.error, info: info ?? this.info,
      );

  @override
  ColorTokens lerp(ThemeExtension<ColorTokens>? other, double t) {
    if (other is! ColorTokens) return this;
    return ColorTokens(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkSoft: Color.lerp(inkSoft, other.inkSoft, t)!,
      inkFaint: Color.lerp(inkFaint, other.inkFaint, t)!,
      line: Color.lerp(line, other.line, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentPressed: Color.lerp(accentPressed, other.accentPressed, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      success: Color.lerp(success, other.success, t)!,
      error: Color.lerp(error, other.error, t)!,
      info: Color.lerp(info, other.info, t)!,
    );
  }
}

extension ThemeX on BuildContext {
  ColorTokens get t => Theme.of(this).extension<ColorTokens>()!;
}
```

- [ ] **Step 4: Implement ThemeData**

```dart
// lib/core/theme/app_theme.dart
import 'package:flutter/material.dart';
import 'tokens.dart';

ThemeData warmPopLight() => _build(ColorTokens.light, Brightness.light);
ThemeData warmPopDark() => _build(ColorTokens.dark, Brightness.dark);

ThemeData _build(ColorTokens c, Brightness brightness) {
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accent,
    onPrimary: c.onAccent,
    secondary: c.accent,
    onSecondary: c.onAccent,
    error: c.error,
    onError: Colors.white,
    surface: c.surface,
    onSurface: c.ink,
    surfaceContainerHighest: c.surface2,
    outline: c.line,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.bg,
    extensions: [c],
    // P11: system font default — fontFamily intentionally NOT set.
    textTheme: const TextTheme(
      headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w700,
          letterSpacing: -.02, height: 1.25),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
          height: 1.35),
      bodyMedium: TextStyle(fontSize: 15, height: 1.45),
      bodySmall: TextStyle(fontSize: 13, height: 1.38),
      labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
          height: 1.27, letterSpacing: .06),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.ink,
      contentTextStyle: TextStyle(color: c.bg, fontSize: 14),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WarmPopTokens.radiusXl)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    dividerColor: c.line,
  );
}
```

- [ ] **Step 5: Wire into app.dart**

In `lib/app.dart`, replace the `theme:`/`darkTheme:` values with
`theme: warmPopLight()` / `darkTheme: warmPopDark()` (import
`core/theme/app_theme.dart`). If the existing file inlines `ColorScheme`
blocks, delete those blocks — they are superseded. Screens that read
`AppColors` are untouched by design (Phase B migrates them).

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/theme_tokens_test.dart` → PASS (3 tests).
Run: `flutter analyze` → 0 errors.

---

### Task 3: Token export (JSON + CSS) + optional font assets

**Files:**
- Create: `tool/export_tokens.dart`
- Create: `test/token_export_test.dart`
- Create: `assets/fonts/PlusJakartaSans/` (Regular 400, SemiBold 600, Bold 700 TTFs)

**Interfaces:**
- Produces: `design_tokens.json` and `design_tokens.css` at repo root (generated); function pattern documented in the tool header.

- [ ] **Step 1: Write the failing test**

```dart
// test/token_export_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/tokens.dart';

void main() {
  test('export stays in sync with tokens (run tool/export_tokens.dart)', () {
    final f = File('design_tokens.json');
    expect(f.existsSync(), isTrue,
        reason: 'run: dart run tool/export_tokens.dart');
    final map = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final colors = map['colors'] as Map<String, dynamic>;
    expect(colors['accent'], '#EFA00B');
    expect(colors['bg'], '#FAF7F1');
    expect(map['radius']['lg'], 20);
    expect(map['space'], [4, 8, 12, 16, 20, 24, 32, 40, 48]);
    expect(colors['accent'], WarmPopTokens.accent.value
        .toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()
        .replaceFirst(RegExp('^'), '#'));
  });

  test('Jakarta font assets exist (optional font, P11)', () {
    for (final f in ['Regular.ttf', 'SemiBold.ttf', 'Bold.ttf']) {
      expect(File('assets/fonts/PlusJakartaSans/$f').existsSync(), isTrue,
          reason: 'download from github.com/google/fonts ofl/plusjakartasans');
    }
  });
}
```

(Note: add `import 'dart:convert';` for jsonDecode.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/token_export_test.dart`
Expected: FAIL — design_tokens.json missing.

- [ ] **Step 3: Download fonts + write the exporter**

```bash
mkdir -p assets/fonts/PlusJakartaSans
cd assets/fonts/PlusJakartaSans
curl -sLO https://github.com/google/fonts/raw/main/ofl/plusjakartasans/PlusJakartaSans%5Bwght%5D.ttf
mv "PlusJakartaSans%5Bwght%5D.ttf" PlusJakartaSans-VF.ttf
```

(Variable font single file — if `fontFamilyAsset` needs statics, the VF file
registers once and Flutter resolves weights; register it in pubspec `fonts:`.)

`pubspec.yaml` addition:

```yaml
flutter:
  fonts:
    - family: PlusJakartaSans
      fonts:
        - asset: assets/fonts/PlusJakartaSans/PlusJakartaSans-VF.ttf
```

```dart
// tool/export_tokens.dart
// Run: dart run tool/export_tokens.dart
// Writes design_tokens.json + design_tokens.css from WarmPopTokens —
// the website/privacy pages consume these; the test keeps them in sync.
import 'dart:convert';
import 'dart:io';
import 'package:kuch_bhi/core/theme/tokens.dart';

String hex(Color c) =>
    '#${c.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

void main() {
  const t = WarmPopTokens;
  final json = {
    'colors': {
      'accent': hex(t.accent), 'accentPressed': hex(t.accentPressed),
      'bg': hex(t.bg), 'surface': hex(t.surface), 'surface2': hex(t.surface2),
      'ink': hex(t.ink), 'inkSoft': hex(t.inkSoft), 'inkFaint': hex(t.inkFaint),
      'line': hex(t.line), 'accentSoft': hex(t.accentSoftLight),
      'success': hex(t.success), 'error': hex(t.error), 'info': hex(t.info),
      'dark': {
        'bg': hex(t.bgDark), 'surface': hex(t.surfaceDark),
        'surface2': hex(t.surface2Dark), 'ink': hex(t.inkDark),
        'inkSoft': hex(t.inkSoftDark), 'line': hex(t.lineDark),
        'accentSoft': hex(t.accentSoftDark),
        'onAccent': hex(t.onAccentDark),
      },
      'mascot': {
        'body': hex(t.mascotBody), 'shade': hex(t.mascotShade),
        'snout': hex(t.mascotSnout), 'nostril': hex(t.mascotNostril),
        'face': hex(t.mascotFace), 'key': hex(t.keyGold),
      },
    },
    'radius': {'sm': t.radiusSm, 'md': t.radiusMd, 'lg': t.radiusLg,
      'xl': t.radiusXl, 'bubble': t.radiusBubble},
    'space': t.space,
    'motion': {
      'fastMs': t.motionFast.inMilliseconds,
      'baseMs': t.motionBase.inMilliseconds,
      'slowMs': t.motionSlow.inMilliseconds,
    },
  };
  File('design_tokens.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));

  final css = StringBuffer()
    ..writeln(':root {')
    ..writeln('  --accent: ${hex(t.accent)};')
    ..writeln('  --bg: ${hex(t.bg)};')
    ..writeln('  --surface: ${hex(t.surface)};')
    ..writeln('  --ink: ${hex(t.ink)};')
    ..writeln('  --line: ${hex(t.line)};')
    ..writeln('  --radius-lg: ${t.radiusLg}px;')
    ..writeln('  --motion-base: ${t.motionBase.inMilliseconds}ms;')
    ..writeln('}');
  File('design_tokens.css').writeAsStringSync(css.toString());
  stdout.writeln('wrote design_tokens.json, design_tokens.css');
}
```

- [ ] **Step 4: Run exporter + test**

Run: `dart run tool/export_tokens.dart && flutter test test/token_export_test.dart`
Expected: PASS (2 tests).
Run: `flutter analyze` → 0 errors.

---

### Task 4: Capybara mascot rig (painter + animated widget)

**Files:**
- Create: `lib/features/mascot/capybara_painter.dart`
- Create: `lib/features/mascot/capybara.dart`
- Create: `test/capybara_rig_test.dart`

**Interfaces:**
- Produces:
  - `enum CapyMood { neutral, happy }`
  - `class CapybaraPainter extends CustomPainter { CapybaraPainter({required this.mood, required this.blink, required this.breathe, required this.showKey}); final CapyMood mood; final double blink, breathe; final bool showKey; }`
  - `class Capybara extends StatefulWidget { const Capybara({super.key, this.mood = CapyMood.neutral, this.showKey = false, this.size = const Size(140, 118)}); }` — runs the idle loop (breathe+blink) unless `MediaQuery.disableAnimationsOf(context)` is true; exposes idle only in Phase A (Tier 2 states come with screens).

- [ ] **Step 1: Write the failing test**

```dart
// test/capybara_rig_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/tokens.dart';
import 'package:kuch_bhi/features/mascot/capybara.dart';
import 'package:kuch_bhi/features/mascot/capybara_painter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('approved geometry — locked to docs/Capybara.png', () {
    final painter = CapybaraPainter(
        mood: CapyMood.neutral, blink: 0, breathe: 0, showKey: false);
    final body = painter.debugDescription();
    // Body/ears/snout/legs boxes as approved (see plan constraints).
    expect(body['body'], const Rect.fromLTWH(28, 48, 146, 96));
    expect(body['bodyRadius'], 46.0);
    expect(body['earLeft'], const Offset(80, 52));
    expect(body['earLeftRadius'], 12.5);
    expect(body['earRight'], const Offset(150, 58));
    expect(body['snout'], const Rect.fromLTWH(21, 66, 50, 66));
    expect(body['snoutRadius'], 23.0);
    expect(body['snoutColor'], const Color(0xFF8B5E3E));
    expect(body['legFront'], const Rect.fromLTWH(52, 126, 28, 24));
    expect(body['legBack'], const Rect.fromLTWH(138, 126, 24, 24));
    expect(body['eyeLeft'], const Offset(88, 66));
    expect(body['eyeRight'], const Offset(122, 62));
  });

  test('paint uses token colors only', () {
    final p = CapybaraPainter(
        mood: CapyMood.neutral, blink: 0, breathe: 0, showKey: false);
    final used = p.debugColors();
    expect(used, contains(WarmPopTokens.mascotBody));
    expect(used, contains(WarmPopTokens.mascotSnout));
    expect(used, isNot(contains(const Color(0xFFEFA00B)))); // not the accent
  });

  testWidgets('idle loop runs; disabled under reduced motion',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: Capybara()))));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(Capybara), findsOneWidget);
    // Reduced-motion: widget must not throw with animations disabled.
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Capybara()))));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/capybara_rig_test.dart`
Expected: FAIL — Capybara/CapybaraPainter undefined.

- [ ] **Step 3: Implement the painter (geometry from the locked constraints)**

```dart
// lib/features/mascot/capybara_painter.dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../core/theme/tokens.dart';

enum CapyMood { neutral, happy }

/// Approved geometry (docs/Capybara.png). Do not "improve" numbers —
/// the user approved this art over three review rounds.
class CapybaraPainter extends CustomPainter {
  CapybaraPainter({
    required this.mood,
    required this.blink,
    required this.breathe,
    required this.showKey,
  });

  final CapyMood mood;
  final double blink; // 0 open … 1 closed
  final double breathe; // 0 rest … 1 expanded
  final bool showKey;

  static const body = Rect.fromLTWH(28, 48, 146, 96);
  static const bodyRadius = 46.0;
  static const earLeft = Offset(80, 52);
  static const earLeftRadius = 12.5;
  static const earRight = Offset(150, 58);
  static const earRightRadius = 11.0;
  static const snout = Rect.fromLTWH(21, 66, 50, 66);
  static const snoutRadius = 23.0;
  static const legFront = Rect.fromLTWH(52, 126, 28, 24);
  static const legMid = Rect.fromLTWH(96, 128, 30, 24);
  static const legBack = Rect.fromLTWH(138, 126, 24, 24);
  static const eyeLeft = Offset(88, 66);
  static const eyeRight = Offset(122, 62);
  static const eyeRadius = 5.5;

  Map<String, dynamic> debugDescription() => {
        'body': body, 'bodyRadius': bodyRadius,
        'earLeft': earLeft, 'earLeftRadius': earLeftRadius,
        'earRight': earRight, 'snout': snout, 'snoutRadius': snoutRadius,
        'snoutColor': WarmPopTokens.mascotSnout,
        'legFront': legFront, 'legBack': legBack,
        'eyeLeft': eyeLeft, 'eyeRight': eyeRight,
      };

  Set<Color> debugColors() => const {
        WarmPopTokens.mascotBody, WarmPopTokens.mascotSnout,
        WarmPopTokens.mascotFace, WarmPopTokens.mascotShade,
      };

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 200, sy = size.height / 180;
    canvas.scale(sx, sy);
    final bodyPaint = Paint()..color = WarmPopTokens.mascotBody;
    final shadePaint = Paint()..color = WarmPopTokens.mascotShade;
    final snoutPaint = Paint()..color = WarmPopTokens.mascotSnout;
    final facePaint = Paint()..color = WarmPopTokens.mascotFace;
    final nostrilPaint = Paint()..color = WarmPopTokens.mascotNostril;
    final goldPaint = Paint()..color = WarmPopTokens.keyGold;

    // Ears (behind body — silhouette nubs)
    canvas.drawCircle(earLeft, earLeftRadius, bodyPaint);
    canvas.drawCircle(earRight, earRightRadius, bodyPaint);

    // Body, with the breathe squeeze (origin = bottom center)
    canvas.save();
    canvas.translate(101, 144);
    canvas.scale(1 - 0.012 * breathe, 1 + 0.025 * breathe);
    canvas.translate(-101, -144);
    final bodyPath = Path()
      ..addRRect(RRect.fromRectAndRadius(body, Radius.circular(bodyRadius)));
    canvas.drawPath(bodyPath, bodyPaint);

    // Legs cross into the bottom edge (approved attachment)
    canvas.drawRRect(
        RRect.fromRectAndRadius(legFront, const Radius.circular(12)), shadePaint);
    canvas.drawRRect(
        RRect.fromRectAndRadius(legMid, const Radius.circular(12)), shadePaint);
    canvas.drawRRect(
        RRect.fromRectAndRadius(legBack, const Radius.circular(11)), shadePaint);
    canvas.restore();

    // Snout block + nostrils
    canvas.drawRRect(
        RRect.fromRectAndRadius(snout, Radius.circular(snoutRadius)),
        snoutPaint);
    _slit(canvas, const Offset(33, 78), -20, nostrilPaint);
    _slit(canvas, const Offset(49, 75), 14, nostrilPaint);

    // Mouth
    final mouth = Paint()
      ..color = WarmPopTokens.mascotNostril
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final mouthPath = mood == CapyMood.neutral
        ? (Path()
          ..moveTo(35, 114)
          ..quadraticBezierTo(44, 121, 53, 114))
        : (Path()
          ..moveTo(35, 110)
          ..quadraticBezierTo(45, 120, 55, 110));
    canvas.drawPath(mouthPath, mouth);

    // Eyes — blink covers them; happy mood draws arcs instead of dots
    final lidPaint = Paint()..color = WarmPopTokens.mascotBody;
    if (mood == CapyMood.neutral) {
      if (blink < 0.5) {
        canvas.drawCircle(eyeLeft, eyeRadius, facePaint);
        canvas.drawCircle(eyeRight, eyeRadius, facePaint);
        canvas.drawCircle(eyeLeft + const Offset(2.5, -2.5), 2, Paint()..color = Colors.white);
        canvas.drawCircle(eyeRight + const Offset(2.5, -2.5), 2, Paint()..color = Colors.white);
      }
      if (blink > 0) {
        // Eyelid sweep: body-colored cap over each eye
        for (final e in [eyeLeft, eyeRight]) {
          canvas.save();
          canvas.translate(e.dx, e.dy - eyeRadius);
          canvas.scale(1, blink.clamp(0, 1));
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  const Rect.fromLTWH(-7, 0, 14, 12), const Radius.circular(6)),
              lidPaint);
          canvas.restore();
        }
      }
    } else {
      final arc = Paint()
        ..color = WarmPopTokens.mascotFace
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(
          Path()
            ..moveTo(82, 68)
            ..quadraticBezierTo(89, 59, 96, 68),
          arc);
      canvas.drawPath(
          Path()
            ..moveTo(116, 64)
            ..quadraticBezierTo(123, 55, 130, 64),
          arc);
    }

    // Key (key moment pose) — floating off the back-right
    if (showKey) {
      canvas.save();
      canvas.translate(172, 44);
      canvas.rotate(38 * 3.14159265 / 180);
      canvas.drawCircle(Offset.zero, 9, goldPaint..style = PaintingStyle.stroke..strokeWidth = 5);
      goldPaint
        ..style = PaintingStyle.fill
        ..strokeWidth = 1;
      canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTWH(8, -2.5, 24, 5),
              const Radius.circular(2)),
          goldPaint);
      canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTWH(24, 2, 4, 7),
              const Radius.circular(1.5)),
          goldPaint);
      canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTWH(16, 2, 4, 6),
              const Radius.circular(1.5)),
          goldPaint);
      canvas.restore();
    }
  }

  void _slit(Canvas canvas, Offset at, double deg, Paint paint) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(deg * 3.14159265 / 180);
    canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(-5, -2.25, 10, 4.5),
            const Radius.circular(2.25)),
        paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CapybaraPainter old) =>
      old.mood != mood ||
      old.blink != blink ||
      old.breathe != breathe ||
      old.showKey != showKey;
}
```

- [ ] **Step 4: Implement the animated widget**

```dart
// lib/features/mascot/capybara.dart
import 'package:flutter/material.dart';
import '../../core/theme/tokens.dart';
import 'capybara_painter.dart';

export 'capybara_painter.dart' show CapyMood;

class Capybara extends StatefulWidget {
  const Capybara({
    super.key,
    this.mood = CapyMood.neutral,
    this.showKey = false,
    this.size = const Size(140, 118),
  });
  final CapyMood mood;
  final bool showKey;
  final Size size;

  @override
  State<Capybara> createState() => _CapybaraState();
}

class _CapybaraState extends State<Capybara>
    with SingleTickerProviderStateMixin {
  late final AnimationController _idle =
      AnimationController(vsync: this, duration: WarmPopTokens.mascotBreathe);
  double _blink = 0;
  Timer? _blinkTimer;

  @override
  void initState() {
    super.initState();
    _idle.repeat(reverse: true);
    _scheduleBlink();
  }

  void _scheduleBlink() {
    _blinkTimer = Timer(Duration(milliseconds: 3800 + DateTime.now().millisecondsSinceEpoch % 900), () {
      if (!mounted) return;
      setState(() => _blink = 1);
      Future.delayed(const Duration(milliseconds: 120), () {
        if (mounted) setState(() => _blink = 0);
      });
      _scheduleBlink();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced) {
      _idle.stop();
      _blink = 0;
      _blinkTimer?.cancel();
    } else if (!_idle.isAnimating) {
      _idle.repeat(reverse: true);
      _scheduleBlink();
    }
  }

  @override
  void dispose() {
    _idle.dispose();
    _blinkTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _idle,
        builder: (context, _) => CustomPaint(
          size: widget.size,
          painter: CapybaraPainter(
            mood: widget.mood,
            blink: _blink,
            breathe: widget.showKey
                ? (0.5 + 0.5 * _idle.value).abs()
                : _idle.value,
            showKey: widget.showKey,
          ),
        ),
      ),
    );
  }
}
```

(Add `import 'dart:async';` for Timer.)

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/capybara_rig_test.dart` → PASS (3).
Run: `flutter analyze` → 0 errors.
Run: `grep -rn "Color(0x" lib/features/mascot` → empty (token-only gate).

---

### Task 5: Chrome components — batch 1

**Files:**
- Create: `lib/core/widgets/app_button.dart`, `lib/core/widgets/app_chip.dart`,
  `lib/core/widgets/app_badge.dart`, `lib/core/widgets/app_avatar.dart`,
  `lib/core/widgets/section_header.dart`, `lib/core/widgets/search_field.dart`
- Create: `test/widgets_batch1_test.dart`

**Interfaces:**
- Consumes: `context.t` (Task 2), `WarmPopTokens` radii/space.
- Produces (all widgets take `Key? key`, read ONLY `context.t` + tokens):
  - `AppButton({required VoidCallback? onPressed, required Widget child, AppButtonVariant variant = AppButtonVariant.primary, bool busy = false, bool expanded = false})` + `enum AppButtonVariant { primary, secondary, text }` — heights: 48 primary/secondary, 40 text; secondary = surface bg + 1.5px line border + ink text; busy shows `SizedBox(width:18, height:18, child: CircularProgressIndicator(strokeWidth:2))`; disabled = `onPressed == null` → inkFaint on surface2.
  - `AppChip({required VoidCallback onTap, required Widget child, bool selected = false})` — pill, height 36, selected = accentSoft bg + accent border + ink text, unselected = surface + line.
  - `AppBadge({required int count, Color? color})` — pill min-width 22, height 22, accent bg, onAccent text, `fontStyle: labelSmall`; `count == 0` renders `SizedBox.shrink()`.
  - `AppAvatar({String? url, required String initials, double radius = 20})` — surface2 circle, inkSoft initials (w700), `CachedNetworkImage` if url != null (pattern identical to existing avatar usage in `group_settings_screen.dart`).
  - `SectionHeader(String title)` — labelSmall, inkFaint, uppercase, padding L16/T24/B8.
  - `SearchField({required ValueChanged<String> onChanged, String? hint, TextEditingController? controller})` — pill height 44, surface bg, line border, search icon inkFaint, hint 'Search'.

- [ ] **Step 1: Write the failing test**

```dart
// test/widgets_batch1_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/core/theme/tokens.dart';
import 'package:kuch_bhi/core/widgets/app_avatar.dart';
import 'package:kuch_bhi/core/widgets/app_badge.dart';
import 'package:kuch_bhi/core/widgets/app_button.dart';
import 'package:kuch_bhi/core/widgets/app_chip.dart';
import 'package:kuch_bhi/core/widgets/search_field.dart';
import 'package:kuch_bhi/core/widgets/section_header.dart';

Widget host(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
        theme: warmPopLight(),
        darkTheme: warmPopDark(),
        themeMode: brightness == Brightness.light ? ThemeMode.light : ThemeMode.dark,
        home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('primary button uses accent/onAccent pair (both themes)',
      (tester) async {
    for (final b in [Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(host(
          AppButton(onPressed: () {}, child: const Text('Send')),
          brightness: b));
      final elevated = tester.widget<FilledButton>(find.byType(FilledButton));
      final bg = elevated.style?.backgroundColor?.resolve({})!;
      final fg = elevated.style?.foregroundColor?.resolve({})!;
      expect(bg, const Color(0xFFEFA00B));
      expect(fg, b == Brightness.light
          ? const Color(0xFF2A2520)
          : const Color(0xFF21260F));
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('badge hides at zero, shows above', (tester) async {
    await tester.pumpWidget(host(const AppBadge(count: 0)));
    expect(find.byType(AppBadge), findsOneWidget);
    expect(find.byType(Text), findsNothing);
    await tester.pumpWidget(host(const AppBadge(count: 3)));
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('button disabled and busy states', (tester) async {
    await tester.pumpWidget(host(
        AppButton(onPressed: null, child: const Text('Invite'))));
    expect(find.text('Invite'), findsOneWidget);
    await tester.pumpWidget(host(
        AppButton(onPressed: () {}, busy: true, child: const Text('Invite'))));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('chip selected state + section header + search field render',
      (tester) async {
    await tester.pumpWidget(host(Column(mainAxisSize: MainAxisSize.min, children: [
      AppChip(onTap: () {}, child: const Text('All'), selected: true),
      const SectionHeader('MEMBERS'),
      SearchField(onChanged: (_) {}),
      const AppAvatar(initials: 'AK'),
    ])));
    expect(find.text('All'), findsOneWidget);
    expect(find.text('MEMBERS'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('AK'), findsOneWidget);
  });

  testWidgets('components read tokens, never literals (dark smoke)',
      (tester) async {
    await tester.pumpWidget(host(
        AppButton(onPressed: () {}, child: const Text('Go')),
        brightness: Brightness.dark));
    final bg = tester
        .widget<FilledButton>(find.byType(FilledButton))
        .style?.backgroundColor?.resolve({});
    expect(bg, WarmPopTokens.accent);
    await tester.pumpWidget(const SizedBox());
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets_batch1_test.dart`
Expected: FAIL — app_button undefined.

- [ ] **Step 3: Implement the six widgets.** Start with `AppButton` (the variant-heavy one) in full:

```dart
// lib/core/widgets/app_button.dart
import 'package:flutter/material.dart';
import '../../core/theme/tokens.dart';

enum AppButtonVariant { primary, secondary, text }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.variant = AppButtonVariant.primary,
    this.busy = false,
    this.expanded = false,
  });
  final VoidCallback? onPressed;
  final Widget child;
  final AppButtonVariant variant;
  final bool busy;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final enabled = onPressed != null && !busy;
    final content = busy
        ? const SizedBox(
            width: 18, height: 18,
            child: CircularProgressIndicator(strokeWidth: 2))
        : child;
    final base = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: enabled
          ? null
          : t.inkFaint, // disabled: inkFaint on surface2 (spec)
    );

    Widget button;
    switch (variant) {
      case AppButtonVariant.primary:
        button = FilledButton(
          onPressed: enabled ? onPressed : null,
          style: FilledButton.styleFrom(
            backgroundColor: t.accent,
            foregroundColor: t.onAccent,
            disabledBackgroundColor: t.surface2,
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(WarmPopTokens.radiusMd)),
            textStyle: base,
          ),
          child: content,
        );
      case AppButtonVariant.secondary:
        button = OutlinedButton(
          onPressed: enabled ? onPressed : null,
          style: OutlinedButton.styleFrom(
            backgroundColor: t.surface,
            foregroundColor: t.ink,
            disabledForegroundColor: t.inkFaint,
            disabledBackgroundColor: t.surface2,
            minimumSize: const Size(0, 48),
            side: BorderSide(color: enabled ? t.line : t.surface2, width: 1.5),
            shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(WarmPopTokens.radiusMd)),
            textStyle: base,
          ),
          child: content,
        );
      case AppButtonVariant.text:
        button = TextButton(
          onPressed: enabled ? onPressed : null,
          style: TextButton.styleFrom(
            foregroundColor: t.ink,
            disabledForegroundColor: t.inkFaint,
            minimumSize: const Size(0, 40),
            textStyle: base,
          ),
          child: content,
        );
    }
    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}
```

Then the remaining five per the Interfaces block (exact sizes from there):
- `app_chip.dart` — pill height 36, selected = `t.accentSoft` bg + `t.accent` border + `t.ink` text, unselected = `t.surface` + `t.line`, radius 999.
- `app_badge.dart` — `count <= 0` → `SizedBox.shrink()`, else Container(minWidth 22, height 22, padding H6, color `t.accent`, shape pill, child Text('$count', style Theme labelSmall merged with `color: t.onAccent, fontWeight: w800`)).
- `app_avatar.dart` — CircleAvatar(radius, backgroundColor `t.surface2`) with initials Text(`t.inkSoft`, w700); if `url != null` use `CachedNetworkImage(imageUrl: url, fit: cover)` as backgroundImage (same import pattern as `group_settings_screen.dart`).
- `section_header.dart` — Padding(left16, top24, bottom8) with Text(title, style labelSmall copyWith(color `t.inkFaint`, letterSpacing .1)).
- `search_field.dart` — SizedBox(height 44) TextField with InputDecoration filled `t.surface`, hintText hint ?? 'Search', hintStyle `t.inkFaint`, prefixIcon Icon(Icons.search, color `t.inkFaint`, size 20), border OutlineInputBorder(borderRadius pill, borderSide `t.line`), contentPadding H16.

- [ ] **Step 4: Run tests**

Run: `flutter test test/widgets_batch1_test.dart` → PASS (5).
Run: `flutter analyze` → 0 errors.
Run: `grep -rn "Color(0x" lib/core/widgets` → empty.

---

### Task 6: Chrome components — batch 2 + mockups (user approval gate)

**Files:**
- Create: `lib/core/widgets/app_toast.dart`, `lib/core/widgets/status_banner.dart`,
  `lib/core/widgets/skeleton.dart`, `lib/core/widgets/empty_state.dart`,
  `lib/core/widgets/settings_tile.dart`
- Create: `test/widgets_batch2_test.dart`
- Create: `docs/mockups/2026-10-05-home-chat.html` (+ served preview)

**Interfaces:**
- Consumes: Task 4 `Capybara`, Task 5 components, `context.t`.
- Produces:
  - `void showToast(BuildContext context, String message, {bool error = false})` — wraps ScaffoldMessenger; error uses `t.error` stripe on surface.
  - `StatusBanner({required String message, Widget? leading, VoidCallback? onRetry})` — accentSoft bg, 1px accent/line border, radius md, 13px semibold, optional retry TextButton.
  - `Skeleton({double height = 16, double? width, double radius = 8})` — surface2 block, shimmer via `TweenAnimationBuilder` loop 1.2s (parks under reduced-motion).
  - `EmptyState({required String title, String? subtitle, Widget? action, bool withMascot = true})` — centered column: `Capybara(size: Size(180,152))`, title (titleMedium), subtitle (bodySmall, inkSoft), action button; padding 32.
  - `SettingsTile({required IconData icon, required String title, String? subtitle, VoidCallback? onTap, Widget? trailing})` — 56px min height, 16px icon in surface2 rounded-square (radius sm, 36×36), title bodyMedium w600.

- [ ] **Step 1: Write the failing test** (batch2_test: renders each; EmptyState contains a `Capybara`; Skeleton builds under `MediaQueryData(disableAnimations: true)` without exception; toast shows via `showToast` pump)

```dart
// test/widgets_batch2_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/core/widgets/empty_state.dart';
import 'package:kuch_bhi/core/widgets/app_toast.dart';
import 'package:kuch_bhi/core/widgets/settings_tile.dart';
import 'package:kuch_bhi/core/widgets/skeleton.dart';
import 'package:kuch_bhi/core/widgets/status_banner.dart';
import 'package:kuch_bhi/features/mascot/capybara.dart';

Widget host(Widget child) => MaterialApp(
    theme: warmPopLight(), home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('empty state carries the mascot + copy', (tester) async {
    await tester.pumpWidget(
        host(const EmptyState(title: 'No chats yet', subtitle: 'Add a friend')));
    expect(find.byType(Capybara), findsOneWidget);
    expect(find.text('No chats yet'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('toast + banner + tile render', (tester) async {
    await tester.pumpWidget(host(const Column(
        mainAxisSize: MainAxisSize.min,
        children: [StatusBanner(message: 'Offline'), SettingsTile(icon: Icons.settings, title: 'Settings')])));
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    await tester.pumpWidget(host(const Column(
        mainAxisSize: MainAxisSize.min,
        children: [Skeleton(height: 20)])));
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('showToast surfaces the message', (tester) async {
    await tester.pumpWidget(host(const SizedBox()));
    final ctx = tester.element(find.byType(Scaffold));
    showToast(ctx, 'Invite sent');
    await tester.pump();
    expect(find.text('Invite sent'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });
}
```

- [ ] **Step 2: Run test to verify it fails** — `flutter test test/widgets_batch2_test.dart` → FAIL (undefined).

- [ ] **Step 3: Implement the five widgets** per Interfaces (EmptyState's mascot honors reduced-motion via Capybara's own handling; Skeleton parks its tween when `MediaQuery.disableAnimationsOf(context)`).

- [ ] **Step 4: Run tests + gates**

`flutter test test/widgets_batch2_test.dart` → PASS (3); `flutter analyze` → 0;
`grep -rn "Color(0x" lib/core/widgets lib/features/mascot` → empty.

- [ ] **Step 5: Build the Home+Chat mockup (taste + impeccable)**

Load the `taste` skill, then create `docs/mockups/2026-10-05-home-chat.html`:
- Title `Kuch Bhi — Home & Chat Mockup`, Google Fonts Plus Jakarta Sans link,
  tokens copied VERBATIM from `design_tokens.json` (light :root + dark
  `[data-theme="dark"]` blocks, three-state token pattern), no gradients.
- Content, exactly: (a) **Home (light)** — "Chats" display header, search
  pill, rows: `Aarav / Sounds good — see you at 8`, `Design Squad / Meera:
  the new build looks clean` + accent badge `3`, `Priya / 📷 Photo`, marigold
  FAB `+`; (b) **Chat (dark)** — header `Meera` with back-chevron + avatar,
  bubbles: `did you see the capybara board?` (them), `on my way 🦫` (me,
  accent/onAccent), `pick marigold, it's warm and nobody uses it` (them),
  composer pill `Message…` + marigold send `↑`; (c) **States strip** —
  EmptyState (capybara + "No chats yet"), Skeleton row trio, StatusBanner
  (`Offline — holding your messages safely`).
- Both phones sit on `surface` cards with `radiusLg`; everything derives
  from the token block — no literal hex outside `:root`.

- [ ] **Step 6: impeccable audit the mockup, fix in one batch**

Load the `impeccable` skill. Run:
`./.claude/skills/impeccable/scripts/impeccable audit docs/mockups/2026-10-05-home-chat.html 2>&1 | tail -40`
Expected: either PASS or a findings list. Apply every finding in ONE edit
batch (no loop), re-run once, accept the second result (per impeccable's
bounded-passes rule).

- [ ] **Step 7: PRESENT TO USER — hard gate**

Serve: `nohup python3 -m http.server 8792 --directory docs/mockups >/dev/null 2>&1 &`
Tell the user: open `http://127.0.0.1:8792/2026-10-05-home-chat.html`, review
Home + Chat + states in both themes. **STOP HERE until they answer.**
Approval options: "Approved" → Step 8; edits → apply, re-serve, re-present.

- [ ] **Step 8 (on approval): On-device smoke + final gate + single commit**

```bash
flutter analyze   # 0 errors
flutter test      # all green
flutter build apk --debug --target-platform android-arm64,android-x64
adb -s RFCRA047WSJ install -r build/app/outputs/flutter-apk/app-debug.apk
```
Launch on Samsung; open **home, chat, login, settings** in light AND dark
(theme follows system). Pass: no unreadable contrast (e.g. inkFaint text on
surface2, accent-on-accent), Material sheets/dialogs show warm surfaces +
radiusLg corners. If anything fails contrast → fix in tokens (not per
screen), re-run gates.

```bash
git add lib test docs design_tokens.json design_tokens.css tool pubspec.yaml pubspec.lock PRODUCT.md
git commit -m "[W3 Phase A] Warm Pop foundation — tokens, theme, Capybara rig, chrome components, approved mockups

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```
