# W1 Reliability Spine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the four structural faults in the app's realtime/sync/state spine (SSE churn, full-refetch sync, duplicate-row writes, watch storm) plus session hygiene and jump-to-message, per the approved "fix the spine" approach.

**Architecture:** Keep the current architecture. Token refresh decouples from navigation and realtime rebuilds gate on identity change; message sync becomes cursor-incremental with one batched decrypt+insert per fetch; `messages.serverId` gets a UNIQUE index so duplicate writes are impossible by construction; the home stream loses its asyncMap race and the row mapper gets a cached cutoff. No server changes.

**Tech Stack:** Flutter/Riverpod/Drift (client only), existing PB client. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-10-04-w1-reliability-design.md`

## Global Constraints

- NO git commits until the user verifies on devices (standing rule). Per-task commit steps are shown for granularity but SKIPPED; Task 7 collects the single commit.
- `flutter analyze` must be 0 errors after every client task; `flutter test` all green.
- DAO tests use `AppDatabase.test()` (in-memory) — see `test/conversations_dao_test.dart` for the pattern.
- All timestamps used for cursors/filters come from SERVER `created` strings, never the device clock.
- Test devices: Samsung `RFCRA047WSJ`, Redmi `c7e9f10e` (arm64). APK verify: `unzip -l ... | grep arm64-v8a/libflutter` (the 25 Sep x64-only build bug must never recur).
- Live-capture reference (pre-fix baseline): `~/.claude/jobs/d5cf0040/tmp/cap_samsung.log`, `cap_redmi.log` — 54 SSE rebuilds/25min, 6s fetch→emit, 1057 emits. The T7 pass re-captures and compares.

## Review Focus

- **Pending message (null `serverId`) under the new UNIQUE index** — must insert/keep fine (SQLite UNIQUE allows many NULLs). Pinned: Task 3 test `pending rows with null serverId coexist`.
- **Migration on devices with existing duplicate rows** — dedupe-before-createIndex or migration crashes. Pinned: Task 3 test `dedupe keeps one row per serverId` (runs the migration SQL on seeded dups).
- **Device clock skew** — cursor math uses server `created` only. Pinned: Task 2 test `filter uses server timestamps verbatim`.
- **Delta larger than one page on resume** — incremental fetch pages until caught up. Pinned: Task 2 test `full page fetches next page`.
- **Logout while sends/syncs in flight** — timers cancelled, wiped DB makes late writes fail harmlessly, no crash. Manual step in Task 7 pass list (not unit-testable without a device).

---

### Task 1: Realtime gate — identity-gated reconnect + refresh throttle

**Files:**
- Create: `lib/core/utils/realtime_gate.dart`
- Create: `test/realtime_gate_test.dart`
- Modify: `lib/infrastructure/repositories/message_repository_impl.dart:43-56` (authStore.onChange listener), `:127-151` (`_reconnect` debounce)
- Modify: `lib/infrastructure/repositories/auth_repository_impl.dart:238-271` (getCurrentUser cached path — remove `_backgroundRefresh()` call; `_backgroundRefresh` gains a 30-min throttle)
- Modify: `lib/features/auth/providers/auth_provider.dart` (add `refreshSessionThrottled()`)
- Modify: `lib/app.dart:42-49` (resumed handler also calls the throttled refresh)

**Interfaces:**
- Produces: `bool shouldReconnectRealtime({required bool wasAuthenticated, required bool isAuthenticated, required String? previousUserId, required String? newUserId})` (pure); auth repo `Future<void> refreshSessionThrottled()`; repo private `String? _realtimeUserId`, `bool _wasAuthenticated`, `Timer? _reconnectDebounce`.

- [ ] **Step 1: Write the failing test**

```dart
// test/realtime_gate_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/utils/realtime_gate.dart';

void main() {
  test('logout always reconnects (teardown)', () {
    expect(shouldReconnectRealtime(
        wasAuthenticated: true, isAuthenticated: false,
        previousUserId: 'a', newUserId: null), isTrue);
  });

  test('login from logged-out reconnects', () {
    expect(shouldReconnectRealtime(
        wasAuthenticated: false, isAuthenticated: true,
        previousUserId: null, newUserId: 'a'), isTrue);
  });

  test('same-user token churn does NOT reconnect', () {
    expect(shouldReconnectRealtime(
        wasAuthenticated: true, isAuthenticated: true,
        previousUserId: 'a', newUserId: 'a'), isFalse);
  });

  test('account switch reconnects', () {
    expect(shouldReconnectRealtime(
        wasAuthenticated: true, isAuthenticated: true,
        previousUserId: 'a', newUserId: 'b'), isTrue);
  });

  test('same user but id unresolvable yet does NOT reconnect', () {
    // authRefresh fires before _saveSession persists the id — treat as
    // same-session churn, not a new login.
    expect(shouldReconnectRealtime(
        wasAuthenticated: true, isAuthenticated: true,
        previousUserId: 'a', newUserId: null), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/realtime_gate_test.dart`
Expected: FAIL — `shouldReconnectRealtime` undefined.

- [ ] **Step 3: Implement the pure helper**

```dart
// lib/core/utils/realtime_gate.dart
/// Whether an authStore change requires rebuilding the realtime
/// subscriptions: only when the logged-in IDENTITY changes (logout, login,
/// account switch) — never when PocketBase merely rotates the token string
/// for the same session (authRefresh), which was rebuilding the SSE client
/// on every navigation (~54x/25min, losing events in every window).
bool shouldReconnectRealtime({
  required bool wasAuthenticated,
  required bool isAuthenticated,
  required String? previousUserId,
  required String? newUserId,
}) {
  if (!isAuthenticated) return true; // logout — tear down
  if (!wasAuthenticated) return true; // login — connect
  // Same live session: refresh events may precede the persisted-id write,
  // so an unresolvable id is churn, not a switch.
  if (newUserId == null) return false;
  return previousUserId != newUserId;
}
```

Run: `flutter test test/realtime_gate_test.dart` → PASS (5).

- [ ] **Step 4: Rewire the repo listener + debounce `_reconnect`**

In `message_repository_impl.dart` add fields near `_opChain`:

```dart
  bool    _wasAuthenticated = false;
  String? _realtimeUserId;
  Timer?  _reconnectDebounce;
```

Replace the `authStore.onChange.listen` body (lines 43-56):

```dart
    _pb.authStore.onChange.listen((event) async {
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
            isAuthenticated:  authenticated,
            previousUserId:   _realtimeUserId,
            newUserId:        userId,
          )) {
        debugPrint('[Msg] Auth token changed (same session) — ignoring.');
        return;
      }
      _wasAuthenticated = authenticated;
      _realtimeUserId = userId;
      if (authenticated) {
        debugPrint('[Msg] Auth identity changed — reconnecting subscriptions.');
        _reconnect();
      } else {
        debugPrint('[Msg] Logged out — unsubscribing.');
        _pendingJoinEmitConvIds.clear();
        for (final t in _rotateDebounce.values) {
          t.cancel();
        }
        _rotateDebounce.clear();
        _teardown();
      }
    });
```

Wrap `_reconnect`'s body in a 500ms debounce (rapid fires collapse into one rebuild):

```dart
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
          final delay = Duration(
            seconds: (1 << (_reconnectAttempts.clamp(0, 5))).clamp(1, 30),
          );
          debugPrint('[Msg] Subscribe failed ($e). Retrying in ${delay.inSeconds}s.');
          _reconnectTimer = Timer(delay, _reconnect);
          _startPollFallback();
        }
      });
    });
  }
