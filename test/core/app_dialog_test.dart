import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/tokens.dart';
import 'package:kuch_bhi/core/widgets/app_dialog.dart';

import 'sheet_harness.dart';

Future<Future<bool>> _show(
  WidgetTester tester, {
  bool destructive = true,
  bool large = false,
  String? fontFamily,
}) async {
  late Future<bool> result;
  await pumpHost(
    tester,
    SheetLauncher((context, _) => result = showConfirmDialog(
          context: context,
          title: 'Delete message?',
          body: 'This message will be deleted for everyone in this chat.',
          confirmLabel: 'Delete',
          confirmIcon: Icons.delete_outline,
          destructive: destructive,
        )),
    large: large,
    fontFamily: fontFamily,
  );
  await tapOpen(tester);
  return result;
}

void main() {
  testWidgets('confirm → true', (tester) async {
    final result = await _show(tester);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
  });

  testWidgets('cancel → false', (tester) async {
    final result = await _show(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });

  testWidgets('barrier tap → false', (tester) async {
    final result = await _show(tester);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(await result, isFalse);
  });

  testWidgets('destructive: error icon, ink label; surface, no tint, radiusXl',
      (tester) async {
    await _show(tester);
    final t = tokens(tester);
    expect(tester.widget<Icon>(find.byIcon(Icons.delete_outline)).color, t.error);
    expect(paintedColor(tester, find.text('Delete')), t.ink);
    expectNoTextIn(
        tester, [t.error, t.accent, t.success], find.byType(AlertDialog));
    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    expect(dialog.backgroundColor, t.surface);
    expect(dialog.surfaceTintColor, Colors.transparent);
    expect(
      dialog.shape,
      RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WarmPopTokens.radiusXl)),
    );
  });

  testWidgets('not destructive: the icon is ink', (tester) async {
    await _show(tester, destructive: false);
    final t = tokens(tester);
    expect(tester.widget<Icon>(find.byIcon(Icons.delete_outline)).color, t.ink);
  });

  testWidgets('title 20/26 w700 ink, body 15/22 ink', (tester) async {
    await _show(tester);
    final t = tokens(tester);
    final title = tester.widget<Text>(find.text('Delete message?'));
    expect(title.style?.fontSize, 20);
    expect(title.style?.fontWeight, FontWeight.w700);
    expect(title.style?.height, 26 / 20);
    expect(paintedColor(tester, find.text('Delete message?')), t.ink);
    final body = tester.widget<Text>(
        find.text('This message will be deleted for everyone in this chat.'));
    expect(body.style?.fontSize, 15);
    expect(body.style?.color, t.ink);
  });

  for (final font in largeTextFonts) {
    testWidgets('360×200% (${font ?? 'system'}): no overflow', (tester) async {
      await _show(tester, large: true, fontFamily: font);
      expect(tester.takeException(), isNull);
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });
  }
}
