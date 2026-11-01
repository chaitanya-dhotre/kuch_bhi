import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/features/chat/widgets/reply_quote.dart';

void main() {
  testWidgets('missing parent quote says Message not available without a skeleton', (
    tester,
  ) async {
    final db = AppDatabase.test();
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: warmPopLight(),
          home: const Scaffold(
            body: ReplyQuote(senderName: 'Aanya', replyToId: 'deleted-parent'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Message not available'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('body-placeholder-deleted-parent')),
      findsNothing,
    );
  });
}
