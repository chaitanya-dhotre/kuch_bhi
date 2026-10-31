import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/domain/entities/message.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';

/// 13.6: a reply belongs to its chat. It never shows in another chat, and it
/// is dropped when its chat closes (nothing listens any more).
void main() {
  test('a reply in one chat is not the reply in another', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final a = c.listen(replyProvider('A'), (_, __) {});
    final b = c.listen(replyProvider('B'), (_, __) {});
    addTearDown(a.close);
    addTearDown(b.close);

    c.read(replyProvider('A').notifier).state = _msg('A');
    expect(c.read(replyProvider('A'))?.conversationId, 'A');
    expect(c.read(replyProvider('B')), isNull);
  });

  test('closing a chat drops its reply', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final a = c.listen(replyProvider('A'), (_, __) {});
    c.read(replyProvider('A').notifier).state = _msg('A');

    a.close(); // the chat screen and its input are gone
    await Future<void>.delayed(Duration.zero);

    final again = c.listen(replyProvider('A'), (_, __) {});
    addTearDown(again.close);
    expect(c.read(replyProvider('A')), isNull);
  });
}

Message _msg(String conversationId) => Message(
      localId: 'l1',
      conversationId: conversationId,
      senderId: 'u1',
      type: 'text',
      status: 'sent',
      createdAt: DateTime(2026, 10, 31),
    );
