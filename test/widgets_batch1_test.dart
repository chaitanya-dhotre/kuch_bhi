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
        themeMode:
            brightness == Brightness.light ? ThemeMode.light : ThemeMode.dark,
        home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('primary button uses accent/onAccent pair (both themes)',
      (tester) async {
    for (final b in [Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(
          host(AppButton(onPressed: () {}, child: const Text('Send')),
              brightness: b));
      final elevated = tester.widget<FilledButton>(find.byType(FilledButton));
      final bg = elevated.style?.backgroundColor?.resolve({})!;
      final fg = elevated.style?.foregroundColor?.resolve({})!;
      expect(bg, const Color(0xFFEFA00B));
      expect(
          fg,
          b == Brightness.light
              ? const Color(0xFF2A2520)
              : const Color(0xFF21260F));
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('badge hides content at zero, shows above', (tester) async {
    await tester.pumpWidget(host(const AppBadge(count: 0)));
    expect(find.byType(AppBadge), findsOneWidget);
    expect(find.byType(Text), findsNothing);
    await tester.pumpWidget(host(const AppBadge(count: 3)));
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('button disabled and busy states', (tester) async {
    await tester.pumpWidget(
        host(AppButton(onPressed: null, child: const Text('Invite'))));
    expect(find.text('Invite'), findsOneWidget);
    await tester.pumpWidget(host(
        AppButton(onPressed: () {}, busy: true, child: const Text('Invite'))));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('chip selected state + section header + search field render',
      (tester) async {
    await tester.pumpWidget(host(
        Column(mainAxisSize: MainAxisSize.min, children: [
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
    await tester.pumpWidget(host(AppButton(onPressed: () {}, child: const Text('Go')),
        brightness: Brightness.dark));
    final bg = tester
        .widget<FilledButton>(find.byType(FilledButton))
        .style?.backgroundColor
        ?.resolve({});
    expect(bg, WarmPopTokens.accent);
    await tester.pumpWidget(const SizedBox());
  });
}
