import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/core/theme/tokens.dart';

/// Page 8 large-text passes: 200% text with the system font, then with
/// Plus Jakarta Sans (R18). `null` = the system font.
const largeTextFonts = <String?>[null, 'PlusJakartaSans'];

/// A button that runs [onOpen] with a context under the app's navigator.
class SheetLauncher extends ConsumerWidget {
  const SheetLauncher(this.onOpen, {super.key});

  final void Function(BuildContext context, WidgetRef ref) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        body: Center(
          child: TextButton(
            key: const Key('open'),
            onPressed: () => onOpen(context, ref),
            child: const Text('open'),
          ),
        ),
      );
}

/// Pumps [home] in the Warm Pop light theme. [large] = 360×640 at 200% text.
Future<void> pumpHost(
  WidgetTester tester,
  Widget home, {
  List<Override> overrides = const [],
  bool large = false,
  String? fontFamily,
}) async {
  if (large) {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }
  await tester.pumpWidget(ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: warmPopLight(fontFamily: fontFamily),
      home: home,
      builder: large
          ? (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              )
          : null,
    ),
  ));
  await tester.pump();
}

Future<void> tapOpen(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('open')));
  await tester.pumpAndSettle();
}

ColorTokens tokens(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(Navigator).first))
        .extension<ColorTokens>()!;

/// The colour a [Text] actually paints with (its own style merged with the
/// ambient DefaultTextStyle).
Color? paintedColor(WidgetTester tester, Finder text) =>
    tester.renderObject<RenderParagraph>(text).text.style?.color;

/// C4: no painted text in any of [banned] colours inside [within] (the
/// open sheet or dialog; the launcher underneath is not this page).
void expectNoTextIn(WidgetTester tester, List<Color> banned, Finder within) {
  final texts = find
      .descendant(of: within, matching: find.byType(RichText))
      .evaluate()
      // An Icon paints its glyph as text; icons are checked on their own.
      .where((e) => e.findAncestorWidgetOfExactType<Icon>() == null);
  for (final p in texts.map((e) => e.renderObject! as RenderParagraph)) {
    final hits = <Color>[];
    p.text.visitChildren((span) {
      final c = span.style?.color;
      if (c != null && banned.contains(c)) hits.add(c);
      return true;
    });
    expect(hits, isEmpty, reason: 'coloured text: "${p.text.toPlainText()}"');
  }
}
