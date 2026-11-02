import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/decrypt/body_cache.dart';
import '../../../data/local/database/app_database.dart';
import '../../../domain/entities/message.dart';

/// Identifies one album's visible rows: the conversation plus item 0's id.
class AlbumKey {
  const AlbumKey(this.conversationId, this.albumId);

  final String conversationId;
  final String albumId;

  @override
  bool operator ==(Object other) =>
      other is AlbumKey &&
      other.conversationId == conversationId &&
      other.albumId == albumId;

  @override
  int get hashCode => Object.hash(conversationId, albumId);
}

/// 12.5 C4/E1/F: the album's visible rows in pick order, live.
///
/// Reads the DAO query (not deleted, ordered by index) so a late item
/// appears and a deleted one leaves, then maps each row to the domain
/// entity the bubbles and labels already use.
final albumRowsProvider =
    StreamProvider.autoDispose.family<List<Message>, AlbumKey>((ref, key) {
  final db = ref.watch(appDatabaseProvider);
  return db.messagesDao
      .rowsInAlbum(key.conversationId, key.albumId)
      .watch()
      .map((rows) {
        // Like the chat's grouping: only the album sender's rows, so another
        // member's message carrying the same album_id never joins it.
        final cover = rows.where(
          (r) => r.localId == key.albumId || r.serverId == key.albumId,
        );
        final sender = (cover.isEmpty ? rows.firstOrNull : cover.first)
            ?.senderId;
        return [
          for (final r in rows)
            if (r.senderId == sender) _messageFromRow(r),
        ];
      });
});

Message _messageFromRow(MessagesTableData r) => Message(
  localId: r.localId,
  serverId: r.serverId,
  conversationId: r.conversationId,
  senderId: r.senderId,
  type: r.type,
  decryptedBody: bodyCache.get(r.localId),
  replyToId: r.replyToId,
  isDeletedForEveryone: r.isDeletedForEveryone,
  isDeletedForMe: r.isDeletedForMe,
  isPinned: r.isPinned,
  isStarred: r.isStarred,
  status: r.status,
  createdAt: r.createdAt,
  mediaId: r.mediaId,
  decryptState: r.decryptState,
  ciphertextLength: r.encryptedBody.length,
  albumId: r.albumId,
  albumIndex: r.albumIndex,
);
