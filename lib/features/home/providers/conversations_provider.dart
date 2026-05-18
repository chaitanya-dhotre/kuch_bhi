import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/conversation.dart';
import '../../../infrastructure/repositories/message_repository_impl.dart';

final conversationsProvider =
    StreamProvider<List<Conversation>>((ref) {
  return ref.watch(messageRepositoryProvider).watchConversations();
});
