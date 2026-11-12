import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:pocketbase/pocketbase.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/app_strings.dart';
import '../../core/decrypt/body_cache.dart';
import '../../core/decrypt/decrypt_pass.dart';
import '../../core/decrypt/device_key_store.dart';
import '../../core/network/pocketbase_client.dart';
import '../../core/utils/format_utils.dart';
import '../../core/utils/group_visibility.dart';
import '../../core/utils/jpeg_without_exif.dart';
import '../../core/utils/key_gap.dart';
import '../../core/utils/op_id.dart';
import '../../core/utils/realtime_gate.dart';
import '../../core/utils/serial_per_key.dart';
import '../../core/utils/session_epoch.dart';
import '../../core/utils/sync_cursor.dart';
import '../../data/local/database/app_database.dart';
import '../../data/local/database/tables/app_settings_table.dart';
import '../../data/local/database/tables/outbox_table.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/group_invite.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/message_repository.dart';
import '../../features/chat/providers/chat_provider.dart' show ReactionGroup;
import '../../features/stickers/stickers.dart' show stickerBody;
import '../offline/outbox_worker.dart';
import '../media/media_blob_store.dart';
import '../ingest/ingest_batch.dart';
import '../ingest/ingest_boundary.dart';
import '../../services/encryption_service.dart';
import '../../services/media_upload_service.dart';
import '../../services/upload_progress.dart';
import '../../data/local/secure_storage/secure_storage_service.dart';
import '../../services/fcm_service.dart';

/// PocketBase duplicate-create parser — ENTRY POINT for the spec §5.2
/// already-sent path. True ONLY when [error] is HTTP 400
/// `validation_not_unique` on FIELD `id` (the exact shape Task 1 pinned
/// against the live server: docs/offline-phase0-verification.md §(c)2,
/// `{"data":{"id":{"code":"validation_not_unique",…}},…,"status":400}`).
/// A uniqueness failure on ANY other field (e.g. `iv`) is not a duplicate
/// send and must never be counted as delivered — it maps through the
/// normal error class instead (Task 3).
///
/// Task 6 note: stays a TOP-LEVEL parse here (create-side ownership flow —
/// see `resolveDuplicateSend`); only the ack WRITE after a verified
/// duplicate rides IngestBoundary.
bool isDuplicateIdError(ClientException error) {
  if (error.statusCode != 400) return false;
  final data = error.response['data'];
  if (data is! Map) return false;
  final fieldError = data['id'];
  if (fieldError is! Map) return false;
  return fieldError['code'] == 'validation_not_unique';
}

class MessageRepositoryImpl implements MessageRepository {
  /// I1 (final fix pass): injection seam fired INSIDE the production
  /// `sendMessage` enqueue transaction, immediately before the outbox row
  /// is written. Arming it to THROW proves the REAL txn (not a
  /// test-authored one) rolls back BOTH the message row and the outbox op.
  ///
  /// The RF1 atomicity test wrote both rows inside its own
  /// `db.transaction(...)` — that pins Drift's rollback, not the production
  /// path. Null in production.
  @visibleForTesting
  static void Function()? debugBeforeOutboxEnqueue;

