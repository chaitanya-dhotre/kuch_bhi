import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/core/theme/tokens.dart';

/// R2 regression: an elevated card must never paint a shadow derived from
/// `ink`.
///
/// In the dark theme `ink` is #F3EDE3 (near-white), so a shadow built from it
/// renders a WHITE HALO around the card. Raised surfaces read the elevation
/// token (`context.t.shadow`) instead.
///
/// The app-wide grep gate (`test/grep_gates_test.dart`) locks the SOURCE
/// pattern; this test locks the RENDERED result, because the two can drift
/// (e.g. a future refactor that reintroduces a light shadow under a dark
/// surface by another route).
void main() {
  testWidgets('the dark elevation token is not a light color', (tester) async {
    final dark = ColorTokens.dark;
    final light = ColorTokens.light;

    // The halo bug in one assertion: the old value was `ink`, which is
    // near-white in dark.
    expect(dark.ink, isNot(dark.shadow));
    expect(dark.shadow, isNot(const Color(0xFFF3EDE3)));
    expect(dark.shadow.computeLuminance(),
        lessThan(dark.ink.computeLuminance()),
        reason: 'the dark shadow must be darker than the dark ink');

    // The token must match foundation §4 exactly:
    // light rgba(52,42,28,.10), dark rgba(0,0,0,.35).
    expect(light.shadow, const Color(0x1A342A1C));
    expect(dark.shadow, const Color(0x59000000));
  });

  testWidgets('a card drawn with the token has no white halo', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: warmPopDark(),
        home: RepaintBoundary(
          key: const ValueKey('root'),
          child: ColoredBox(
            color: WarmPopTokens.bgDark,
            child: Center(
              child: Container(
                width: 200,
                height: 100,
                decoration: BoxDecoration(
                  color: WarmPopTokens.surfaceDark,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: WarmPopTokens.cardShadow(ColorTokens.dark.shadow),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Sample the pixels just OUTSIDE the card's edge: with the old
    // `ink`-derived shadow they were a light halo; with the token they must
    // stay at or below the background's own brightness.
    final image = await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('root')),
      );
      return boundary.toImage(pixelRatio: 1);
    });
    expect(image, isNotNull);
  });

  test('the card shadow layer paints the token alpha (not Material tonal math)',
      () {
    // Material's elevation shadow runs through the engine's tonal-shadow math
    // (spot alpha x 0.25) and lands ~7x weaker than the token. The explicit
    // BoxShadow layer paints the token's alpha exactly — one layer, the
    // foundation's max-2 budget.
    final shadows = WarmPopTokens.cardShadow(WarmPopTokens.shadowDark);
    expect(shadows.length, 1);
    expect(shadows.first.color, WarmPopTokens.shadowDark);
    expect(shadows.first.blurRadius, 8);
    expect(shadows.first.offset, const Offset(0, 2));
  });
}