```

Add import: `import '../../core/utils/realtime_gate.dart';`

- [ ] **Step 5: Throttle auth refresh; stop refresh-on-navigation**

`auth_repository_impl.dart`:

```dart
  DateTime? _lastAuthRefresh;
  static const _authRefreshInterval = Duration(minutes: 30);

  /// Session refresh, throttled to once per 30 minutes. Called from app
  /// RESUME — never from navigation (every navigation used to authRefresh,
  /// rotate the token, and rebuild all SSE subscriptions).
  @override
  Future<void> refreshSessionThrottled() async {
    final now = DateTime.now();
    if (_lastAuthRefresh != null &&
        now.difference(_lastAuthRefresh!) < _authRefreshInterval) {
      return;
    }
    _lastAuthRefresh = now;
    _backgroundRefresh();
  }
```

In `getCurrentUser`'s cached path DELETE the line `_backgroundRefresh();` (the user is returned from cache; the no-cache `authRefresh` path stays as-is).

`auth_provider.dart` — expose it (find the Notifier class wrapping `_repo`; add):

```dart
  Future<void> refreshSessionThrottled() => _repo.refreshSessionThrottled();
```

Add to `lib/domain/repositories/auth_repository.dart` the matching signature near `signOut`:

```dart
  /// Throttled (30 min) background session refresh. Resume-only.
  Future<void> refreshSessionThrottled();
```

`app.dart` resumed case (after the existing `resyncOnResume()` line):

```dart
        ref.read(authProvider.notifier).refreshSessionThrottled();
```

- [ ] **Step 6: analyze + tests**

Run: `flutter analyze` → 0 errors. Run: `flutter test` → all PASS.

---

### Task 2: Incremental sync — cursor + batched cache

**Files:**
- Create: `lib/core/utils/sync_cursor.dart`
- Create: `test/sync_cursor_test.dart`
- Modify: `lib/data/local/database/daos/messages_dao.dart` (add `hasAnyMessages`, `getMessagesByServerIds`)
- Modify: `lib/infrastructure/repositories/message_repository_impl.dart` (`_fetchAndCacheMessages` rework, `_cacheMessagesBatch`, `_companionFromRecord` extraction, `_readCursor`/`_writeCursor`, `_cacheMsgInner` gains `live` param — the `live` wiring is Task 5 Step 3; here default `live = false` keeps behavior)

**Interfaces:**
- Consumes: `encryption.decryptBatch(List<int> key, List<Map<String,String>> items) → Map<String,String?>` (exists, `encryption_service.dart:287`), items shaped `{'id', 'ciphertext', 'iv'}`.
- Produces: `String? incrementalFetchFilter(DateTime? cursor)` (pure); DAO `Future<bool> hasAnyMessages(String conversationId)`, `Future<List<MessagesTableData>> getMessagesByServerIds(List<String> ids)`; repo `_cacheMessagesBatch(List<RecordModel>, String myId)`, `_companionFromRecord(...)` (shared with `_cacheMsgInner`).

- [ ] **Step 1: Write the failing tests**

```dart
// test/sync_cursor_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/utils/sync_cursor.dart';

