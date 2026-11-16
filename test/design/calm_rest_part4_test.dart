// Calm-rest spec, part 4 test gate 12, plus the E3 backup PIN motion tokens.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/core/theme/tokens.dart';

String _src(String path) => File(path).readAsStringSync();

// `t.accent` but not `t.accentText` / `t.accentSoft`.
final _solidAccent = RegExp(r'\bt\.accent\b(?![A-Za-z])');

void main() {
  test('E1: Starred paints no solid accent; the star is accentText', () {
    final src =
        _src('lib/features/starred_messages/screens/starred_messages_screen.dart');
    expect(_solidAccent.allMatches(src), isEmpty);
    expect(src, contains('Icons.star, color: context.t.accentText'));
    expect(src, contains('LeavingColumn<_StarredEntry>'));
  });

  test('E2: Media & docs uses t.accent only for the player disc and progress',
      () {
    final src = _src('lib/features/media/screens/media_docs_screen.dart');
    final hits = [
      for (final l in src.split('\n'))
        if (_solidAccent.hasMatch(l)) l.trim(),
    ];
    expect(hits, ['color: t.accent,', 'valueColor:      AlwaysStoppedAnimation(t.accent),']);
    // Tabs come from the shared theme, never local overrides.
    expect(src, contains('bottom: const TabBar('));
    expect(src, isNot(contains('indicator:')));
    expect(src, isNot(contains('labelColor:')));
  });

  test('A6: the shared tab theme is ink label, inkSoft others, 2 dp accent bar',
      () {
    for (final theme in [
      warmPopLight(),
      warmPopDark(),
      warmPopDark(amoled: true),
    ]) {
      final c = theme.extension<ColorTokens>()!;
      final tabs = theme.tabBarTheme;
      expect(tabs.labelColor, c.ink);
      expect(tabs.unselectedLabelColor, c.inkSoft);
      expect(tabs.labelStyle!.fontSize, 15);
      expect(tabs.labelStyle!.fontWeight, FontWeight.w600);
      expect(tabs.indicatorSize, TabBarIndicatorSize.tab);
      final bar = (tabs.indicator! as UnderlineTabIndicator).borderSide;
      expect(bar.color, c.accent);
      expect(bar.width, 2);
    }
  });

  test('E3: backup PIN restore progress moves on motionSlow + curveMove', () {
    final src = _src('lib/features/auth/screens/backup_pin_screen.dart');
    expect(src, contains(': WarmPopTokens.motionSlow,'));
    expect(src, contains('curve: WarmPopTokens.curveMove,'));
    expect(src, isNot(contains('easeInOutCubic')));
    expect(src, isNot(contains('Duration(milliseconds: 450)')));
    // Restore progress stays marigold (C5).
    expect(src, contains('AlwaysStoppedAnimation<Color>(t.accent)'));
  });

  test('E3: the forgot-password sent disc is surface2', () {
    final src = _src('lib/features/auth/screens/forgot_password_screen.dart');
    expect(src, contains('BoxDecoration(color: t.surface2, shape: BoxShape.circle)'));
    expect(src, isNot(contains('accentSoft')));
  });
}
