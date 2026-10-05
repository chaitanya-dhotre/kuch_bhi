import 'package:drift/drift.dart';

/// Core messages table. Uses a local UUID as primary key for
/// offline-first support. serverId is null until synced to PocketBase.
/// The unique index on serverId makes duplicate bubbles impossible by
/// construction — the FCM background isolate's placeholder writes update
/// the main-isolate row instead of inserting a second one (schema v6).
@TableIndex(name: 'idx_messages_server_id', columns: {#serverId}, unique: true)
class MessagesTable extends Table {
  /// Local UUID — always set immediately on message creation.
  TextColumn get localId => text()();

  /// PocketBase record ID — null until server confirms receipt.
  TextColumn get serverId => text().nullable()();

  TextColumn get conversationId => text()();
  TextColumn get senderId => text()();

  /// 'text' | 'image' | 'video' | 'voice' | 'poll' | 'system'
  TextColumn get type => text()();

  /// AES-256-GCM ciphertext, base64 encoded.
  TextColumn get encryptedBody => text()();

  /// AES IV, base64 encoded.
  TextColumn get iv => text()();

  /// Decrypted plaintext — cached after first decryption to avoid
  /// re-decrypting on every rebuild. Never sent to server.
  TextColumn get decryptedBody => text().nullable()();

  TextColumn get replyToId => text().nullable()();
  TextColumn get replyPreview => text().nullable()();

  BoolColumn get isDeletedForEveryone =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get isDeletedForMe =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  BoolColumn get isStarred => boolean().withDefault(const Constant(false))();

  DateTimeColumn get expiresAt => dateTime().nullable()();

  /// PocketBase `message_media` record ID — set for voice/image/video/document messages.
  TextColumn get mediaId => text().nullable()();

  /// 'pending' | 'sent' | 'delivered' | 'read' | 'failed'
  TextColumn get status => text().withDefault(const Constant('pending'))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {localId};
}
