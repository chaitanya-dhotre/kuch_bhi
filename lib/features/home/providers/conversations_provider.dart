import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/conversation.dart';
import '../../../infrastructure/repositories/message_repository_impl.dart';

/// autoDispose: the stream (and its asyncMap mapping) tears down with the
/// home screen instead of notifying defunct elements after dispose — the
/// `_lifecycleState != _ElementLifecycle.defunct` crash class.
final conversationsProvider = StreamProvider.autoDispose<List<Conversation>>(
    (ref) {
  return ref.watch(messageRepositoryProvider).watchConversations();
});
