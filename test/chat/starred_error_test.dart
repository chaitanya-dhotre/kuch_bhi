import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/domain/entities/message.dart';
import 'package:kuch_bhi/features/starred_messages/screens/starred_messages_screen.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';

import '../core/sheet_harness.dart';
import '../fakes/fake_message_repository.dart';

/// The first load fails; every later one finds nothing starred.
class _FailsOnce extends FakeMessageRepository {
  int loads = 0;
  @override
  Future<List<Message>> getStarredMessages(String conversationId) async {
    if (++loads == 1) throw Exception('ClientException: Connection reset');
    return const [];
  }
}

/// Bug wave 2 §5.2: the starred list's error state shows plain copy and a
/// Retry that loads again, never the exception text.
void main() {
  testWidgets('failed load: plain copy, no exception text, Retry reloads '
      '(360dp, 200%)', (tester) async {
    final repo = _FailsOnce();
    await pumpHost(
      tester,
      const StarredMessagesScreen(conversationId: 'c1'),
      overrides: [messageRepositoryProvider.overrideWithValue(repo)],
      large: true,
    );
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load starred messages."), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(repo.loads, 2);
    expect(find.text('No starred messages'), findsOneWidget);
  });
}
