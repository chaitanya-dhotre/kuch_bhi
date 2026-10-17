import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kuch_bhi/core/decrypt/body_cache.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/features/chat/providers/message_body_provider.dart';
import 'package:kuch_bhi/features/chat/widgets/message_body_text.dart';

void main() {
  setUp(bodyCache.clear);

  testWidgets('transient body paints bars during the 150ms grace', (
    tester,
  ) async {
    final body = Completer<String?>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [messageBodyProvider.overrideWith((ref, id) => body.future)],
        child: MaterialApp(
          theme: warmPopLight(),
          home: const Scaffold(
            body: MessageBodyText(
              messageId: 'transient',
              styleContext: 'bubble',
              ciphertextLength: 96,
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(
      find.byKey(MessageBodyText.placeholderKey('transient')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('body-skeleton-96')), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testWidgets('terminal decrypt paints one label and no skeleton bars', (
    tester,
  ) async {
    final body = Completer<String?>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [messageBodyProvider.overrideWith((ref, id) => body.future)],
        child: MaterialApp(
          theme: warmPopLight(),
          home: const Scaffold(
            body: MessageBodyText(
              messageId: 'terminal',
              styleContext: 'bubble',
              decryptState: 'failed',
              ciphertextLength: 96,
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.text("Can't decrypt"), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.byKey(const ValueKey('body-skeleton-96')), findsNothing);
  });

  testWidgets('keeps the last body when the provider later returns null', (
    tester,
  ) async {
    final bodyState = StateProvider<String?>((ref) => null);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bodyState.overrideWith((ref) => 'first body'),
          messageBodyProvider.overrideWith(
            (ref, id) async => ref.watch(bodyState),
          ),
        ],
        child: MaterialApp(
          theme: warmPopLight(),
          home: const Scaffold(
            body: MessageBodyText(
              messageId: 'sticky',
              styleContext: 'bubble',
              ciphertextLength: 48,
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('first body'), findsOneWidget);

    bodyCache.clear();
    // Trigger the provider's null result without remounting the stateful body.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MessageBodyText)),
    );
    container.read(bodyState.notifier).state = null;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('first body'), findsOneWidget);
    expect(find.byKey(MessageBodyText.placeholderKey('sticky')), findsNothing);
  });
}
