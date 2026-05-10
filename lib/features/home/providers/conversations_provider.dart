import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/conversation.dart';
import '../../../infrastructure/repositories/message_repository_impl.dart';

class ConversationsNotifier extends AsyncNotifier<List<Conversation>> {
  @override
  Future<List<Conversation>> build() async {
    final stream = ref.watch(messageRepositoryProvider).watchConversations();
    ref.onDispose(() {});
    await for (final list in stream) {
      state = AsyncData(list);
    }
    return [];
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    final list = await ref
        .read(messageRepositoryProvider)
        .watchConversations()
        .first;
    state = AsyncData(list);
  }
}

final conversationsProvider =
    AsyncNotifierProvider<ConversationsNotifier, List<Conversation>>(
  ConversationsNotifier.new,
);
