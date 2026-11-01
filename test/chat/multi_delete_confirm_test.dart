import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/features/chat/widgets/message_context_menu.dart';

import '../core/sheet_harness.dart';

/// Wave 4: the chat's multi-select delete removed every selected message
/// without asking. It now asks once, naming the count, in the single
/// delete-for-me wording.
void main() {
  /// Opens the confirm for [ids]; the returned list fills as they're deleted.
  Future<List<String>> open(WidgetTester tester, List<String> ids) async {
    final deleted = <String>[];
    await pumpHost(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => confirmAndDeleteForMe(
              context,
              ids,
              (id) async => deleted.add(id),
            ),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    return deleted;
  }

  Future<void> answer(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('three selected: asks "Delete 3 messages?"; Cancel deletes '
      'nothing', (tester) async {
    final deleted = await open(tester, ['a', 'b', 'c']);
    expect(find.text('Delete 3 messages?'), findsOneWidget);
    expect(find.text('These messages will be deleted for you only.'),
        findsOneWidget);
    await answer(tester, 'Cancel');
    expect(deleted, isEmpty);
  });

  testWidgets('Delete removes each selected message', (tester) async {
    final deleted = await open(tester, ['a', 'b', 'c']);
    await answer(tester, 'Delete');
    expect(deleted, ['a', 'b', 'c']);
  });

  testWidgets('one selected uses the single-message wording', (tester) async {
    await open(tester, ['a']);
    expect(find.text('Delete message?'), findsOneWidget);
    expect(find.text('This message will be deleted for you only.'),
        findsOneWidget);
  });
}
