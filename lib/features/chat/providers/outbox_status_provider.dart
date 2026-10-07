import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database/app_database.dart';

/// Reactive outbox rows for ONE conversation (spec §5.2 / Task 4).
///
/// The chat list watches this so each message bubble can locate its own op
/// by `ref == message.localId`; when that row is `failedTerminal` the bubble
/// renders the stuck-message banner (Retry / Discard). Emits on every
/// outbox change (enqueue, FSM write, discard) — one shared stream per
/// conversation, same pattern as [messagesProvider] (chat_provider.dart).
///
/// A stream-open failure surfaces as [AsyncValue.error]; bubbles read
/// `.value ?? const []`, so a broken DB means "no banner", never a crash.
final outboxStatusProvider =
    StreamProvider.family<List<OutboxTableData>, String>((ref, conversationId) {
  final db = ref.read(appDatabaseProvider);
  return (db.select(db.outboxTable)
        ..where((t) => t.conversationId.equals(conversationId)))
      .watch();
});
