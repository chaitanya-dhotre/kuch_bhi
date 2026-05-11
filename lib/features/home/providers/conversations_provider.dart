import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/conversation.dart';
import '../../../infrastructure/repositories/message_repository_impl.dart';

class ConversationsNotifier extends AsyncNotifier<List<Conversation>> {
  @override
  Future<List<Conversation>> build() async {
    // Drift reactive stream — auto-updates on any table change.
    final stream = ref.watch(messageRepositoryProvider).watchConversations();
    await for (final list in stream) {
      state = AsyncData(list);
    }
    return [];
  }

  Future<void> refresh() async {
    // Just invalidate — build() will restart the stream.
    ref.invalidateSelf();
  }
}

final conversationsProvider =
    AsyncNotifierProvider<ConversationsNotifier, List<Conversation>>(
  ConversationsNotifier.new,
);
