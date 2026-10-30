import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/tokens.dart';
import 'package:kuch_bhi/core/widgets/app_sheet.dart';

import 'sheet_harness.dart';

const _handle = Key('h');

void _open(
  BuildContext context, {
  String? title,
  Widget? header,
  List<Widget>? children,
}) {
  showAppSheet<void>(
    context: context,
    builder: (_) => AppSheetChrome(
      handleKey: _handle,
      title: title,
      header: header,
      children: children ??
          [SheetActionRow(icon: Icons.reply, label: 'Row', onTap: () {})],
    ),
  );
}

Future<void> _pumpSheet(
  WidgetTester tester, {
  String? title,
  Widget? header,
  List<Widget>? children,
  bool large = false,
  String? fontFamily,
}) async {
  await pumpHost(
    tester,
    SheetLauncher((context, _) => _open(context,
        title: title, header: header, children: children)),
    large: large,
    fontFamily: fontFamily,
  );
  await tapOpen(tester);
}

void main() {
  testWidgets('opens on t.surface with the theme radius radiusLg, no tint',
      (tester) async {
    await _pumpSheet(tester);
    final t = tokens(tester);
    final material = tester.widget<Material>(find
        .descendant(of: find.byType(BottomSheet), matching: find.byType(Material))
        .first);
    expect(material.color, t.surface);
    expect(material.surfaceTintColor, Colors.transparent);
    expect(
      material.shape,
      const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(WarmPopTokens.radiusLg)),
      ),
    );
    expect(tester.widget<BottomSheet>(find.byType(BottomSheet)).shape, isNull,
        reason: 'no per-call shape: the theme owns it');
  });

  testWidgets('handle is 36×4 in t.line and is excluded from semantics',
      (tester) async {
    await _pumpSheet(tester);
    final t = tokens(tester);
    final box = find.descendant(
        of: find.byKey(_handle), matching: find.byType(DecoratedBox));
    expect(tester.getSize(box), const Size(36, 4));
    final deco = tester.widget<DecoratedBox>(box).decoration as BoxDecoration;
    expect(deco.color, t.line);
    expect(
      find.ancestor(
        of: find.byKey(_handle),
        matching: find.byWidgetPredicate(
            (w) => w is ExcludeSemantics && w.excluding),
      ),
      findsOneWidget,
    );
  });

  testWidgets('title is a header and wraps at 360dp × 200%', (tester) async {
    final semantics = tester.ensureSemantics();
    const long = 'A sheet title that is long enough to need two lines';
    await _pumpSheet(tester, title: long, large: true);
    expect(tester.takeException(), isNull);
    expect(tester.getSemantics(find.text(long)), isSemantics(isHeader: true));
    expect(tester.getSize(find.text(long)).height, greaterThan(26 * 2 * 1.5),
        reason: 'wrapped onto more than one line');
    semantics.dispose();
  });

  testWidgets('row label is 15 w600 ink, icon 24 inkSoft, min height 52',
      (tester) async {
    await _pumpSheet(tester);
    final t = tokens(tester);
    final label = tester.widget<Text>(find.text('Row'));
    expect(label.style?.fontSize, 15);
    expect(label.style?.fontWeight, FontWeight.w600);
    expect(paintedColor(tester, find.text('Row')), t.ink);
    final icon = tester.widget<Icon>(find.byIcon(Icons.reply));
    expect(icon.color, t.inkSoft);
    expect(icon.size, 24);
    expect(tester.getSize(find.byType(ListTile)).height,
        greaterThanOrEqualTo(52));
  });

  testWidgets('destructive: error icon, ink label', (tester) async {
    await _pumpSheet(tester, children: [
      SheetActionRow(
          icon: Icons.delete_outline,
          label: 'Delete',
          destructive: true,
          onTap: () {}),
    ]);
    final t = tokens(tester);
    expect(tester.widget<Icon>(find.byIcon(Icons.delete_outline)).color, t.error);
    expect(paintedColor(tester, find.text('Delete')), t.ink);
  });

  testWidgets(
      'disabled: one 38% dim over icon + label, hint not dimmed, not enabled',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpSheet(tester, children: [
      SheetActionRow(
        key: const Key('pin'),
        icon: Icons.push_pin_outlined,
        label: 'Pin',
        trailing: 'Available online',
        enabled: false,
        onTap: () {},
      ),
    ]);
    final dimOfIcon = find.ancestor(
        of: find.byIcon(Icons.push_pin_outlined),
        matching: find.byType(Opacity));
    final dimOfLabel =
        find.ancestor(of: find.text('Pin'), matching: find.byType(Opacity));
    expect(dimOfIcon, findsOneWidget);
    expect(tester.widget<Opacity>(dimOfIcon).opacity, 0.38);
    expect(tester.widget(dimOfIcon), same(tester.widget(dimOfLabel)),
        reason: 'one Opacity over both');
    expect(
        find.ancestor(
            of: find.text('Available online'), matching: find.byType(Opacity)),
        findsNothing);
    expect(
      tester.getSemantics(find.byKey(const Key('pin'))),
      isSemantics(hasEnabledState: true, isEnabled: false),
    );
    final tile = tester.widget<ListTile>(find.byKey(const Key('pin')));
    expect((tile.trailing! as Text).data, 'Available online');
    expect(tile.onTap, isNull);
    semantics.dispose();
  });

  for (final font in largeTextFonts) {
    testWidgets('trailing value wraps at 360×200% and ends at the row end '
        '(${font ?? 'system'})', (tester) async {
      await _pumpSheet(tester, large: true, fontFamily: font, children: [
        SheetActionRow(
          icon: Icons.timer_outlined,
          label: 'Disappearing messages',
          trailing: '30 days',
          onTap: () {},
        ),
        SheetActionRow(
          icon: Icons.push_pin_outlined,
          label: 'Pin',
          trailing: 'Available online',
          enabled: false,
          onTap: () {},
        ),
      ]);
      expect(tester.takeException(), isNull);
      expect(tester.getTopRight(find.text('30 days')).dx, 360 - 16);
    });
  }

  testWidgets('the keyboard inset lifts the content above it', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);
    await _pumpSheet(tester);
    expect(tester.getBottomLeft(find.byType(ListTile)).dy,
        lessThanOrEqualTo(640 - 300));
  });

  testWidgets('30 rows scroll inside 90% of the screen', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pumpSheet(tester, children: [
      for (var i = 0; i < 30; i++)
        SheetActionRow(icon: Icons.reply, label: 'Row $i', onTap: () {}),
    ]);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(BottomSheet)).height,
        lessThanOrEqualTo(640 * 0.9 + 0.5));
    await tester.scrollUntilVisible(find.text('Row 29'), 200,
        scrollable: find.byType(Scrollable).last);
    expect(tester.getBottomLeft(find.text('Row 29')).dy, lessThan(640));
  });

  testWidgets('the divider comes only with a header', (tester) async {
    await _pumpSheet(tester);
    expect(find.byType(Divider), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await _pumpSheet(tester, header: const Text('Preview'));
    expect(find.byType(Divider), findsOneWidget);
    expect(tester.getTopLeft(find.byType(Divider)).dy,
        greaterThan(tester.getBottomLeft(find.text('Preview')).dy));
  });

  testWidgets('reduced motion: the sheet appears without the slide',
      (tester) async {
    await pumpHost(
      tester,
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: SheetLauncher((context, _) => _open(context)),
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await tester.pump();
    await tester.pump();
    final sheetTop = tester.getTopLeft(find.byType(BottomSheet)).dy;
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(BottomSheet)).dy, sheetTop,
        reason: 'already in place one frame after opening');
  });
}