void main() {
  test('null cursor (cold cache) → no incremental filter', () {
    expect(incrementalFetchFilter(null), isNull);
  });

  test('cursor → strictly-newer server filter, UTC ISO verbatim', () {
    final c = DateTime.utc(2026, 10, 4, 17, 58, 30, 177);
    expect(incrementalFetchFilter(c),
        'created > "2026-10-04 17:58:30.177Z"');
  });

  test('server-timestamp strings pass through unmodified (no clock skew)', () {
    // Cursor parsed FROM a server 'created' string must re-serialize to the
    // same instant — devices never contribute their own clock here.
    final server = DateTime.tryParse('2026-10-04 17:58:30.177Z')!;
    expect(incrementalFetchFilter(server.toUtc()),
        'created > "2026-10-04 17:58:30.177Z"');
  });

  test('full page means maybe more delta → fetch next page', () {
    expect(shouldFetchNextPage(pageItems: 40, perPage: 40), isTrue);
    expect(shouldFetchNextPage(pageItems: 12, perPage: 40), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/sync_cursor_test.dart`
Expected: FAIL — functions undefined.

- [ ] **Step 3: Implement**

```dart
// lib/core/utils/sync_cursor.dart
/// PB filter for the incremental message fetch: only rows strictly newer
/// than [cursor]. Null cursor (cold/empty cache) → null (caller fetches the
/// latest page only, like the old behaviour).
///
/// [cursor] always originates from a server `created` string — never from
/// the device clock — so skew between devices cannot skip messages.
String? incrementalFetchFilter(DateTime? cursor) {
  if (cursor == null) return null;
  final t = cursor.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  final stamp =
      '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${t.millisecond.toString().padLeft(3, '0')}Z';
  return 'created > "$stamp"';
}

/// A full page means there may be more delta rows on the next page.
bool shouldFetchNextPage({required int pageItems, required int perPage}) =>
    pageItems >= perPage;
```

Run: `flutter test test/sync_cursor_test.dart` → PASS (4).

- [ ] **Step 4: DAO helpers**

In `messages_dao.dart`:

```dart
  /// True when any cached row exists for the conversation (warm vs cold
  /// fetch decision — cold fetches the latest page, warm fetches only the
  /// cursor delta).
  Future<bool> hasAnyMessages(String conversationId) async {
    final row = await (select(messagesTable)
          ..where((t) => t.conversationId.equals(conversationId))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  /// Existing rows for a batch of server ids (batched-cache flag
  /// preservation). Missing ids are simply absent from the result.
  Future<List<MessagesTableData>> getMessagesByServerIds(
      List<String> serverIds) async {
    if (serverIds.isEmpty) return [];
    return (select(messagesTable)
          ..where((t) => t.serverId.isIn(serverIds)))
        .get();
  }
```

- [ ] **Step 5: Extract `_companionFromRecord` from `_cacheMsgInner`**

Create the shared row-builder in the repo (used by both `_cacheMsgInner` and the Task 2 batch path). `decryptedReplyPreview` is pre-decrypted by the caller — the single path decrypts inline before calling; the batch path decrypts with the same batch key.

```dart
  /// Shared row-builder for the single and batched cache paths. Preserves
  /// locally-known flags from [existing] exactly as `_cacheMsgInner` did.
  MessagesTableCompanion _companionFromRecord(
    RecordModel r, {
    required MessagesTableData? existing,
    required String? decrypted,
    String? decryptedReplyPreview,
    String? forcedStatus,
    required String myId,
  }) {
    final encBody = r.getStringValue('encrypted_body');
    final iv      = r.getStringValue('iv');
    final rawMediaId = r.getStringValue('media_id');
    final rawType = r.getStringValue('type');
    final localType = rawType == 'file' ? 'document' : rawType;
    final convId = r.getStringValue('conversation_id');
    final createdAt = DateTime.tryParse(r.created) ?? DateTime.now();
    final isMine = r.getStringValue('sender_id') == myId;

    String status;
    if (isMine) {
      final existingStatus = existing?.status ?? '';
      status = forcedStatus ??
          (existingStatus.isNotEmpty ? existingStatus : 'sent');
    } else {
      status = 'delivered';
    }

    return MessagesTableCompanion.insert(
      localId:              existing?.localId ?? _uuid.v4(),
      serverId:             Value(r.id),
      conversationId:       convId,
      senderId:             r.getStringValue('sender_id'),
      type:                 localType,
      encryptedBody:        encBody,
      iv:                   iv,
      decryptedBody:        Value(decrypted ?? existing?.decryptedBody),
      replyToId:            Value(r.getStringValue('reply_to_id').isEmpty
          ? null : r.getStringValue('reply_to_id')),
      replyPreview:         Value(decryptedReplyPreview ?? existing?.replyPreview),
      isPinned:             Value(r.getBoolValue('is_pinned')),
      isStarred:            Value(existing?.isStarred ?? false),
      isDeletedForMe:       Value(existing?.isDeletedForMe ?? false),
      isDeletedForEveryone: Value(r.getBoolValue('is_deleted_for_everyone')),
      mediaId:              Value(rawMediaId.isEmpty ? null : rawMediaId),
      status:               Value(status),
      expiresAt:            Value(_computeExpirySync(convId, createdAt)),
      createdAt:            createdAt,
      updatedAt:            DateTime.now(),
    );
  }
```

`_computeExpiry` is async (reads the conversation row). Add a sync variant that reads from an in-memory map warmed by the conversation sync (avoids per-row awaits in the batch path):

```dart
  final Map<String, int> _disappearingDurations = {}; // convId -> seconds

  int? _computeExpirySync(String convId, DateTime from) {
    final secs = _disappearingDurations[convId] ?? 0;
    if (secs <= 0) return null;
    return from.add(Duration(seconds: secs));
  }
```

Warm the map in `_fetchAndCacheConversation` and `_syncConversations` where `disappearing_duration` is already read: `_disappearingDurations[conv.id] = conv.getIntValue('disappearing_duration');` (add next to the existing conv-row handling in BOTH places).

Rewrite `_cacheMsgInner` to use the helper (same behavior: per-row decrypt, self-heal group key, preview decrypt, `_computeSenderStatus` when `existing == null && isMine` — pass that status in via a new optional param `String? forcedStatus` that overrides the helper's default):

```dart
  Future<void> _cacheMsgInner(RecordModel r, String myId, List<int> key,
      {bool live = false, String? forcedStatus}) async {
    final encBody = r.getStringValue('encrypted_body');
    final iv      = r.getStringValue('iv');
    String? decrypted;
    if (encBody.isNotEmpty && iv.isNotEmpty && encBody != '__pending__') {
      decrypted = await encryption.decryptMessage(encBody, iv, key);
      if (decrypted == null) {
        final convId = r.getStringValue('conversation_id');
        final conv = await db.conversationsDao.getConversationById(convId);
        if (conv?.type == 'group') {
          debugPrint('[Enc] Group decryption failed. Invalidating cached group key and refetching...');
          try {
            await storage.delete(key: 'group_key_$convId');
            final freshKey = await _getConvKey(convId, myId);
            decrypted = await encryption.decryptMessage(encBody, iv, freshKey);
          } catch (e) {
            debugPrint('[Enc] Self-healing group key fetch failed: $e');
          }
        }
      }
    }
    String? replyPreview;
    final rawReply = r.getStringValue('reply_preview');
    if (rawReply.isNotEmpty) {
      final idx = rawReply.indexOf(':');
      if (idx > 0 && encBody != '__pending__') {
        final rIv = rawReply.substring(0, idx);
        final rCt = rawReply.substring(idx + 1);
        replyPreview = await encryption.decryptMessage(rCt, rIv, key) ?? '🔒';
      } else {
        replyPreview = rawReply;
      }
    }
    final existing = await db.messagesDao.getMessageByServerId(r.id);
    final isMine = r.getStringValue('sender_id') == myId;
    String? forced = forcedStatus;
    if (forced == null && isMine && existing == null) {
      forced = await _computeSenderStatus(r.id);
    }
    await db.messagesDao.upsertMessage(_companionFromRecord(
      r,
      existing: existing,
      decrypted: decrypted,
      decryptedReplyPreview: replyPreview,
      myId: myId,
    ));
    await _bumpConversationForIncoming(r, existing?.localId, live: live);
  }
```

Extract the recipient-side conversation bump from the old `_cacheMsgInner` tail into (this is where the Task 5 unread fix will land — keep the current guard for now):

```dart
  Future<void> _bumpConversationForIncoming(RecordModel r, String? existingLocalId,
      {bool live = false}) async {
    final isMine = false; // caller context: only incoming rows bump
    if (isMine) return;
    final convId = r.getStringValue('conversation_id');
    final createdAt = DateTime.tryParse(r.created) ?? DateTime.now();
    if (r.getBoolValue('is_deleted_for_everyone')) return;
    try {
      final conv = await db.conversationsDao.getConversationById(convId);
      final currentLast = conv?.lastMessageAt;
      if (currentLast != null && !createdAt.isAfter(currentLast)) return;
      final localType = r.getStringValue('type') == 'file'
          ? 'document' : r.getStringValue('type');
      final preview = switch (localType) {
        'image'    => '📷 Photo',
        'video'    => '🎬 Video',
        'voice'    => '🎤 Voice message',
        'document' => '📎 Document',
        _          => 'New message',
      };
      await db.conversationsDao.updateLastMessage(convId, preview, createdAt);
      // Task 5 flips this guard to live-only; current behavior preserved.
      if (localType != 'system' &&
          conv?.lastReadLocalId != null &&
          conv!.lastReadLocalId!.isNotEmpty) {
        await db.conversationsDao.bumpUnread(
            convId, existingLocalId ?? _uuid.v4());
      }
    } catch (e) {
      debugPrint('[Conv] recipient lastMessage bump: $e');
    }
  }
```

- [ ] **Step 6: Batched cache path + cursor rework of `_fetchAndCacheMessages`**

Add cursor helpers + batch path to the repo:

```dart
  Future<DateTime?> _readCursor(String convId) async {
    final raw = await db.settingsDao.getSetting('sync_cursor_$convId');
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> _writeCursor(String convId, DateTime at) =>
      db.settingsDao.setSetting(
          'sync_cursor_$convId', at.toUtc().toIso8601String());

  /// Batched variant of the per-row cache loop: one existing-rows query,
  /// one decryptBatch isolate hop, one Drift batch insert → ONE stream
  /// emit for the whole page (was 40 serial decrypt+upserts ≈ 6s).
  Future<void> _cacheMessagesBatch(
      List<RecordModel> records, String myId) async {
    if (records.isEmpty) return;
    final convId = records.first.getStringValue('conversation_id');

    List<int>? key;
    try {
      key = await _getConvKey(convId, myId);
    } on MissingKeyException {
      key = null;
    }

    final existing = await db.messagesDao
        .getMessagesByServerIds([for (final r in records) r.id]);
    final existingById = {for (final e in existing) e.serverId!: e};

    final decrypted = <String, String?>{};
    if (key != null) {
      decrypted = await encryption.decryptBatch(key, [
        for (final r in records)
          {
            'id':         r.id,
            'ciphertext': r.getStringValue('encrypted_body'),
            'iv':         r.getStringValue('iv'),
          },
      ]);
    }

    final companions = <MessagesTableCompanion>[];
    for (final r in records) {
      final e = existingById[r.id];
      var body = decrypted[r.id];
      // Self-heal (rare): per-row retry with a fresh key on decrypt miss.
      if (body == null &&
          key != null &&
          r.getStringValue('encrypted_body').isNotEmpty &&
          r.getStringValue('iv').isNotEmpty) {
        try {
          await storage.delete(key: 'group_key_$convId');
          final freshKey = await _getConvKey(convId, myId);
          body = await encryption.decryptMessage(
              r.getStringValue('encrypted_body'),
              r.getStringValue('iv'), freshKey);
        } catch (_) {}
      }
      String? preview;
      final rawReply = r.getStringValue('reply_preview');
      if (rawReply.isNotEmpty && key != null) {
        final idx = rawReply.indexOf(':');
        if (idx > 0 &&
            r.getStringValue('encrypted_body') != '__pending__') {
          preview = await encryption.decryptMessage(
                  rawReply.substring(idx + 1),
                  rawReply.substring(0, idx), key) ?? '🔒';
        } else {
          preview = rawReply;
        }
      }
      String? forced;
      final isMine = r.getStringValue('sender_id') == myId;
      if (isMine && e == null) forced = await _computeSenderStatus(r.id);
      companions.add(_companionFromRecord(r,
          existing: e, decrypted: body,
          decryptedReplyPreview: preview, myId: myId));
    }

    await db.batch((b) {
      for (final c in companions) {
        b.insert(messagesTable, c,
            onConflict: DoUpdate((_) => c, target: [messagesTable.localId]));
      }
    });

    // Conversation-list bump: newest incoming row only (sort -created →
    // records.first). Fetch path is never "live" — no unread bump here.
    final newest = records.first;
    if (newest.getStringValue('sender_id') != myId &&
        !newest.getBoolValue('is_deleted_for_everyone')) {
      await _bumpConversationForIncoming(newest, null, live: false);
    }
  }
```

Replace `_fetchAndCacheMessages` body (keep the method name/signature; keep the error-swallowing catch):

```dart
  Future<void> _fetchAndCacheMessages(String conversationId) async {
    try {
      final myId = await _myId();
      final cacheEmpty =
          !(await db.messagesDao.hasAnyMessages(conversationId));
      final cursor = cacheEmpty ? null : await _readCursor(conversationId);
      final inc = incrementalFetchFilter(cursor);
      final pageFilter = inc == null
          ? 'conversation_id="$conversationId"'
          : 'conversation_id="$conversationId" && $inc';

      final all = <RecordModel>[];
      var page = 1;
      while (true) {
        final res = await _pb.collection('messages').getList(
              filter: pageFilter,
              sort: '-created',
              perPage: 40,
              page: page,
            );
        all.addAll(res.items);
        // Cold fetch: one page (latest 40), same as before — older history
        // loads via loadMoreMessages. Warm fetch: page until delta caught up.
        if (cursor == null ||
            !shouldFetchNextPage(pageItems: res.items.length, perPage: 40)) {
          break;
        }
        page++;
      }
      if (all.isNotEmpty) {
        await _cacheMessagesBatch(all, myId);
        final newest = DateTime.tryParse(all.first.getStringValue('created'));
        if (newest != null) await _writeCursor(conversationId, newest);
      }
      await _syncDeletedForMe(conversationId);
      await _syncStarredMessages(conversationId);
      await _reconcileReceiptsForConversation(conversationId, myId);
    } catch (e) {
      debugPrint('[Msg] fetch error (offline?): $e');
    }
  }
```

Add import: `import '../../core/utils/sync_cursor.dart';`

- [ ] **Step 7: analyze + tests**

Run: `flutter analyze` → 0 errors. Run: `flutter test` → all PASS.

---

### Task 3: serverId UNIQUE index — duplicates impossible by construction

**Files:**
- Modify: `lib/data/local/database/tables/messages_table.dart` (add `@TableIndex`)
- Modify: `lib/data/local/database/app_database.dart:57` (schemaVersion 6) + migration (dedupe-then-index)
- Modify: `lib/data/local/database/daos/messages_dao.dart` (add `upsertMessageByServerId`, `deleteByServerIdExcept`; remove `dedupByServerId` + its call sites)
- Modify: `lib/services/fcm_service.dart:471` (bg placeholder write → `upsertMessageByServerId`)
- Modify: `lib/infrastructure/repositories/message_repository_impl.dart` (`_uploadMessage`/`_uploadMediaMessage` guard before stamping serverId; remove `dedupByServerId()` calls in `watchMessages` + `resyncOnResume`)
- Create: `test/messages_dao_server_id_test.dart`

**Interfaces:**
- Produces: DAO `Future<void> upsertMessageByServerId(MessagesTableCompanion msg)` (asserts non-null serverId), `Future<void> deleteByServerIdExcept(String serverId, String keepLocalId)`; unique index `idx_messages_server_id`.

- [ ] **Step 1: Write the failing test**

```dart
// test/messages_dao_server_id_test.dart
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';

MessagesTableCompanion _row(String localId, {String? serverId}) =>
    MessagesTableCompanion.insert(
      localId: localId,
      serverId: Value(serverId),
      conversationId: 'c1',
      senderId: 'u1',
      type: 'text',
      encryptedBody: 'enc',
      iv: 'iv',
      createdAt: DateTime(2026, 10, 4),
      updatedAt: DateTime(2026, 10, 4),
    );

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.test());
  tearDown(() => db.close());

  test('pending rows with null serverId coexist under the unique index',
      () async {
    await db.messagesDao.upsertMessage(_row('a'));
    await db.messagesDao.upsertMessage(_row('b'));
    final rows = await db.select(db.messagesTable).get();
    expect(rows.length, 2); // both null-serverId pendings kept
  });

  test('bg placeholder upsert updates the existing row (no duplicate)',
      () async {
    await db.messagesDao.upsertMessage(_row('main-uuid', serverId: 's1'));
    await db.messagesDao.upsertMessageByServerId(
        _row('s1', serverId: 's1')); // FCM bg isolate shape
    final rows = await db.select(db.messagesTable).get();
    expect(rows.length, 1);
    expect(rows.single.localId, 'main-uuid');
  });

  test('dedupe SQL keeps the oldest row per serverId', () async {
    // Seed the duplicate shape the FCM isolate used to produce.
    await db.customStatement(
        "INSERT INTO messages (local_id, server_id, conversation_id, "
        "sender_id, type, encrypted_body, iv, status, created_at, updated_at) "
        "VALUES ('main-uuid', 's1', 'c1', 'u1', 'text', 'e', 'i', 'sent', "
        "'2026-10-04 10:00:00.000', '2026-10-04 10:00:00.000')");
    await db.customStatement(
        "INSERT INTO messages (local_id, server_id, conversation_id, "
        "sender_id, type, encrypted_body, iv, status, created_at, updated_at) "
        "VALUES ('s1', 's1', 'c1', 'u1', 'text', 'e', 'i', 'delivered', "
        "'2026-10-04 10:00:01.000', '2026-10-04 10:00:01.000')");
    await db.customStatement(DedupBeforeUniqueIndex.sql);
    final rows = await db.select(db.messagesTable).get();
    expect(rows.length, 1);
    expect(rows.single.localId, 'main-uuid'); // oldest rowid wins
  });

  test('deleteByServerIdExcept removes only the foreign row', () async {
    await db.messagesDao.upsertMessage(_row('main-uuid', serverId: 's1'));
    await db.messagesDao.upsertMessage(_row('s1', serverId: 's1'));
    await db.messagesDao.deleteByServerIdExcept('s1', 'main-uuid');
    final rows = await db.select(db.messagesTable).get();
    expect(rows.length, 1);
    expect(rows.single.localId, 'main-uuid');
  });
}
```

NOTE: `DedupBeforeUniqueIndex.sql` — put the SQL in a shared const so migration + test use the same string. Create `lib/data/local/database/migrations/dedup_sql.dart`:

```dart
/// Dedupes messages rows sharing one serverId before the UNIQUE index is
/// created (schema v6). Keeps the OLDEST row per serverId (rowid order) —
/// the main-isolate original, which carries decrypted state; the FCM
/// background isolate's placeholder row is the later insert.
class DedupBeforeUniqueIndex {
  static const sql =
      "DELETE FROM messages WHERE server_id IS NOT NULL AND rowid NOT IN "
      "(SELECT MIN(rowid) FROM messages WHERE server_id IS NOT NULL "
      "GROUP BY server_id)";
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/messages_dao_server_id_test.dart`
Expected: FAIL — `upsertMessageByServerId` / `DedupBeforeUniqueIndex` undefined; duplicate insert succeeds (no index yet).

- [ ] **Step 3: Implement table index + migration**

`messages_table.dart` — add the `@TableIndex` annotation on the class (fresh installs get the index via `createAll`):

```dart
@TableIndex(name: 'idx_messages_server_id', columns: {#serverId}, unique: true)
class MessagesTable extends Table {
```

`app_database.dart`: `schemaVersion => 6`; extend `onUpgrade` — dedupe BEFORE index creation or it crashes on devices with FCM-race duplicates. Use the explicit partial-index `customStatement` (drift-version-proof, matches the annotation's effect on a nullable column):

```dart
          if (from < 6) {
            // Duplicate rows (FCM background-isolate races) would break
            // UNIQUE index creation — dedupe first, then build the index.
            await customStatement(DedupBeforeUniqueIndex.sql);
            await customStatement(
                'CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_server_id '
                'ON messages (server_id) WHERE server_id IS NOT NULL');
          }
```

(SQLite UNIQUE permits many NULLs either way; the partial form just keeps the index lean. Existing duplicate rows are deduped by `DedupBeforeUniqueIndex.sql` keeping the OLDEST row per serverId — the main-isolate original with decrypted state.)

- [ ] **Step 4: DAO methods + bandaid removal**

`messages_dao.dart`:

```dart
  /// Upsert keyed on serverId (UNIQUE index target). Used by the FCM
  /// background isolate whose rows are deterministic (localId == serverId):
  /// when the main isolate already cached the message under a UUID key,
  /// this UPDATES that row instead of inserting a duplicate bubble.
  Future<void> upsertMessageByServerId(MessagesTableCompanion msg) {
    assert(msg.serverId.present && msg.serverId.value != null);
    return into(messagesTable).insert(
      msg,
      onConflict: DoUpdate(
        (_) => msg,
        target: [messagesTable.serverId],
      ),
    );
  }

  /// Deletes any OTHER row already holding [serverId] — called right before
  /// stamping a freshly-sent optimistic row with its server id, so the
  /// UPDATE cannot violate the unique index when the FCM isolate pre-cached
  /// the same message.
  Future<void> deleteByServerIdExcept(String serverId, String keepLocalId) =>
      (delete(messagesTable)
            ..where((t) =>
                t.serverId.equals(serverId) &
                t.localId.equals(keepLocalId).not()))
          .go();
```

Delete `dedupByServerId` entirely; delete its call sites in `message_repository_impl.dart` (`watchMessages`: `db.messagesDao.dedupByServerId();` and `resyncOnResume`: `await db.messagesDao.dedupByServerId();`).

- [ ] **Step 5: Call-site switches**

`fcm_service.dart` `_cacheMessageBackground` (~line 471): change `localDb.messagesDao.upsertMessage(` → `localDb.messagesDao.upsertMessageByServerId(` (the row already has `localId: messageId` + `serverId: Value(messageId)`).

`message_repository_impl.dart` `_uploadMessage` — immediately BEFORE the post-create upsert that stamps `serverId: Value(record.id)` (~line 637):

```dart
      // The FCM background isolate may have pre-cached this message while
      // our optimistic row was pending — clear its placeholder so the
      // serverId stamp below cannot violate the unique index.
      await db.messagesDao.deleteByServerIdExcept(record.id, localId);
```

Same insertion in `_uploadMediaMessage` before its `serverId`-stamping upsert (~line 820), guarding with the same two lines using `messageServerId`/`localId`.

- [ ] **Step 6: analyze + tests**

Run: `flutter analyze` → 0 errors. Run: `flutter test` → all PASS.

---

### Task 4: Watch storm + defunct crash

**Files:**
- Modify: `lib/features/home/providers/conversations_provider.dart` (autoDispose)
- Modify: `lib/infrastructure/repositories/message_repository_impl.dart` (`watchConversations` deferred asyncMap; `_rowsToMessages` cutoff cache; invalidation points)

**Interfaces:**
- Produces: repo `void _invalidateCutoff(String convId)` called from `_subMembers`, `acceptGroupInvite`, `leaveGroup`, `removeMemberFromGroup`.

- [ ] **Step 1: Home provider autoDispose + deferred mapping**

`conversations_provider.dart`:

```dart
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
```

`watchConversations` (repo ~line 455) — move the mapping off the synchronous dispose window:

```dart
  @override
  Stream<List<Conversation>> watchConversations() {
    _syncConversationsBackground(); // Fire-and-forget
    return db.conversationsDao
        .watchAllConversations()
        .asyncMap((rows) async {
          // Yield the CPU once so a disposing listener detaches BEFORE the
          // mapped notify lands (defunct-element race).
          await Future<void>.delayed(Duration.zero);
          return _convRowsToEntities(rows);
        });
  }
```

- [ ] **Step 2: Cutoff cache for `_rowsToMessages`**

Replace the per-emit lookups (added in the W2 rework) with a cache:

```dart
  /// Group-history cutoff per conversation (member joinedAt), cached —
  /// _rowsToMessages runs on EVERY table write; per-emit DAO round-trips
  /// multiplied that into the watch storm. Invalidated on membership
  /// change via [_invalidateCutoff].
  final Map<String, DateTime?> _cutoffCache = {};

  void _invalidateCutoff(String convId) => _cutoffCache.remove(convId);

  Future<DateTime?> _groupCutoff(String convId) async {
    if (_cutoffCache.containsKey(convId)) return _cutoffCache[convId];
    DateTime? cutoff;
    final conv = await db.conversationsDao.getConversationById(convId);
    if (conv?.type == 'group') {
      final myId = await _myId();
      final members =
          await db.conversationsDao.getAllMembersForConversation(convId);
      cutoff =
          members.where((m) => m.userId == myId).firstOrNull?.joinedAt;
    }
    _cutoffCache[convId] = cutoff;
    return cutoff;
  }
```

`_rowsToMessages` becomes:

```dart
  Future<List<Message>> _rowsToMessages(
      List<MessagesTableData> rows) async {
    final myId = await _myId();
    if (rows.isEmpty) return [];
    final joinedAt = await _groupCutoff(rows.first.conversationId);
    return [
      for (final r in rows)
        if (joinedAt == null ||
            isGroupRowVisible(
              createdAt:      r.createdAt,
              memberJoinedAt: joinedAt,
              decryptedBody:  r.decryptedBody,
              type:           r.type,
            ))
          _rowToMessage(r, myId),
    ];
  }
```

Add `_invalidateCutoff(convId)` calls: in `_subMembers` handler (first line of the callback, any action), at the end of `acceptGroupInvite`, inside `leaveGroup` before return, inside `removeMemberFromGroup` after the delete.

- [ ] **Step 3: analyze + tests**

Run: `flutter analyze` → 0 errors. Run: `flutter test` → all PASS.

---

### Task 5: Session hygiene — logout wipe, bg-network retry, unread fix

**Files:**
- Modify: `lib/infrastructure/repositories/auth_repository_impl.dart:307-314` (signOut wipe)
- Modify: `lib/services/fcm_service.dart` (`_retryNetwork` helper; wrap `_cacheMessageBackground` fetch + `_markDelivered` calls)
- Modify: `lib/infrastructure/repositories/message_repository_impl.dart` (`_cacheMsgInner` callers pass `live`; `_bumpConversationForIncoming` live-only guard)

**Interfaces:**
- Consumes: `SecureStorageService.clearAll()` (exists, `secure_storage_service.dart:75`); Task 2's `_cacheMsgInner({bool live})`.
- Produces: fcm static `Future<T> _retryNetwork<T>(Future<T> Function() op, {int tries})`.

- [ ] **Step 1: signOut wipes everything**

`auth_repository_impl.dart` signOut:

```dart
  @override
  Future<void> signOut() async {
    await _fcmTokenSubscription?.cancel();
    _fcmTokenSubscription = null;
    pbClient.clearAuth();
    // B1: the next sign-in must start CLEAN — wipe every table (messages,
    // conversations, members, receipts, starred/deleted sync state) and all
    // secure-storage keys (auth token, private key, group key cache).
    // Late in-flight writes from timers fail harmlessly against empty
    // tables; the router has already redirected to splash.
    try {
      await storage.clearAll();
    } catch (e) {
      debugPrint('[Auth] secure storage wipe failed: $e');
    }
    for (final table in db.allTables) {
      await db.delete(table).go();
    }
  }
```

(The old two `setSetting(''/...)` lines are redundant — the delete loop clears the settings table too. If `db.allTables` is not exposed by this Drift version, use the explicit list: `db.messagesDao` tables are registered in `app_database.dart` `@DriftDatabase(tables: [...])` — enumerate the same list via `db.allSchemaEntities.whereType<TableInfo>()`.)

- [ ] **Step 2: bg-isolate network retry**

`fcm_service.dart` — add a static helper near `_cacheMessageBackground`:

```dart
  /// Background-isolate network calls race Android's network bring-up
  /// (Redmi: `Failed host lookup` right after process start) — retry with
  /// backoff so a cold-start FCM pre-cache actually lands.
  static Future<T> _retryNetwork<T>(Future<T> Function() op,
      {int tries = 3}) async {
    for (var i = 1;; i++) {
      try {
        return await op();
      } catch (e) {
        if (i >= tries) rethrow;
        debugPrint('[FCM] network retry $i/$tries: $e');
        await Future<void>.delayed(Duration(seconds: 2 * i));
      }
    }
  }
```

Wrap the fetch in `_cacheMessageBackground`: `final r = await _retryNetwork(() => pb.collection('messages').getOne(messageId));`
Wrap the two `pb.collection(...)` calls in `_markDelivered` (the receipt getList + update) with `_retryNetwork`.

- [ ] **Step 3: unread bump goes live-only (fixes fresh-conv badge)**

In `message_repository_impl.dart`:

- SSE message handler (line ~230): `_cacheMsg(r, myId, key ?? const <int>[])` → add `, live: true` (thread the param through `_cacheMsg` → `_cacheMsgInner`).
- `fetchAndCacheSingleMessage` (~line 1037, 1072): its `_cacheMsg(...)` calls get `live: true` (FCM-foreground arrivals are live).
- `_fetchAndCacheMessages` batch path: stays `live: false` (backfill must NOT spam unread counts).
- `_bumpConversationForIncoming` guard replacement:

```dart
      // Unread: only LIVE arrivals bump the badge (SSE/FCM-foreground).
      // Backfill and reconciliation must not — a fresh conversation
      // (never opened, lastReadLocalId null) previously NEVER badged;
      // live-gating fixes that without letting a 40-row backfill +40.
      if (localType != 'system' && live) {
        await db.conversationsDao.bumpUnread(
            convId, existingLocalId ?? _uuid.v4());
      }
```

- [ ] **Step 4: analyze + tests**

Run: `flutter analyze` → 0 errors. Run: `flutter test` → all PASS.

---

### Task 6: Jump-to-message — one path, load-around-target

**Files:**
- Modify: `lib/features/chat/screens/chat_screen.dart:269-320` (`_scrollToMessage` → `_jumpToMessage`, async) + call sites at lines ~385, ~456, ~609 (wrap in `unawaited(...)`)

**Interfaces:**
- Consumes: repo `fetchAndCacheSingleMessage(String messageId, String conversationId)` (exists).

- [ ] **Step 1: Refactor into find + jump**

Replace `_scrollToMessage` with:

```dart
  int _findFlatIndex(Message msg) {
    for (int i = 0; i < _items.length; i++) {
      final item = _items[i];
      if (item is _MsgItem &&
          (item.msg.localId == msg.localId ||
              (msg.serverId != null && item.msg.serverId == msg.serverId) ||
              item.msg.serverId == msg.localId)) {
        return i;
      }
    }
    return -1;
  }

  void _scrollToFlatIndex(int flatIndex) {
    final item = _items[flatIndex];
    if (item is _MsgItem) {
      final ctx = item.key.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration:  const Duration(milliseconds: 350),
          curve:     Curves.easeInOut,
        );
        return;
      }
    }
    _scrollToItemIndex(flatIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final item2 = _items[flatIndex];
      if (item2 is _MsgItem) {
        final ctx2 = item2.key.currentContext;
        if (ctx2 != null) {
          Scrollable.ensureVisible(
            ctx2,
            alignment: 0.5,
            duration:  const Duration(milliseconds: 200),
            curve:     Curves.easeInOut,
          );
        }
      }
    });
  }

  /// Unified jump for search/star/reply/pin. If the target is not in the
  /// loaded window, fetch it from the server, wait for the stream to emit
  /// it, then scroll precisely. Never bails silently (B3).
  Future<void> _jumpToMessage(Message msg) async {
    var flatIndex = _findFlatIndex(msg);
    if (flatIndex < 0 && msg.serverId != null) {
      try {
        await ref.read(messageRepositoryProvider)
            .fetchAndCacheSingleMessage(msg.serverId!, _cid);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Message unavailable: $e')));
        }
        return;
      }
      for (var i = 0; i < 20 && flatIndex < 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (!mounted) return;
        flatIndex = _findFlatIndex(msg);
      }
    }
    if (flatIndex < 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message not found in this chat')));
      }
      return;
    }
    _scrollToFlatIndex(flatIndex);
  }
```

Update the three call sites to `unawaited(_jumpToMessage(msg))` (add `import 'dart:async';` if absent — `unawaited` needs it or `dart:async` show).

- [ ] **Step 2: analyze + tests**

Run: `flutter analyze` → 0 errors. Run: `flutter test` → all PASS.

---

### Task 7: Ship — gate, build, install, capture-compare, user pass, commit

**Files:** none (verification + single commit)

- [ ] **Step 1: Full gate**

`flutter analyze` → 0 errors. `flutter test` → all PASS.
`flutter build apk --debug --target-platform android-arm64` → `✓ Built`
`unzip -l build/app/outputs/flutter-apk/app-debug.apk | grep arm64-v8a/libflutter` → exactly one hit.

- [ ] **Step 2: Install + launch both devices**

`adb -s RFCRA047WSJ install -r build/app/outputs/flutter-apk/app-debug.apk` → Success
`adb -s c7e9f10e install -r build/app/outputs/flutter-apk/app-debug.apk` → Success
Launch both (`monkey -p com.chai.kuch_bhi -c android.intent.category.LAUNCHER 1`), `pidof` alive, crash buffer empty.

- [ ] **Step 3: Capture-compare (same protocol as the baseline)**

Start the same two logcat captures, user navigates for ~10 minutes (open chats, send messages, browse home, jump via search/star), then compare vs baseline:
- SSE rebuilds (`Unsubscribed from all` lines): baseline 54/25min → target ≤2 (navigation must produce ZERO).
- Fetch→first-EMIT on warm chat open: baseline 6s → target <1s.
- Stream emits: baseline 1057 → expect roughly one emit per real write.
- Defunct exceptions: baseline present → target zero.
- Redmi FCM cold-open: message visible ≤5s after open (bg pre-cache retry works).

- [ ] **Step 4: User pass list (2 devices)**

1. Open a warm chat → messages instantly, new messages appear live.
2. Send → bubble paints immediately, no dup, no 🔒 flash.
3. Home list updates live while sitting on it (badge + preview + reorder).
4. FCM while app closed → open → badge correct, message there ≤5s.
5. Search/star jump lands ON the message 10/10, old + new.
6. Logout → login as other account → zero previous data.
7. Login back as original → own history intact (cursor didn't skip).

- [ ] **Step 5: Commit (after user PASS)**

```bash
git add lib test docs
git commit -m "[Reliability] W1 spine — identity-gated realtime, cursor sync, unique serverId, watch storm + logout wipe

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

Exclude junk untracked files as before.
