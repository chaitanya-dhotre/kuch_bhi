import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/features/app_lock/widgets/pin_pad.dart';

Widget _host(PinPad pad) => MaterialApp(
  theme: warmPopLight(),
  home: Scaffold(body: SingleChildScrollView(child: pad)),
);

void main() {
  testWidgets('one check at a time: no delete or retype while it runs', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final pending = Completer<bool>();
    var calls = 0;
    await tester.pumpWidget(
      _host(
        PinPad(
          title: 'Enter your PIN',
          onCompleted: (_) {
            calls++;
            return pending.future;
          },
        ),
      ),
    );
    for (final d in '123456'.split('')) {
      await tester.tap(find.text(d));
      await tester.pump();
    }
    expect(calls, 1);
    await tester.tap(find.bySemanticsLabel('Delete digit'));
    await tester.tap(find.text('7'));
    await tester.pump();
    expect(find.bySemanticsLabel('PIN, 6 of 6 digits entered'), findsOneWidget);
    expect(calls, 1);
    pending.complete(false);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('PIN, 0 of 6 digits entered'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a counting-down wait line is announced once, a new line again', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    Future<void> show(String message) => tester.pumpWidget(
      _host(PinPad(title: 'Enter your PIN', message: message)),
    );
    bool live(String label) => tester
        .getSemantics(find.bySemanticsLabel(label))
        .hasFlag(SemanticsFlag.isLiveRegion);

    await show('Too many tries. Try again in 0:30.');
    expect(live('Too many tries. Try again in 0:30.'), isTrue);
    await show('Too many tries. Try again in 0:29.');
    expect(find.bySemanticsLabel('Too many tries. Try again in 0:30.'), findsOneWidget);
    expect(find.text('Too many tries. Try again in 0:29.'), findsOneWidget);
    await show('Wrong PIN.');
    expect(live('Wrong PIN.'), isTrue);
    handle.dispose();
  });
}
