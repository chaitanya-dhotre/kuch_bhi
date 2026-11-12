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

  /// 'text' | 'image' | 'video' | 'voice' | 'poll' | 'system' | 'sticker'
  TextColumn get type => text()();

  /// AES-256-GCM ciphertext, base64 encoded.
  TextColumn get encryptedBody => text()();

  /// AES IV, base64 encoded.
  TextColumn get iv => text()();

  // T9 (spec §3 / schema v10): the `decryptedBody` plaintext column is
  // DROPPED — bodies decrypt on read into the in-memory body cache via
  // `messageBodyProvider`; the DB stores ciphertext + decrypt_state +
  // key_id only. No plaintext body store exists anywhere.
  //
  // P7 (spec §3 / schema v11): the `replyPreview` column is DROPPED too —
  // a reply quote DERIVES its text from the parent row through
  // `messageBodyProvider` at render time. Nothing preview-shaped is ever
  // durable (user ruling: plaintext previews at rest = merge blocker).

  TextColumn get replyToId => text().nullable()();

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

  /// Decrypt lifecycle (spec §5.1, schema v9 / Task 7):
  /// 'pending' = committed, decrypt not yet attempted ·
  /// 'key_missing' = attempted, key unavailable (retried on key arrival) ·
  /// 'ready' = decryptable (key resolves) · 'failed' = terminal bad MAC.
  /// Default 'ready': legacy pre-v9 rows carry `decryptedBody`, so they
  /// read as decryptable without a backfill.
  TextColumn get decryptState =>
      text().withDefault(const Constant('ready'))();

  /// Key/epoch reference so a later reader knows which key the ciphertext
  /// needs after rotation (spec §5.1). Nullable — Task 8 wires population;
  /// Task 7 only preserves it across re-caches.
  TextColumn get keyId => text().nullable()();

  /// Albums (schema v13): photos/videos sent together share the record id
  /// of item 0 as [albumId]; [albumIndex] is the pick order. Null = not in
  /// an album (the server's empty `album_id` maps to null).
  TextColumn get albumId => text().nullable()();
  IntColumn get albumIndex => integer().nullable()();

  /// Disappearing timer (schema v14): the length in seconds the server fixed
  /// when this message arrived. Null = it never disappears. [expiresAt] stays
  /// null until the clock starts, which is when the message is read.
  IntColumn get disappearAfter => integer().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {localId};
}
