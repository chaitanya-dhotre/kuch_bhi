import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database/app_database.dart';
import '../../../domain/entities/conversation.dart';
import '../../../domain/entities/message.dart';
import '../../../infrastructure/repositories/message_repository_impl.dart';

final activeConversationProvider =
    StateProvider<Conversation?>((ref) => null);

class MessagesNotifier
    extends FamilyAsyncNotifier<List<Message>, String> {
  @override
  Future<List<Message>> build(String conversationId) async {
    final stream = ref
        .watch(messageRepositoryProvider)
        .watchMessages(conversationId);
    await for (final msgs in stream) {
      state = AsyncData(msgs);
    }
    return [];
  }
}

final messagesProvider =
    AsyncNotifierProviderFamily<MessagesNotifier, List<Message>, String>(
  MessagesNotifier.new,
);

class SendMessageNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  /// Fire-and-forget — the optimistic insert makes the message appear
  /// immediately. We don't block the UI waiting for the server response.
  void send({
    required String conversationId,
    required String text,
    String? replyToLocalId,
    String? replyPreview,
  }) {
    if (text.trim().isEmpty) return;

    ref.read(messageRepositoryProvider).sendMessage(
      conversationId: conversationId,
      plaintext:      text.trim(),
      replyToLocalId: replyToLocalId,
      replyPreview:   replyPreview,
    );
    // Don't await — message appears via optimistic Drift insert.
  }
}

final sendMessageProvider =
    NotifierProvider<SendMessageNotifier, bool>(SendMessageNotifier.new);

// Current user ID (for determining sent/received alignment).
final currentUserIdProvider = FutureProvider<String>((ref) async {
  final db = ref.read(appDatabaseProvider);
  return await db.settingsDao.getSetting('current_user_id') ?? '';
});