  MessageRepositoryImpl({
    required this.pbClient,
    required this.db,
    required this.storage,
    required this.encryption,
    required this.mediaUploadService,
  }) {
    // ── Task 3: the OutboxWorker owns the drain FSM, the connectivity
    // listener (moved from _initConnectivityRetry) and stale-`sending`
    // recovery. Built FIRST: the kick below and every hook route through it.
    outboxWorker = OutboxWorker(
      outbox: db.outboxDao,
      messages: db.messagesDao,
      settings: db.settingsDao,
      send: sendOutboxOp,
    );
    // Task 5: blob FSM + janitor/eviction kick (construction-time
    // maintenance — OutboxWorker precedent).
    mediaBlobStore = MediaBlobStore(
      dao: db.mediaBlobDao,
      messages: db.messagesDao,
      pbClient: pbClient,
      encryption: encryption,
      resolveKey: (convId) async => _getConvKey(convId, await _myId()),
      // Spec §11 (fix I1): live session epoch — same counter the repo's
      // own write guards read (logout/account switch bumps it).
      epoch: () => _sessionEpoch,
    );
    // Task 6: IngestBoundary is the SOLE writer of network-sourced message
    // records (spec §4/§7) — built like outboxWorker/mediaBlobStore so the
    // epoch/auth seams read the repo's live session state.
    ingestBoundary = IngestBoundary(
      db: db,
      epoch: () => _sessionEpoch,
      authValid: () => _pb.authStore.isValid,
    );
    // Task 8: DecryptPass (spec §8) — same ctor pattern so its apply-step
    // guard reads the repo's LIVE session epoch (dropped results after
    // logout/account-switch never touch Drift or the body cache). P8 also
    // hands it the device key store so a `device_sealed` row unwraps on
    // read (the bubble renders, the placeholder law is never violated).
    deviceKeyStore = DeviceKeyStore(storage);
    decryptPass = DecryptPass(
      db: db,
      enc: encryption,
      epoch: () => _sessionEpoch,
      deviceKeys: deviceKeyStore,
    );
    // Kick off the very first connect (serialized — see _reconnect).
    _reconnect();
    // D4: a reconnect resumes media uploads (app start runs through
    // retryPendingMessages).
    Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        unawaited(resumeMediaUploads());
      }
    });

    // A restored session starts "authenticated" so the first authRefresh
    // token rotation is treated as same-session churn, not a fresh login.
    _wasAuthenticated = _pb.authStore.isValid;
    // Seed the identity too (review minor): without it the first auth event
    // compares prev=null != id and does one spurious rebuild per session.
    // Init-once — never overwrite a value a later event already resolved.
    unawaited(
      storage.getCurrentUserId().then((id) {
        if (_realtimeUserId == null && id != null && id.isNotEmpty) {
          _realtimeUserId = id;
        }
      }),
    );

    // Re-subscribe ONLY on identity change (login/logout/account switch) —
    // token-string churn from authRefresh must not rebuild the SSE client.
    _pb.authStore.onChange.listen((event) async {
      // Fix R1: outbox unpause seam runs FIRST — before the same-session
      // early-return below — so every token save (login, refresh, rotation)
      // releases an outbox 401 pause (spec §6 resume-on-reauth).
      handleAuthStoreChange(event.token);
      final authenticated = event.token.isNotEmpty;
      String? userId;
      if (authenticated) {
        for (var i = 0; i < 10; i++) {
          userId = await storage.getCurrentUserId();
          if (userId != null && userId.isNotEmpty) break;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
      if (!shouldReconnectRealtime(
        wasAuthenticated: _wasAuthenticated,
        isAuthenticated: authenticated,
        previousUserId: _realtimeUserId,
        newUserId: userId,
      )) {
        debugPrint('[Msg] Auth token changed (same session) — ignoring.');
        return;
      }
      _wasAuthenticated = authenticated;
      _realtimeUserId = userId;
      _sessionEpoch++; // in-flight work from the old session must not write
      // Task 8 (spec §3/§11): the in-memory decrypt cache is session-scoped
      // too — logout / account switch purges it alongside the epoch bump.
      bodyCache.clear();
      _cutoffCache.clear(); // identity changed — group cutoffs are per-user
      _removalMissCounts.clear(); // and removal verdicts are per-user too
      _repairMissCounts.clear(); // and the repair give-up count is per-user
      // P8 (F1 fix): the device-local outbox key lives in a
      // session-scoped secure-storage slot, so the in-memory copy is
      // session-scoped too. Without this, the next keyless enqueue in the
      // new session seals under the OLD key whose slot was wiped — the row
      // is unopenable by any future process.
      deviceKeyStore.forget();
      // C (2026-10-14): the group-key memory is session-scoped too — without
      // this the next account would read the previous account's keys from
      // RAM (signOut wipes the disk slots; this fires on any identity
      // change, including the null transition after that wipe).
      encryption.clearAllGroupKeyCache();
      if (authenticated) {
        debugPrint('[Msg] Auth identity changed — reconnecting subscriptions.');
        _reconnect();
      } else {
        debugPrint('[Msg] Logged out — unsubscribing.');
        _pendingJoinEmitConvIds.clear(); // no join polls for the previous user
        for (final t in _rotateDebounce.values) {
          t.cancel();
        }
        _rotateDebounce.clear(); // no stale auto-rotates for the previous user
        // Spec D5: cancel the ticking timers too — nothing may run against
        // the wiped session.
        _pollTimer?.cancel();
        _reconnectTimer?.cancel();
        _reconnectDebounce?.cancel();
        _mediaResumeRetry?.cancel();
        _teardown();
      }
    });
  }

  bool _wasAuthenticated = false;
  String? _realtimeUserId;
  Timer? _reconnectDebounce;

  /// Bumped on every auth identity change (login/logout/account switch).
  /// Async work captures it at start and re-checks before DB writes —
  /// INSERTs into the signOut-wiped tables would repopulate the next
  /// account's data (review C1, spec D5).
  int _sessionEpoch = 0;

  /// Fix R1 — PRODUCTION unpause path for the outbox's 401 pause.
  /// Invoked from the `authStore.onChange` listener for EVERY token save —
  /// login AND refresh/rotation — BEFORE the same-session early-return, so
  /// an expired-token pause (spec §6: "pause until re-auth succeeds") is
  /// always released on re-auth. Empty token (logout/clear) does NOT
  /// resume here — the signOut wipe owns that path. Resume on an
  /// already-unpaused outbox is a no-op, so rotation noise is harmless.
  ///
  /// Extracted from the inline listener so tests can drive the seam
  /// directly (`repo.handleAuthStoreChange(token)`).
  @visibleForTesting
  void handleAuthStoreChange(String token) {
    if (token.isNotEmpty) {
      outboxWorker.onAuthResumed();
    }
  }

  final PocketBaseClient pbClient;
  final AppDatabase db;
  final SecureStorageService storage;
  final EncryptionService encryption;
  final MediaUploadService mediaUploadService;

  /// Task 3: drain FSM + connectivity/auth hooks. Exposed for tests and
  /// for [retryOp]/[discardOp] delegation (Task 4 banner routes here).
  late final OutboxWorker outboxWorker;

  /// Task 5: MediaBlobStore is the SOLE writer of blob rows + files
  /// (spec §4). Built here (same precedent as [outboxWorker]) so the
  /// store's key resolution reuses [_getConvKey]; exposed for the
  /// mediaFileProvider re-point (chat_provider.dart).
  late final MediaBlobStore mediaBlobStore;

  /// Task 6: IngestBoundary is the SOLE writer of network-sourced message
  /// records (spec §4/§7). The repo keeps fetch/SSE orchestration (network,
  /// decrypt, flag preservation) and delegates every such record write to
  /// `ingestBoundary.commit(batch, source)` — SSE handler, fetch loop and
  /// the interim drain-ack body all route here. Exposed for tests
  /// (outboxWorker/mediaBlobStore precedent).
  late final IngestBoundary ingestBoundary;

  /// Task 8: batch decrypt orchestrator (spec §8) — constructed here so
  /// its epoch seam reads [_sessionEpoch]; exposed for
  /// `decryptPassProvider` (chat_provider / mediaFileProvider precedent).
  late final DecryptPass decryptPass;

  /// P8 (user ruling): the device-local key that wraps a body at keyless
  /// enqueue so the outbox row survives a kill without durable plaintext.
  /// Lives over the app's EXISTING secure storage (§11) — no new crypto
  /// dependency, and `clearSession()` wipes it with the session.
  late final DeviceKeyStore deviceKeyStore;

  /// T9 carry-in (brief): fired AFTER a write lands REAL ciphertext for a
  /// message the drain/upload just stamped (`_sendTextOp` dual-truth txn,
  /// media upload stamp). `messageBodyProvider` values do not re-run on
  /// row-stream emissions, so watchers of that id must be invalidated
  /// explicitly or a bubble that resolved null while the row was
  /// `__pending__` stays at the placeholder forever. Wired by
  /// `decryptPassProvider`'s build — every null-resolving body read
  /// funnels through it (T8 `onApplied` bridge pattern — alive-guarded,
  /// last-writer-wins across containers, ledgered like T8's).
  void Function(String messageId)? onBodyStamped;

  PocketBase get _pb => pbClient.pb;
  static const _uuid = Uuid();

  final _reactionsCtrl = StreamController<String>.broadcast();
  final _mediaChangesCtrl = StreamController<String>.broadcast();

  /// Conversations where an accepted invite's "X joined the group" bubble is
  /// still deferred (no admin device has rotated the group key yet). Retried
  /// on every resume sync — see [_emitJoinedWhenKeyReady].
  final Set<String> _pendingJoinEmitConvIds = {};

  @override
  Stream<String> get reactionsChanges => _reactionsCtrl.stream;

  /// Emits the message serverId of any `message_media` record created or
  /// updated on the server (SSE). Bubbles use this to recover from the
  /// upload race where the messages row hits the realtime feed BEFORE its
  /// media row exists — see mediaFileProvider (#18).
  @override
  Stream<String> get mediaChanges => _mediaChangesCtrl.stream;

  // ── Realtime subscription lifecycle ───────────────────────────
  //
  // PocketBase's subscribe()/unsubscribe() are ASYNC under the hood (they
  // negotiate a single shared /api/realtime SSE client). Firing them
  // concurrently — which used to happen from the constructor, the auth-change
  // listener and resyncOnResume all at once — corrupts that shared client
  // ("Missing or invalid client id", "Cannot add new events after close") and
  // leaves every subscription dead. So ALL connect/teardown work is funnelled
  // through a single serialized chain (_opChain) and guarded by retry+backoff.
  // A lightweight poll fallback keeps devices without a working SSE/FCM path
  // (e.g. de-Googled ROMs) up to date.

  Future<void> _opChain = Future.value();
  bool _subscribed = false;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  Timer? _pollTimer;

  /// Serializes [action] after any in-flight connect/teardown so the shared
  /// SSE client is never mutated concurrently.
  Future<T> _serialize<T>(Future<T> Function() action) {
    final next = _opChain.then((_) => action());
    // Keep the chain alive even if an action throws.
    _opChain = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<void> _teardown() => _serialize(_teardownInner);

  Future<void> _teardownInner() async {
    _subscribed = false;
    for (final c in const [
      'messages',
      'conversations',
      'conversation_members',
      'message_receipts',
      'reactions',
      'message_media',
    ]) {
      try {
        await _pb.collection(c).unsubscribe('*');
      } catch (_) {}
    }
    debugPrint('[Msg] Unsubscribed from all PocketBase collections.');
  }

  /// Public entry point — always safe to call, always serialized.
  /// Debounced 500ms so rapid identity/connectivity fires collapse into a
  /// single teardown+subscribe cycle instead of rebuilding the SSE client
  /// N times.
  void _reconnect() {
    _reconnectDebounce?.cancel();
    _reconnectDebounce = Timer(const Duration(milliseconds: 500), () {
      _reconnectTimer?.cancel();
      _serialize(() async {
        if (!_pb.authStore.isValid) return;
        try {
          await _teardownInner();
          await _subscribeAll();
          _subscribed = true;
          _reconnectAttempts = 0;
          debugPrint('[Msg] Realtime subscriptions established.');
          _startPollFallback();
        } catch (e) {
          _subscribed = false;
          _reconnectAttempts += 1;
          // Exponential backoff, capped at 30s.
          final delay = Duration(
            seconds: (1 << (_reconnectAttempts.clamp(0, 5))).clamp(1, 30),
          );
          debugPrint(
            '[Msg] Subscribe failed ($e). Retrying in ${delay.inSeconds}s.',
          );
          _reconnectTimer = Timer(delay, _reconnect);
          // Even while SSE is down, keep polling so the UI still updates.
          _startPollFallback();
        }
      });
    });
  }

  /// Awaits each subscribe() so failures propagate to the retry logic and the
  /// shared SSE client is built up one collection at a time.
  Future<void> _subscribeAll() async {
    await _subMessages();
    await _subConversations();
    await _subMembers();
    await _subReceipts();
    await _subReactions();
    await _subMedia();
  }

  /// SSE pin/delete sync companion (Task 6 review I1): the FULL row built
  /// from [existing] with the server's pin/delete flags. Every one of the
  /// messages table's 21 columns must be carried EXPLICITLY — the
  /// boundary's delete-then-insert rebuilds the row from this companion,
  /// so an omitted column resets to its default (I1: a missing
  /// `expiresAt` wiped the expiry of a disappearing message on an SSE pin
  /// toggle). Extracted so `ingest_boundary_test` pins the production
  /// column set, not a test-side copy.
  @visibleForTesting
  MessagesTableCompanion ssePinDeleteCompanion({
    required MessagesTableData existing,
    required bool serverPinned,
    required bool serverDeleted,
  }) => MessagesTableCompanion.insert(
    localId: existing.localId,
    serverId: Value(existing.serverId),
    conversationId: existing.conversationId,
    senderId: existing.senderId,
    type: existing.type,
    encryptedBody: existing.encryptedBody,
    iv: existing.iv,
    replyToId: Value(existing.replyToId),
    isPinned: Value(serverPinned),
    isStarred: Value(existing.isStarred),
    isDeletedForMe: Value(existing.isDeletedForMe),
    isDeletedForEveryone: Value(serverDeleted),
    expiresAt: Value(existing.expiresAt), // I1 — never drop
    mediaId: Value(existing.mediaId),
    status: Value(existing.status),
    // Task 7: full-row rebuild via the boundary — carry decrypt_state /
    // key_id like every other preserved column (omission would reset a
    // key_missing row to the column default 'ready').
    decryptState: Value(existing.decryptState),
    keyId: Value(existing.keyId),
    albumId: Value(existing.albumId),
    albumIndex: Value(existing.albumIndex),
    disappearAfter: Value(existing.disappearAfter),
    createdAt: existing.createdAt,
    updatedAt: DateTime.now(),
  );

  Future<void> _subMessages() async {
    // Messages subscription — handles incoming messages from all conversations
    await _pb.collection('messages').subscribe('*', onMessageEvent);
  }

  @visibleForTesting
  Future<void> onMessageEvent(RecordSubscriptionEvent event) async {
    // A delete (the disappearing cron) carries the dead record: ingesting it
    // would bring the row back. The phone's own clock removes its copy.
    if (event.record == null || event.action == 'delete') return;
    final r = event.record!;
    final myId = await _myId();
    // Never process incoming events before the session id is known — that
    // caused own-message echoes and empty recipient_id receipts.
    if (myId.isEmpty) return;

    // Sync pin + delete-for-everyone state for ANY message (including our
    // own), so these reflect live across devices without reopening.
    // Task 6: the former fast-path write is now an IngestBoundary commit
    // (the SSE fast path is gone — spec §4: no third writer).
    try {
      final existing = await db.messagesDao.getMessageByServerId(r.id);
      if (existing != null) {
        final serverPinned = r.getBoolValue('is_pinned');
        final serverDeleted = r.getBoolValue('is_deleted_for_everyone');
        if (serverPinned != existing.isPinned ||
            serverDeleted != existing.isDeletedForEveryone) {
          await ingestBoundary.commit(
            IngestBatch(
              upserts: [
                MessageUpsert(
                  ssePinDeleteCompanion(
                    existing: existing,
                    serverPinned: serverPinned,
                    serverDeleted: serverDeleted,
                  ),
                ),
              ],
            ),
            IngestSource.sse,
          );
        }
      }
    } catch (_) {}

    // Skip our own sent messages for the incoming-decrypt path — already
    // handled optimistically in sendMessage (pin/delete synced above).
    if (r.getStringValue('sender_id') == myId) return;

    final convId = r.getStringValue('conversation_id');
    final senderId = r.getStringValue('sender_id');
    try {
      // Ensure sender is cached in Drift (important for group messages)
      if (await db.usersDao.getUserById(senderId) == null) {
        try {
          final u = await _pb.collection('users').getOne(senderId);
          await _cacheUserRecord(u);
        } catch (_) {}
      }
      List<int>? key;
      try {
        key = await _getConvKey(convId, myId);
      } on MissingKeyException catch (e) {
        debugPrint('[Msg] incoming key not ready, caching ciphertext: $e');
        key = null;
      }
      // Cache even if we can't decrypt yet — a later fetch/reconcile will
      // decrypt once the key is available. Message is never lost.
      // Task 7: pass the NULL key through (was: `key ?? const <int>[]`)
      // so the row lands decrypt_state='key_missing', not 'pending'.
      await _cacheMsg(r, myId, key, source: IngestSource.sse);
      // Acknowledge delivery so the sender's tick advances — narrative
      // 'system' rows carry no ticks, skip them.
      if (r.getStringValue('type') != 'system') {
        await _markDelivered(r.id, convId, myId);
      }
      // Drift stream auto-emits — no manual push needed
    } catch (e) {
      debugPrint('[Msg] incoming error: $e');
    }
  }

  Future<void> _subConversations() async {
    // Keep home screen in sync when a chat is created or membership changes
    // on the other device.
    await _pb.collection('conversations').subscribe('*', (_) {
      _syncConversationsBackground();
    });
  }

  /// Per-conversation rotate debounce (one rotation per join burst).
  final Map<String, Timer> _rotateDebounce = {};
  final _rotations = SerialPerKey();

  Future<void> _subMembers() async {
    await _pb.collection('conversation_members').subscribe('*', (event) {
      _cutoffCache.clear(); // membership changed somewhere — recompute
      _syncConversationsBackground();
      if (event.action != 'create' || event.record == null) return;
      final r = event.record!;
      _maybeScheduleRotate(
        r.getStringValue('conversation_id'),
        r.getStringValue('user_id'),
      );
    });
  }

  /// Invite-accept self-joins create the member row from the JOINER's device.
  /// Key distribution must come from a key-holding device: any admin of the
  /// group rotates (debounced) so the joiner receives the current key.
  Future<void> _maybeScheduleRotate(String convId, String newUserId) async {
    if (convId.isEmpty) return;
    final myId = await _myId();
    if (myId.isEmpty || newUserId == myId) return;
    final conv = await db.conversationsDao.getConversationById(convId);
    if (conv?.type != 'group') return;
    if (!await isCurrentUserAdmin(convId)) return;

    // Deterministic rotate election: with 2+ admins online, every admin
    // device used to schedule its own rotation; both then read the same
    // next key_version before either wrote, colliding on
    // UNIQUE(conversation_id,user_id,key_version). All admins now compute
    // the same single owner (smallest admin user id) and only that device
    // rotates. If the owner is offline, no rotation happens on this pass —
    // the joiner's key-poll and the resume retry reconcile later.
    if (!await _isRotationOwner(convId, myId)) return;

    _rotateDebounce[convId]?.cancel();
    _rotateDebounce[convId] = Timer(const Duration(seconds: 3), () async {
      _rotateDebounce.remove(convId);
      try {
        await _rotateGroupKey(convId, myId);
      } catch (e) {
        debugPrint('[Group] auto-rotate on join failed: $e');
      }
    });
  }

  /// Election helper: true only if [myId] is the elected rotation owner —
  /// the lexicographically smallest admin user id of [convId]. Every admin
  /// device computes the same owner, so exactly one schedules the rotation.
  /// DAO rows first (cheap); PB fallback when the DAO throws or a fresh
  /// install has no local member rows yet.
  Future<bool> _isRotationOwner(String convId, String myId) async {
    var adminIds = const <String>[];
    try {
      final members = await db.conversationsDao.getAllMembersForConversation(
        convId,
      );
      adminIds = members
          .where((m) => m.role == 'admin')
          .map((m) => m.userId)
          .toList();
    } catch (e) {
      debugPrint('[Group] rotate election: dao member fetch failed: $e');
    }
    if (adminIds.isEmpty) {
      try {
        final recs = await _pb
            .collection('conversation_members')
            .getFullList(
              filter: 'conversation_id="$convId"&&role="admin"',
              batch: 200,
            );
        adminIds = recs.map((r) => r.getStringValue('user_id')).toList();
      } catch (e) {
        debugPrint('[Group] rotate election: pb admin fetch failed: $e');
        // Cannot enumerate admins — isCurrentUserAdmin above already
        // confirmed locally that we are one; proceed rather than stall the
        // joiner's key distribution forever.
        return true;
      }
    }
    final sorted = adminIds.where((id) => id.isNotEmpty).toList()..sort();
    if (sorted.isEmpty) return true;
    if (sorted.first != myId) {
      debugPrint(
        '[Group] rotate election: owner=${sorted.first}, me=$myId -> skip',
      );
      return false;
    }
    return true;
  }

  Future<void> _subReceipts() async {
    // Receipts subscription — updates tick status
    await _pb.collection('message_receipts').subscribe('*', (event) async {
      if (event.record == null) return;
      final r = event.record!;
      final myId = await _myId();
      if (myId.isEmpty) return;
      final msgServerId = r.getStringValue('message_id');
      final recipientId = r.getStringValue('recipient_id');
      final deliveredAt = r.getStringValue('delivered_at');
      final readAt = r.getStringValue('read_at');

      debugPrint(
        '[Receipt] Subscription update - msg: $msgServerId, recipient: $recipientId, delivered: ${deliveredAt.isNotEmpty}, read: ${readAt.isNotEmpty}',
      );

      try {
        final local = await db.messagesDao.getMessageByServerId(msgServerId);
        if (local == null) {
          debugPrint(
            '[Receipt] Local message not found for server ID: $msgServerId',
          );
          return;
        }

        // Only update status for messages I sent
        if (local.senderId != myId) {
          debugPrint(
            '[Receipt] Ignoring receipt update for message sent by someone else',
          );
          return;
        }

        debugPrint(
          '[Receipt] Updating status for local message: ${local.localId}',
        );
        await _updateMsgReceiptStatus(local.localId, msgServerId);
        // Drift auto-emits after the status update above
      } catch (e) {
        debugPrint('[Receipt] ERROR in subscription update: $e');
      }
    });
  }

  Future<void> _subReactions() async {
    // Reactions subscription — fires on both devices when any reaction changes.
    await _pb.collection('reactions').subscribe('*', (event) async {
      if (event.record == null) return;
      final msgServerId = event.record!.getStringValue('message_id');
      if (msgServerId.isNotEmpty) {
        debugPrint('[Reaction] Change detected for message: $msgServerId');
        _reactionsCtrl.add(msgServerId);
      }
    });
  }

  Future<void> _subMedia() async {
    // Media records land AFTER their messages row (the sender uploads the
    // encrypted file only after creating the message, since the media row
    // needs the message id), so the message's live SSE echo can beat the
    // media row by seconds. Broadcast the message_id so open bubbles can
    // retry their media fetch the moment the row exists (#18).
    await _pb.collection('message_media').subscribe('*', (event) {
      final r = event.record;
      if (r == null) return;
      final messageId = r.getStringValue('message_id');
      if (messageId.isNotEmpty) {
        debugPrint('[Media] Change detected for message: $messageId');
        _mediaChangesCtrl.add(messageId);
      }
    });
  }

  // ── Poll fallback ─────────────────────────────────────────────
  // For devices where SSE is flaky or FCM is unavailable (de-Googled ROMs),
  // poll the active conversations every few seconds so incoming messages,
  // receipts, reactions, pins and deletions still surface without a reopen.
  //
  // IMPORTANT: this loop only does the heavy work (re-fetch messages +
  // receipts + full conversation sync) when SSE is NOT healthy — i.e. when
  // `_subscribed == false`. When realtime is live, those updates arrive via
  // the subscriptions, so re-fetching here would re-cache every message every
  // 5s, and each cached row re-emits via the Drift stream → the open chat's
  // `markConversationRead` listener fires N times → a server round-trip for
  // each → creates receipts → the receipts subscription floods. That was the
  // "receipts run infinitely while a chat is open" storm.

  void _startPollFallback() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        final myId = await _myId();
        if (myId.isEmpty) return;
        final active = _activeConversationId;
        if (active != null && !_subscribed) {
          // SSE is down — re-fetch messages + receipts for the on-screen chat.
          await _fetchAndCacheMessages(active);
          // Task 7: the fetch cursor now advances PAST key_missing rows, so
          // the poll's old implicit heal ("re-deliver the same window until
          // the key lands") is gone — run the bounded repair pass instead
          // (one indexed query; no-op without stuck rows, decrypts once the
          // key has arrived while the chat stays open).
          await _repairUndecrypted(active);
          await _reconcileReceiptsForConversation(active, myId);
        }
        // Only reconcile the conversation list server-side when SSE is down;
        // when it's live, subscription handlers already drive `_syncConversations`.
        if (!_subscribed) {
          await _syncConversations(myId);
        }
      } catch (e) {
        debugPrint('[Msg] poll fallback: $e');
      }
    });
  }

  /// The conversation currently on screen (set by watchMessages). Polled more
  /// eagerly than the rest so the open chat feels live even without SSE.
  String? _activeConversationId;

  // Task 3: `_initConnectivityRetry` MOVED into OutboxWorker — its listener
  // now calls OutboxWorker.onConnectivityRestored (attempts reset + drain).

  // ── Watch conversations (Drift reactive) ──────────────────────

  @override
  Stream<List<Conversation>> watchConversations() {
    _syncConversationsBackground(); // Fire-and-forget

    return db.conversationsDao.watchAllConversations().asyncMap(
      (rows) => _convRowsToEntities(rows),
    );
  }

  Future<void> _syncConversationsBackground() async {
    try {
      final myId = await _myId();
      await _syncConversations(myId);
      // D2 (loading-issue fix): post-login / home-watch path — same
      // prefetch as resyncOnResume, so the first chat open after a fresh
      // login (or pm-clear) finds warm keys too.
      unawaited(prefetchGroupKeys());
    } catch (e) {
      debugPrint('[Conv] background sync: $e');
    }
  }

  /// #71 Prewarm (2026-10-14): decrypt the VISIBLE home previews FIRST —
  /// newest conversations first — before backfill and background key
  /// refreshes, so the conversation list never shows preview locks while
  /// work happens behind it. Purely local: the newest non-deleted row per
  /// membership (the exact row `conversationLastMessageProvider` renders);
  /// media/system rows are skipped — the widget layer shows a constant
  /// label for those and never decrypts (spec §3/P7). Rows already warm in
  /// the body cache are skipped. Called from [_resyncRun]: full path
  /// always, light path only when the cache was purged (paused → quick
  /// return under the cutoff), so a quick HOME-and-back never flashes
  /// preview locks either. Unawaited there — badge/messages never wait.
  bool _prewarmInFlight = false;
  Future<void> prewarmHomePreviews({int limit = 15}) async {
    if (_prewarmInFlight) return;
    _prewarmInFlight = true;
    try {
      final myId = await _myId();
      if (myId.isEmpty) return;
      final memberships = await db.conversationsDao.getMembershipsOfUser(myId);
      final convs = <ConversationsTableData>[];
      for (final m in memberships) {
        if (m.role == 'left') continue;
        final conv =
            await db.conversationsDao.getConversationById(m.conversationId);
        if (conv != null) convs.add(conv);
      }
      // Newest activity first — the preview the user is most likely to
      // read gets its plaintext first.
      convs.sort((a, b) => (b.lastMessageAt ?? b.createdAt)
          .compareTo(a.lastMessageAt ?? a.createdAt));
      final ids = <String>[];
      for (final conv in convs.take(limit)) {
        final row = await db.messagesDao.newestVisibleMessage(conv.id);
        if (row == null || row.type != 'text') continue;
        if (bodyCache.get(row.localId) != null) continue;
        ids.add(row.localId);
      }
      debugPrint(
        '[Msg] prewarm scan: convs=${convs.map((c) => c.id).toList()} '
        'limit=$limit ids=$ids',
      );
      if (ids.isEmpty) {
        debugPrint('[Msg] prewarm: 0 previews (cache warm or no text rows)');
        return;
      }
      await decryptPass.runFor(ids);
      debugPrint(
        '[Msg] prewarm: ${ids.length} previews decrypted '
        '(${convs.length} convs scanned)',
      );
    } catch (e) {
      debugPrint('[Msg] prewarmHomePreviews: $e');
    } finally {
      _prewarmInFlight = false;
    }
  }

  /// #74 tap-down predecrypt: kicked by the conversation tile on
  /// POINTER-DOWN, before navigation — the ~250ms open transition hides
  /// the runFor, so bubbles that first build during the transition
  /// resolve from `bodyCache` instead of the coalescer's 50ms window +
  /// decrypt (tap→text ≤100ms p95 target, Astra recs). Local-only (key
  /// memory, spec C); the cache-miss filter makes repeat presses and
  /// already-warm rows free. Never throws into navigation.
  @override
  Future<void> predecryptConversation(
    String conversationId, {
    int limit = 30,
  }) async {
    try {
      final rows = await db.messagesDao.recentBodyMessages(
        conversationId,
        limit: limit,
      );
      final ids = [
        for (final r in rows)
          if (bodyCache.get(r.localId) == null) r.localId,
      ];
      if (ids.isEmpty) {
        debugPrint('[Msg] tap-predecrypt conv=$conversationId warm '
            '(0 misses over ${rows.length} rows)');
        return;
      }
      final tapClock = Stopwatch()..start();
      await decryptPass.runFor(ids);
      debugPrint(
        '[Msg] tap-predecrypt conv=$conversationId n=${ids.length} '
        'ms=${tapClock.elapsedMilliseconds}',
      );
    } catch (e) {
      debugPrint('[Msg] tap-predecrypt failed: $e');
    }
  }

  /// D2 (loading-issue fix, 2026-10-13): hydrate group-key caches for every
  /// group whose keys are not yet resident, so a chat open NEVER pays a
  /// network round-trip — the video's 1–4s lock window was exactly a cold
  /// conv hydrating at open. Runs after conversation syncs (launch, resume,
  /// post-login home watch); warm conversations cost one local storage scan
  /// and zero requests ([EncryptionService.hasLocalGroupKey]). Failures are
  /// per-conversation and swallowed — a conv stays cold and its open falls
  /// back to the candidates path's own network hydrate.
  bool _prefetchKeysInFlight = false;
  Future<void> prefetchGroupKeys() async {
    if (_prefetchKeysInFlight) return;
    _prefetchKeysInFlight = true;
    try {
      final myId = await _myId();
      if (myId.isEmpty) return;
      final memberships = await db.conversationsDao.getMembershipsOfUser(myId);
      final groupConversationIds = <String>[];
      for (final m in memberships) {
        if (m.role == 'left') continue;
        final conv = await db.conversationsDao.getConversationById(
          m.conversationId,
        );
        if (conv?.type == 'group') groupConversationIds.add(m.conversationId);
      }
      final warmGroupIds = await encryption.getLocalGroupKeyConversationIds(
        groupConversationIds,
      );
      var warm = 0;
      var hydrated = 0;
      for (final conversationId in groupConversationIds) {
        if (warmGroupIds.contains(conversationId)) {
          warm++;
          continue;
        }
        try {
          await encryption.getOrFetchGroupKeyCandidates(conversationId, myId);
          hydrated++;
        } catch (e) {
          debugPrint('[Msg] group-key prefetch failed for $conversationId: $e');
        }
      }
      debugPrint('[Msg] group-key prefetch: warm=$warm hydrated=$hydrated');
    } catch (e) {
      debugPrint('[Msg] prefetchGroupKeys: $e');
    } finally {
      _prefetchKeysInFlight = false;
    }
  }

  // ── Watch messages (Drift reactive) ──────────────────────────

  /// Returns Drift's own reactive stream.
  /// Auto-emits on every table write — including optimistic inserts.
  /// No manual StreamController needed.
  ///
  /// COLD-START: if the local Drift cache for this conversation is empty we
  /// HOLD the stream until the first server fetch completes, so Riverpod
  /// reports `AsyncLoading` (spinner) rather than `AsyncData([])` ("Say hello
  /// 👋") during the 1–2s before the fetch writes the rows. If we already have
  /// cached rows (re-entering a chat) we hand them back immediately and let
  /// the background fetch update the stream reactively — no warm-open delay.
  @override
  Stream<List<Message>> watchMessages(String conversationId) {
    // Track the on-screen conversation for the poll fallback — set FIRST so the
    // poll can track it even while the fetch below is awaiting.
    _activeConversationId = conversationId;
    return _messagesStream(conversationId);
  }

  /// Spec B8. Server time only: a phone's clock moved ahead must never delete
  /// a message early, and with no server time yet this waits for the next
  /// open. Files first, so a kill between the two steps repeats the purge
  /// rather than strand a decrypted photo with no row pointing at it.
  Future<void> _purgeExpired() async {
    final now = pbClient.serverClock.now;
    if (now == null) return;
    try {
      final myId = await _myId();
      if (myId.isEmpty) return;
      for (final row in await db.messagesDao.getExpiredMessages(now)) {
        if (row.senderId != myId && !await _readReceiptOnServer(row, myId)) {
          continue;
        }
        final sid = row.serverId;
        if (sid != null) await mediaBlobStore.forgetLocal(sid);
        await db.messagesDao.deleteByLocalId(row.localId);
      }
    } catch (e) {
      debugPrint('[Msg] purge: $e');
    }
  }

  /// Spec B7: the server's clock only starts on my receipt, and a purged row
  /// can no longer send one, so the sender's copy and the server's would stay
  /// for good. False only when the network failed: the row waits. A refusal
  /// is final, and must not keep an expired message on this phone.
  Future<bool> _readReceiptOnServer(MessagesTableData row, String myId) async {
    final sid = row.serverId;
    if (sid == null) return true;
    final nowUtc = DateTime.now().toUtc().toIso8601String();
    final receipts = _pb.collection('message_receipts');
    try {
      final res = await receipts.getList(
        filter: 'message_id="$sid"&&recipient_id="$myId"',
        perPage: 1,
      );
      if (res.items.isEmpty) {
        await receipts.create(
          body: {
            'message_id': sid,
            'conversation_id': row.conversationId,
            'recipient_id': myId,
            'delivered_at': nowUtc,
            'read_at': nowUtc,
          },
        );
      } else if (res.items.first.getStringValue('read_at').isEmpty) {
        await receipts.update(res.items.first.id, body: {'read_at': nowUtc});
      }
      return true;
    } on ClientException catch (e) {
      return e.statusCode != 0;
    }
  }

  /// Backlog §170 fix (b): the count behind the "old messages need
  /// re-sharing" empty state. Shares [getUndecryptableRows]'s query with the
  /// repair pass, which is the point — the same rows the repair pass cannot
  /// decrypt are the rows the screen must stop reporting as "nothing here".
  /// Returns a number only; ciphertext and plaintext never leave the DB.
  @override
  Future<int> countUndecryptable(String conversationId) async {
    try {
      final rows = await db.messagesDao.getUndecryptableRows(
        conversationId,
        limit: 500,
      );
      return rows.length;
    } catch (_) {
      return 0;
    }
  }

  Stream<List<Message>> _messagesStream(String conversationId) async* {
    // Before the first emission: an expired row on screen would ask for its
    // media again. Bounded, so a slow network can't hold the chat open.
    await _purgeExpired().timeout(
      const Duration(seconds: 2),
      onTimeout: () {},
    );
    // Peek at the current local cache once to choose the cold vs warm path.
    final cached = await db.messagesDao.watchMessages(conversationId).first;
    if (cached.isEmpty) {
      // Cold: await the first server fetch so the UI shows a spinner, not the
      // empty-state, before the rows arrive. _fetchAndCacheMessages swallows its
      // own errors (offline) so on failure we still yield the (empty) Drift
      // stream below → "Say hello 👋" shows correctly when truly unreachable.
      await _fetchAndCacheMessages(conversationId);
      unawaited(_repairUndecrypted(conversationId));
    } else {
      // Warm: hand cached rows back instantly; refresh in the background.
      _fetchAndCacheMessages(conversationId);
      unawaited(_repairUndecrypted(conversationId));
    }

    await for (final rows in db.messagesDao.watchMessages(conversationId)) {
      debugPrint(
        '[Msg] watchMessages EMIT — convId: $conversationId, rowCount: ${rows.length}',
      );
      yield await _rowsToMessages(rows);
    }
  }

  /// Group-history cutoff per conversation (member joinedAt), cached —
  /// _rowsToMessages runs on EVERY table write; per-emit DAO round-trips
  /// multiplied the watch storm. Invalidated on membership change via
  /// [_invalidateCutoff].
  final Map<String, DateTime?> _cutoffCache = {};

  /// §7 false-removal guard — consecutive membership-list misses per
  /// conversation since the row was last seen. A verdict requires
  /// [_removalConfirmMisses] misses in a row PLUS a confirmation point
  /// query reporting the row gone (see the reconcile loop in
  /// [_syncConversations]). Session-scoped: cleared on identity change.
  final Map<String, int> _removalMissCounts = {};

  /// Misses needed before a confirmed absence condemns the row. 2 = one
  /// stale-snapshot cycle is forgiven (fresh-group race), a real removal
  /// still lands on the very next sync after that.
  static const int _removalConfirmMisses = 2;

  /// Consecutive repair passes per conversation that healed NOTHING
  /// (backlog §170). A row stuck on a key this device can never obtain is
  /// unrecoverable, and the pass used to retry it on every single open
  /// forever. After [_repairGiveUp] fruitless passes the row is left alone
  /// until the key actually arrives (which invalidates via
  /// [_invalidateCutoff]-style reset below). Session-scoped: cleared on
  /// identity change.
  final Map<String, int> _repairMissCounts = {};

  /// Fruitless passes before a row is left to the banner path. 2 forgives a
  /// transient heal race; an unrecoverable row stops costing an open.
  static const int _repairGiveUp = 2;

  /// How many times the repair pass has actually run per conversation
  /// (backlog §170). Readable so a test can prove the give-up budget stops
  /// the retries — the pass has no other observable seam.
  @visibleForTesting
  final Map<String, int> debugRepairRuns = {};


  /// Drops the cached group cutoff for [convId] and reopens the repair
  /// budget: every caller of this is a membership/key change, which is exactly
  /// when a row previously given up on might now be healable (backlog §170).
  void _invalidateCutoff(String convId) {
    _cutoffCache.remove(convId);
    _repairMissCounts.remove(convId);
  }

  Future<DateTime?> _groupCutoff(String convId) async {
    if (_cutoffCache.containsKey(convId)) return _cutoffCache[convId];
    DateTime? cutoff;
    final conv = await db.conversationsDao.getConversationById(convId);
    if (conv?.type == 'group') {
      final myId = await _myId();
      final members = await db.conversationsDao.getAllMembersForConversation(
        convId,
      );
      cutoff = members.where((m) => m.userId == myId).firstOrNull?.joinedAt;
    }
    _cutoffCache[convId] = cutoff;
    return cutoff;
  }

  Future<List<Message>> _rowsToMessages(List<MessagesTableData> rows) async {
    final myId = await _myId();
    if (rows.isEmpty) return [];
    final conv = await db.conversationsDao.getConversationById(
      rows.first.conversationId,
    );
    final joinedAt = await _groupCutoff(rows.first.conversationId);
    // A group row without a local membership record is not yet authorized
    // locally (fresh install/sync race, or membership loss). Fail closed
    // instead of exposing the full server history while the cutoff is null.
    if (conv?.type == 'group' && joinedAt == null) return [];
    return [
      for (final r in rows)
        if (joinedAt == null ||
            isGroupRowVisible(
              createdAt: r.createdAt,
              memberJoinedAt: joinedAt,
              decryptState: r.decryptState,
              type: r.type,
            ))
          _rowToMessage(r, myId),
    ];
  }

  // ── Send message ──────────────────────────────────────────────

  @override
  Future<void> sendMessage({
    required String conversationId,
    required String plaintext,
    String? replyToLocalId,
  }) => _enqueueTextSend(conversationId, plaintext, replyToLocalId, 'text');

  /// Mascot §J2.4: a sticker is a text send whose body names the sticker, so
  /// the queue, F-b cancel, burst-order lift and offline count stay one path.
  @override
  Future<void> sendSticker({
    required String conversationId,
    required String stickerId,
    String? replyToLocalId,
  }) => _enqueueTextSend(
    conversationId,
    stickerBody(stickerId),
    replyToLocalId,
    'sticker',
  );

  Future<void> _enqueueTextSend(
    String conversationId,
    String plaintext,
    String? replyToLocalId,
    String type,
  ) async {
    final myId = await _myId();
    // Hard group-membership gate (#17): the chat screen hides the composer
    // for removed/left members, this covers races (removed while the
    // composer was open) and retry paths.
    await _assertCanSend(conversationId);
    final localId = _uuid.v4();
    final now = DateTime.now();

    debugPrint(
      '[Msg] Sending message - localId: $localId, convId: $conversationId',
    );
    debugPrint(
      '[Msg] OPTIMISTIC INSERT — localId: $localId, convId: $conversationId, senderId: $myId',
    );

    // ── Atomic enqueue (spec §5.2): message row + outbox op in ONE
    // Drift transaction — a kill between them is impossible by
    // construction (ghost message / lost send cannot happen).
    //
    // C1 (spec §5.2 "Enqueue atomicity", final fix pass): the body
    // ENCRYPTION runs inside that same transaction while the conversation
    // key resolves, so the committed row carries REAL ciphertext + iv and
    // no plaintext-only copy exists anywhere (neither the row nor the
    // outbox payload). Before this, enqueue stored `__pending__` with the
    // plaintext in the in-memory body cache alone — backgrounding
    // (`bodyCache.clear()`, app.dart:69) or a process kill destroyed the
    // only copy, so the drain read a cache miss and deferred FOREVER
    // (permanent non-delivery, device-proven in matrix R2: 5 ops queued,
    // attempts=0). bodyCache.put(plaintext) STAYS below for display
    // (spec §5.1: the bubble never flashes a placeholder).
    //
    // Keyless enqueue: the KEYLESS-SEALED path (P8, user ruling). The
    // conversation key did not resolve, so the body is wrapped with the
    // DEVICE-LOCAL key (secure storage, §11) and that SEALED ciphertext
    // + iv land in the same row. Before P8 this wrote the interim
    // `__pending__` marker with the plaintext in the body cache alone —
    // backgrounding or a process kill destroyed the only copy, so the
    // outbox could lose a send forever (matrix R2: 5 ops, attempts=0).
    // Spec §3 forbids durable PLAINTEXT, not durable sealed text, which is
    // exactly what this writes. The drain re-encrypts to the group key the
    // moment it arrives (see [_sendTextOp]).
    //
    // Encryption-at-enqueue (C1, spec §5.2): resolve the key OUTSIDE the
    // transaction (it may hit the network / secure storage), then write the
    // row, the outbox op AND the ciphertext in ONE transaction. A helper
    // returns null instead of assigning inside a catch, which Dart's
    // definite-assignment analysis cannot prove unreachable.
    final List<int>? enqueueKey = await _tryResolveSendKey(
      conversationId,
      myId,
    );
    final EncryptResult? encBody = enqueueKey == null
        ? null
        : await encryption.encryptMessage(plaintext, enqueueKey);
    // P8 seals only when the CONVERSATION key is absent. A failure of the
    // device-key path must not break the send: it falls back to the legacy
    // `__pending__` marker (C1's drain still persists at first encrypt), so
    // this change can only make the keyless path SURVIVABLE, never worse.
    EncryptResult? sealedBody;
    String? sealedKeyId;
    if (enqueueKey == null) {
      try {
        final deviceKey = await deviceKeyStore.resolve();
        sealedBody = await encryption.encryptMessage(plaintext, deviceKey);
        sealedKeyId = deviceKeyStore.keyId(deviceKey);
        // P8 (F2): when the secure-storage slot was cleared or corrupted,
        // resolve() regenerates and every row sealed under the OLD key becomes
        // permanently undecryptable. Silent orphans are the F2 shape — report
        // the count loudly instead (recovery is impossible: the old key is
        // unrecoverable by construction).
        if (deviceKeyStore.wasRegenerated) {
          final orphans = (await db.select(db.messagesTable).get())
              .where(
                (m) =>
                    m.decryptState == kDeviceSealedState &&
                    m.keyId != sealedKeyId,
              )
              .length;
          if (orphans > 0) {
            debugPrint(
              '[P8] Device key REGENERATED — $orphans sealed '
              'outbox row(s) are now UNDECRYPTABLE (old key unrecoverable)',
            );
          }
        }
      } catch (e) {
        debugPrint('[Msg] P8 device-key seal failed — legacy marker: $e');
      }
    }
    // C1 covers the BODY. The REPLY PREVIEW (P7, spec §3 / user ruling:
    // plaintext previews at rest = merge blocker) is NOT stored locally at
    // all — `messages.reply_preview` is dropped in schema v11. The quote
    // derives the parent text from the parent row through
    // `messageBodyProvider` at render time, so enqueue writes nothing
    // preview-shaped. The preview still rides to the SERVER encrypted
    // (`_sendTextOp` below) because the server-side contract is unchanged.

    await db.transaction(() async {
      // I1: production-path injection seam — fires INSIDE the real enqueue
      // transaction just before the outbox write, so a test can prove the
      // production txn (not a test-authored one) rolls BOTH rows back.
      debugBeforeOutboxEnqueue?.call();
      await db.messagesDao.upsertMessage(
        MessagesTableCompanion.insert(
          localId: localId,
          conversationId: conversationId,
          senderId: myId,
          type: type,
          // Real ciphertext when the key resolved (C1); the DEVICE-SEALED
          // ciphertext when the keyless path sealed under the device key
          // (P8); the interim marker only if even that failed. Never a
          // plaintext column (spec §3, T9 drop).
          encryptedBody:
              encBody?.ciphertext ?? sealedBody?.ciphertext ?? '__pending__',
          iv: encBody?.iv ?? sealedBody?.iv ?? '',
          replyToId: Value(replyToLocalId),
          status: Value('pending'),
          createdAt: now,
          updatedAt: now,
          // Own rows resolve on read: decrypt_state='ready' + key_id so a
          // cache miss re-decrypts instead of rendering a placeholder
          // (spec §5.1: "own sent messages are never placeholders"). A
          // keyless-sealed row instead carries `device_sealed` + the device
          // key's fingerprint — the body IS here, under the device key
          // (P8), so it renders via an unwrap on read rather than a
          // placeholder.
          decryptState: Value(
            sealedBody == null ? 'ready' : kDeviceSealedState,
          ),
          keyId: Value(
            enqueueKey == null
                ? sealedKeyId
                : DecryptPass.fingerprintOf(enqueueKey),
          ),
        ),
      );
      await db.outboxDao.enqueue(
        OutboxTableCompanion.insert(
          opId: generateOpId(),
          kind: 'text_send',
          ref: localId,
          conversationId: conversationId,
          seq: await db.outboxDao.nextSeq(conversationId),
          createdAt: now,
        ),
      );
    });
    // T9 carry-in (spec §5.1): own-sent bodies resolve instantly from the
    // cache — the provider never sees this id as unresolvable while the
    // row is optimistic.
    bodyCache.put(localId, plaintext);
    debugPrint(
      '[Msg] OPTIMISTIC INSERT DONE — myId: $myId, convId: $conversationId',
    );

    // ── Drain kick (Task 3): the OutboxWorker drains the queued op —
    // FSM-driven (error classes/backoff/FIFO) instead of the interim
    // direct send. Fire-and-forget, exactly as before.
    outboxWorker.kick();
  }

  /// Kind-sender for [OutboxWorker] (brief §Interfaces: the worker's
  /// "repo-ish sender callback"). Dispatches on `op.kind`:
  ///  - `text_send` → the network-create path moved out of the old
  ///    `_drainOutbox`/`sendMessage` send, now op-aware (client id on the
  ///    create + error propagation for the worker's FSM);
  ///  - everything else → loud [StateError]: outgoing `media_upload`
  ///    enqueue wiring is a plan follow-up (progress.md ruling — nothing
  ///    enqueues other kinds yet; the worker's dependency gating for them
  ///    is covered by seeded-row tests).
  ///
  /// Contract with the worker:
  ///  - success → message row stamped + outbox `sent` in ONE txn →
  ///    [OpSendOutcome.sent];
  ///  - local defer (no key / no session / row gone) →
  ///    [OpSendOutcome.deferred] — re-queue, NO schedule change;
  ///  - HTTP failures → thrown ([ClientException], or rethrown after the
  ///    duplicate-id ownership check) for `nextAttempt` classification.
  Future<OpSendOutcome> sendOutboxOp(OutboxTableData op) async {
    switch (op.kind) {
      case 'text_send':
        return _sendTextOp(op);
      case _reactionAdd:
        return _sendReactionAddOp(op);
      case _reactionRemove:
        return _sendReactionRemoveOp(op);
      default:
        throw StateError('No sender wired for outbox kind "${op.kind}"');
    }
  }

  /// `text_send` sender: body moved from the interim `_drainOutbox`
  /// (itself `_uploadMessage` renamed — guard 5 lineage), adapted to the
  /// op-driven flow:
  ///  1. derives all send inputs from the op + its message row;
  ///  2. create carries `'id': op.opId` (spec §5.2 idempotency key);
  ///  3. duplicate-id → [resolveDuplicateSend] ownership check (success or
  ///     terminal verdict), never a blind re-create;
  ///  4. failures PROPAGATE to the worker (old catch-all → message
  ///     'failed' is gone: the FSM decides terminal vs backoff).
  Future<OpSendOutcome> _sendTextOp(OutboxTableData op) async {
    final localId = op.ref;
    final conversationId = op.conversationId;
    final msg = await db.messagesDao.getMessageByLocalId(localId);
    if (msg == null) {
      // Message row gone (discarded/wiped) — the op can never complete.
      await db.outboxDao.deleteOp(op.opId);
      return OpSendOutcome.deferred;
    }
    if (msg.status == 'cancelled') return _finishCancelledText(op); // F-b
    // C1 (final fix pass): the row's ciphertext is the SOURCE OF TRUTH for
    // the drain. Enqueue encrypted inside its transaction (spec §5.2), so a
    // cleared/never-warmed body cache (backgrounding, process kill) can
    // NEVER defer an op whose ciphertext is already durable. The cache is
    // the fast path (no crypto hop) and the display source, not a
    // requirement.
    //
    // Keyless enqueue: the row may still carry the interim `__pending__`
    // (P8's device-key seal also failed), and the plaintext may be in the
    // cache (only if this same process enqueued it). Decrypting the stored
    // ciphertext is preferred; the cache is used ONLY when there is no
    // ciphertext to decrypt.
    //
    // P8 DEVICE-SEALED row: the body is durable, sealed under the
    // DEVICE-LOCAL key. Unwrap it with that key — a cleared cache then
    // cannot change the outcome, exactly like the C1 group-key path. The
    // unwrapped plaintext feeds only the send below; the row stays sealed
    // at rest (spec §3) until the group key arrives and [key] re-encrypts.
    final myId = await _myId();
    if (myId.isEmpty) {
      return OpSendOutcome.deferred; // session not ready — retry on kick
    }
    final createdAt = msg.createdAt;

    final uploadEpoch = _sessionEpoch;
    debugPrint('[Msg] Starting upload for localId: $localId');

    final bool needFreshBody =
        msg.encryptedBody.isEmpty || msg.encryptedBody == '__pending__';
    final bool deviceSealed =
        msg.decryptState == kDeviceSealedState && !needFreshBody;
    String? plaintext;
    if (deviceSealed) {
      // P8: unwrap with the device-local key. The cached plaintext (this
      // process enqueued it) is only a fallback for a seal written under a
      // key that secure storage no longer holds.
      try {
        final deviceKey = await deviceKeyStore.resolve();
        plaintext = await encryption.decryptMessage(
          msg.encryptedBody,
          msg.iv,
          deviceKey,
        );
      } catch (e) {
        debugPrint('[Msg] P8 device unwrap failed, trying cache: $e');
      }
      final cached = bodyCache.get(localId);
      if (plaintext == null || plaintext.isEmpty) plaintext = cached;
      if (plaintext == null || plaintext.isEmpty) {
        return OpSendOutcome.deferred; // nothing sendable yet
      }
    } else if (!needFreshBody) {
      // C1: re-derive the plaintext from the DURABLE ciphertext — a cleared
      // cache must not change the outcome.
      try {
        final rowKey = await _getConvKey(conversationId, myId);
        plaintext = await encryption.decryptMessage(
          msg.encryptedBody,
          msg.iv,
          rowKey,
        );
      } on MissingKeyException catch (e) {
        // Row key unavailable: fall back to the cache (this process may
        // still hold the plaintext) — if that is empty too, defer.
        debugPrint('[Msg] Row key unavailable, trying cache: $e');
      } catch (e) {
        debugPrint('[Msg] Row ciphertext undecryptable, trying cache: $e');
      }
      // decryptMessage returns NULL (not throws) for a MAC/parse failure —
      // including a placeholder ciphertext written by a test seed or a
      // corrupted row. Either way the session cache is the next source.
      final cached = bodyCache.get(localId);
      if (plaintext == null || plaintext.isEmpty) {
        plaintext = cached;
      }
      if (plaintext == null || plaintext.isEmpty) {
        return OpSendOutcome.deferred; // nothing sendable yet
      }
    } else {
      // Keyless enqueue: plaintext exists ONLY in the cache for the
      // remainder of this process. A cache miss is the honest defer.
      plaintext = bodyCache.get(localId);
      if (plaintext == null) {
        return OpSendOutcome.deferred; // nothing to send yet
      }
    }
    // From here on `plaintext` is non-null (both branches returned on null).
    final String body = plaintext;

    // Resolve the parent row FIRST (P7): the wire-bound reply preview is
    // DERIVED from it below — the local row no longer stores one (schema
    // v11 dropped `messages.reply_preview`).
    String? replyServerId;
    MessagesTableData? replyMsg;
    final replyRef = msg.replyToId;
    if (replyRef != null && replyRef.isNotEmpty) {
      replyMsg =
          await db.messagesDao.getMessageByLocalId(replyRef) ??
          await db.messagesDao.getMessageByServerId(replyRef);
      replyServerId = replyMsg?.serverId;
    }

    final List<int> key;
    final EncryptResult encrypted;
    final EncryptResult? encryptedReply;
    try {
      key = await _getConvKey(conversationId, myId);
      encrypted = await encryption.encryptMessage(body, key);
      // Encrypt the reply preview too — it must never hit the server as
      // plaintext. P7: the preview is DERIVED from the parent row here
      // (no durable column to read), so the server payload keeps its exact
      // 'iv:ciphertext' shape.
      final replyPreview = await _deriveReplyPreview(replyMsg, key);
      encryptedReply = (replyPreview != null && replyPreview.isNotEmpty)
          ? await encryption.encryptMessage(replyPreview, key)
          : null;
      debugPrint('[Msg] Message encrypted successfully');
    } on MissingKeyException catch (e) {
      // Key not ready yet (peer key not synced / offline). Keep the message
      // PENDING so it retries automatically — do NOT mark failed, and never
      // send under a placeholder key.
      debugPrint('[Msg] Key not ready, staying pending: $e');
      await db.messagesDao.updateMessageStatus(localId, 'pending');
      return OpSendOutcome.deferred;
    } catch (e) {
      // Local crypto failure — not retryable by backoff. Terminal on both
      // rows (worker sees state != sending and leaves it alone).
      debugPrint('[Msg] Encryption failed: $e');
      await db.messagesDao.updateMessageStatus(localId, 'failed');
      await db.outboxDao.setState(
        op.opId,
        OutboxState.failedTerminal,
        lastError: '$e',
        errorClass: 'encrypt_failed',
      );
      return OpSendOutcome.deferred;
    }

    // C1 (final fix pass): persist the ciphertext to the row BEFORE the
    // server create. A keyless enqueue carries the interim `__pending__`, so
    // this first successful encrypt is the moment the durable copy exists —
    // a kill between here and the ack now resumes from row ciphertext
    // instead of losing the message (the row id == op id, so the re-send is
    // idempotent: spec §5.2 duplicate-id = success). Only the keyless path
    // needs the write; the enqueue-time ciphertext is already durable.
    //
    // P8: the DEVICE-SEALED row needs the same write — the ruling's
    // "re-encrypt to the group key when it arrives". The device-wrapped copy
    // is durable SEND-material, but it must not become the row's final
    // at-rest state: every other device decrypts under the GROUP key, so a
    // row left `device_sealed` after a successful send would be undecryptable
    // anywhere else. The write below is therefore the promotion point:
    // sealed-ciphertext-in → group-ciphertext + `ready` out, before create.
    if (needFreshBody || deviceSealed) {
      await db.messagesDao.upsertMessage(
        MessagesTableCompanion.insert(
          localId: localId,
          conversationId: conversationId,
          senderId: myId,
          type: msg.type,
          encryptedBody: encrypted.ciphertext,
          iv: encrypted.iv,
          createdAt: msg.createdAt,
          updatedAt: DateTime.now(),
          decryptState: const Value('ready'),
          keyId: Value(DecryptPass.fingerprintOf(key)),
        ),
      );
      debugPrint(
        '[Msg] C1: ciphertext persisted before create '
        '(${deviceSealed ? 'P8 device-sealed' : 'keyless'} path)',
      );
    }

    debugPrint('[Msg] Creating message record on server');
    final RecordModel record;
    try {
      record = await _pb
          .collection('messages')
          .create(
            body: {
              // spec §5.2: the op id IS the server record id (idempotency key).
              'id': op.opId,
              'conversation_id': conversationId,
              'sender_id': myId,
              'type': msg.type,
              'encrypted_body': encrypted.ciphertext,
              'iv': encrypted.iv,
              'reply_to_id': replyServerId ?? '',
              // Encrypted preview stored as 'iv:ciphertext' (empty when no reply).
              'reply_preview': encryptedReply == null
                  ? ''
                  : '${encryptedReply.iv}:${encryptedReply.ciphertext}',
              'is_deleted_for_everyone': false,
            },
          );
    } on ClientException catch (e) {
      if (isDuplicateIdError(e)) {
        // Timeout-retry / send-after-kill: the record already exists.
        final ours = await resolveDuplicateSend(
          opId: op.opId,
          senderId: myId,
          conversationId: conversationId,
        );
        if (!ours) return OpSendOutcome.deferred; // collision verdict written
        // F-b: deleted during this retry; the ack left the tombstone alone.
        final now = await db.messagesDao.getMessageByLocalId(localId);
        return now?.status == 'cancelled'
            ? _finishCancelledText(op)
            : OpSendOutcome.sent;
      }
      rethrow; // real HTTP failure → worker classifies via nextAttempt
    }
    debugPrint('[Msg] Message created on server with serverId: ${record.id}');

    final serverCreated = DateTime.tryParse(record.created) ?? createdAt;
    // Review C1: encryption+create span the gap — never stamp rows into a
    // session that ended mid-send (the local row was wiped with it).
    if (!sessionStillValid(
      epochAtStart: uploadEpoch,
      currentEpoch: _sessionEpoch,
      authValid: _pb.authStore.isValid,
    )) {
      debugPrint('[Msg] send landed after logout — local write skipped');
      return OpSendOutcome.deferred;
    }
    // Dual-truth txn (spec §5.1): message stamp + outbox `sent` together.
    final cancelled = await db.transaction(() async {
      // F-b: deleted while the create was in flight — never stamped.
      final now = await db.messagesDao.getMessageByLocalId(localId);
      if (now?.status == 'cancelled') return true;
      // Clear any FCM-isolate placeholder for this id so stamping ours
      // cannot violate the serverId unique index.
      await db.messagesDao.deleteByServerIdExcept(record.id, localId);
      await db.messagesDao.upsertMessage(
        MessagesTableCompanion.insert(
          localId: localId,
          serverId: Value(record.id),
          conversationId: conversationId,
          senderId: myId,
          type: msg.type,
          encryptedBody: encrypted.ciphertext,
          iv: encrypted.iv,
          replyToId: Value(replyServerId),
          // Keep the local plaintext reply preview for display.
          status: Value('sent'),
          disappearAfter: Value(_disappearAfterOf(record)),
          // Use the server's canonical timestamp so ordering matches all devices.
          createdAt: serverCreated,
          updatedAt: DateTime.now(),
          // C1: preserve the decrypt state the enqueue/first-encrypt write
          // set ('ready' + key fingerprint) — a full-row rebuild here would
          // otherwise reset the row to the column default and lose key_id.
          decryptState: const Value('ready'),
          keyId: Value(DecryptPass.fingerprintOf(key)),
        ),
      );
      await db.outboxDao.setState(op.opId, OutboxState.sent, attempts: 0);
      await db.messagesDao.liftQueuedTextSends(conversationId, serverCreated);
      return false;
    });
    if (cancelled) return _finishCancelledText(op);
    // T9 carry-in: the ciphertext write + status flip must re-resolve any
    // bubble still watching this id (row streams never invalidate
    // messageBodyProvider) — wired in message_body_provider.dart.
    onBodyStamped?.call(localId);
    debugPrint('[Msg] Local message updated with status: sent');

    // P7 (spec §3): only the ORDERING timestamp is bumped. The old call
    // wrote `body.substring(0, 50)` into `conversations.last_message_preview`
    // — plaintext at rest. The tile now derives the preview from this row
    // through `messageBodyProvider`.
    await db.conversationsDao.updateLastMessage(conversationId, serverCreated);

    debugPrint('[Msg] Creating receipts for serverId: ${record.id}');
    await _createReceipts(record.id, conversationId, myId);
    return OpSendOutcome.sent;
  }

  /// Drain-ack: stamp the message row (`serverId` + `status='sent'`) and
  /// the outbox state in ONE transaction (dual-truth rule — spec §5.1/§7:
  /// `messages.status` only ever mutates alongside the matching
  /// `outbox.state`). [senderId]/[conversationId] guard the update to OUR
  /// row in OUR conversation; the outbox `ref` resolves the local row.
  ///
  /// Task 6 (AS-BUILT): the body is now `ingestBoundary.commit(batch,
  /// IngestSource.drainAck)` — the op read (`outbox.ref` → localId) joins
  /// the boundary's transaction (carry-in 1), the epoch guard wraps the
  /// commit (spec §7), and the signature stays for Task 7+ cleanup.
  Future<void> handleDrainAck(
    String opId, {
    required String serverId,
    required String senderId,
    required String conversationId,
  }) => ingestBoundary.commit(
    IngestBatch(
      ack: OutboxAck(
        opId: opId,
        serverId: serverId,
        senderId: senderId,
        conversationId: conversationId,
      ),
    ),
    IngestSource.drainAck,
  );

  /// Spec §5.2 ownership check for a CONFIRMED duplicate-id create —
  /// call ONLY after [isDuplicateIdError] said the 400 was
  /// `validation_not_unique` on FIELD `id`. Fetches the server record at
  /// [opId] and verifies it is ours (`sender_id` matches the session,
  /// `conversation_id` matches the op):
  ///  - match → already-sent: [handleDrainAck], return `true`
  ///    (the timeout-retry must NOT re-create);
  ///  - `404`/`403` (view rule hides foreign records) or field mismatch →
  ///    `outbox.state = failedTerminal`, `errorClass = 'id_collision'`,
  ///    return `false` — terminal: never retried, never counted success.
  ///
  /// Task 6 note: the ownership check stays HERE untouched (create-side,
  /// carry-in 2) — only its success arm now lands via [handleDrainAck] →
  /// `ingestBoundary.commit(batch, drainAck)`.
  Future<bool> resolveDuplicateSend({
    required String opId,
    required String senderId,
    required String conversationId,
  }) async {
    try {
      final rec = await _pb.collection('messages').getOne(opId);
      final owned =
          rec.getStringValue('sender_id') == senderId &&
          rec.getStringValue('conversation_id') == conversationId;
      if (owned) {
        // C1b (review #72): the duplicate-create FOUND the record already
        // on the server — stamp its server created BEFORE the drain-ack
        // attaches serverId, so the optimistic device-clock createdAt
        // never joins the maxServerCreatedAt watermark (serverId-not-null
        // rows must be server-time only). The local row is keyed by the
        // op's ref, not the op/server id.
        final serverCreated = DateTime.tryParse(rec.created);
        final dupOp = await db.outboxDao.byId(opId);
        if (serverCreated != null && dupOp != null) {
          await db.transaction(() async {
            await db.messagesDao.stampServerCreatedAt(
              dupOp.ref,
              serverCreated,
            );
            await (db.update(db.messagesTable)
                  ..where((t) => t.localId.equals(dupOp.ref)))
                .write(MessagesTableCompanion(
              disappearAfter: Value(_disappearAfterOf(rec)),
            ));
            await db.messagesDao.liftQueuedTextSends(
              conversationId,
              serverCreated,
            );
          });
        }
        await handleDrainAck(
          opId,
          serverId: opId,
          senderId: senderId,
          conversationId: conversationId,
        );
        return true;
      }
      await _markIdCollision(
        opId,
        'id $opId owned by sender=${rec.getStringValue('sender_id')} '
        'conversation=${rec.getStringValue('conversation_id')}',
      );
      return false;
    } on ClientException catch (e) {
      if (e.statusCode == 404 || e.statusCode == 403) {
        await _markIdCollision(
          opId,
          'ownership GET HTTP ${e.statusCode} for id $opId',
        );
        return false;
      }
      rethrow; // transient GET failure — not a collision verdict
    }
  }

  /// Terminal id-collision verdict (spec §5.2): the op is NEVER retried
  /// and NEVER counted as delivered.
  Future<void> _markIdCollision(String opId, String why) =>
      db.outboxDao.setState(
        opId,
        OutboxState.failedTerminal,
        lastError: why,
        errorClass: 'id_collision',
      );

  // ── Send media message ───────────────────────────────────────

  @override
  Future<void> sendMediaMessage({
    required String conversationId,
    required String mediaType,
    required File mediaFile,
    File? thumbnailFile,
    String? quality,
    int? durationSeconds,
    String? durationText,
    int? videoWidth,
    int? videoHeight,
    String? albumId,
    int? albumIndex,
  }) async {
    final myId = await _myId();
    await _assertCanSend(conversationId);
    // B1: a PocketBase-style id from the first frame. It becomes the server
    // record id, so a page fetch mid-upload finds this row instead of
    // inserting a second one (13.7), and a re-run converges on one record.
    // An album's item 0 uses the album id as its own (12.5 A1).
    final localId =
        albumId != null && albumIndex == 0 ? albumId : generateOpId();
    final now = DateTime.now();
    final q = quality ?? 'normal';

    debugPrint(
      '[Msg] Sending media message - type: $mediaType, file: ${mediaFile.path}',
    );

    // B2/C2: the sent file IS the sender's cleartext copy — kept as a ready
    // blob (13.8), with the metadata the bubble needs from frame one.
    final size = mediaType == 'image' ? await _imageSize(mediaFile) : null;
    String meta(File f) => mediaMetaJson(
          LocalMediaFile(
            file: f,
            width: size?.$1 ?? videoWidth,
            height: size?.$2 ?? videoHeight,
            durationSeconds: durationSeconds,
            expiresAt: MediaUploadService.retentionExpiry(mediaType, q),
            mimeType: lookupMimeType(f.path),
            fileName: p.basename(f.path),
          ),
          {'quality': q},
        );
    final moved = <File>[];
    try {
      await db.transaction(() async {
        await db.messagesDao.upsertMessage(
          MessagesTableCompanion.insert(
            localId: localId,
            conversationId: conversationId,
            senderId: myId,
            type: mediaType,
            encryptedBody: '',
            iv: '',
            status: Value('pending'),
            albumId: Value(albumId),
            albumIndex: Value(albumId == null ? null : albumIndex),
            createdAt: now,
            updatedAt: now,
          ),
        );
        for (final (file, thumb) in [
          (mediaFile, false),
          if (thumbnailFile != null) (thumbnailFile, true),
        ]) {
          final f = await mediaBlobStore.registerLocal(
            blobId: mediaBlobId(localId, thumb: thumb),
            file: file,
            meta: meta(file),
            uploadPending: true,
          );
          if (f == null) throw StateError('session ended mid-send');
          moved.add(f);
        }
      });
    } catch (_) {
      // Send-failure rule: no failed row — the composer's toast says so.
      for (final f in moved) {
        try {
          await f.delete();
        } catch (_) {}
      }
      rethrow;
    }
    // T9: duration stub is a body — session cache, never the dropped column.
    if (durationText != null) bodyCache.put(localId, durationText);
    // Album items upload through one serial pass (sendMediaAlbum), never
    // N at once.
    if (albumId != null) return;

    // A network failure while the link looks up retries once by itself
    // (D5); a reconnect or app resume covers the rest.
    unawaited(
      _uploadMediaMessage(localId).then((ok) {
        if (!ok) _retryMediaSoon();
      }),
    );
  }

  @override
  Future<void> sendMediaAlbum({
    required String conversationId,
    required List<AlbumSendItem> items,
    String? quality,
  }) async {
    final albumId = generateOpId();
    try {
      for (final (i, it) in items.indexed) {
        await sendMediaMessage(
          conversationId: conversationId,
          mediaType: it.mediaType,
          mediaFile: it.mediaFile,
          thumbnailFile: it.thumbnailFile,
          quality: quality,
          durationSeconds: it.durationSeconds,
          durationText: it.durationText,
          videoWidth: it.videoWidth,
          videoHeight: it.videoHeight,
          albumId: albumId,
          albumIndex: i,
        );
      }
    } finally {
      // A pass already running read its ids before these rows existed:
      // let it finish, then one more pass picks the album up in order.
      unawaited(() async {
        await _mediaResume;
        await resumeMediaUploads();
      }());
    }
  }

  /// Width/height from the encoded header (no pixel decode).
  static Future<(int, int)?> _imageSize(File f) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(
        await f.readAsBytes(),
      );
      final d = await ui.ImageDescriptor.encoded(buffer);
      final size = (d.width, d.height);
      d.dispose();
      buffer.dispose();
      return size;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _blobMeta(MediaBlobTableData? row) {
    try {
      return row?.meta == null
          ? const {}
          : jsonDecode(row!.meta!) as Map<String, dynamic>;
    } catch (_) {
      return const {};
    }
  }

  /// Offline, a stall, 5xx and 429 wait for the network; any other answer
  /// is final (D5).
  static bool _isTransientUpload(Object e) {
    if (e is ClientException) {
      final s = e.statusCode;
      return s == 0 || s == 429 || s >= 500;
    }
    return e is TimeoutException ||
        e is SocketException ||
        e is http.ClientException;
  }

  /// One upload attempt — fresh send, resume and Try again all run this.
  /// Everything comes from the row and its blob rows, so a re-run after a
  /// kill is the same path. Returns false when it stopped on a network
  /// failure (the row stays `pending`).
  Future<bool> _uploadMediaMessage(String localId) async {
    final ticket = uploadTracker.start(localId);
    if (ticket == null) return true; // already running
    final uploadEpoch = _sessionEpoch;
    bool stillValid() => sessionStillValid(
          epochAtStart: uploadEpoch,
          currentEpoch: _sessionEpoch,
          authValid: _pb.authStore.isValid,
        );
    try {
      final msg = await db.messagesDao.getMessageByLocalId(localId);
      final myId = await _myId();
      if (msg == null || msg.isDeletedForEveryone || myId.isEmpty) {
        return true;
      }
      final conversationId = msg.conversationId;
      final mediaType = msg.type;
      final fullRow = await mediaBlobStore.dao.byId(
        mediaBlobId(localId, thumb: false),
      );
      // Done already (the latch clears with the upload); the status column
      // can't tell: receipts move an acked row to delivered mid-upload.
      if (fullRow != null && !fullRow.uploadPending) return true;
      final thumbRow = await mediaBlobStore.dao.byId(
        mediaBlobId(localId, thumb: true),
      );
      final mediaFile = fullRow?.localPath == null
          ? null
          : File(fullRow!.localPath!);
      if (mediaFile == null || !await mediaFile.exists()) {
        // Legacy row (its file was deleted after the old upload): nothing
        // can ever be uploaded.
        await db.messagesDao.updateMessageStatus(localId, 'failed');
        return true;
      }
      final thumbnailFile = thumbRow?.localPath == null
          ? null
          : File(thumbRow!.localPath!);
      final meta = _blobMeta(fullRow);
      final quality = meta['quality'] as String?;
      final durationSeconds = meta['durationSeconds'] as int? ?? 0;
      final durationText =
          bodyCache.get(localId) ??
          (mediaType == 'voice' ? formatMmSs(durationSeconds) : null);

      // Step A: Get conversation key. Media bytes AND the body stub are
      // E2E-encrypted with this key.
      final List<int> key;
      final EncryptResult encrypted;
      try {
        key = await _getConvKey(conversationId, myId);
        encrypted = await encryption.encryptMessage(durationText ?? '', key);
      } on MissingKeyException catch (e) {
        debugPrint('[Msg] Media key not ready, staying pending: $e');
        await db.messagesDao.updateMessageStatus(localId, 'pending');
        return false;
      } catch (e) {
        final transient = _isTransientUpload(e);
        debugPrint('[Msg] Media encryption failed: $e');
        await db.messagesDao.updateMessageStatus(
          localId,
          transient ? 'pending' : 'failed',
        );
        return !transient;
      }

      // Step B: Create message on PocketBase first (no media_id yet)
      // 'document' is not a valid server enum value — map it to 'file'.
      final serverType = mediaType == 'document' ? 'file' : mediaType;
      var rerun = msg.serverId != null;
      RecordModel record;
      try {
        record = await _pb
            .collection('messages')
            .create(
              body: {
                'id': localId,
                'conversation_id': conversationId,
                'sender_id': myId,
                'type': serverType,
                'encrypted_body': encrypted.ciphertext,
                'iv': encrypted.iv,
                'reply_to_id': '',
                'reply_preview': '',
                'is_deleted_for_everyone': false,
                'media_id': '',
                if (msg.albumId != null) ...{
                  'album_id': msg.albumId,
                  'album_index': msg.albumIndex ?? 0,
                },
              },
            );
      } on ClientException catch (e) {
        if (!isDuplicateIdError(e)) rethrow;
        // A re-run after a lost ack: ours when sender and chat match.
        rerun = true;
        record = await _pb.collection('messages').getOne(localId);
        if (record.getStringValue('sender_id') != myId ||
            record.getStringValue('conversation_id') != conversationId) {
          debugPrint('[Msg] media id $localId belongs to another record');
          await db.messagesDao.updateMessageStatus(localId, 'failed');
          return true;
        }
      }
      if (ticket.cancelled) {
        await _markCancelledOnServer(localId);
        return true;
      }

      // B4: stamp at the create ack, so a page fetch during the upload
      // finds this row by server id. C1 (review #72): the server's created,
      // never device time — device time + serverId would poison the
      // maxServerCreatedAt watermark.
      final serverCreated = DateTime.tryParse(record.created) ?? msg.createdAt;
      debugPrint('[Msg] Media message created on server: $localId');
      if (!stillValid()) {
        debugPrint('[Msg] media send landed after logout — write skipped');
        return true;
      }
      await db.transaction(() async {
        // Placeholder guard: clear any FCM-isolate row holding this id.
        await db.messagesDao.deleteByServerIdExcept(localId, localId);
        await db.messagesDao.stampMediaCreateAck(
          localId,
          serverCreated: serverCreated,
          encryptedBody: encrypted.ciphertext,
          iv: encrypted.iv,
          disappearAfter: _disappearAfterOf(record),
        );
        await db.messagesDao.liftQueuedSends(conversationId, serverCreated);
      });
      if (durationText != null) bodyCache.put(localId, durationText);
      onBodyStamped?.call(localId);

      // Step C: Upload media WITH the message_id now available. A re-run
      // first looks for a media record an earlier attempt already made.
      final existing = rerun ? await _mediaRecordFor(localId) : null;
      final String mediaId;
      final thumbMeta = _blobMeta(thumbRow);
      final sentName = meta['fileName'] as String?;
      final sentThumbName = thumbMeta['fileName'] as String?;
      if (existing != null) {
        mediaId = existing;
      } else if (mediaType == 'image') {
        if (thumbnailFile == null) {
          throw Exception('Thumbnail required for image upload');
        }
        mediaId = await mediaUploadService.uploadImage(
          mediaFile,
          thumbnailFile,
          conversationId,
          quality ?? 'normal',
          localId,
          key,
          ticket: ticket,
          sentName: sentName,
          sentThumbName: sentThumbName,
        );
      } else if (mediaType == 'video') {
        if (thumbnailFile == null) {
          throw Exception('Thumbnail required for video upload');
        }
        mediaId = await mediaUploadService.uploadVideo(
          mediaFile,
          thumbnailFile,
          conversationId,
          quality ?? 'normal',
          durationSeconds,
          localId,
          key,
          videoWidth: meta['width'] as int?,
          videoHeight: meta['height'] as int?,
          ticket: ticket,
          sentName: sentName,
          sentThumbName: sentThumbName,
        );
      } else if (mediaType == 'document') {
        mediaId = await mediaUploadService.uploadDocument(
          mediaFile,
          conversationId,
          localId,
          key,
          ticket: ticket,
          sentName: sentName,
        );
      } else {
        mediaId = await mediaUploadService.uploadVoice(
          mediaFile,
          conversationId,
          durationSeconds,
          localId,
          key,
          ticket: ticket,
          sentName: sentName,
        );
      }
      debugPrint('[Msg] Media uploaded, mediaId: $mediaId');

      // Step D: mediaId + sent; the blobs are ordinary cache entries again.
      if (ticket.cancelled) {
        await _markCancelledOnServer(localId);
        return true;
      }
      if (!stillValid()) {
        debugPrint('[Msg] media send landed after logout — write skipped');
        return true;
      }
      final written = await db.transaction(() async {
        final n = await db.messagesDao.markMediaSent(localId, mediaId);
        await mediaBlobStore.dao.clearUploadPending(localId);
        return n;
      });
      if (written == 0) {
        await _markCancelledOnServer(localId); // cancelled mid-commit
        return true;
      }

      // P7 (spec §3): the media label ('📷 Photo' …) is computed by the
      // tile from `lastMsg.type` at render time — nothing preview-shaped
      // is written to Drift here anymore.
      await db.conversationsDao.updateLastMessage(
        conversationId,
        DateTime.now(),
      );

      await _createReceipts(localId, conversationId, myId);
      return true;
    } catch (e) {
      // The cancel path owns a cancelled row.
      if (ticket.cancelled) return true;
      final transient = _isTransientUpload(e);
      debugPrint(
        '[Msg] media upload ${transient ? 'waiting for network' : 'failed'}: $e',
      );
      if (stillValid()) {
        await db.messagesDao.updateMessageStatus(
          localId,
          transient ? 'pending' : 'failed',
        );
      }
      return !transient;
    } finally {
      uploadTracker.end(localId, ticket);
    }
  }

  /// The `message_media` record an earlier attempt made, or null (404).
  Future<String?> _mediaRecordFor(String messageId) async {
    try {
      final rec = await _pb
          .collection('message_media')
          .getFirstListItem('message_id="$messageId"');
      return rec.id;
    } on ClientException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<bool> cancelMediaUpload(String localId) async {
    final msg = await db.messagesDao.getMessageByLocalId(localId);
    final blob = await mediaBlobStore.dao.byId(
      mediaBlobId(localId, thumb: false),
    );
    // Uploaded already (whatever receipts did to the status): nothing to stop.
    if (msg == null || blob == null || !blob.uploadPending) return false;
    uploadTracker.ticket(localId)?.cancel();
    await db.messagesDao.markCancelledLocally(localId);
    await mediaBlobStore.forgetLocal(localId);
    unawaited(_markCancelledOnServer(localId));
    return true;
  }

  /// D3: a cancelled send's server copy (if it got that far) is marked
  /// deleted for everyone, so receivers never keep an empty bubble. Then
  /// the hidden local row goes. Offline it stays for the next resume pass.
  Future<void> _markCancelledOnServer(String localId) async {
    try {
      await _pb
          .collection('messages')
          .update(localId, body: {'is_deleted_for_everyone': true});
    } catch (e) {
      final never = e is ClientException && e.statusCode == 404;
      // Not created yet, but the create may still be in flight: keep the
      // row, so the upload (or the next resume) marks it once it lands.
      if (never && uploadTracker.ticket(localId) != null) return;
      if (!never && _isTransientUpload(e)) {
        debugPrint('[Msg] cancel mark deferred: $e');
        return;
      }
    }
    await db.messagesDao.deleteByLocalId(localId);
  }

  /// F-b: deleting an own text the outbox has not acked cancels its send,
  /// whichever delete was picked (an unsent text reached no one). The row
  /// gets the media `cancelled` tombstone and its op does the rest when the
  /// worker reaches it ([_finishCancelledText]); a failed op is just dropped,
  /// the server refused it. The op read and the mark share one transaction
  /// with the ack's stamp, so an ack lands either before (false) or after.
  Future<bool> _cancelTextSend(MessagesTableData msg) async {
    final op = await db.transaction(() async {
      final op = (await db.outboxDao.forConversation(msg.conversationId))
          .where((o) => o.kind == 'text_send' && o.ref == msg.localId)
          .firstOrNull;
      if (op == null || op.state == OutboxState.sent) return null;
      if (op.state == OutboxState.failedTerminal) {
        await db.messagesDao.deleteByLocalId(msg.localId);
        await db.outboxDao.deleteOp(op.opId);
      } else {
        await db.messagesDao.markCancelledLocally(msg.localId);
      }
      return op;
    });
    if (op == null) return false;
    outboxWorker.kick();
    return true;
  }

  /// F-b: a cancelled text's create may have reached the server (a lost ack,
  /// or deleted while in flight): mark that copy deleted for everyone, a 404
  /// meaning it never got there, then drop the hidden row(s) and the op.
  /// Offline the throw backs the op off, so the next drain retries the mark.
  Future<OpSendOutcome> _finishCancelledText(OutboxTableData op) async {
    try {
      await _pb
          .collection('messages')
          .update(op.opId, body: {'is_deleted_for_everyone': true});
    } catch (e) {
      final never = e is ClientException && e.statusCode == 404;
      final signedOut = e is ClientException && e.statusCode == 401;
      if (!never && (signedOut || _isTransientUpload(e))) rethrow;
    }
    await db.transaction(() async {
      await db.messagesDao.deleteByLocalId(op.ref);
      await db.messagesDao.deleteByServerIdExcept(op.opId, op.ref); // an echo
      await db.outboxDao.deleteOp(op.opId);
    });
    return OpSendOutcome.deferred;
  }

  Future<void>? _mediaResume;
  Timer? _mediaResumeRetry;

  /// D4: own media rows still `pending` re-run one at a time, oldest first,
  /// on app start (via [retryPendingMessages]) and on every reconnect. A
  /// pass that stops on a network failure tries once more 10s later: the
  /// connectivity event often fires before the link carries traffic.
  Future<void> resumeMediaUploads({bool retryLater = true}) =>
      _mediaResume ??= _resumeMedia(retryLater).whenComplete(
        () => _mediaResume = null,
      );

  Future<void> _resumeMedia(bool retryLater) async {
    final myId = await _myId();
    if (myId.isEmpty) return;
    for (final m in await db.messagesDao.pendingOwnMedia(myId)) {
      if (m.isDeletedForEveryone) await _markCancelledOnServer(m.localId);
    }
    // Uploads: every latched blob, not `status == pending` (a receipt may
    // have moved the row on); op ids sort in send order. Failed = terminal.
    final ids = (await mediaBlobStore.dao.uploadPendingMessageIds())..sort();
    for (final id in ids) {
      final m = await db.messagesDao.getMessageByLocalId(id);
      if (m == null ||
          m.senderId != myId ||
          m.isDeletedForEveryone ||
          m.status == 'failed') {
        continue;
      }
      if (!await _uploadMediaMessage(id)) {
        if (retryLater) _retryMediaSoon();
        return;
      }
    }
  }

  void _retryMediaSoon() {
    _mediaResumeRetry?.cancel();
    _mediaResumeRetry = Timer(
      const Duration(seconds: 10),
      () => unawaited(resumeMediaUploads(retryLater: false)),
    );
  }

  /// Group send-gate (#17): throws when the current user is not an ACTIVE
  /// member of a group conversation (removed or left). DMs always pass.
  Future<void> _assertCanSend(String conversationId) async {
    final conv = await db.conversationsDao.getConversationById(conversationId);
    if (conv?.type != 'group') return;
    final myId = await _myId();
    final members = await db.conversationsDao.getAllMembersForConversation(
      conversationId,
    );
    final mine = members.where((m) => m.userId == myId).firstOrNull;
    if (mine == null || mine.role == 'left') {
      throw StateError('You are no longer a member of this group.');
    }
  }

  // ── Retry pending messages ────────────────────────────────────

  @override
  Future<void> retryPendingMessages() async {
    final pending = await db.messagesDao.getPendingMessages();
    if (pending.isEmpty) return;

    debugPrint('[Msg] Retrying ${pending.length} pending messages.');

    // Resolve our id once; if the session isn't ready, skip this pass entirely
    // (we do NOT delete or fail the user's queued messages — they'll retry).
    final myId = await _myId();
    if (myId.isEmpty) {
      debugPrint('[Msg] Session not ready; deferring pending retry.');
      return;
    }

    // Media rows upload through their own path, never the text outbox.
    unawaited(resumeMediaUploads());
    for (final msg in pending) {
      if (!kTextLikeTypes.contains(msg.type)) continue;
      if (bodyCache.get(msg.localId) == null && msg.mediaId == null) continue;
      // Repair ghost messages whose senderId was lost to an early auth race:
      // adopt the now-known id instead of destroying the user's message.
      if (msg.senderId.isEmpty) {
        debugPrint(
          '[Msg] Repairing pending message ${msg.localId} with resolved senderId.',
        );
      }
      // Never retry into a group we're no longer a member of (#17) — the
      // server would reject the create anyway.
      final conv = await db.conversationsDao.getConversationById(
        msg.conversationId,
      );
      if (conv?.type == 'group') {
        final members = await db.conversationsDao.getAllMembersForConversation(
          msg.conversationId,
        );
        final mine = members.where((m) => m.userId == myId).firstOrNull;
        if (mine == null || mine.role == 'left') {
          debugPrint(
            '[Msg] Skipping retry in group we left: ${msg.conversationId}',
          );
          continue;
        }
      }
      await retryMessage(msg.localId);
    }
  }

  @override
  Future<void> retryMessage(String localId) async {
    final msg = await db.messagesDao.getMessageByLocalId(localId);
    if (msg == null) return;
    // D5 Try again: media re-runs its own upload (an acked create may
    // already have given it a server id).
    if (!kTextLikeTypes.contains(msg.type)) {
      await db.messagesDao.updateMessageStatus(localId, 'pending');
      unawaited(_uploadMediaMessage(localId));
      return;
    }
    // Already synced — nothing to retry.
    if (msg.serverId != null && msg.serverId!.isNotEmpty) return;

    final myId = await _myId();
    if (myId.isEmpty) return;

    // Reset to pending -> Drift stream auto-emits -> retry button disappears
    await db.messagesDao.updateMessageStatus(localId, 'pending');

    // Task 3: route through the outbox (SINGLE send path — the old direct
    // `_drainOutbox` call could race the worker's drain and double-create).
    // Reset the existing op, or enqueue one for pre-outbox legacy rows.
    final ops = await db.outboxDao.forConversation(msg.conversationId);
    OutboxTableData? op;
    for (final o in ops) {
      if (o.ref == localId) {
        op = o;
        break;
      }
    }
    if (op == null) {
      final enqueuedAt = DateTime.now();
      await db.transaction(() async {
        await db.outboxDao.enqueue(
          OutboxTableCompanion.insert(
            opId: generateOpId(),
            kind: 'text_send',
            ref: localId,
            conversationId: msg.conversationId,
            seq: await db.outboxDao.nextSeq(msg.conversationId),
            createdAt: enqueuedAt,
          ),
        );
      });
    } else {
      await db.outboxDao.clearRetry(op.opId);
      await db.outboxDao.setState(op.opId, OutboxState.queued);
    }
    await outboxWorker.drain();
  }

  /// Task 4 banner Retry: re-queue a terminal op (clears its retry
  /// metadata) and drain — delegates to [outboxWorker.retryOp].
  @override
  Future<void> retryOp(String opId) => outboxWorker.retryOp(opId);

  /// Task 4 banner Discard: remove the op + every `dependsOn` dependent
  /// (and their message rows), then drain — see [outboxWorker.discardOp].
  @override
  Future<void> discardOp(String opId) => outboxWorker.discardOp(opId);

  // ── Mark read ─────────────────────────────────────────────────

  @override
  Future<void> markConversationRead(String conversationId) async {
    try {
      final myId = await _myId();
      if (myId.isEmpty) return;
      final nowUtc = DateTime.now().toUtc().toIso8601String();

      // Spec B8 on every open and resume: the chat's message stream is built
      // once per app run, so its own purge only covers the first open.
      await _purgeExpired();

      // Spec B5: first, so reading offline still starts the clock. With no
      // server time yet it starts at the next read, never on the device
      // clock: a clock set back would make the message expire early.
      final readAt = pbClient.serverClock.latest;
      if (readAt != null) {
        await db.messagesDao.startClockOnIncoming(
          conversationId,
          myId,
          readAt,
        );
      }

      // Spec B5: a row I can't show has not been read. A read receipt would
      // start the server's clock and delete it before its key arrives.
      final rows = await db.messagesDao.watchMessages(conversationId).first;
      final readable = {
        for (final row in rows)
          if (row.serverId != null && row.decryptState == 'ready') row.serverId,
      };

      // 1) Mark all my existing unread receipts in this conversation as read.
      // Fetch read ones too: step 2 must skip them, or every open re-creates
      // a receipt per old message (unique-index 400s, then 429 on *:create).
      final res = await _pb
          .collection('message_receipts')
          .getFullList(
            filter:
                'conversation_id="$conversationId"&&recipient_id="$myId"',
            batch: 200,
          );
      for (final r in res) {
        if (r.getStringValue('read_at').isNotEmpty) continue;
        if (!readable.contains(r.getStringValue('message_id'))) continue;
        try {
          await _pb
              .collection('message_receipts')
              .update(
                r.id,
                body: {
                  'read_at': nowUtc,
                  // Ensure delivered is set too — reading implies delivered.
                  if (r.getStringValue('delivered_at').isEmpty)
                    'delivered_at': nowUtc,
                },
              );
        } catch (_) {}
      }

      // 2) For any incoming messages that don't yet have a receipt for me
      //    (e.g. the sender's create failed), create one now marked read.
      final withReceipt = res
          .map((r) => r.getStringValue('message_id'))
          .toSet();
      for (final row in rows) {
        final sid = row.serverId;
        if (sid == null || sid.isEmpty) continue;
        if (row.senderId == myId) continue; // not my own messages
        if (row.type == 'system') continue; // narrative rows carry no receipts
        if (!readable.contains(sid)) continue;
        if (withReceipt.contains(sid)) continue; // already handled above
        try {
          await _pb
              .collection('message_receipts')
              .create(
                body: {
                  'message_id': sid,
                  'conversation_id': conversationId,
                  'recipient_id': myId,
                  'delivered_at': nowUtc,
                  'read_at': nowUtc,
                },
              );
        } catch (_) {
          // Unique-index race — a receipt now exists; mark it read.
          try {
            final ex = await _pb
                .collection('message_receipts')
                .getList(
                  filter: 'message_id="$sid"&&recipient_id="$myId"',
                  perPage: 1,
                );
            if (ex.items.isNotEmpty) {
              await _pb
                  .collection('message_receipts')
                  .update(ex.items.first.id, body: {'read_at': nowUtc});
            }
          } catch (_) {}
        }
      }

      // 3) Reset the LOCAL unread badge for this conversation. Pick the most
      //    recent message localId and persist it as the new last-read cursor so
      //    the next incoming message bumps the count from zero again.
      String? lastReadLocalId;
      if (rows.isNotEmpty) {
        // rows from `watchMessages` are DESC by createdAt → first = newest.
        lastReadLocalId = rows.first.localId;
      }
      await db.conversationsDao.markRead(conversationId, lastReadLocalId ?? '');
    } catch (e) {
      debugPrint('[Receipt] markRead: $e');
    }
  }

  // ── Load more (pagination) ────────────────────────────────────

  @override
  Future<bool> loadMoreMessages(String conversationId, int offset) async {
    try {
      final myId = await _myId();
      final res = await _pb
          .collection('messages')
          .getList(
            filter:
                'conversation_id="$conversationId"&&is_deleted_for_everyone=false',
            sort: '-created',
            page: (offset ~/ 40) + 1,
            perPage: 40,
          )
          .timeout(const Duration(seconds: 8));
      // Same always-commit as the main fetch: no key yet → rows land
      // key_missing and heal on key arrival, instead of failing the page.
      List<List<int>> keys;
      try {
        keys = await _getConvKeyCandidates(conversationId, myId);
      } on MissingKeyException catch (e) {
        debugPrint('[Msg] loadMore key not ready — committing ciphertext: $e');
        keys = const [];
      }
      for (final r in await _withoutRunOut(res.items, myId)) {
        await _cacheMsg(r, myId, keys.firstOrNull, keyCandidates: keys);
      }
      // Drift auto-emits after the inserts above
      return res.items.length >= 40;
    } catch (e) {
      // Rethrown so the chat keeps its offset and offers Retry: a swallowed
      // failure used to skip this page and mark history as ended (bug §1.3).
      debugPrint('[Msg] loadMore: $e');
      rethrow;
    }
  }

  @override
  Future<void> fetchAndCacheSingleMessage(
    String messageId,
    String conversationId,
  ) async {
    try {
      final myId = await _myId();

      // Check if already cached
      final existing = await db.messagesDao.getMessageByServerId(messageId);
      if (existing != null) {
        debugPrint('[Msg] Single message $messageId already cached locally.');
        return;
      }

      final r = await _pb.collection('messages').getOne(messageId);
      final senderId = r.getStringValue('sender_id');

      // Ensure sender is cached in Drift
      if (await db.usersDao.getUserById(senderId) == null) {
        try {
          final u = await _pb.collection('users').getOne(senderId);
          await _cacheUserRecord(u);
        } catch (_) {}
      }

      final keys = await _getConvKeyCandidates(conversationId, myId);
      await _cacheMsg(r, myId, keys.firstOrNull, keyCandidates: keys);
      debugPrint(
        '[Msg] Successfully fetched and cached single message $messageId',
      );
    } on MissingKeyException catch (e) {
      debugPrint('[Msg] single message key not ready: $e');
    } catch (e) {
      debugPrint('[Msg] Error fetching and caching single message: $e');
    }
  }

  // ── Get or create conversation ────────────────────────────────

  @override
  Future<Conversation> getOrCreateDirectConversation(String otherUserId) async {
    final myId = await _myId();

    final existingId = await db.conversationsDao.findDirectConversationId(
      myId,
      otherUserId,
    );

    if (existingId != null) {
      final conv = await db.conversationsDao.getConversationById(existingId);
      if (conv != null) {
        final other = await _getOtherUser(existingId, myId);
        return _convDataToEntity(conv, other);
      }
    }

    await _syncConversations(myId);

    final syncedId = await db.conversationsDao.findDirectConversationId(
      myId,
      otherUserId,
    );
    if (syncedId != null) {
      final conv = await db.conversationsDao.getConversationById(syncedId);
      if (conv != null) {
        final other = await _getOtherUser(syncedId, myId);
        return _convDataToEntity(conv, other);
      }
    }

    throw StateError('Direct conversation not found yet.');
  }

  @override
  Future<void> deleteMessage(String localId, {bool forEveryone = false}) async {
    var row = await db.messagesDao.getMessageByLocalId(localId);
    if (row == null) return;
    if (kTextLikeTypes.contains(row.type) && row.serverId == null) {
      if (await _cancelTextSend(row)) return;
      // Acked meanwhile: the normal delete, with the server id.
      row = await db.messagesDao.getMessageByLocalId(localId) ?? row;
    }
    final msg = row;
    // An own media send still holding its upload latch is cancelled (blobs
    // freed, any server copy hidden) when deleted for everyone, or when it
    // never reached anyone complete (not created yet, or failed for good).
    // Deleted for me, a pending upload just finishes, clearing the latch.
    if ((forEveryone || msg.serverId == null || msg.status == 'failed') &&
        await cancelMediaUpload(localId)) {
      return;
    }

    if (forEveryone) {
      if (msg.serverId != null) {
        try {
          await _pb
              .collection('messages')
              .update(msg.serverId!, body: {'is_deleted_for_everyone': true});
        } catch (e) {
          debugPrint('[Msg] deleteForEveryone: $e');
        }
      }

      await db.messagesDao.upsertMessage(
        MessagesTableCompanion.insert(
          localId: msg.localId,
          serverId: Value(msg.serverId),
          conversationId: msg.conversationId,
          senderId: msg.senderId,
          type: msg.type,
          encryptedBody: msg.encryptedBody,
          iv: msg.iv,
          isDeletedForEveryone: Value(true),
          status: Value(msg.status),
          createdAt: msg.createdAt,
          updatedAt: DateTime.now(),
        ),
      );
    } else {
      await db.messagesDao.upsertMessage(
        MessagesTableCompanion.insert(
          localId: msg.localId,
          serverId: Value(msg.serverId),
          conversationId: msg.conversationId,
          senderId: msg.senderId,
          type: msg.type,
          encryptedBody: msg.encryptedBody,
          iv: msg.iv,
          isDeletedForMe: Value(true),
          status: Value(msg.status),
          createdAt: msg.createdAt,
          updatedAt: DateTime.now(),
        ),
      );

      if (msg.serverId != null) {
        final myId = await _myId();
        unawaited(() async {
          try {
            await _pb
                .collection('deleted_messages_for_me')
                .create(
                  body: {
                    'user_id': myId,
                    'message_id': msg.serverId,
                    'conversation_id': msg.conversationId,
                  },
                );
          } catch (e) {
            debugPrint('[Delete] PB sync failed (offline?): $e');
          }
        }());
      }
    }
  }

  @override
  Future<void> toggleStar(String localId) async {
    final msg = await db.messagesDao.getMessageByLocalId(localId);
    if (msg == null) return;

    final nextStarred = !msg.isStarred;

    await db.messagesDao.upsertMessage(
      MessagesTableCompanion.insert(
        localId: msg.localId,
        conversationId: msg.conversationId,
        senderId: msg.senderId,
        type: msg.type,
        encryptedBody: msg.encryptedBody,
        iv: msg.iv,
        isStarred: Value(nextStarred),
        status: Value(msg.status),
        createdAt: msg.createdAt,
        updatedAt: DateTime.now(),
      ),
    );

    if (msg.serverId != null) {
      final myId = await _myId();
      unawaited(() async {
        try {
          if (nextStarred) {
            await _pb
                .collection('starred_messages')
                .create(
                  body: {
                    'user_id': myId,
                    'message_id': msg.serverId,
                    'conversation_id': msg.conversationId,
                    // §8.1: no body field — a decrypted preview here is
                    // plaintext at rest on the server.
                    'sender_id': msg.senderId,
                  },
                );
          } else {
            final res = await _pb
                .collection('starred_messages')
                .getList(
                  filter: 'user_id="$myId"&&message_id="${msg.serverId}"',
                  perPage: 1,
                );
            if (res.items.isNotEmpty) {
              await _pb
                  .collection('starred_messages')
                  .delete(res.items.first.id);
            }
          }
        } catch (e) {
          debugPrint('[Star] PB sync failed (offline?): $e');
        }
      }());
    }
  }

  /// D6 pacing clock; tests swap in a virtual one.
  @visibleForTesting
  DateTime Function() starClock = DateTime.now;
  @visibleForTesting
  Future<void> Function(Duration) starDelay = Future<void>.delayed;

  /// Bulk star sends run one call after another, so a star then an unstar
  /// of the same rows reach the server in that order.
  Future<void> _starSends = Future<void>.value();
  @visibleForTesting
  Future<void> get starSendsDone => _starSends;

  /// Start times of recent star creates (the server allows 20 per 5 s).
  final List<DateTime> _starCreates = [];

  @override
  Future<void> setStarred(List<String> localIds, bool starred) async {
    final changed = await db.transaction(() async {
      final rows = await (db.select(db.messagesTable)
            ..where(
              (m) => m.localId.isIn(localIds) & m.isStarred.equals(!starred),
            ))
          .get();
      if (rows.isNotEmpty) {
        await (db.update(db.messagesTable)
              ..where((m) => m.localId.isIn([for (final r in rows) r.localId])))
            .write(
              MessagesTableCompanion(
                isStarred: Value(starred),
                updatedAt: Value(DateTime.now()),
              ),
            );
      }
      return [
        for (final r in rows)
          if (r.serverId != null) r,
      ];
    });
    if (changed.isEmpty) return;
    // Errors stay inside the chain, so one failure never stops later sends.
    _starSends = _starSends
        .then((_) => _sendStars(changed, starred))
        .catchError((Object e) => debugPrint('[Star] bulk sync failed: $e'));
  }

  Future<void> _sendStars(List<MessagesTableData> rows, bool starred) async {
    final myId = await _myId();
    final stars = _pb.collection('starred_messages');
    for (final msg in rows) {
      try {
        if (!starred) {
          final res = await stars.getList(
            filter: 'user_id="$myId"&&message_id="${msg.serverId}"',
            perPage: 1,
          );
          if (res.items.isNotEmpty) await stars.delete(res.items.first.id);
          continue;
        }
        for (var retry = 0; ; retry++) {
          await _paceStarCreate();
          try {
            await stars.create(
              body: {
                'user_id': myId,
                'message_id': msg.serverId,
                'conversation_id': msg.conversationId,
                // §8.1: ids only, never a body.
                'sender_id': msg.senderId,
              },
            );
            break;
          } on ClientException catch (e) {
            if (e.statusCode != 429 || retry == 3) rethrow;
            await starDelay(const Duration(seconds: 5));
          }
        }
      } catch (e) {
        debugPrint('[Star] PB sync failed (offline?): $e');
      }
    }
  }

  /// Waits until fewer than 15 creates started in the last 5 s.
  Future<void> _paceStarCreate() async {
    const window = Duration(seconds: 5);
    while (true) {
      final now = starClock();
      _starCreates.removeWhere((t) => !now.isBefore(t.add(window)));
      if (_starCreates.length < 15) break;
      await starDelay(_starCreates.first.add(window).difference(now));
    }
    _starCreates.add(starClock());
  }

  @override
  Future<void> togglePin(
    String localId,
    String conversationId,
    bool pin,
  ) async {
    final msg = await db.messagesDao.getMessageByLocalId(localId);
    if (msg == null) return;

    // Enforce max 3 pinned messages per conversation (bible §6.4).
    if (pin) {
      final current = await db.messagesDao.getPinnedMessages(conversationId);
      final alreadyPinned = current.any((m) => m.localId == localId);
      if (!alreadyPinned && current.length >= AppConstants.maxPinnedMessages) {
        throw StateError(
          'You can pin up to ${AppConstants.maxPinnedMessages} messages.',
        );
      }
    }

    await db.messagesDao.upsertMessage(
      MessagesTableCompanion.insert(
        localId: msg.localId,
        conversationId: msg.conversationId,
        senderId: msg.senderId,
        type: msg.type,
        encryptedBody: msg.encryptedBody,
        iv: msg.iv,
        isPinned: Value(pin),
        status: Value(msg.status),
        createdAt: msg.createdAt,
        updatedAt: DateTime.now(),
      ),
    );

    if (msg.serverId != null) {
      try {
        await _pb
            .collection('messages')
            .update(msg.serverId!, body: {'is_pinned': pin});
      } catch (e) {
        debugPrint('[Msg] togglePin server: $e');
      }
    }
  }

  // ── Reactions: offline-first ────────────────────────────────────────
  // Drift is the truth the UI watches. A local add/remove writes Drift and
  // queues an outbox op; the op's sender pushes it (the row id IS the server
  // record id, so a retry can't duplicate). A server read merges into Drift
  // without undoing ops still queued.

  static const _reactionAdd = 'reaction_add';
  static const _reactionRemove = 'reaction_remove';

  @override
  Future<void> addReaction(String messageServerId, String emoji) async {
    final msg = await db.messagesDao.getMessageByServerId(messageServerId);
    if (msg == null) return;
    final myId = await _myId();
    final id = generateOpId();
    final now = DateTime.now();
    // Check and insert in one transaction: a double tap can't add twice.
    final existingId = await db.transaction(() async {
      final mine = await (db.select(db.reactionsTable)
            ..where((r) =>
                r.messageLocalId.equals(msg.localId) &
                r.userId.equals(myId) &
                r.emoji.equals(emoji)))
          .get();
      if (mine.isNotEmpty) return mine.first.id;
      await db.into(db.reactionsTable).insert(ReactionsTableCompanion.insert(
            id: id,
            messageLocalId: msg.localId,
            conversationId: msg.conversationId,
            userId: myId,
            emoji: emoji,
            createdAt: now,
          ));
      await db.outboxDao.enqueue(OutboxTableCompanion.insert(
        opId: generateOpId(),
        kind: _reactionAdd,
        ref: id,
        conversationId: msg.conversationId,
        seq: await db.outboxDao.nextSeq(msg.conversationId),
        createdAt: now,
      ));
      return null;
    });
    // Same emoji again = take it back (the old server-side toggle).
    if (existingId != null) return removeReaction(existingId);
    outboxWorker.kick();
  }

  @override
  Future<void> removeReaction(String reactionId) async {
    final row = await (db.select(db.reactionsTable)
          ..where((r) => r.id.equals(reactionId)))
        .getSingleOrNull();
    if (row == null) return;
    await db.transaction(() async {
      await (db.delete(db.reactionsTable)
            ..where((r) => r.id.equals(reactionId)))
          .go();
      // An add never tried yet: cancel it, the server never hears of
      // either. Decided here, in the txn, so the worker can't pick it up in
      // between; a tried add (attempts > 0) may have landed with its
      // answer lost, so that one gets a delete (404 = done).
      final cancelled = await (db.delete(db.outboxTable)
            ..where((o) =>
                o.kind.equals(_reactionAdd) &
                o.ref.equals(reactionId) &
                o.state.equalsValue(OutboxState.queued) &
                o.attempts.equals(0)))
          .go();
      if (cancelled > 0) return;
      await db.outboxDao.enqueue(OutboxTableCompanion.insert(
        opId: generateOpId(),
        kind: _reactionRemove,
        ref: reactionId,
        conversationId: row.conversationId,
        seq: await db.outboxDao.nextSeq(row.conversationId),
        createdAt: DateTime.now(),
      ));
    });
    outboxWorker.kick();
  }

  @override
  Future<List<ReactionGroup>> getReactions(String messageServerId) =>
      watchReactions(messageServerId).first;

  @override
  Stream<List<ReactionGroup>> watchReactions(String messageServerId) async* {
    final msg = await db.messagesDao.getMessageByServerId(messageServerId);
    if (msg == null) {
      yield const [];
      return;
    }
    final myId = await _myId();
    yield* (db.select(db.reactionsTable)
          ..where((r) => r.messageLocalId.equals(msg.localId))
          ..orderBy([(r) => OrderingTerm(expression: r.createdAt)]))
        .watch()
        .map((rows) {
      final byEmoji = <String, List<ReactionsTableData>>{};
      for (final r in rows) {
        byEmoji.putIfAbsent(r.emoji, () => []).add(r);
      }
      return [
        for (final MapEntry(key: emoji, value: rs) in byEmoji.entries)
          ReactionGroup(
            emoji: emoji,
            count: rs.length,
            isMine: rs.any((r) => r.userId == myId),
            reactionId: rs.where((r) => r.userId == myId).firstOrNull?.id,
          ),
      ];
    });
  }

  @override
  Future<void> refreshReactions(String messageServerId) async {
    final epoch = _sessionEpoch;
    try {
      final msg = await db.messagesDao.getMessageByServerId(messageServerId);
      if (msg == null) return;
      final pendingAdds = <String>{};
      final pendingRemoves = <String>{};
      // Pending = any reaction op not yet `sent`. Read BEFORE the server
      // (an op that is sent during the read still counts) and AGAIN inside
      // the write txn (an op queued during the read counts too).
      Future<void> readPending() async {
        for (final o
            in await db.outboxDao.forConversation(msg.conversationId)) {
          if (o.state == OutboxState.sent) continue;
          if (o.kind == _reactionAdd) pendingAdds.add(o.ref);
          if (o.kind == _reactionRemove) pendingRemoves.add(o.ref);
        }
      }

      await readPending();
      final res = await _pb
          .collection('reactions')
          .getList(filter: 'message_id="$messageServerId"', perPage: 200)
          .timeout(const Duration(seconds: 8));
      await db.transaction(() async {
        // Signed out (or switched account) during the read: the wipe has
        // run, so nothing of the old session may be written back.
        if (!sessionStillValid(
          epochAtStart: epoch,
          currentEpoch: _sessionEpoch,
          authValid: _pb.authStore.isValid,
        )) {
          return;
        }
        await readPending();
        final known = {
          for (final r in await (db.select(db.reactionsTable)
                ..where((r) => r.messageLocalId.equals(msg.localId)))
              .get())
            r.id: r.createdAt,
        };
        await (db.delete(db.reactionsTable)
              ..where((r) =>
                  r.messageLocalId.equals(msg.localId) &
                  r.id.isNotIn(pendingAdds)))
            .go();
        for (final r in res.items) {
          if (pendingRemoves.contains(r.id)) continue;
          await db.into(db.reactionsTable).insertOnConflictUpdate(
                ReactionsTableCompanion.insert(
                  id: r.id,
                  messageLocalId: msg.localId,
                  conversationId: msg.conversationId,
                  userId: r.getStringValue('user_id'),
                  emoji: r.getStringValue('emoji'),
                  // No server stamp: keep ours, so chips don't reorder.
                  createdAt:
                      DateTime.tryParse(r.getStringValue('created')) ??
                          known[r.id] ??
                          DateTime.now(),
                ),
              );
        }
      });
    } catch (e) {
      // Offline or refused: Drift keeps what it has.
      debugPrint('[Reaction] refresh: $e');
    }
  }

  /// A refusal the worker would mark terminal; for a reaction that would
  /// stall every later op in the conversation, so the sender drops it.
  static bool _refused(int status) => const {400, 403, 404, 413}.contains(status);

  Future<OpSendOutcome> _sendReactionAddOp(OutboxTableData op) async {
    final row = await (db.select(db.reactionsTable)
          ..where((r) => r.id.equals(op.ref)))
        .getSingleOrNull();
    final msg = row == null
        ? null
        : await db.messagesDao.getMessageByLocalId(row.messageLocalId);
    if (row == null || msg == null) {
      await db.outboxDao.deleteOp(op.opId); // reaction or message gone
      return OpSendOutcome.deferred;
    }
    final serverId = msg.serverId;
    if (serverId == null || serverId.isEmpty) {
      // Can't happen today (adds need a server id); a deferred op here would
      // block every later op in the conversation, so drop it instead.
      await _dropReactionAdd(op, row.id);
      return OpSendOutcome.deferred;
    }
    try {
      await _pb.collection('reactions').create(body: {
        'id': row.id,
        'message_id': serverId,
        'conversation_id': row.conversationId,
        'user_id': row.userId,
        'emoji': row.emoji,
      });
    } on ClientException catch (e) {
      if (!_refused(e.statusCode)) rethrow;
      // A retry after a lost answer collides with our own id: already done.
      if (e.statusCode == 400) {
        try {
          await _pb.collection('reactions').getOne(row.id);
          return OpSendOutcome.sent;
        } catch (_) {}
      }
      debugPrint('[Reaction] add refused (${e.statusCode}), dropped');
      await _dropReactionAdd(op, row.id);
      return OpSendOutcome.deferred;
    }
    return OpSendOutcome.sent;
  }

  Future<void> _dropReactionAdd(OutboxTableData op, String reactionId) =>
      db.transaction(() async {
        await (db.delete(db.reactionsTable)
              ..where((r) => r.id.equals(reactionId)))
            .go();
        await db.outboxDao.deleteOp(op.opId);
      });

  Future<OpSendOutcome> _sendReactionRemoveOp(OutboxTableData op) async {
    try {
      await _pb.collection('reactions').delete(op.ref);
    } on ClientException catch (e) {
      if (e.statusCode == 404) return OpSendOutcome.sent; // already gone
      if (!_refused(e.statusCode)) rethrow;
      // Refused: drop the op; the next server read shows the row again.
      debugPrint('[Reaction] remove refused (${e.statusCode}), dropped');
      await db.outboxDao.deleteOp(op.opId);
      return OpSendOutcome.deferred;
    }
    return OpSendOutcome.sent;
  }

  @override
  Future<List<Message>> getStarredMessages(String conversationId) async {
    try {
      final myId = await _myId();
      final res = await _pb
          .collection('starred_messages')
          .getList(
            filter: 'user_id="$myId"&&conversation_id="$conversationId"',
            sort: '-starred_at',
            perPage: 200,
          )
          .timeout(const Duration(seconds: 8));

      final out = <Message>[];
      for (final record in res.items) {
        final serverId = record.getStringValue('message_id');
        // §8.1: the server record carries ids only. Type and body come from
        // the local row (body decrypted on device); a message that isn't
        // local renders the keyed placeholder (null body, 'text').
        MessagesTableData? local;
        try {
          local = await db.messagesDao.getMessageByServerId(serverId);
        } catch (_) {}
        out.add(
          Message(
            localId: local?.localId ?? record.id,
            serverId: serverId,
            conversationId: record.getStringValue('conversation_id'),
            senderId: record.getStringValue('sender_id'),
            type: (local?.type.isNotEmpty ?? false) ? local!.type : 'text',
            decryptedBody: local == null ? null : bodyCache.get(local.localId),
            decryptState: local?.decryptState ?? 'pending',
            ciphertextLength: local?.encryptedBody.length ?? 0,
            status: 'read',
            createdAt: DateTime.tryParse(record.created) ?? DateTime.now(),
            isStarred: true,
          ),
        );
      }
      return out;
    } catch (e) {
      debugPrint('[Star] getStarredMessages: $e');
      // Offline: list the locally starred rows instead of an empty screen.
      try {
        // '' not _myId(): the mapper never reads it, and _myId can poll 10s.
        final rows = await db.messagesDao.getStarredMessages(conversationId);
        return rows.map((r) => _rowToMessage(r, '')).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      } catch (_) {
        return [];
      }
    }
  }

  @override
  Future<List<Message>> getPinnedMessages(String conversationId) async {
    final rows = await db.messagesDao.getPinnedMessages(conversationId);
    final myId = await _myId();
    return rows.map((r) => _rowToMessage(r, myId)).toList();
  }

  @override
  Stream<List<Message>> watchPinnedMessages(String conversationId) {
    return db.messagesDao.watchPinnedMessages(conversationId).asyncMap((
      rows,
    ) async {
      final myId = await _myId();
      return rows.map((r) => _rowToMessage(r, myId)).toList();
    });
  }

  @override
  Future<LocalMediaFile?> getDecryptedMedia(
    String conversationId,
    String messageServerId, {
    bool thumb = false,
  }) async {
    // Task 5 re-point (call-site only): the download+decrypt body moved
    // verbatim into MediaBlobStore.requestBlob — the store resolves the
    // conversation key itself (via the resolveKey closure built in our
    // constructor) and owns every blob file write (spec §4 single writer).
    try {
      return await mediaBlobStore.requestBlob(
        mediaBlobId(messageServerId, thumb: thumb),
        'repo.getDecryptedMedia',
      );
    } on MissingKeyException catch (e) {
      debugPrint('[Media] key not ready for decrypt: $e');
      return null;
    }
  }

  @override
  Future<void> syncAllHistory({
    void Function(HistorySyncProgress)? onProgress,
  }) async {
    final myId = await _myId();
    if (myId.isEmpty) return;
    debugPrint('[Sync] Full history sync starting for $myId');
    try {
      // Ensure conversations + members are cached first.
      onProgress?.call(
        const HistorySyncProgress(
          phase: HistorySyncPhase.fetchingConversations,
        ),
      );
      await _syncConversations(myId);
      final convs = await db.conversationsDao.watchAllConversations().first;
      final convTotal = convs.length;
      for (var i = 0; i < convs.length; i++) {
        final conv = convs[i];
        // Find the message count up-front so we can show "downloading X of Y".
        final headRes = await _pb
            .collection('messages')
            .getList(
              filter:
                  'conversation_id="${conv.id}"&&is_deleted_for_everyone=false',
              page: 1,
              perPage: 1,
            );
        final msgTotal = headRes.totalItems;
        try {
          List<List<int>> keys = const [];
          // Retry key derivation a few times — during reinstall restore the
          // peer's public key fetch can transiently fail on a flaky network,
          // and skipping it would leave the whole conversation blank.
          for (var attempt = 0; attempt < 3 && keys.isEmpty; attempt++) {
            try {
              keys = await _getConvKeyCandidates(conv.id, myId);
            } on MissingKeyException {
              if (attempt < 2) {
                await Future.delayed(
                  Duration(milliseconds: 400 * (attempt + 1)),
                );
              }
            }
          }
          if (keys.isEmpty) {
            debugPrint(
              '[Sync] conv ${conv.id}: no key after retries, '
              'messages will re-decrypt once key is available',
            );
          }
          // Page through the ENTIRE conversation history.
          var page = 1;
          var downloaded = 0;
          while (true) {
            final res = await _pb
                .collection('messages')
                .getList(
                  filter:
                      'conversation_id="${conv.id}"&&is_deleted_for_everyone=false',
                  sort: '-created',
                  page: page,
                  perPage: 200,
                );
            if (res.items.isEmpty) break;
            // Cache every row even when key is null — _cacheMsg stores the
            // ciphertext and a later chat-open re-decrypts. Never drop history.
            // Task 7: null key passes through so rows land key_missing.
            for (final r in await _withoutRunOut(res.items, myId)) {
              await _cacheMsg(r, myId, keys.firstOrNull, keyCandidates: keys);
              downloaded++;
              if (msgTotal > 0) {
                onProgress?.call(
                  HistorySyncProgress(
                    phase: HistorySyncPhase.downloadingMessages,
                    conversationIndex: i + 1,
                    conversationCount: convTotal,
                    messageCurrent: downloaded,
                    messageTotal: msgTotal,
                  ),
                );
              }
            }
            if (page >= res.totalPages) break;
            page++;
          }
          onProgress?.call(
            HistorySyncProgress(
              phase: HistorySyncPhase.finalisingConversation,
              conversationIndex: i + 1,
              conversationCount: convTotal,
            ),
          );
          await _syncDeletedForMe(conv.id);
          await _syncStarredMessages(conv.id);
        } catch (e) {
          debugPrint('[Sync] conversation ${conv.id} failed: $e');
        }
      }
      onProgress?.call(
        const HistorySyncProgress(phase: HistorySyncPhase.complete),
      );
      debugPrint('[Sync] Full history sync complete');
    } catch (e) {
      debugPrint('[Sync] Full history sync error: $e');
    }
  }

  @override
  Future<List<Message>> searchMessages(
    String conversationId,
    String query,
  ) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final rows =
        await (db.select(db.messagesTable)
              ..where((t) => t.conversationId.equals(conversationId))
              ..where((t) => t.isDeletedForMe.equals(false))
              ..where((t) => t.isDeletedForEveryone.equals(false))
              // Its body "Sticker: hi" would match "hi" (mascot §J2.5).
              ..where((t) => t.type.equals('sticker').not())
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.createdAt,
                  mode: OrderingMode.desc,
                ),
              ]))
            .get();

    if (rows.isEmpty) return [];
    // T9 / spec §5.1: decrypt-on-query — metadata prefilter (above), then
    // resolve candidates through the DecryptPass machinery: cache hits are
    // free, misses coalesce into ONE runFor batch. The match set stays
    // EPHEMERAL (this return value): search never writes the DB, and the
    // only plaintext it produces lands in the session cache via
    // DecryptPass's own apply — never a search-owned store (spec §19.1).
    final missing = <String>[
      for (final r in rows)
        if (bodyCache.get(r.localId) == null &&
            r.encryptedBody.isNotEmpty &&
            r.encryptedBody != '__pending__')
          r.localId,
    ];
    if (missing.isNotEmpty) await decryptPass.runFor(missing);
    final myId = await _myId();
    final needle = trimmed.toLowerCase();
    final hits = <Message>[];
    for (final r in rows) {
      final body = bodyCache.get(r.localId);
      if (body != null && body.toLowerCase().contains(needle)) {
        hits.add(_rowToMessage(r, myId));
      }
    }
    return hits;
  }

  @override
  Future<void> setDisappearingDuration(
    String conversationId,
    int seconds,
  ) async {
    try {
      await _pb
          .collection('conversations')
          .update(conversationId, body: {'disappearing_duration': seconds});
      await (db.update(
        db.conversationsTable,
      )..where((t) => t.id.equals(conversationId))).write(
        ConversationsTableCompanion(
          disappearingDuration: Value(seconds),
          updatedAt: Value(DateTime.now()),
        ),
      );
    } catch (e) {
      debugPrint('[Conv] setDisappearing: $e');
    }
  }

  // ── Group admin ───────────────────────────────────────────────

  @override
  Future<bool> isCurrentUserAdmin(String conversationId) async {
    final myId = await _myId();
    final members = await db.conversationsDao.getMembersForConversation(
      conversationId,
    );
    return members.where((m) => m.userId == myId).firstOrNull?.role == 'admin';
  }

  @override
  Future<bool> hasUsableKey(String conversationId) async {
    final conv = await db.conversationsDao.getConversationById(conversationId);
    if (conv?.type != 'group') return true;
    try {
      // Local-first (loading-issue fix, D1): a resident key set satisfies
      // the readiness gate without a blocking group_keys round-trip — the
      // old requireCurrent call made the "Waiting for a group admin…" banner
      // poll the network every 3s and showed it on cold-process opens even
      // with warm keys. The candidate path revalidates in the background;
      // cold caches fall through to its network hydrate, so the
      // join-accepted-but-no-key-yet case still contacts the server (pinned
      // by the D1-negative test), and send-time getOrFetchGroupKey remains
      // the authoritative freshness check.
      final candidates = await encryption.getOrFetchGroupKeyCandidates(
        conversationId,
        await _myId(),
      );
      return candidates.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<User>> getGroupMembers(String conversationId) async {
    // UNFILTERED on purpose (#17): the chat screen's isLeft/isMeAdmin gate
    // looks for the user's OWN row in this list — the filtered dao query
    // drops 'left' rows, so a removed member's gate never fired and they
    // could keep typing. Display lists filter `groupRole != 'left'` locally.
    final members = await db.conversationsDao.getAllMembersForConversation(
      conversationId,
    );
    final users = <User>[];
    for (final m in members) {
      var u = await db.usersDao.getUserById(m.userId);
      if (u == null) {
        try {
          final r = await _pb.collection('users').getOne(m.userId);
          await _cacheUserRecord(r);
          u = await db.usersDao.getUserById(m.userId);
        } catch (_) {}
      }
      if (u != null) {
        users.add(_tableUserToEntity(u, groupRole: m.role));
      }
    }
    return users;
  }

  @override
  Future<void> sendGroupInvite(String conversationId, String userId) async {
    final myId = await _myId();
    if (!await isCurrentUserAdmin(conversationId)) {
      throw Exception('Not an admin');
    }
    // Idempotent: one invite per (conversation, user) — UNIQUE index
    // server-side. Re-invite flips an existing row back to pending.
    try {
      final existing = await _pb
          .collection('group_invites')
          .getFirstListItem(
            'conversation_id="$conversationId"&&invited_user_id="$userId"',
          );
      await _pb
          .collection('group_invites')
          .update(existing.id, body: {'status': 'pending'});
    } on ClientException catch (e) {
      if (e.statusCode != 404) rethrow;
      await _pb
          .collection('group_invites')
          .create(
            body: {
              'conversation_id': conversationId,
              'invited_user_id': userId,
              'invited_by': myId,
              'status': 'pending',
            },
          );
    }
  }

  /// Minimal RecordModel → User mapping for invite senders (this file has no
  /// shared record→entity helper; mirrors friend_repository_impl's shape).
  User _inviteRecordToUser(RecordModel r) {
    final avatar = r.getStringValue('avatar');
    return User(
      id: r.id,
      displayName: r.getStringValue('display_name'),
      username: r.getStringValue('username'),
      email: r.getStringValue('email'),
      friendCode: r.getStringValue('friend_code'),
      avatarUrl: avatar.isEmpty
          ? null
          : '${_pb.baseUrl}/api/files/users/${r.id}/$avatar',
      createdAt: DateTime.tryParse(r.created) ?? DateTime.now(),
    );
  }

  @override
  Future<List<GroupInvite>> getIncomingGroupInvites() async {
    final myId = await _myId();
    if (myId.isEmpty) return [];
    final items = await _pb
        .collection('group_invites')
        .getFullList(
          filter: 'invited_user_id="$myId"&&status="pending"',
          expand: 'invited_by,conversation_id',
          sort: '-created',
          batch: 100,
        );
    final invites = <GroupInvite>[];
    for (final r in items) {
      final inviter = r.expand['invited_by']?.firstOrNull;
      if (inviter != null) await _cacheUserRecord(inviter);
      final convName = r.expand['conversation_id']?.firstOrNull?.getStringValue(
        'name',
      );
      invites.add(
        GroupInvite(
          id: r.id,
          conversationId: r.getStringValue('conversation_id'),
          conversationName: convName?.isNotEmpty == true ? convName! : 'Group',
          invitedBy: inviter != null
              ? _inviteRecordToUser(inviter)
              : User(
                  id: '',
                  displayName: 'Someone',
                  username: '',
                  email: '',
                  friendCode: '',
                  createdAt: DateTime.now(),
                ),
          status: r.getStringValue('status'),
          createdAt:
              DateTime.tryParse(r.getStringValue('created')) ?? DateTime.now(),
        ),
      );
    }
    return invites;
  }

  @override
  Future<void> acceptGroupInvite(String inviteId) async {
    final myId = await _myId();
    if (myId.isEmpty) throw Exception('Not authenticated');
    final invite = await _pb.collection('group_invites').getOne(inviteId);
    final convId = invite.getStringValue('conversation_id');

    // Self-join — conversation_members.createRule's invite clause covers
    // this. A 400 here can be a UNIQUE(conversation_id,user_id) duplicate or
    // a rule denial (e.g. the invite was cancelled between getOne and
    // create); the catch below verifies which before tolerating.
    try {
      await _pb
          .collection('conversation_members')
          .create(
            body: {
              'conversation_id': convId,
              'user_id': myId,
              'role': 'member',
            },
          );
    } on ClientException catch (e) {
      // 400 means the row was not created. Tolerate it ONLY if the
      // membership already exists (UNIQUE duplicate, e.g. accepted on
      // another device): verify the row, then continue as joined. If the
      // lookup fails (404 or otherwise) this was a rule denial, not a
      // duplicate — rethrow the original create failure so the caller sees
      // it and the invite below is NOT marked accepted for a non-member.
      if (e.statusCode != 400) rethrow;
      try {
        await _pb
            .collection('conversation_members')
            .getFirstListItem('conversation_id="$convId"&&user_id="$myId"');
      } catch (_) {
        throw e;
      }
      debugPrint('[Invite] already a member of $convId — continuing');
    }

    await _pb
        .collection('group_invites')
        .update(inviteId, body: {'status': 'accepted'});
    _invalidateCutoff(convId); // this device just joined — new cutoff

    // Make the group appear locally right away (messages stay garbled until
    // an admin device rotates the key and we fetch it).
    try {
      await _syncConversationsBackground();
    } catch (e) {
      debugPrint('[Invite] post-accept sync failed: $e');
    }

    // Bounded wait for the group key (admin auto-rotate), then a single
    // "X joined the group" bubble.
    unawaited(_emitJoinedWhenKeyReady(convId, myId));
  }

  /// After accepting an invite, the joiner holds no group key until an admin
  /// device rotates. Poll (bounded) for the key, then emit the join bubble
  /// exactly once (guarded by a local lookup for an existing copy).
  Future<void> _emitJoinedWhenKeyReady(String convId, String myId) async {
    const tries = 15;
    for (var i = 0; i < tries; i++) {
      try {
        await encryption.getOrFetchGroupKey(convId, myId);
        final myName = await _userName(myId);
        final body = '$myName joined the group';
        final already = await db.messagesDao.findSystemMessage(
          convId,
          myId,
          body,
        );
        if (already == null) {
          await _emitSystemMessage(convId, body, actorUserId: myId);
        }
        _pendingJoinEmitConvIds.remove(convId);
        return;
      } on Exception {
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    debugPrint(
      '[Invite] key not distributed within ${tries * 2}s — '
      'join bubble deferred to next resume sync',
    );
    _pendingJoinEmitConvIds.add(convId);
  }

  @override
  Future<void> declineGroupInvite(String inviteId) async {
    await _pb
        .collection('group_invites')
        .update(inviteId, body: {'status': 'declined'});
  }

  @override
  Future<Map<String, String>> getInviteStatusesForConversation(
    String conversationId,
  ) async {
    final rows = await _pb
        .collection('group_invites')
        .getFullList(filter: 'conversation_id="$conversationId"', batch: 100);
    return {
      for (final r in rows)
        r.getStringValue('invited_user_id'): r.getStringValue('status'),
    };
  }

  @override
  Future<List<PendingGroupInvite>> getPendingInvitesForConversation(
    String conversationId,
  ) async {
    final rows = await _pb
        .collection('group_invites')
        .getFullList(
          filter: 'conversation_id="$conversationId"',
          expand: 'invited_user_id',
          batch: 100,
        );
    final out = <PendingGroupInvite>[];
    for (final r in rows) {
      final u = r.expand['invited_user_id']?.firstOrNull;
      if (u == null) continue;
      out.add(
        PendingGroupInvite(
          inviteId: r.id,
          status: r.getStringValue('status'),
          user: _inviteRecordToUser(u),
        ),
      );
    }
    return out;
  }

  @override
  Future<void> cancelGroupInvite(String inviteId) async {
    await _pb.collection('group_invites').delete(inviteId);
  }

  @override
  Future<void> removeMemberFromGroup(
    String conversationId,
    String userId,
  ) async {
    final myId = await _myId();
    if (!await isCurrentUserAdmin(conversationId)) {
      throw Exception('Not an admin');
    }
    if (userId == myId) {
      throw StateError('Use leave group to remove yourself.');
    }
    final liveMembers = await _pb
        .collection('conversation_members')
        .getFullList(filter: 'conversation_id="$conversationId"', batch: 200);
    final liveTarget = liveMembers
        .where((m) => m.getStringValue('user_id') == userId)
        .firstOrNull;
    if (liveTarget == null) {
      throw StateError('User is not an active group member.');
    }
    final liveAdminCount = liveMembers
        .where((m) => m.getStringValue('role') == 'admin')
        .length;
    if (liveTarget?.getStringValue('role') == 'admin' && liveAdminCount <= 1) {
      throw StateError('The group must retain an admin.');
    }

    // Capture display names BEFORE we drop the membership rows / caches.
    final removedName = await _userName(userId);
    final adminName = await _userName(myId);

    // 1) Delete ALL membership rows for this user (defensive against any
    //    pre-existing duplicates). Do NOT swallow failures — a silent 403
    //    here was the root cause of #17: the "removed" member stayed a full
    //    member server-side, reappeared after reopen and kept receiving.
    //    Let the caller see the error so the failure surfaces.
    final memberRecs = await _pb
        .collection('conversation_members')
        .getFullList(
          filter: 'conversation_id="$conversationId"&&user_id="$userId"',
          batch: 50,
        );
    for (final rec in memberRecs) {
      await _pb.collection('conversation_members').delete(rec.id);
    }

    // 2) Purge any pending invite for this user in this conversation — a live
    //    invite would let them self-rejoin after being removed.
    try {
      final invs = await _pb
          .collection('group_invites')
          .getFullList(
            filter:
                'conversation_id="$conversationId"&&invited_user_id="$userId"',
            batch: 20,
          );
      for (final inv in invs) {
        await _pb.collection('group_invites').delete(inv.id);
      }
    } catch (e) {
      debugPrint('[Group] invite purge on remove failed: $e');
    }

    // 3) Emit "X was removed by Y" only on success, BEFORE the key
    //    rotation. The removed member still holds the CURRENT group key in
    //    their cache (their own sync wipes it later), so this row stays
    //    decryptable for them too; emitting after the rotation would garble
    //    it. Their device also gets its own local "You were removed" bubble
    //    from the membership sync — this one is for the remaining members.
    try {
      await _emitSystemMessage(
        conversationId,
        '$removedName was removed by $adminName',
        actorUserId: myId,
      );
    } catch (e) {
      debugPrint('[Group] removeMember system message emit failed: $e');
    }
    _invalidateCutoff(conversationId);

    // 4) Keep the removed user's historical key rows. They are required to
    // decrypt messages sent while that user was a member. The new rotation
    // below creates a fresh version only for current members, so these rows do
    // not grant access to future messages.

    // 5) Fully remove locally (not a soft 'left' — they were removed by an
    //    admin). The removed user's own device flips to 'left' via
    //    _syncConversations when it sees the server row gone.
    await (db.delete(db.conversationMembersTable)..where(
          (t) =>
              t.conversationId.equals(conversationId) & t.userId.equals(userId),
        ))
        .go();

    // 6) Rotate the key so the removed member can't read future messages.
    await _rotateGroupKey(conversationId, myId);
  }

  /// Every rotation trigger (remove, leave, join debounce, key-gap repair)
  /// funnels through here, so one device never rotates a group twice at once.
  Future<void> _rotateGroupKey(String convId, String myId) =>
      _rotations.run(convId, () => _rotateGroupKeyNow(convId, myId));

  Future<void> _rotateGroupKeyNow(String convId, String myId) async {
    // Version allocation is not a server transaction. If another admin wins
    // the same max+1 race, never overwrite its row with ciphertext for a
    // different random key. Retry at the next version instead.
    for (var attempt = 0; attempt < 3; attempt++) {
      final newKey = encryption.generateGroupKey();

      // Read CURRENT membership so a just-added member is included and a
      // removed member is excluded.
      final memberRecs = await _pb
          .collection('conversation_members')
          .getFullList(filter: 'conversation_id="$convId"', batch: 200);
      // A fully empty group has no recipient and therefore no key to create.
      // This is valid after the last member leaves/is removed.
      if (memberRecs.isEmpty) return;

      final existing = await _pb
          .collection('group_keys')
          .getList(
            filter: 'conversation_id="$convId"',
            sort: '-key_version',
            perPage: 1,
          );
      final newVersion =
          (existing.items.isEmpty
              ? 0
              : existing.items.first.getIntValue('key_version')) +
          1;

      // Resolve and encrypt every member before the first write. A missing
      // public key must fail the rotation, not silently create a group where
      // one member can never decrypt.
      final encryptedForMember = <String, String>{};
      for (final m in memberRecs) {
        final uid = m.getStringValue('user_id');
        final user = await _pb.collection('users').getOne(uid);
        await _cacheUserRecord(user);
        final pubKey = user.getStringValue('public_key');
        if (pubKey.isEmpty) {
          throw StateError('Member $uid has no public key');
        }
        encryptedForMember[uid] = await encryption.encryptGroupKeyForMember(
          newKey,
          pubKey,
          convId,
        );
      }

      var collision = false;
      for (final entry in encryptedForMember.entries) {
        try {
          await _pb
              .collection('group_keys')
              .create(
                body: {
                  'conversation_id': convId,
                  'user_id': entry.key,
                  'encrypted_key': entry.value,
                  'encrypted_by_user_id': myId,
                  'key_version': newVersion,
                },
              );
        } on ClientException catch (e) {
          // A row already existing at this version proves a concurrent
          // rotation. Do not update it: its ciphertext may wrap another key.
          try {
            await _pb
                .collection('group_keys')
                .getFirstListItem(
                  'conversation_id="$convId"&&user_id="${entry.key}"'
                  '&&key_version=$newVersion',
                );
            collision = true;
            break;
          } catch (_) {
            throw e;
          }
        }
      }
      if (collision) {
        debugPrint('[Group] rotation collision at v$newVersion; retrying');
        continue;
      }

      // Historical versions are required for cold-start decryption.
      // C: saveGroupKey = disk + process-memory write-through (raw
      // storage.write here would leave the RAM map serving the old key).
      await encryption.saveGroupKey(convId, newKey);
      await encryption.saveGroupKey(convId, newKey, version: newVersion);
      await storage.write(key: 'contact_key_${convId}_gk', value: '');
      return;
    }
    throw StateError('Group-key rotation conflicted repeatedly: $convId');
  }

  @override
  Future<void> promoteMemberToAdmin(
    String conversationId,
    String userId,
  ) async {
    if (!await isCurrentUserAdmin(conversationId)) {
      throw Exception('Not an admin');
    }
    final rec = await _pb
        .collection('conversation_members')
        .getFirstListItem(
          'conversation_id="$conversationId"&&user_id="$userId"',
        );
    await _pb
        .collection('conversation_members')
        .update(rec.id, body: {'role': 'admin'});
    await (db.update(db.conversationMembersTable)..where(
          (t) =>
              t.conversationId.equals(conversationId) & t.userId.equals(userId),
        ))
        .write(const ConversationMembersTableCompanion(role: Value('admin')));
    try {
      final myId = await _myId();
      final name = await _userName(userId);
      await _emitSystemMessage(
        conversationId,
        adminPromotedCopy(name),
        actorUserId: myId,
      );
    } catch (e) {
      debugPrint('[Group] promote system message emit failed: $e');
    }
  }

  @override
  Future<void> demoteAdminToMember(String conversationId, String userId) async {
    final members = await db.conversationsDao.getMembersForConversation(
      conversationId,
    );
    final adminCount = members.where((m) => m.role == 'admin').length;
    final myId = await _myId();
    if (userId == myId && adminCount <= 1) {
      throw Exception('Cannot demote the only admin');
    }
    if (!await isCurrentUserAdmin(conversationId)) {
      throw Exception('Not an admin');
    }
    final rec = await _pb
        .collection('conversation_members')
        .getFirstListItem(
          'conversation_id="$conversationId"&&user_id="$userId"',
        );
    await _pb
        .collection('conversation_members')
        .update(rec.id, body: {'role': 'member'});
    await (db.update(db.conversationMembersTable)..where(
          (t) =>
              t.conversationId.equals(conversationId) & t.userId.equals(userId),
        ))
        .write(const ConversationMembersTableCompanion(role: Value('member')));
    try {
      final myId = await _myId();
      final name = await _userName(userId);
      await _emitSystemMessage(
        conversationId,
        adminDemotedCopy(name),
        actorUserId: myId,
      );
    } catch (e) {
      debugPrint('[Group] demote system message emit failed: $e');
    }
  }

  @override
  Future<void> setOnlyAdminsCanMessage(
    String conversationId,
    bool value,
  ) async {
    if (!await isCurrentUserAdmin(conversationId)) {
      throw Exception('Not an admin');
    }
    await _pb
        .collection('conversations')
        .update(conversationId, body: {'only_admins_can_message': value});
    await (db.update(db.conversationsTable)
          ..where((t) => t.id.equals(conversationId)))
        .write(ConversationsTableCompanion(onlyAdminsCanMessage: Value(value)));
  }

  @override
  Future<void> leaveGroup(String conversationId) async {
    final myId = await _myId();
    final members = await db.conversationsDao.getMembersForConversation(
      conversationId,
    );
    final me = members.where((m) => m.userId == myId).firstOrNull;

    if (me?.role == 'admin') {
      final otherAdmins = members.where(
        (m) => m.userId != myId && m.role == 'admin',
      );
      if (otherAdmins.isEmpty && members.length > 1) {
        final nextAdmin = members
            .where((m) => m.userId != myId)
            .reduce((a, b) => a.joinedAt.isBefore(b.joinedAt) ? a : b);
        await promoteMemberToAdmin(conversationId, nextAdmin.userId);
      }
    }

    // Membership removal is security-critical. Do not swallow a failed
    // delete and then rotate: if the row remains, the leaver is still a
    // current member and would receive the next key.
    final rec = await _pb
        .collection('conversation_members')
        .getFirstListItem('conversation_id="$conversationId"&&user_id="$myId"');
    await _pb.collection('conversation_members').delete(rec.id);

    // Emit after membership deletion but before key-cache cleanup/rotation.
    // The old key is still available locally, and a failed membership delete
    // can no longer produce a false "left" event.
    try {
      final myName = await _userName(myId);
      await _emitSystemMessage(
        conversationId,
        '$myName left the group',
        actorUserId: myId,
      );
    } catch (e) {
      debugPrint('[Group] leaveGroup system message emit failed: $e');
    }

    // Retain older versioned keys for authorized historical messages, but
    // drop the active key locally before persisting the left state.
    // C: encryption.clearCurrentGroupKey = storage semantics + RAM eviction.
    await encryption.clearCurrentGroupKey(conversationId);
    _invalidateCutoff(conversationId);

    if (me != null) {
      await (db.update(db.conversationMembersTable)..where(
            (t) =>
                t.conversationId.equals(conversationId) & t.userId.equals(myId),
          ))
          .write(const ConversationMembersTableCompanion(role: Value('left')));
    }

    // Rotate the key so the leaver (who still holds the previous key in
    // SecureStorage) cannot decrypt any FUTURE group messages they might
    // still observe. Their membership row is already gone server-side, so
    // _rotateGroupKey distributes the new key to the remaining members only.
    await _rotateGroupKey(conversationId, myId);
  }

  @override
  Future<void> updateGroupInfo(
    String conversationId, {
    String? name,
    File? iconFile,
  }) async {
    if (!await isCurrentUserAdmin(conversationId)) {
      throw Exception('Not an admin');
    }
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    List<http.MultipartFile>? files;
    if (iconFile != null) {
      files = [
        http.MultipartFile.fromBytes(
          'icon',
          await jpegWithoutExif(iconFile),
          filename: 'icon.jpg',
          contentType: MediaType('image', 'jpeg'),
        ),
      ];
    }
    final rec = await _pb
        .collection('conversations')
        .update(conversationId, body: body, files: files ?? []);
    final iconField = rec.getStringValue('icon');
    final iconUrl = iconField.isEmpty
        ? null
        : '${_pb.baseUrl}/api/files/conversations/$conversationId/$iconField';

    await (db.update(
      db.conversationsTable,
    )..where((t) => t.id.equals(conversationId))).write(
      ConversationsTableCompanion(
        name: Value(rec.getStringValue('name')),
        iconUrl: Value(iconUrl),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Stream<Conversation?> watchConversation(String conversationId) {
    return db.conversationsDao.watchConversationById(conversationId).asyncMap((
      row,
    ) async {
      if (row == null) return null;
      if (row.type == 'group') {
        final count = await _getMemberCount(row.id);
        return _convDataToEntity(row, null, memberCount: count);
      } else {
        final myId = await _myId();
        final other = await _getOtherUser(row.id, myId);
        return _convDataToEntity(row, other);
      }
    });
  }

  @override
  Stream<List<User>> watchGroupMembers(String conversationId) {
    return db.conversationsDao
        .watchMembersForConversation(conversationId)
        .asyncMap((_) => getGroupMembers(conversationId));
  }

  // ── Private helpers ───────────────────────────────────────────

  Future<String> _myId() async {
    // Poll until the session is saved to Drift (avoids race with _saveSession
    // on first launch / after reinstall where sendMessage may be called before
    // the auth flow has finished writing current_user_id).
    for (var i = 0; i < 50; i++) {
      final id = await db.settingsDao.getSetting(AppSettingsKeys.currentUserId);
      if (id != null && id.isNotEmpty) return id;
      // Also check SecureStorage — _saveSession writes there first.
      final secureId = await storage.getCurrentUserId();
      if (secureId != null && secureId.isNotEmpty) return secureId;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return '';
  }

  /// F2b: a resume shorter than this takes the LIGHT path — one aggregate
  /// delta query instead of the all-conversation backfill scan. 60s covers
  /// shade pulls, recents, HOME and quick app switches; anything longer
  /// (or an unknown duration — cold start) fails SAFE to the full path.
  static const _lightResumeCutoff = Duration(seconds: 60);

  /// Single-flight guard: cold start's postFrame resync and a lifecycle
  /// resume can land in the same tick — never run two backfills in parallel.
  Future<void>? _resyncInFlight;

  @override
  Future<void> resyncOnResume({Duration? awayFor}) async {
    final inFlight = _resyncInFlight;
    if (inFlight != null) {
      debugPrint('[Msg] resyncOnResume — already in flight, coalescing.');
      return inFlight;
    }
    final run = _resyncRun(awayFor: awayFor);
    _resyncInFlight = run;
    try {
      await run;
    } finally {
      _resyncInFlight = null;
    }
  }

  Future<void> _resyncRun({Duration? awayFor}) async {
    final light = awayFor != null && awayFor < _lightResumeCutoff;
    final resyncClock = Stopwatch()..start();
    debugPrint(
      '[Msg] resyncOnResume — path=${light ? 'light' : 'full'}'
      '${awayFor != null ? ' away=${awayFor.inMilliseconds}ms' : ''}',
    );
    // 1. Force-reconnect the SSE subscriptions. Android suspends the socket
    //    while backgrounded and events sent in that window are lost forever —
    //    a fresh subscribe guarantees a live connection. _reconnect() is
    //    serialized internally, so calling it here can never race the
    //    constructor or the auth-change listener.
    _reconnect();

    // 2. Refetch conversations + recent messages/receipts for every
    //    conversation so anything missed while suspended is backfilled.
    try {
      final myId = await _myId();
      if (myId.isEmpty) return;
      // #71 Prewarm: the visible home previews decrypt FIRST — newest
      // conversations first — before sync/backfill/key refreshes. Full
      // path always; light path only when the body cache was purged
      // (paused → quick return, B keeps inactive intact), so a short
      // HOME-and-back never flashes preview locks. Local-only; unawaited
      // so the badge/messages below never wait on it.
      if (!light || bodyCache.length == 0) {
        unawaited(prewarmHomePreviews());
      }
      await _syncConversations(myId);

      if (light) {
        // F2b light path: SSE has no replay, so a delta fetch is still
        // mandatory — but ONE aggregate `created >= <local watermark>`
        // query picks the target set instead of scanning all conversations.
        // Zero actionable rows ⇒ zero per-conversation fetches (a shade
        // pull with no traffic becomes a true no-op resume). Key-gap
        // reconcile and prefetch are deliberately skipped: neither can
        // lose data inside 60s, and pre-cache they were the dominant
        // resume cost. retryPending + join retries stay (local, cheap,
        // the only resume-path send recovery).
        final targets = await _deltaBackfillTargets(myId);
        debugPrint('[Msg] resync light — delta convs=${targets.length}');
        await _backfillTargets(targets);
        // C2 (review #72 accepted tradeoff, now closed): the per-conv
        // star/delete/receipt syncs inside _fetchAndCacheMessages only ran
        // for TARGET convs — quiet convs waited for chat-open or a ≥60s
        // full resume. User-scoped variants: one query per table covers
        // every conv. Target convs get both passes; both are idempotent
        // no-ops after the first apply (guards in each method).
        await _syncDeletedForMeUser(myId);
        await _syncStarredMessagesUser(myId);
        await _reconcileReceiptsUser(myId);
        await retryPendingMessages();
        for (final convId in _pendingJoinEmitConvIds.toList()) {
          unawaited(_emitJoinedWhenKeyReady(convId, myId));
        }
        return;
      }

      // D2 (loading-issue fix): fill any group whose keys are not yet
      // resident so the FIRST chat open never pays a network round-trip.
      // Unawaited — badge/messages above must not wait on it.
      unawaited(prefetchGroupKeys());
      final memberships = await db.conversationsDao.getMembershipsOfUser(myId);
      final targets = <String>[
        for (final m in memberships)
          if (m.role != 'left') m.conversationId,
      ];
      // Most-recently-active first (the likely unread conv), fetched in
      // small parallel batches — the old serial loop made the badge land
      // 15-30s after open with a dozen conversations.
      await _backfillTargets(targets);
      // 2b. Rotate for members whose key distribution was missed while
      // every admin device was offline (spec D2) — AFTER the backfill so
      // rare key-gap work never delays the badge/messages above.
      await _reconcileGroupKeyGaps();
      // 3. Flush anything that failed to send while backgrounded.
      await retryPendingMessages();

      // 4. Retry deferred join bubbles (accept happened while no admin
      //    device was online to rotate the group key).
      for (final convId in _pendingJoinEmitConvIds.toList()) {
        unawaited(_emitJoinedWhenKeyReady(convId, myId));
      }
    } catch (e) {
      debugPrint('[Msg] resyncOnResume: $e');
    } finally {
      // Device measurement anchor: total resume cost incl. the C2
      // user-scoped syncs (was unmeasurable — no end-of-run marker).
      debugPrint('[Msg] resync done — path=${light ? 'light' : 'full'}'
          ' total=${resyncClock.elapsedMilliseconds}ms');
    }
  }

  /// F2b: conversations holding server rows that are NOT already durable
  /// locally, discovered by ONE aggregate query filtered from the newest
  /// server-backed local timestamp. Row-level no-op filtering is the same
  /// `_filterUnresolvedOrChanged` the fetch path uses, so a boundary-row
  /// match alone never triggers a backfill. `null` = no local watermark
  /// (fresh install) → caller falls back to the full membership set.
  Future<List<String>> _deltaBackfillTargets(String myId) async {
    final watermark = await db.messagesDao.maxServerCreatedAt();
    final filter =
        watermark == null ? null : incrementalFetchFilter(watermark);
    if (filter == null) {
      final memberships = await db.conversationsDao.getMembershipsOfUser(myId);
      return [
        for (final m in memberships)
          if (m.role != 'left') m.conversationId,
      ];
    }
    // C4 (review #72): paginate — a single 100-row page caps target
    // discovery at the newest 100 rows app-wide, so a busy burst could
    // hide a conversation whose only new rows fell past page 1. The cap
    // bounds the worst case (1000 rows); hitting it is LOGGED, never
    // silent.
    final byConv = <String, List<RecordModel>>{};
    const maxDeltaPages = 10;
    var page = 1;
    while (page <= maxDeltaPages) {
      final res = await _pb.collection('messages').getList(
            filter: filter,
            sort: '-created',
            perPage: 100,
            page: page,
          );
      for (final r in res.items) {
        byConv.putIfAbsent(r.getStringValue('conversation_id'), () => []).add(r);
      }
      if (res.items.length < 100) break;
      page++;
      if (page > maxDeltaPages) {
        debugPrint(
          '[Msg] delta discovery hit the $maxDeltaPages-page cap — '
          'rows beyond it wait for the next full path',
        );
      }
    }
    final targets = <String>[];
    for (final e in byConv.entries) {
      final actionable = await _filterUnresolvedOrChanged(e.value, myId);
      if (actionable.isNotEmpty) targets.add(e.key);
    }
    return targets;
  }

  /// Shared per-conversation backfill: most-recently-active first, small
  /// parallel batches (chunks of 3).
  Future<void> _backfillTargets(List<String> targets) async {
    final recency = <String, DateTime>{};
    for (final cid in targets) {
      final c = await db.conversationsDao.getConversationById(cid);
      recency[cid] = c?.lastMessageAt ?? c?.createdAt ?? DateTime(2000);
    }
    targets.sort((a, b) => recency[b]!.compareTo(recency[a]!));
    for (var i = 0; i < targets.length; i += 3) {
      final chunk = targets.skip(i).take(3);
      await Future.wait(chunk.map((cid) => _fetchAndCacheMessages(cid)));
    }
  }

  /// Spec D2: after resume, find groups where some member has no current
  /// key row (all admin devices missed the join SSE event) and rotate so
  /// they can read the group. Only the elected rotation owner acts.
  Future<void> _reconcileGroupKeyGaps() async {
    try {
      final myId = await _myId();
      if (myId.isEmpty) return;
      final memberships = await db.conversationsDao.getMembershipsOfUser(myId);
      for (final m in memberships) {
        if (m.role != 'admin') continue;
        final convId = m.conversationId;
        final conv = await db.conversationsDao.getConversationById(convId);
        if (conv?.type != 'group') continue;
        try {
          final members = await _pb
              .collection('conversation_members')
              .getFullList(filter: 'conversation_id="$convId"', batch: 200);
          final keys = await _pb
              .collection('group_keys')
              .getFullList(filter: 'conversation_id="$convId"', batch: 200);
          final maxByVersion = <String, int?>{};
          int current = 0;
          for (final k in keys) {
            final uid = k.getStringValue('user_id');
            final v = k.getIntValue('key_version');
            if (v > current) current = v;
            if ((maxByVersion[uid] ?? 0) < v) maxByVersion[uid] = v;
          }
          final memberVersions = {
            for (final r in members)
              r.getStringValue('user_id'):
                  maxByVersion[r.getStringValue('user_id')],
          };
          final missing = current == 0
              ? memberVersions.keys.toSet()
              : membersMissingCurrentKey(
                  memberToMaxVersion: memberVersions,
                  currentVersion: current,
                );
          if (missing.isEmpty) continue;
          debugPrint('[Group] key gap in $convId for $missing');
          if (!await _isRotationOwner(convId, myId)) continue;
          _rotateDebounce[convId]?.cancel();
          _rotateDebounce[convId] = Timer(const Duration(seconds: 3), () {
            _rotateDebounce.remove(convId);
            _rotateGroupKey(convId, myId).catchError((e) {
              debugPrint('[Group] key-gap rotate failed: $e');
            });
          });
        } catch (e) {
          debugPrint('[Group] key-gap check failed for $convId: $e');
        }
      }
    } catch (e) {
      debugPrint('[Group] key-gap reconcile failed: $e');
    }
  }

  Future<DateTime?> _readCursor(String convId) async {
    final raw = await db.settingsDao.getSetting('sync_cursor_$convId');
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  // `_writeCursor` DELETED (Task 6): the cursor write moved into
  // IngestBoundary.commit — it advances in the SAME transaction as the
  // batch it belongs to (spec §7), never as a separate write.

  /// Incremental fetch: cursor delta on warm caches (pages until caught
  /// up), latest-40 only on cold. Batched cache = one existing-rows query,
  /// one decryptBatch isolate hop, one Drift batch → ONE stream emit for
  /// the whole page (was 40 serial decrypt+upserts ≈ 6s).
  Future<void> _fetchAndCacheMessages(String conversationId) async {
    final epoch = _sessionEpoch;
    try {
      final myId = await _myId();
      debugPrint(
        '[Msg] _fetchAndCacheMessages — myId: $myId, convId: $conversationId',
      );
      // No is_deleted_for_everyone filter: deletions that happened while this
      // device was offline must ALSO sync (companionFromRecord flips the local flag).
      final cacheEmpty = !(await db.messagesDao.hasAnyMessages(conversationId));
      final cursor = cacheEmpty ? null : await _readCursor(conversationId);
      final inc = incrementalFetchFilter(cursor);
      final pageFilter = inc == null
          ? 'conversation_id="$conversationId"'
          : 'conversation_id="$conversationId" && $inc';

      final all = <RecordModel>[];
      var page = 1;
      var totalAtStart = -1;
      while (true) {
        final res = await _pb
            .collection('messages')
            .getList(
              filter: pageFilter,
              sort: '-created',
              perPage: 40,
              page: page,
            );
        if (totalAtStart < 0) totalAtStart = res.totalItems;
        all.addAll(res.items);
        // Cold fetch: one page (latest 40), same as before — older history
        // loads via loadMoreMessages. Warm fetch: page until delta caught up.
        if (cursor == null ||
            !shouldFetchNextPage(pageItems: res.items.length, perPage: 40)) {
          break;
        }
        page++;
      }
      debugPrint(
        '[Msg] _fetchAndCacheMessages — fetched ${all.length} messages (cursor=${cursor != null})',
      );

      // Review C1: the awaits above span seconds — a logout/account-switch
      // during them must not write into the wiped session.
      if (all.isNotEmpty &&
          !sessionStillValid(
            epochAtStart: epoch,
            currentEpoch: _sessionEpoch,
            authValid: _pb.authStore.isValid,
          )) {
        debugPrint('[Msg] fetch aborted — session ended mid-flight');
        return;
      }
      if (all.isNotEmpty) {
        // F2a (idle-cascade fix, 2026-10-14): the delta filter is
        // inclusive (`created >= cursor`), so EVERY resume refetches each
        // conversation's boundary row. Records that are already durable,
        // locally resolved and byte-identical are dropped BEFORE the
        // key-resolve + decrypt hop — a no-op re-ingest used to
        // delete+insert the row (dirtying messages_table → a
        // watchMessages emission storm + per-conv key resolve on every
        // focus return; measured 18 convs / ~15s per shade pull). Dropped
        // records are proven present locally by serverId, so the cursor
        // still advances safely; unresolved rows (key_missing / pending)
        // keep the old retry path.
        final actionable = await _filterUnresolvedOrChanged(all, myId);
        // Review I2: only advance the cursor when the whole delta present
        // at fetch start landed (offset shifts during multi-page
        // catch-up would otherwise skip rows forever). Cold fetches
        // (cursor == null) commit to newest-40 by design — older history
        // is loadMoreMessages' job, nothing is being skipped.
        // Task 6: the delta rides the SAME commit as the batch (spec §7)
        // — an aborted commit holds rows AND cursor back together.
        final advance =
            cursor == null ||
            shouldAdvanceCursor(
              fetched: all.length,
              totalAtStart: totalAtStart,
            );
        final newest = DateTime.tryParse(all.first.getStringValue('created'));
        final cursorAdvance = (newest != null && advance)
            ? CursorDelta(conversationId: conversationId, to: newest)
            : null;

        if (actionable.isEmpty) {
          // Everything fetched is already durable — cursor-only commit:
          // no row writes, no stream emissions, no key resolve.
          if (cursorAdvance != null) {
            await ingestBoundary.commit(
              IngestBatch(cursorAdvance: cursorAdvance),
              IngestSource.fetch,
            );
          }
        } else {
          // Task 7 always-commit (the :2484 fix, spec §7): a missing key no
          // longer skips the cache — rows land with decrypt_state='key_missing'
          // and the cursor advances WITH them (same boundary txn), so the
          // window can neither be lost nor double-fetched; key arrival heals
          // via _repairUndecrypted / the batch self-heal.
          List<List<int>> keys;
          try {
            keys = await _getConvKeyCandidates(conversationId, myId);
          } on MissingKeyException catch (e) {
            debugPrint(
              '[Msg] key not ready during fetch — committing ciphertext: $e',
            );
            keys = const [];
          }
          await _cacheMessagesBatch(
            actionable,
            keys,
            myId,
            cursorAdvance: cursorAdvance,
          );
        }
        // Review C1 (hardening): the batch aborts WITHOUT writing when the
        // session ended mid-flight — the cursor lives in that same txn,
        // so it cannot advance past unwritten rows (spec §7). The
        // early-return keeps the trailing sync passes out of the wiped
        // session.
        if (!sessionStillValid(
          epochAtStart: epoch,
          currentEpoch: _sessionEpoch,
          authValid: _pb.authStore.isValid,
        )) {
          debugPrint('[Msg] cursor held back — batch aborted (session)');
          return;
        }
        if (!advance) {
          debugPrint(
            '[Msg] cursor held back (partial catch-up '
            '${all.length}/$totalAtStart)',
          );
        }
      }

      await _syncDeletedForMe(conversationId);
      await _syncStarredMessages(conversationId);
      // Repair any stuck ticks for my own messages in this conversation.
      await _reconcileReceiptsForConversation(conversationId, myId);
    } catch (e) {
      debugPrint('[Msg] fetch error (offline?): $e');
    }
  }

  /// Batched cache: one existing-rows query, one decryptBatch hop, one
  /// boundary commit. [records] must be one conversation, sorted
  /// `-created`. An empty [keys] list means the key lookup threw (Task 7
  /// always-commit):
  /// no decrypt attempt, every row commits `decrypt_state='key_missing'`,
  /// and the key-invalidating self-heal is skipped — there is no key to
  /// invalidate. Decrypt misses self-heal per-row (groups only) exactly
  /// like the single-row path. [cursorAdvance] rides the SAME commit as
  /// the upserts (spec §7 — Task 6).
  Future<void> _cacheMessagesBatch(
    List<RecordModel> records,
    List<List<int>> keys,
    String myId, {
    CursorDelta? cursorAdvance,
  }) async {
    if (records.isEmpty) return;
    final epoch = _sessionEpoch;
    final existing = await db.messagesDao.getMessagesByServerIds([
      for (final r in records) r.id,
    ]);
    final existingById = {for (final e in existing) e.serverId!: e};

    // Task 7: keyless batches skip the decrypt hop entirely — the
    // ciphertext still lands (key_missing), nothing is attempted, so no
    // miss can be mistaken for a stale key below.
    final decrypted = <String, String?>{};
    final decryptedKeyIds = <String, String>{};
    for (final key in keys) {
      final batch = await encryption.decryptBatch(key, [
        for (final r in records)
          {
            'id': r.id,
            'ciphertext': r.getStringValue('encrypted_body'),
            'iv': r.getStringValue('iv'),
          },
      ]);
      for (final r in records) {
        final body = batch[r.id];
        if (body != null && !decrypted.containsKey(r.id)) {
          decrypted[r.id] = body;
          decryptedKeyIds[r.id] = DecryptPass.fingerprintOf(key);
        }
      }
    }

    final companions = <MessagesTableCompanion>[];
    for (final r in records) {
      final e = existingById[r.id];
      final body = decrypted[r.id];

      // P7 (spec §3): the server's `reply_preview` is NOT decrypted and
      // NOT stored — schema v11 dropped `messages.reply_preview`. The UI
      // derives the quote from the parent row through
      // `messageBodyProvider`, so the only durable data a reply needs is
      // `reply_to_id` (kept below).

      String? forced;
      final isMine = r.getStringValue('sender_id') == myId;
      if (isMine && (e == null || e.status.isEmpty)) {
        forced = await _computeSenderStatus(r.id);
      }

      companions.add(
        _companionFromRecord(
          r,
          existing: e,
          decrypted: body,
          forcedStatus: forced,
          myId: myId,
          keyId: body == null || keys.isEmpty
              ? e?.keyId
              : decryptedKeyIds[r.id],
          decryptState: _ingestDecryptState(
            decrypted: body,
            keyMissing: keys.isEmpty,
            existing: e,
            record: r,
          ),
        ),
      );
    }

    // Review C1: decrypt awaited across the gap above — re-check before
    // touching the (possibly wiped) tables. The boundary re-checks its own
    // entry epoch too; this guard covers the DECRYPT window (epoch captured
    // at function entry, before the isolate hop), which a commit-time
    // capture would miss.
    if (!sessionStillValid(
      epochAtStart: epoch,
      currentEpoch: _sessionEpoch,
      authValid: _pb.authStore.isValid,
    )) {
      return;
    }
    // T9 (spec §3): decrypt-at-write plaintext lands ONLY in the session
    // body cache — same instant the column write used to occupy, so the
    // row's stream emission sees a resident body for entity hydration and
    // provider cache hits. Put BEFORE the commit so no stream consumer
    // can map the row before the cache is warm; an aborted commit leaves
    // at worst an orphan cache entry (LRU-bounded, never at rest).
    for (final c in companions) {
      final sid = c.serverId.value;
      final body = sid == null ? null : decrypted[sid];
      if (body != null) bodyCache.put(c.localId.value, body);
    }
    // Sole writer (Task 6): upserts + the cursor delta land in ONE
    // boundary transaction (spec §7). The delete-then-insert mechanics
    // (clear prior cache + FCM bg placeholders so ONE collision cannot
    // abort the batch; companions carry preserved flags; onConflict targets
    // localId — a placeholder written between the delete and the batch
    // would still abort, rare ms window, cursor held with the txn now
    // recovers it) moved into IngestBoundary.commit verbatim.
    await ingestBoundary.commit(
      IngestBatch(
        upserts: [for (final c in companions) MessageUpsert(c)],
        cursorAdvance: cursorAdvance,
      ),
      IngestSource.fetch,
    );

    // All retained keys were tried above. Rows that still miss are left
    // pending/key_missing and will be retried when key distribution catches up.

    // Conversation-list bump: newest incoming row only (sort -created →
    // records.first). It badges too: FCM background rows rely on it.
    final newest = records.first;
    if (newest.getStringValue('sender_id') != myId) {
      await _bumpConversationForIncoming(
        newest,
        _uuid.v4(),
        wasStored: existingById.containsKey(newest.id),
      );
    }
  }

  /// F2a: records from the delta that must take the ingest path.
  ///
  /// A record is DROPPED (already durable → no re-decrypt, no delete+insert,
  /// no stream emission) only when the local row by the same serverId is:
  ///  - locally resolved (`ready` or `device_sealed`) — unresolved rows keep
  ///    the per-resume retry (key arrival, transient decrypt failures), and
  ///  - byte-identical on every field `_companionFromRecord` would write
  ///    from the record (body, iv, sender, type, createdAt, deletion/pin
  ///    flags, reply, media), and
  ///  - not an own message with an uncomputed sender tick (the status
  ///    recompute lives in the batch builder).
  /// Anything else — a server-side change, a new row, an unresolved row —
  /// falls through to the old path unchanged.
  Future<List<RecordModel>> _filterUnresolvedOrChanged(
    List<RecordModel> records,
    String myId,
  ) async {
    if (records.isEmpty) return records;
    records = await _withoutRunOut(records, myId);
    final existing = await db.messagesDao.getMessagesByServerIds([
      for (final r in records) r.id,
    ]);
    if (existing.isEmpty) return records;
    final byId = {for (final e in existing) e.serverId!: e};
    final out = <RecordModel>[];
    for (final r in records) {
      final e = byId[r.id];
      if (e == null) {
        out.add(r); // never ingested → actionable
        continue;
      }
      final resolved =
          e.decryptState == 'ready' || e.decryptState == kDeviceSealedState;
      if (!resolved) {
        out.add(r); // retry semantics preserved
        continue;
      }
      if (r.getStringValue('sender_id') == myId && e.status.isEmpty) {
        out.add(r); // sender tick still owed
        continue;
      }
      final rawType = r.getStringValue('type');
      final type = rawType == 'file' ? 'document' : rawType;
      final createdAt = DateTime.tryParse(r.created);
      // createdAt compared at SECOND precision: PocketBase stamps carry
      // milliseconds but drift persists created_at at second granularity —
      // a raw ms equality made every real record look "changed" (the .000Z
      // test fixtures hid it; M52 rewrote all 21 convs on 2026-10-14).
      final sameSecond = createdAt != null &&
          e.createdAt.millisecondsSinceEpoch ~/ 1000 ==
              createdAt.millisecondsSinceEpoch ~/ 1000;
      final unchanged = sameSecond &&
          e.encryptedBody == r.getStringValue('encrypted_body') &&
          e.iv == r.getStringValue('iv') &&
          e.senderId == r.getStringValue('sender_id') &&
          e.type == type &&
          e.isDeletedForEveryone == r.getBoolValue('is_deleted_for_everyone') &&
          e.isPinned == r.getBoolValue('is_pinned') &&
          (e.replyToId ?? '') == r.getStringValue('reply_to_id') &&
          (e.mediaId ?? '') == r.getStringValue('media_id') &&
          (e.disappearAfter ?? 0) == r.getIntValue('disappear_after');
      if (!unchanged) out.add(r);
    }
    return out;
  }

  /// Spec B12: drops timed records this phone has no row for because its
  /// clock already removed them. The server keeps a copy until everyone has
  /// read it, and re-ingesting one would bring it back with a fresh clock and
  /// a phantom unread badge. Records of one chat. Any doubt keeps the record:
  /// a message must never be lost to this check.
  Future<List<RecordModel>> _withoutRunOut(
    List<RecordModel> records,
    String myId,
  ) async {
    final timed = [
      for (final r in records)
        if (r.getIntValue('disappear_after') > 0) r,
    ];
    if (timed.isEmpty) return records;
    final stored = await db.messagesDao.getMessagesByServerIds([
      for (final r in timed) r.id,
    ]);
    final storedIds = {for (final e in stored) e.serverId};
    final missing = [
      for (final r in timed)
        if (!storedIds.contains(r.id)) r,
    ];
    if (missing.isEmpty) return records;

    final now = pbClient.serverClock.now;
    if (now == null) return records;
    final gone = <String>{};
    if (missing.any((r) => r.getStringValue('sender_id') != myId)) {
      try {
        final mine = await _pb
            .collection('message_receipts')
            .getFullList(
              filter:
                  'conversation_id="${records.first.getStringValue('conversation_id')}"'
                  '&&recipient_id="$myId"&&read_at!=""',
              batch: 200,
            );
        final readAt = {
          for (final x in mine)
            x.getStringValue('message_id'): DateTime.tryParse(
              x.getStringValue('updated'),
            ),
        };
        for (final r in missing) {
          final seconds = r.getIntValue('disappear_after');
          if (readAt[r.id]?.add(Duration(seconds: seconds)).isBefore(now) ??
              false) {
            gone.add(r.id);
          }
        }
      } catch (e) {
        debugPrint('[Msg] run-out check skipped: $e');
      }
    }
    return [
      for (final r in records)
        if (!gone.contains(r.id)) r,
    ];
  }

  /// Review I1: bounded repair pass for rows whose ciphertext never
  /// decrypted (transient heal failures the cursor would otherwise skip
  /// forever). Runs on every chat open; at most 40 rows; media excluded by
  /// the query; keyless conversations are left to the banner path.
  Future<void> _repairUndecrypted(String conversationId) async {
    try {
      final rows = await db.messagesDao.getUndecryptableRows(conversationId);
      if (rows.isEmpty) {
        // Nothing left to heal — the give-up count no longer applies.
        _repairMissCounts.remove(conversationId);
        return;
      }
      // Backlog §170 (c): stop paying for rows we have already proven we
      // cannot heal. Two fruitless passes is one forgiven transient race.
      if ((_repairMissCounts[conversationId] ?? 0) >= _repairGiveUp) return;
      // Counted AFTER the cap so the number is work actually done, not
      // entries short-circuited by the budget.
      debugRepairRuns[conversationId] =
          (debugRepairRuns[conversationId] ?? 0) + 1;
      final epoch = _sessionEpoch;
      final myId = await _myId();
      if (myId.isEmpty) return;
      List<List<int>> keys;
      try {
        keys = await _getConvKeyCandidates(conversationId, myId);
      } on MissingKeyException {
        // No key on this device at all — the definitive key-loss case, and
        // exactly the row this budget exists to stop retrying.
        _accountRepair(conversationId, 0);
        return;
      }
      var decrypted = 0;
      for (final row in rows) {
        if (!sessionStillValid(
          epochAtStart: epoch,
          currentEpoch: _sessionEpoch,
          authValid: _pb.authStore.isValid,
        )) {
          return;
        }
        String? plain;
        String? keyId;
        for (final key in keys) {
          plain = await encryption.decryptMessage(
            row.encryptedBody,
            row.iv,
            key,
          );
          if (plain != null) {
            keyId = DecryptPass.fingerprintOf(key);
            break;
          }
        }
        if (plain != null) {
          decrypted++;
          bodyCache.put(row.localId, plain);
          await (db.update(
            db.messagesTable,
          )..where((t) => t.localId.equals(row.localId))).write(
            MessagesTableCompanion(
              decryptState: const Value('ready'),
              keyId: Value(keyId),
            ),
          );
        }
      }
      // Report what ACTUALLY decrypted. The old line logged rows.length — the
      // number ATTEMPTED — so a pass that healed nothing still claimed to have
      // healed every row, and the key-loss class was invisible in the logs.
      debugPrint(
        '[Enc] repair pass decrypted '
        '$decrypted of ${rows.length} stuck row(s) in $conversationId',
      );
      _accountRepair(conversationId, decrypted);
    } catch (e) {
      debugPrint('[Enc] repair pass failed: $e');
      // A fruitless attempt is still a fruitless attempt.
      _accountRepair(conversationId, 0);
    }
  }

  /// Counts a finished repair pass toward [conversationId]'s give-up budget.
  ///
  /// Called from every exit path, because the pass has several early returns
  /// (no key available, session changed) that are all fruitless — counting
  /// only the full loop would leave the budget permanently at zero and the
  /// cap unreachable.
  void _accountRepair(String conversationId, int decrypted) {
    if (decrypted == 0) {
      final misses = (_repairMissCounts[conversationId] ?? 0) + 1;
      _repairMissCounts[conversationId] = misses;
    } else {
      // A healed row proves the key situation can change — start the
      // transient-race budget again rather than stopping at the first row.
      _repairMissCounts.remove(conversationId);
    }
  }

  /// Repairs sender-side tick status for a conversation by recomputing from
  /// the server receipts. Fixes ticks that got stuck due to missed events.
  @visibleForTesting
  Future<void> debugReconcileReceipts(String conversationId) async =>
      _reconcileReceiptsForConversation(conversationId, await _myId());

  Future<void> _reconcileReceiptsForConversation(
    String conversationId,
    String myId,
  ) async {
    try {
      final rows = await db.messagesDao.watchMessages(conversationId).first;
      for (final row in rows) {
        if (row.senderId != myId) continue;
        final sid = row.serverId;
        if (sid == null || sid.isEmpty) continue;
        if (row.status == 'read') continue; // already terminal
        await _updateMsgReceiptStatus(row.localId, sid);
      }
    } catch (e) {
      debugPrint('[Receipt] reconcile: $e');
    }
  }

  Future<void> _syncDeletedForMe(String conversationId) async {
    final myId = await _myId();
    try {
      final res = await _pb
          .collection('deleted_messages_for_me')
          .getList(
            filter: 'user_id="$myId"&&conversation_id="$conversationId"',
            perPage: 500,
          );
      final deletedIds = res.items
          .map((r) => r.getStringValue('message_id'))
          .toSet();
      if (deletedIds.isEmpty) return;

      final rows = await db.messagesDao.watchMessages(conversationId).first;
      for (final row in rows) {
        if (row.serverId != null && deletedIds.contains(row.serverId)) {
          // Task 6: fetch-loop record write → boundary commit. Companion
          // now carries replyToId/expiresAt too — the
          // boundary's delete-then-insert rebuilds the row from the
          // companion, so every column the old conflict-update preserved
          // implicitly must be explicit here (lossless move). Task 7:
          // decryptState/keyId are the same class of column (omission
          // would reset a key_missing row to the default 'ready').
          await ingestBoundary.commit(
            IngestBatch(
              upserts: [
                MessageUpsert(
                  MessagesTableCompanion.insert(
                    localId: row.localId,
                    serverId: Value(row.serverId),
                    conversationId: row.conversationId,
                    senderId: row.senderId,
                    type: row.type,
                    encryptedBody: row.encryptedBody,
                    iv: row.iv,
                    replyToId: Value(row.replyToId),
                    isDeletedForMe: Value(true),
                    isDeletedForEveryone: Value(row.isDeletedForEveryone),
                    isStarred: Value(row.isStarred),
                    isPinned: Value(row.isPinned),
                    expiresAt: Value(row.expiresAt),
                    disappearAfter: Value(row.disappearAfter),
                    mediaId: Value(row.mediaId),
                    status: Value(row.status),
                    decryptState: Value(row.decryptState),
                    keyId: Value(row.keyId),
                    createdAt: row.createdAt,
                    updatedAt: DateTime.now(),
                  ),
                ),
              ],
            ),
            IngestSource.fetch,
          );
        }
      }
    } catch (e) {
      debugPrint('[Delete] syncDeletedForMe: $e');
    }
  }

  Future<void> _syncStarredMessages(String conversationId) async {
    final myId = await _myId();
    try {
      final res = await _pb
          .collection('starred_messages')
          .getList(
            filter: 'user_id="$myId"&&conversation_id="$conversationId"',
            perPage: 500,
          );
      final starredIds = res.items
          .map((r) => r.getStringValue('message_id'))
          .toSet();
      if (starredIds.isEmpty) return;

      final rows = await db.messagesDao.watchMessages(conversationId).first;
      for (final row in rows) {
        // F2a no-op: an already-starred row must not be rewritten — the
        // unconditional companion write (updatedAt: now) dirtied
        // messages_table on every resume for every starred message.
        if (row.serverId != null &&
            starredIds.contains(row.serverId) &&
            !row.isStarred) {
          // Task 6: fetch-loop record write → boundary commit (companion
          // completed with reply/expires columns — see _syncDeletedForMe;
          // Task 7 adds decryptState/keyId for the same rebuild reason).
          await ingestBoundary.commit(
            IngestBatch(
              upserts: [
                MessageUpsert(
                  MessagesTableCompanion.insert(
                    localId: row.localId,
                    serverId: Value(row.serverId),
                    conversationId: row.conversationId,
                    senderId: row.senderId,
                    type: row.type,
                    encryptedBody: row.encryptedBody,
                    iv: row.iv,
                    replyToId: Value(row.replyToId),
                    isDeletedForMe: Value(row.isDeletedForMe),
                    isDeletedForEveryone: Value(row.isDeletedForEveryone),
                    isStarred: Value(true),
                    isPinned: Value(row.isPinned),
                    expiresAt: Value(row.expiresAt),
                    disappearAfter: Value(row.disappearAfter),
                    mediaId: Value(row.mediaId),
                    status: Value(row.status),
                    decryptState: Value(row.decryptState),
                    keyId: Value(row.keyId),
                    createdAt: row.createdAt,
                    updatedAt: DateTime.now(),
                  ),
                ),
              ],
            ),
            IngestSource.fetch,
          );
        }
      }
    } catch (e) {
      debugPrint('[Star] syncStarredMessages: $e');
    }
  }

  // ── C2 user-scoped variants (review #72 accepted tradeoff, closed) ──
  //
  // The per-conversation syncs above run inside `_fetchAndCacheMessages`.
  // On a LIGHT resume that only backfills conversations with new rows,
  // quiet conversations' star/delete/tick state never reconciled until
  // chat-open or a ≥60s full resume. All three backing tables are
  // user_id-keyed (or user-scoped by nature): ONE query each covers every
  // conversation — the per-conversation filter simply drops.

  Future<void> _syncDeletedForMeUser(String myId) async {
    try {
      final res = await _pb.collection('deleted_messages_for_me').getFullList(
            filter: 'user_id="$myId"',
            batch: 200,
          );
      final deletedIds = {
        for (final r in res) r.getStringValue('message_id'),
      };
      if (deletedIds.isEmpty) return;
      final rows =
          await db.messagesDao.getMessagesByServerIds(deletedIds.toList());
      for (final row in rows) {
        // Idempotent: an already-flagged row is never rewritten (the
        // unconditional companion write would dirty drift on every resume).
        if (row.serverId == null || row.isDeletedForMe) continue;
        await ingestBoundary.commit(
          IngestBatch(
            upserts: [
              MessageUpsert(
                MessagesTableCompanion.insert(
                  localId: row.localId,
                  serverId: Value(row.serverId),
                  conversationId: row.conversationId,
                  senderId: row.senderId,
                  type: row.type,
                  encryptedBody: row.encryptedBody,
                  iv: row.iv,
                  replyToId: Value(row.replyToId),
                  isDeletedForMe: const Value(true),
                  isDeletedForEveryone: Value(row.isDeletedForEveryone),
                  isStarred: Value(row.isStarred),
                  isPinned: Value(row.isPinned),
                  expiresAt: Value(row.expiresAt),
                  disappearAfter: Value(row.disappearAfter),
                  mediaId: Value(row.mediaId),
                  status: Value(row.status),
                  decryptState: Value(row.decryptState),
                  keyId: Value(row.keyId),
                  createdAt: row.createdAt,
                  updatedAt: DateTime.now(),
                ),
              ),
            ],
          ),
          IngestSource.fetch,
        );
      }
    } catch (e) {
      debugPrint('[Delete] syncDeletedForMeUser: $e');
    }
  }

  Future<void> _syncStarredMessagesUser(String myId) async {
    try {
      final res = await _pb.collection('starred_messages').getFullList(
            filter: 'user_id="$myId"',
            batch: 200,
          );
      final starredIds = {
        for (final r in res) r.getStringValue('message_id'),
      };
      if (starredIds.isEmpty) return;
      final rows =
          await db.messagesDao.getMessagesByServerIds(starredIds.toList());
      for (final row in rows) {
        // F2a no-op: already-starred rows are never rewritten.
        if (row.serverId == null || row.isStarred) continue;
        await ingestBoundary.commit(
          IngestBatch(
            upserts: [
              MessageUpsert(
                MessagesTableCompanion.insert(
                  localId: row.localId,
                  serverId: Value(row.serverId),
                  conversationId: row.conversationId,
                  senderId: row.senderId,
                  type: row.type,
                  encryptedBody: row.encryptedBody,
                  iv: row.iv,
                  replyToId: Value(row.replyToId),
                  isDeletedForMe: Value(row.isDeletedForMe),
                  isDeletedForEveryone: Value(row.isDeletedForEveryone),
                  isStarred: const Value(true),
                  isPinned: Value(row.isPinned),
                  expiresAt: Value(row.expiresAt),
                  disappearAfter: Value(row.disappearAfter),
                  mediaId: Value(row.mediaId),
                  status: Value(row.status),
                  decryptState: Value(row.decryptState),
                  keyId: Value(row.keyId),
                  createdAt: row.createdAt,
                  updatedAt: DateTime.now(),
                ),
              ),
            ],
          ),
          IngestSource.fetch,
        );
      }
    } catch (e) {
      debugPrint('[Star] syncStarredMessagesUser: $e');
    }
  }

  Future<void> _reconcileReceiptsUser(String myId) async {
    try {
      final rows =
          await db.messagesDao.messagesNeedingReceiptReconcile(myId);
      // Parallel, chunked: each tick costs up to 3 HTTP round-trips, and
      // serially that measured ~300ms/row on M52 (6 rows = ~1.8s of a
      // light resume). Chunks of 8 cut the wall-clock ~4x while staying
      // a polite burst toward PocketBase.
      for (var i = 0; i < rows.length; i += 8) {
        final batch = rows.skip(i).take(8);
        await Future.wait(batch.map((row) async {
          final sid = row.serverId;
          if (sid == null || sid.isEmpty) return;
          if (row.status == 'read') return; // already terminal
          await _updateMsgReceiptStatus(row.localId, sid);
        }));
      }
    } catch (e) {
      debugPrint('[Receipt] reconcileUser: $e');
    }
  }

  /// In-flight cache operations keyed by serverId. The realtime subscription,
  /// the FCM foreground handler, and background fetches can all try to cache
  /// the same message concurrently — without serialization both see
  /// "no existing row" and insert duplicates (two bubbles for one message).
  final Map<String, Future<void>> _cacheInFlight = {};

  Future<void> _cacheMsg(
    RecordModel r,
    String myId,
    List<int>? key, {
    IngestSource source = IngestSource.fetch,
    List<List<int>>? keyCandidates,
  }) {
    final pending = _cacheInFlight[r.id];
    // Swallow the previous op's error so the chain always continues.
    final next = (pending ?? Future.value())
        .catchError((_) {})
        .then((_) => _cacheMsgInner(r, myId, key, source, keyCandidates));
    _cacheInFlight[r.id] = next.whenComplete(() {
      if (identical(_cacheInFlight[r.id], next)) _cacheInFlight.remove(r.id);
    });
    return next;
  }

  Future<void> _cacheMsgInner(
    RecordModel r,
    String myId,
    List<int>? key,
    IngestSource source,
    List<List<int>>? keyCandidates,
  ) async {
    final epoch = _sessionEpoch;
    // Note: isDeletedForEveryone is already synchronized automatically on fresh install
    // since is_deleted_for_everyone is fetched directly from the PocketBase messages collection schema.
    final encBody = r.getStringValue('encrypted_body');
    final iv = r.getStringValue('iv');
    String? decrypted;
    List<int>? decryptedWithKey;
    // Task 7: null key (the callers' MissingKeyException catch) means no
    // attempt — the ciphertext lands key_missing, no self-heal (there is
    // no cached key to invalidate and _getConvKey would just throw again).
    final List<List<int>> candidates =
        keyCandidates ?? (key == null ? const <List<int>>[] : <List<int>>[key]);
    for (final candidate in candidates) {
      if (decrypted != null) break;
      if (encBody.isEmpty || iv.isEmpty || encBody == '__pending__') break;
      decrypted = await encryption.decryptMessage(encBody, iv, candidate);
      if (decrypted != null) decryptedWithKey = candidate;
    }
    if (decrypted == null &&
        keyCandidates == null &&
        key != null &&
        encBody.isNotEmpty &&
        iv.isNotEmpty &&
        encBody != '__pending__') {
      final convId = r.getStringValue('conversation_id');
      final conv = await db.conversationsDao.getConversationById(convId);
      if (conv?.type == 'group') {
        debugPrint(
          '[Enc] Group decryption failed. Invalidating cached group key and refetching...',
        );
        try {
          await encryption.invalidateGroupKeyBase(convId); // C: disk + RAM
          final freshKey = await _getConvKey(convId, myId);
          decrypted = await encryption.decryptMessage(encBody, iv, freshKey);
          if (decrypted != null) decryptedWithKey = freshKey;
        } catch (e) {
          debugPrint('[Enc] Self-healing group key fetch failed: $e');
        }
      }
    }
    // P7 (spec §3): the server's `reply_preview` is NOT decrypted and NOT
    // stored (schema v11 dropped the column) — the quote derives from the
    // parent row at render time.

    final existing = await db.messagesDao.getMessageByServerId(r.id);
    final isMine = r.getStringValue('sender_id') == myId;

    // For my own messages: keep any existing (locally-known) status, but on a
    // fresh install (existing == null) — or when a prior cache left the status
    // empty — compute the real status from receipts instead of blindly
    // resetting to 'sent'.
    String? forcedStatus;
    if (isMine && (existing == null || (existing.status.isEmpty))) {
      forcedStatus = await _computeSenderStatus(r.id);
    }

    if (!sessionStillValid(
      epochAtStart: epoch,
      currentEpoch: _sessionEpoch,
      authValid: _pb.authStore.isValid,
    )) {
      return; // session ended mid-decrypt — do not resurrect wiped rows
    }
    // T9 (spec §3): decrypt-at-write plaintext → session cache only, pre-
    // commit (see the same pattern in _cacheMessagesBatch).
    final single = _companionFromRecord(
      r,
      existing: existing,
      decrypted: decrypted,
      forcedStatus: forcedStatus,
      myId: myId,
      keyId: decrypted == null || decryptedWithKey == null
          ? existing?.keyId
          : DecryptPass.fingerprintOf(decryptedWithKey),
      decryptState: _ingestDecryptState(
        decrypted: decrypted,
        keyMissing: candidates.isEmpty,
        existing: existing,
        record: r,
      ),
    );
    if (decrypted != null) bodyCache.put(single.localId.value, decrypted);
    // Sole writer (Task 6): the boundary re-checks its own entry epoch for
    // the commit window; the guard above covers the decrypt window.
    await ingestBoundary.commit(
      IngestBatch(upserts: [MessageUpsert(single)]),
      source,
    );
    if (!isMine) {
      await _bumpConversationForIncoming(
        r,
        existing?.localId ?? _uuid.v4(),
        wasStored: existing != null,
      );
    }
  }

  /// Task 7 (spec §5.1/§7): `decrypt_state` at ingest time —
  /// decrypt-at-write success ⇒ `'ready'`; key lookup threw (no attempt)
  /// ⇒ `'key_missing'`; key present but the ciphertext missed ⇒
  /// `'pending'` (committed, not decryptable yet — the retry/terminal
  /// split is DecryptPass's, Task 8; `'failed'` is never written here).
  /// A refetch that misses again keeps DecryptPass's earlier verdict for the
  /// same ciphertext: `pending` would put the row back on a skeleton that
  /// nothing re-resolves (backlog 13.3).
  String _ingestDecryptState({
    required String? decrypted,
    required bool keyMissing,
    MessagesTableData? existing,
    RecordModel? record,
  }) {
    if (decrypted != null) return 'ready';
    if (keyMissing) return 'key_missing';
    final prior = existing?.decryptState;
    if ((prior == 'key_missing' || prior == 'failed') &&
        existing!.encryptedBody == record?.getStringValue('encrypted_body')) {
      return prior!;
    }
    return 'pending';
  }

  /// Shared row-builder for the single and batched cache paths. Preserves
  /// locally-known flags from [existing].
  MessagesTableCompanion _companionFromRecord(
    RecordModel r, {
    required MessagesTableData? existing,
    required String? decrypted,
    String? forcedStatus,
    required String myId,
    required String decryptState,
    String? keyId,
  }) {
    final encBody = r.getStringValue('encrypted_body');
    final iv = r.getStringValue('iv');
    final rawMediaId = r.getStringValue('media_id');
    final rawType = r.getStringValue('type');
    final localType = rawType == 'file' ? 'document' : rawType;
    final convId = r.getStringValue('conversation_id');
    final createdAt = DateTime.tryParse(r.created) ?? DateTime.now();
    final isMine = r.getStringValue('sender_id') == myId;
    final albumId = r.getStringValue('album_id');

    String status;
    if (isMine) {
      final existingStatus = existing?.status ?? '';
      status =
          forcedStatus ?? (existingStatus.isNotEmpty ? existingStatus : 'sent');
    } else {
      status = 'delivered';
    }

    return MessagesTableCompanion.insert(
      localId: existing?.localId ?? _uuid.v4(),
      serverId: Value(r.id),
      conversationId: convId,
      senderId: r.getStringValue('sender_id'),
      type: localType,
      encryptedBody: encBody,
      iv: iv,
      replyToId: Value(
        r.getStringValue('reply_to_id').isEmpty
            ? null
            : r.getStringValue('reply_to_id'),
      ),
      // P7: NO reply_preview write — schema v11 dropped the column; the
      // quote derives from the parent row (replyToId) at render time.
      // Preserve locally-known star/pin/delete-for-me flags across re-caches.
      isPinned: Value(r.getBoolValue('is_pinned')),
      isStarred: Value(existing?.isStarred ?? false),
      isDeletedForMe: Value(existing?.isDeletedForMe ?? false),
      isDeletedForEveryone: Value(r.getBoolValue('is_deleted_for_everyone')),
      mediaId: Value(rawMediaId.isEmpty ? null : rawMediaId),
      status: Value(status),
      // Persist the fingerprint whenever ingest successfully decrypts. This
      // lets the lazy path distinguish rotation from actual corruption after
      // the in-memory body cache is cleared.
      decryptState: Value(decryptState),
      keyId: Value(keyId ?? existing?.keyId),
      // C3: old rows and non-album sends read `album_id = ''`, index 0.
      albumId: Value(albumId.isEmpty ? null : albumId),
      albumIndex: Value(
        albumId.isEmpty ? null : r.getIntValue('album_index'),
      ),
      disappearAfter: Value(_disappearAfterOf(r)),
      // Spec B3: a running clock is never moved. A new row copies a clock the
      // server already started (reinstall). Never derived from the chat's
      // timer: that stamped old history and purged it (backlog §7).
      expiresAt: Value(
        existing?.expiresAt ??
            DateTime.tryParse(r.getStringValue('expires_at')),
      ),
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  /// P7 (spec §3 / user ruling): the SERVER-BOUND reply preview, DERIVED
  /// at drain time from the parent row — never read from a durable column
  /// (`messages.reply_preview` is dropped in schema v11).
  ///
  /// Mirrors the labels the composer used to compute (chat_screen), so the
  /// wire payload keeps its exact `iv:ciphertext` shape. The plaintext
  /// source is the same one the UI's quote uses: the session body cache
  /// first, then the parent row's ciphertext with the already-resolved key
  /// (a process kill between enqueue and drain must not lose the preview).
  /// Returns null when there is no parent or nothing quotable — the caller
  /// then sends an empty `reply_preview`, exactly like a non-reply.
  Future<String?> _deriveReplyPreview(
    MessagesTableData? parent,
    List<int> key,
  ) async {
    if (parent == null) return null;
    switch (parent.type) {
      case 'image':
        return kPreviewPhotoLabel;
      case 'video':
        return kPreviewVideoLabel;
      case 'voice':
        return kPreviewVoiceLabel;
      case 'document':
        return kPreviewDocumentLabel;
      case 'sticker':
        return kPreviewStickerLabel;
      case 'poll':
        return '📊 Poll';
      case 'system':
        return 'System message';
    }
    var text = bodyCache.get(parent.localId);
    if (text == null || text.isEmpty) {
      if (parent.encryptedBody.isNotEmpty &&
          parent.encryptedBody != '__pending__' &&
          parent.iv.isNotEmpty) {
        // P8 (F3): a device-sealed parent was wrapped under the DEVICE key,
        // not the conversation key — [key] would decrypt it to garbage or
        // throw. Unwrap with the device key instead, same as
        // messageBodyProvider's `_splitSealed`.
        if (parent.decryptState == kDeviceSealedState) {
          final deviceKey = await deviceKeyStore.resolve();
          text = await encryption.decryptMessage(
            parent.encryptedBody,
            parent.iv,
            deviceKey,
          );
        } else {
          text = await encryption.decryptMessage(
            parent.encryptedBody,
            parent.iv,
            key,
          );
        }
      }
    }
    if (text == null || text.isEmpty) return null;
    return text.length > 60 ? '${text.substring(0, 60)}…' : text;
  }

  /// Keep the conversation list ordered on the RECIPIENT side too (the
  /// sender's device bumps it in sendMessage). Callers must gate on
  /// `!isMine` first. Only bumps for messages newer than the current
  /// lastMessageAt, so backfills can't reorder the list or double-count:
  /// the newest row bumps once, every older row is skipped. This is what
  /// makes the resume/cold-open backfill badge correctly.
  ///
  /// P7 (spec §3): bumps the ORDERING timestamp + unread badge only — the
  /// preview string used to be written here (decrypted body / media glyph)
  /// and is now DERIVED by the tile from this conversation's newest row.
  Future<void> _bumpConversationForIncoming(
    RecordModel r,
    String incomingLocalId, {
    required bool wasStored,
  }) async {
    final convId = r.getStringValue('conversation_id');
    final createdAt = DateTime.tryParse(r.created) ?? DateTime.now();
    if (r.getBoolValue('is_deleted_for_everyone')) return;
    final rawType = r.getStringValue('type');
    final localType = rawType == 'file' ? 'document' : rawType;
    try {
      final conv = await db.conversationsDao.getConversationById(convId);
      final currentLast = conv?.lastMessageAt;
      // Drift stores lastMessageAt in seconds and the record carries ms, so
      // a refetched row in the same second looked newer and re-badged on
      // every fetch (backlog 13.3). Same second: only a new row counts.
      if (currentLast != null) {
        final sec = createdAt.millisecondsSinceEpoch ~/ 1000;
        final lastSec = currentLast.millisecondsSinceEpoch ~/ 1000;
        if (sec < lastSec || (sec == lastSec && wasStored)) return;
      }
      await db.conversationsDao.updateLastMessage(convId, createdAt);
      // Unread badge: fires only for rows newer than the last known message
      // (the guard above), so a backfill of older history never counts, and
      // a genuinely-new message badges regardless of which path cached it
      // (SSE, FCM foreground, or resume backfill). While the chat is open,
      // markConversationRead resets it within ~1.5s as before.
      if (localType != 'system') {
        await db.conversationsDao.bumpUnread(convId, incomingLocalId);
      }
    } catch (e) {
      debugPrint('[Conv] recipient lastMessage bump: $e');
    }
  }

  /// Returns the user's cached display name, falling back to the username
  /// then the bare id. Local-only caller; safe to use everywhere.
  Future<String> _userName(String userId) async {
    if (userId.isEmpty) return 'Someone';
    try {
      final u = await db.usersDao.getUserById(userId);
      if (u != null) {
        if (u.displayName.isNotEmpty) return u.displayName;
        if (u.username.isNotEmpty) return '@${u.username}';
      }
      // Cache miss — pull and try again.
      try {
        final r = await _pb.collection('users').getOne(userId);
        await _cacheUserRecord(r);
        if (r.getStringValue('display_name').isNotEmpty) {
          return r.getStringValue('display_name');
        }
        if (r.getStringValue('username').isNotEmpty) {
          return '@${r.getStringValue('username')}';
        }
      } catch (_) {}
    } catch (_) {}
    return userId.length > 8 ? 'Member' : userId;
  }

  /// Emits a system / info message — a centered, italic "Alice created the
  /// group" / "Bob added Charlie" / "You were removed by David" row that
  /// surfaces to every group member (including the newly-added or just-
  /// removed user) via the realtime SSE feed. Strategy:
  ///  1. Insert a local row IMMEDIATELY so the actor (e.g. the admin who
  ///     pressed "remove") sees the bubble appear without waiting for the
  ///     round-trip.
  ///  2. Encrypt the body with the group key and POST it to PB as a real
  ///     `messages` record of `type='system'`. The SSE subscription will
  ///     deliver it to every other device. The local cache is already there
  ///     so the returning SSE echo is a harmless upsert (same localId).
  ///  3. If the PB write fails (offline), the local bubble is still useful —
  ///     it just won't reach other members until sync resumes.
  Future<void> _emitSystemMessage(
    String convId,
    String body, {
    required String actorUserId,
  }) async {
    try {
      final id = 'sys_${_uuid.v4()}';
      final now = DateTime.now();

      // (1) local immediate insert
      await db.messagesDao.upsertMessage(
        MessagesTableCompanion.insert(
          localId: id,
          serverId: const Value(null),
          conversationId: convId,
          senderId: actorUserId,
          type: 'system',
          encryptedBody: '',
          iv: '',
          status: const Value('sent'),
          createdAt: now,
          updatedAt: now,
        ),
      );
      // T9: local system text lives in the session cache (the server echo
      // re-lands it as ciphertext later — provider path then applies).
      bodyCache.put(id, body);
      debugPrint('[SysMsg] local emit → "$body" in $convId');

      // (2) push to PB so every group member sees it too
      try {
        // Only groups post system messages; DMs don't have this concept.
        final conv = await db.conversationsDao.getConversationById(convId);
        if (conv?.type != 'group') return;
        final myId = await _myId();
        final key = await _getConvKey(convId, myId);
        final res = await encryption.encryptMessage(body, key);

        await _pb
            .collection('messages')
            .create(
              body: {
                'conversation_id': convId,
                'sender_id': actorUserId,
                'type': 'system',
                'encrypted_body': res.ciphertext,
                'iv': res.iv,
                // No reply, no media, no star/pin — system row stays boring.
                'is_pinned': false,
                'is_deleted_for_everyone': false,
                'created': now.toUtc().toIso8601String(),
              },
            );
        debugPrint('[SysMsg] PB posted.');
      } catch (e) {
        debugPrint('[SysMsg] PB post failed (kept local-only): $e');
      }
    } catch (e) {
      debugPrint('[SysMsg] emit failed: $e');
    }
  }

  /// Local-only info bubble (never pushed to PocketBase) — for narrative
  /// rows that are only true on THIS device, e.g. "You were removed from
  /// this group" when a membership sync notices an admin removal.
  Future<void> _emitLocalSystemMessage(String convId, String body) async {
    // Spec D5 / review C1: never drop a local-only bubble into a signed-out
    // (wiped) session — straggler timers from the previous account land here.
    if (!_pb.authStore.isValid) return;
    final id = 'sys_${_uuid.v4()}';
    final now = DateTime.now();
    await db.messagesDao.upsertMessage(
      MessagesTableCompanion.insert(
        localId: id,
        serverId: const Value(null),
        conversationId: convId,
        senderId: await _myId(),
        type: 'system',
        encryptedBody: '',
        iv: '',
        status: const Value('sent'),
        createdAt: now,
        updatedAt: now,
      ),
    );
    // T9: session cache is this local-only row's only body home (no
    // ciphertext will ever arrive for it).
    bodyCache.put(id, body);
    debugPrint('[SysMsg] local-only emit → "$body" in $convId');
  }

  /// Computes a sender's message status ('sent'/'delivered'/'read') from the
  /// current receipts. Used when re-caching own messages after a reinstall.
  /// Strict semantics (see [_updateMsgReceiptStatus]) — every non-sender
  /// member of the conversation must have the matching timestamp.
  Future<String> _computeSenderStatus(String serverId) async {
    try {
      final res = await _pb
          .collection('message_receipts')
          .getFullList(filter: 'message_id="$serverId"', batch: 200);
      if (res.isEmpty) return 'sent';

      // Identify the conversation + sender so we can requery the live member
      // list (the present-receipts list isn't reliable during member
      // add/remove windows).
      String? convId;
      String? senderId;
      try {
        final msg = await _pb.collection('messages').getOne(serverId);
        convId = msg.getStringValue('conversation_id');
        senderId = msg.getStringValue('sender_id');
      } catch (_) {}

      Set<String> required = res
          .map((r) => r.getStringValue('recipient_id'))
          .where((uid) => uid.isNotEmpty)
          .toSet();
      if (convId != null) {
        try {
          final members = await _pb
              .collection('conversation_members')
              .getFullList(filter: 'conversation_id="$convId"', batch: 200);
          required = members
              .map((m) => m.getStringValue('user_id'))
              .where((uid) => uid.isNotEmpty && uid != senderId)
              .toSet();
          if (required.isEmpty)
            required = {
              '__none__',
            }; // Direct conv: no other members → tick immediately
        } catch (_) {}
      }

      final deliveredIds = res
          .where((r) => r.getStringValue('delivered_at').isNotEmpty)
          .map((r) => r.getStringValue('recipient_id'))
          .toSet();
      final readIds = res
          .where((r) => r.getStringValue('read_at').isNotEmpty)
          .map((r) => r.getStringValue('recipient_id'))
          .toSet();

      if (required.every(readIds.contains)) return 'read';
      if (required.every(deliveredIds.contains)) return 'delivered';
      return 'sent';
    } catch (_) {
      return 'sent';
    }
  }

  Future<void> _updateMsgReceiptStatus(String localId, String serverId) async {
    try {
      // getFullList avoids the 30-row default cap for large groups.
      final items = await _pb
          .collection('message_receipts')
          .getFullList(filter: 'message_id="$serverId"', batch: 200);
      if (items.isEmpty) {
        debugPrint('[Receipt] No receipts found for message: $serverId');
        return;
      }

      // Strict WhatsApp-style semantics: delivered/read is ticked ONLY when
      // EVERY non-sender member of the conversation has the matching
      // timestamp. The naive `items.every(...)` over present receipts
      // misses members whose receipt was never created (race during member
      // add/remove windows) — that was letting "delivered" tick as soon as
      // even one recipient filled it in. We cross-check against the live
      // conversation_members list from the server.
      // The local row, not the server's: an expired record is hidden from
      // every client, and this must still run for it.
      final local = await db.messagesDao.getMessageByLocalId(localId);
      final convId = local?.conversationId;
      final senderId = local?.senderId;

      Set<String> requiredRecipientIds = {};
      if (convId != null && senderId != null) {
        try {
          final members = await _pb
              .collection('conversation_members')
              .getFullList(filter: 'conversation_id="$convId"', batch: 200);
          requiredRecipientIds = members
              .map((m) => m.getStringValue('user_id'))
              .where((uid) => uid.isNotEmpty && uid != senderId)
              .toSet();
        } catch (_) {}
      }
      // Fall back to the present receipts when the cross-check can't run
      // (server unreachable, message row missing — shouldn't regress tick).
      if (requiredRecipientIds.isEmpty) {
        requiredRecipientIds = items
            .map((r) => r.getStringValue('recipient_id'))
            .where((uid) => uid.isNotEmpty)
            .toSet();
      }

      final deliveredIds = items
          .where((r) => r.getStringValue('delivered_at').isNotEmpty)
          .map((r) => r.getStringValue('recipient_id'))
          .toSet();
      final readIds = items
          .where((r) => r.getStringValue('read_at').isNotEmpty)
          .map((r) => r.getStringValue('recipient_id'))
          .toSet();

      final allDelivered = requiredRecipientIds.every(deliveredIds.contains);
      final allRead = requiredRecipientIds.every(readIds.contains);

      final computed = allRead
          ? 'read'
          : allDelivered
          ? 'delivered'
          : 'sent';

      // Never regress a stronger status (read > delivered > sent) — receipt
      // events can arrive out of order.
      const rank = {'sent': 0, 'delivered': 1, 'read': 2};
      final current = await db.messagesDao.getMessageByServerId(serverId);
      final currentStatus = current?.status ?? 'sent';
      if ((rank[computed] ?? 0) < (rank[currentStatus] ?? 0)) {
        debugPrint('[Receipt] Skipping regression $currentStatus -> $computed');
        return;
      }
      // Same value: the write would only re-emit the whole list (13.2).
      if (computed == current?.status) return;

      debugPrint(
        '[Receipt] Updating local message status to: $computed '
        '(deliveredIds=${deliveredIds.length}/${requiredRecipientIds.length}, '
        'readIds=${readIds.length}/${requiredRecipientIds.length})',
      );
      // `updated` is server time; `read_at` is the reader's device clock.
      final reads = items
          .where((r) => r.getStringValue('read_at').isNotEmpty)
          .map((r) => DateTime.tryParse(r.getStringValue('updated')))
          .nonNulls
          .toList()
        ..sort();
      // One transaction: 'read' is terminal for reconcile, so a kill between
      // the two writes would leave my copy's clock unstarted for good.
      await db.transaction(() async {
        await db.messagesDao.updateMessageStatus(localId, computed);
        // Spec B6: everyone has read it, so my copy counts from the last read.
        if (allRead && reads.isNotEmpty) {
          await db.messagesDao.startClockOnRow(localId, reads.last);
        }
      });
    } catch (e) {
      debugPrint('[Receipt] ERROR in statusUpdate: $e');
    }
  }

  /// Marks a message delivered for the current user (the recipient).
  /// Idempotent: the server has a UNIQUE(message_id, recipient_id) index, so
  /// a racing create just fails harmlessly and we fall back to update.
  Future<void> _markDelivered(
    String serverId,
    String convId,
    String myId,
  ) async {
    final nowUtc = DateTime.now().toUtc().toIso8601String();
    try {
      final res = await _pb
          .collection('message_receipts')
          .getList(
            filter: 'message_id="$serverId"&&recipient_id="$myId"',
            perPage: 1,
          );
      if (res.items.isEmpty) {
        try {
          await _pb
              .collection('message_receipts')
              .create(
                body: {
                  'message_id': serverId,
                  'conversation_id': convId,
                  'recipient_id': myId,
                  'delivered_at': nowUtc,
                },
              );
        } catch (_) {
          // Lost the create race (unique index) — someone else created it;
          // re-read and set delivered_at if still empty.
          final again = await _pb
              .collection('message_receipts')
              .getList(
                filter: 'message_id="$serverId"&&recipient_id="$myId"',
                perPage: 1,
              );
          if (again.items.isNotEmpty &&
              again.items.first.getStringValue('delivered_at').isEmpty) {
            await _pb
                .collection('message_receipts')
                .update(again.items.first.id, body: {'delivered_at': nowUtc});
          }
        }
      } else if (res.items.first.getStringValue('delivered_at').isEmpty) {
        await _pb
            .collection('message_receipts')
            .update(res.items.first.id, body: {'delivered_at': nowUtc});
      }
    } catch (e) {
      debugPrint('[Receipt] markDelivered: $e');
    }
  }

  Future<void> _createReceipts(
    String serverId,
    String convId,
    String myId,
  ) async {
    try {
      final members = await db.conversationsDao.getMembersForConversation(
        convId,
      );
      debugPrint(
        '[Receipt] Creating receipts for message $serverId to ${members.length} members',
      );

      for (final m in members) {
        if (m.userId == myId) {
          debugPrint('[Receipt] Skipping self receipt for $serverId');
          continue;
        }
        try {
          final existing = await _pb
              .collection('message_receipts')
              .getList(
                filter: 'message_id="$serverId"&&recipient_id="${m.userId}"',
                perPage: 1,
              );
          if (existing.items.isEmpty) {
            debugPrint(
              '[Receipt] Creating new receipt for recipient: ${m.userId}',
            );
            await _pb
                .collection('message_receipts')
                .create(
                  body: {
                    'message_id': serverId,
                    'conversation_id': convId,
                    'recipient_id': m.userId,
                  },
                );
            debugPrint('[Receipt] Receipt created for recipient: ${m.userId}');
          } else {
            debugPrint(
              '[Receipt] Receipt already exists for recipient: ${m.userId}',
            );
          }
        } catch (e) {
          debugPrint('[Receipt] ERROR creating receipt for ${m.userId}: $e');
        }
      }
    } catch (e) {
      debugPrint('[Receipt] ERROR in create: $e');
    }
  }

  Future<ConversationsTableData?> _fetchAndCacheConversation(
    String convId,
    String myId,
  ) async {
    try {
      _invalidateCutoff(convId);
      final conv = await _pb.collection('conversations').getOne(convId);
      final iconField = conv.getStringValue('icon');
      final iconUrl = iconField.isEmpty
          ? null
          : '${_pb.baseUrl}/api/files/conversations/${conv.id}/$iconField';
      final tableData = ConversationsTableData(
        id: conv.id,
        type: conv.getStringValue('type'),
        name: conv.getStringValue('name').isEmpty
            ? null
            : conv.getStringValue('name'),
        iconUrl: iconUrl,
        createdById: conv.getStringValue('created_by'),
        onlyAdminsCanMessage: conv.getBoolValue('only_admins_can_message'),
        disappearingDuration: conv.getIntValue('disappearing_duration'),
        isPinned: false,
        unreadCount: 0,
        lastReadLocalId: null,
        createdAt:
            DateTime.tryParse(conv.getStringValue('created')) ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await db.conversationsDao.upsertConversation(
        ConversationsTableCompanion.insert(
          id: tableData.id,
          type: tableData.type,
          name: Value(tableData.name),
          iconUrl: Value(tableData.iconUrl),
          createdById: tableData.createdById,
          onlyAdminsCanMessage: Value(tableData.onlyAdminsCanMessage),
          disappearingDuration: Value(tableData.disappearingDuration),
          isPinned: Value(tableData.isPinned),
          createdAt: tableData.createdAt,
          updatedAt: tableData.updatedAt,
        ),
      );
      final membersRes = await _pb
          .collection('conversation_members')
          .getFullList(
            filter: 'conversation_id="$convId"',
            expand: 'user_id',
            batch: 200,
          );
      // Join-triggered rotate, sync-discovery variant (see _syncConversations):
      // pre-check BEFORE each upsert so rows new-to-this-device schedule the
      // admin auto-rotate even when this fetch beats the full conversation
      // sync to a freshly (re)installed device.
      final localMemberIds =
          (await db.conversationsDao.getAllMembersForConversation(
            convId,
          )).map((lm) => lm.userId).toSet();
      for (final m in membersRes) {
        final u = m.expand['user_id']?.firstOrNull;
        if (u != null) await _cacheUserRecord(u);
        if (!localMemberIds.contains(m.getStringValue('user_id'))) {
          await _maybeScheduleRotate(convId, m.getStringValue('user_id'));
        }
        await db.conversationsDao.upsertMember(
          ConversationMembersTableCompanion.insert(
            id: m.id,
            conversationId: convId,
            userId: m.getStringValue('user_id'),
            role: Value(
              m.getStringValue('role').isEmpty
                  ? 'member'
                  : m.getStringValue('role'),
            ),
            joinedAt:
                DateTime.tryParse(m.getStringValue('joined_at')) ??
                DateTime.tryParse(m.created) ??
                DateTime.now(),
          ),
        );
      }
      // Drop stale rows (leave+rejoin gives the same user a NEW server row
      // id; the old local row would keep role 'left' and break the gate).
      await db.conversationsDao.removeStaleMemberRows(convId, {
        for (final m in membersRes) m.id,
      });
      return tableData;
    } catch (e) {
      debugPrint('[Msg] Failed to fetch and cache conversation $convId: $e');
      return null;
    }
  }

  /// The timer length the server fixed on this message. 0 means none.
  int? _disappearAfterOf(RecordModel r) {
    final seconds = r.getIntValue('disappear_after');
    return seconds > 0 ? seconds : null;
  }

  /// C1: best-effort conversation key resolution for encryption-at-enqueue.
  /// Returns null when the key is unavailable (peer key not synced, group
  /// key not yet rotated, storage/network failure) — the enqueue still
  /// lands with the interim `__pending__` marker and the drain persists the
  /// ciphertext at its first successful encrypt. Never lets a key failure
  /// block the user's optimistic message.
  Future<List<int>?> _tryResolveSendKey(String convId, String myId) async {
    try {
      // Preserve the offline-first optimistic path: a cached group key is
      // enough to seal the local outbox row immediately. The outbox drain's
      // _getConvKey call performs the authoritative current-key check before
      // server publication.
      final conv = await db.conversationsDao.getConversationById(convId);
      if (conv?.type == 'group') {
        final cachedGroupKey = await encryption.getCachedGroupKey(convId);
        if (cachedGroupKey != null) return cachedGroupKey;
      }
      return await _getConvKey(convId, myId);
    } catch (e) {
      debugPrint('[Msg] Enqueue key unavailable — keyless path: $e');
      return null;
    }
  }

  Future<List<int>> _getConvKey(String convId, String myId) async {
    var conv = await db.conversationsDao.getConversationById(convId);
    if (conv == null) {
      conv = await _fetchAndCacheConversation(convId, myId);
    }
    if (conv?.type == 'group') {
      // The single-key facade requires the newest server version when online;
      // it still falls back to locally retained keys only on transport loss.
      return encryption.getOrFetchGroupKey(convId, myId);
    }

    final members = await db.conversationsDao.getMembersForConversation(convId);
    final otherUserId = members
        .where((m) => m.userId != myId)
        .map((m) => m.userId)
        .firstOrNull;

    if (otherUserId == null || otherUserId.isEmpty) {
      throw const MissingKeyException(
        'no other member resolved for conversation',
      );
    }

    var u = await db.usersDao.getUserById(otherUserId);
    final cachedPublicKey = u?.publicKey;

    // Always fetch the latest public key from the server to detect key rotation
    // (e.g. the other user reinstalled the app and got a new key pair).
    try {
      final r = await _pb.collection('users').getOne(otherUserId);
      final serverPublicKey = r.getStringValue('public_key');
      if (serverPublicKey.isNotEmpty && serverPublicKey != cachedPublicKey) {
        debugPrint(
          '[Keys] Public key rotation detected for user $otherUserId — clearing derived key cache.',
        );
        await storage.saveContactEncryptionKey(
          convId,
          '',
        ); // Invalidate derived key
        await storage.clearAllContactKeys(); // Clear all stale derived keys
      }
      await _cacheUserRecord(r);
      u = await db.usersDao.getUserById(otherUserId);
    } catch (_) {}

    if (u?.publicKey == null || u!.publicKey!.isEmpty) {
      throw const MissingKeyException('peer public key not available yet');
    }
    return encryption.getOrDeriveConversationKey(convId, u.publicKey!);
  }

  Future<List<List<int>>> _getConvKeyCandidates(
    String convId,
    String myId,
  ) async {
    var conv = await db.conversationsDao.getConversationById(convId);
    if (conv == null) {
      conv = await _fetchAndCacheConversation(convId, myId);
    }
    if (conv?.type == 'group') {
      try {
        return await encryption.getOrFetchGroupKeyCandidates(convId, myId);
      } catch (e) {
        throw MissingKeyException('group key unavailable for $convId: $e');
      }
    }
    return [await _getConvKey(convId, myId)];
  }

  /// Test seam: drives the production reconcile path (list fetch +
  /// membership-reconcile + removal verdict) without going through the
  /// fire-and-forget background wrapper.
  @visibleForTesting
  Future<void> debugSyncConversations() async {
    final myId = await _myId();
    if (myId.isEmpty) return;
    await _syncConversations(myId);
  }

  Future<void> _syncConversations(String myId) async {
    final epoch = _sessionEpoch;
    // Membership rows and join timestamps are the authorization boundary for
    // group history. Never reuse a cutoff across a server reconciliation.
    _cutoffCache.clear();
    try {
      final res = await _pb
          .collection('conversation_members')
          .getList(
            filter: 'user_id="$myId"',
            expand: 'conversation_id',
            sort: '-created',
          );
      for (final m in res.items) {
        // Review C1: this loop spans many round-trips — bail the moment the
        // session ends, or the wiped DB refills with the old account's
        // conversations/members/users.
        if (!sessionStillValid(
          epochAtStart: epoch,
          currentEpoch: _sessionEpoch,
          authValid: _pb.authStore.isValid,
        )) {
          debugPrint('[Msg] conversation sync aborted — session ended');
          return;
        }
        final conv = m.expand['conversation_id']?.firstOrNull;
        if (conv == null) continue;
        final iconField = conv.getStringValue('icon');
        final iconUrl = iconField.isEmpty
            ? null
            : '${_pb.baseUrl}/api/files/conversations/${conv.id}/$iconField';
        // NEVER clobber the locally-computed last-message preview/time with
        // the server fields — nothing maintains them server-side, so they are
        // stale. Local Drift (updated by _cacheMsg/updateLastMessage) is the
        // source of truth; keep whichever timestamp is NEWER.
        final existingConv = await db.conversationsDao.getConversationById(
          conv.id,
        );
        final serverAtStr = conv.getStringValue('last_message_at');
        final serverAt = serverAtStr.isEmpty
            ? null
            : DateTime.tryParse(serverAtStr);
        final localAt = existingConv?.lastMessageAt;
        final keepLocal =
            localAt != null && (serverAt == null || localAt.isAfter(serverAt));
        await db.conversationsDao.upsertConversation(
          ConversationsTableCompanion.insert(
            id: conv.id,
            type: conv.getStringValue('type'),
            name: Value(
              conv.getStringValue('name').isEmpty
                  ? null
                  : conv.getStringValue('name'),
            ),
            iconUrl: Value(iconUrl),
            createdById: conv.getStringValue('created_by'),
            onlyAdminsCanMessage: Value(
              conv.getBoolValue('only_admins_can_message'),
            ),
            disappearingDuration: Value(
              conv.getIntValue('disappearing_duration'),
            ),
            isPinned: Value(existingConv?.isPinned ?? false),
            // P7 (spec §3): the server's `last_message_preview` is NOT
            // stored — schema v11 dropped the column. Local Drift keeps
            // only the ordering timestamp; the tile derives its label from
            // the newest message row (this server field is stale anyway —
            // see the comment above).
            lastMessageAt: Value(keepLocal ? localAt : (serverAt ?? localAt)),
            createdAt: DateTime.tryParse(conv.created) ?? DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
        await db.conversationsDao.upsertMember(
          ConversationMembersTableCompanion.insert(
            id: m.id,
            conversationId: conv.id,
            userId: myId,
            role: Value(
              m.getStringValue('role').isEmpty
                  ? 'member'
                  : m.getStringValue('role'),
            ),
            joinedAt:
                DateTime.tryParse(m.getStringValue('joined_at')) ??
                DateTime.tryParse(m.created) ??
                DateTime.now(),
          ),
        );
        // getFullList (not getList's 30 cap) so large groups sync fully.
        final others = await _pb
            .collection('conversation_members')
            .getFullList(
              filter: 'conversation_id="${conv.id}"&&user_id!="$myId"',
              expand: 'user_id',
              batch: 200,
            );
        final serverMemberIds = <String>{myId};
        // Join-triggered rotate, sync-discovery variant: if the SSE create
        // event was missed (offline admin), a member row that is NEW to this
        // device is discovered here. Must run BEFORE the upsert below makes
        // the row exist locally — same-map debounce collapses the duplicate
        // scheduling when the SSE handler fired moments earlier.
        final localMemberIds =
            (await db.conversationsDao.getAllMembersForConversation(
              conv.id,
            )).map((lm) => lm.userId).toSet();
        for (final om in others) {
          serverMemberIds.add(om.getStringValue('user_id'));
          final u = om.expand['user_id']?.firstOrNull;
          if (u != null) await _cacheUserRecord(u);
          if (!localMemberIds.contains(om.getStringValue('user_id'))) {
            await _maybeScheduleRotate(conv.id, om.getStringValue('user_id'));
          }
          await db.conversationsDao.upsertMember(
            ConversationMembersTableCompanion.insert(
              id: om.id,
              conversationId: conv.id,
              userId: om.getStringValue('user_id'),
              role: Value(
                om.getStringValue('role').isEmpty
                    ? 'member'
                    : om.getStringValue('role'),
              ),
              joinedAt:
                  DateTime.tryParse(om.getStringValue('joined_at')) ??
                  DateTime.tryParse(om.created) ??
                  DateTime.now(),
            ),
          );
        }

        // Reconcile removals: drop local members who are no longer on the
        // server (fixes "removed member still shows" on the other device),
        // and drop stale rows whose server row id no longer exists (a
        // leave+rejoin creates a NEW server row for the same user; the old
        // local row would keep its 'left' role and break the rejoiner's
        // composer gate).
        final localForConv = await db.conversationsDao
            .getMembersForConversation(conv.id);
        for (final lm in localForConv) {
          if (!serverMemberIds.contains(lm.userId)) {
            await (db.delete(db.conversationMembersTable)..where(
                  (t) =>
                      t.conversationId.equals(conv.id) &
                      t.userId.equals(lm.userId),
                ))
                .go();
          }
        }
        await db.conversationsDao.removeStaleMemberRows(conv.id, {
          m.id,
          for (final om in others) om.id,
        });
      }

      final activeConvIds = res.items
          .map((m) => m.expand['conversation_id']?.firstOrNull?.id)
          .whereType<String>()
          .toSet();

      final localMembers = await db.conversationsDao.getMembershipsOfUser(myId);
      for (final lm in localMembers) {
        if (lm.role == 'left') continue;
        if (activeConvIds.contains(lm.conversationId)) {
          _removalMissCounts.remove(lm.conversationId); // seen — healthy
          continue;
        }
        final conv = await db.conversationsDao.getConversationById(
          lm.conversationId,
        );
        if (conv?.type != 'group') continue;

        // §7 false-removal guard: this list snapshot can PRECEDE a freshly
        // created membership row (live repro 2026-10-12 — group condemned
        // seconds after creation), and one page can also cap older rows out.
        // Absence from the list is therefore only a MISS: count consecutive
        // misses and confirm against a direct point query before condemning.
        final misses = (_removalMissCounts[lm.conversationId] ?? 0) + 1;
        _removalMissCounts[lm.conversationId] = misses;

        final bool stillMember;
        try {
          final probe = await _pb
              .collection('conversation_members')
              .getList(
                filter:
                    'conversation_id="${lm.conversationId}"&&user_id="$myId"',
              );
          stillMember = probe.items.isNotEmpty;
        } catch (e) {
          debugPrint(
            '[Conv] removal confirm failed for ${lm.conversationId}: $e',
          );
          continue; // cannot confirm absence — never condemn on an error
        }
        if (stillMember) {
          _removalMissCounts.remove(lm.conversationId); // race, not removal
          continue;
        }
        if (misses < _removalConfirmMisses) {
          debugPrint(
            '[Conv] membership miss $misses/$_removalConfirmMisses for '
            '${lm.conversationId} — holding verdict',
          );
          continue;
        }
        _removalMissCounts.remove(lm.conversationId);

        await (db.update(db.conversationMembersTable)..where(
              (t) =>
                  t.conversationId.equals(lm.conversationId) &
                  t.userId.equals(myId),
            ))
            .write(
              const ConversationMembersTableCompanion(role: Value('left')),
            );
        // We did NOT leave from THIS device (leaveGroup sets 'left'
        // locally first, so the branch above is skipped there) — the
        // server dropped our membership: an admin removed us (#17).
        // Wipe the cached group key so we can neither decrypt nor send
        // anything further, and drop a local-only info bubble so the
        // removal is visible in the timeline even if the removal SSE
        // message was missed (e.g. offline at the time).
        try {
          // C: storage semantics + RAM eviction (write-through).
          await encryption.clearCurrentGroupKey(lm.conversationId);
          await storage.write(
            key: 'contact_key_${lm.conversationId}_gk',
            value: '',
          );
          await _emitLocalSystemMessage(
            lm.conversationId,
            'You were removed from this group',
          );
        } catch (e) {
          debugPrint('[Group] membership-loss cleanup failed: $e');
        }
      }
    } catch (e) {
      debugPrint('[Conv] sync: $e');
    }
  }

  Future<List<Conversation>> _convRowsToEntities(
    List<ConversationsTableData> rows,
  ) async {
    final myId = await _myId();

    // ── Pass 1: best direct-conv-row per counter-party + cache the peer ──
    // For DMs with the same peer we keep the row with the most recent message.
    final bestDirectByUser = <String, ConversationsTableData>{};
    final otherByConvId = <String, User?>{};
    for (final r in rows) {
      if (r.type != 'direct') continue;
      final other = await _getOtherUser(r.id, myId);
      otherByConvId[r.id] = other;
      if (other == null) continue;
      final candidateScore = r.lastMessageAt ?? r.createdAt;
      final existing = bestDirectByUser[other.id];
      if (existing == null ||
          candidateScore.isAfter(
            existing.lastMessageAt ?? existing.createdAt,
          )) {
        bestDirectByUser[other.id] = r;
      }
    }

    // ── Pass 2: emit in ORIGINAL DB order (pinned desc, then last_msg desc).
    //    DMs and groups mix naturally — no more "all DMs then all groups".
    final out = <Conversation>[];
    for (final r in rows) {
      if (r.type == 'direct') {
        final other = otherByConvId[r.id];
        if (other == null) {
          // Peer not yet in local user cache — drop this row from the
          // chat list. The Friends section below surfaces them.
          continue;
        }
        if (bestDirectByUser[other.id]?.id != r.id)
          continue; // dup, kept the newer row
        final count = await _getMemberCount(r.id);
        out.add(_convDataToEntity(r, other, memberCount: count));
      } else {
        final count = await _getMemberCount(r.id);
        out.add(_convDataToEntity(r, null, memberCount: count));
      }
    }
    return out;
  }

  Future<int> _getMemberCount(String convId) async =>
      (await db.conversationsDao.getMembersForConversation(convId)).length;

  Future<User?> _getOtherUser(String convId, String myId) async {
    final members = await db.conversationsDao.getMembersForConversation(convId);
    for (final m in members) {
      if (m.userId != myId) {
        final u = await db.usersDao.getUserById(m.userId);
        if (u != null) return _tableUserToEntity(u);
      }
    }
    return null;
  }

  Conversation _convDataToEntity(
    ConversationsTableData r,
    User? otherUser, {
    int? memberCount,
  }) => Conversation(
    id: r.id,
    type: r.type,
    name: r.name,
    iconUrl: r.iconUrl,
    lastMessageAt: r.lastMessageAt,
    isPinned: r.isPinned,
    otherUser: otherUser,
    onlyAdminsCanMessage: r.onlyAdminsCanMessage,
    memberCount: memberCount ?? 0,
    unreadCount: r.unreadCount,
  );

  Message _rowToMessage(MessagesTableData r, String myId) => Message(
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

  User _tableUserToEntity(dynamic u, {String? groupRole}) => User(
    id: u.id,
    displayName: u.displayName,
    username: u.username,
    email: u.email ?? '',
    friendCode: u.friendCode,
    avatarUrl: u.avatarUrl,
    about: u.about,
    publicKey: u.publicKey,
    isOnline: u.isOnline,
    lastSeen: u.lastSeen,
    createdAt: u.createdAt,
    groupRole: groupRole,
  );

  Future<void> _cacheUserRecord(RecordModel r) async {
    final avatar = r.getStringValue('avatar');
    await db.usersDao.upsertUser(
      UsersTableCompanion(
        id: Value(r.id),
        displayName: Value(r.getStringValue('display_name')),
        username: Value(r.getStringValue('username')),
        email: Value(r.getStringValue('email')),
        avatarUrl: Value(
          avatar.isEmpty
              ? null
              : '${_pb.baseUrl}/api/files/users/${r.id}/$avatar',
        ),
        friendCode: Value(r.getStringValue('friend_code')),
        publicKey: Value(
          r.getStringValue('public_key').isEmpty
              ? null
              : r.getStringValue('public_key'),
        ),
        isOnline: Value(r.getBoolValue('is_online')),
        createdAt: Value(DateTime.tryParse(r.created) ?? DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}

final messageRepositoryProvider = Provider<MessageRepository>((ref) {
  final repo = MessageRepositoryImpl(
    pbClient: ref.watch(pocketbaseClientProvider),
    db: ref.read(appDatabaseProvider),
    storage: ref.read(secureStorageProvider),
    encryption: ref.read(encryptionServiceProvider),
    mediaUploadService: ref.read(mediaUploadServiceProvider),
  );
  FcmService.setRepository(repo);
  return repo;
});
// REPLACE the existing deleteMessage with this:
