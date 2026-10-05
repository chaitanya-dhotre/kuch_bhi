import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/conversation.dart';
import '../../../infrastructure/repositories/message_repository_impl.dart';

/// autoDispose: the stream tears down with the home screen instead of
/// notifying defunct elements after dispose — the
/// `_lifecycleState != _ElementLifecycle.defunct` crash class.
/// keepAlive (review I4): retain state across home re-entries so each
/// re-entry does NOT re-run watchConversations' full server sync (~20
/// requests at N=10) and the list doesn't flash a spinner. Pull-to-refresh
/// still works — home_screen invalidates explicitly.
final conversationsProvider = StreamProvider.autoDispose<List<Conversation>>(
    (ref) {
  ref.keepAlive();
  return ref.watch(messageRepositoryProvider).watchConversations();
});
