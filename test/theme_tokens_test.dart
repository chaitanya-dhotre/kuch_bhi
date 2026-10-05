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

  test('system font is the default (P11) — optional font never forced', () {
    // ThemeData materializes the platform default (Roboto on Android);
    // the rule is that WE never set the bundled optional font here.
    expect(warmPopLight().textTheme.bodyMedium?.fontFamily,
        isNot('PlusJakartaSans'));
    expect(warmPopDark().textTheme.bodyMedium?.fontFamily,
        isNot('PlusJakartaSans'));
  });

  test('AMOLED variant keeps Warm Pop colors on a pure-black ground', () {
    final amoled = warmPopDark(amoled: true);
    final t = amoled.extension<ColorTokens>()!;
    expect(t.bg, Colors.black);
    expect(t.accent, const Color(0xFFEFA00B));
  });
}
