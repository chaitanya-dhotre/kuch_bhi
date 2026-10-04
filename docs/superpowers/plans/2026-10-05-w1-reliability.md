# W1 Reliability Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the four structural faults in the sync/send/realtime layer: SSE churn from token refreshes, full-40-row refetch on every chat open, duplicate rows by construction, and the storm/crash from reactive plumbing — plus logout data wipe, Redmi bg-isolate DNS race, unread badge null-guard, and jump-to-message.

**Architecture:** Keep the current layers and files; change the connection lifecycle (identity-gated reconnect), the fetch strategy (per-conversation cursor + batch cache), the DB constraint (UNIQUE serverId, schema v6), and the cleanup of stream plumbing (sync mapping, cached cutoff). No server changes; no new dependencies; no new collections.

**Tech Stack:** Flutter/Riverpod/Drift (client), PocketBase 0.37.5 (server, untouched).

**Spec:** `docs/superpowers/specs/2026-10-04-w1-reliability-design.md` — the plan argues from the spec; executors read both.

## Global Constraints

- No commit until the user verifies on 2 devices (standing rule — Task 9 collects the single commit; skip the per-task commit steps during execution).
- Back-reference rules use `?=` on every `@collection` comparison (plain `=` is match-ALL on this PB build) — no rule changes in this plan, constraint is context.
- `flutter analyze` must be 0 errors after every client task; `flutter test` must pass after every task that adds tests.
- Build target is always `--target-platform android-arm64` (the 25 Sep x64-only build crashed both phones); verify `lib/arm64-v8a/libflutter.so` in the APK.
- Server credentials (only if a probe needs them): superuser password file `/home/chaitanyadhotre/Chaitanya/Oracle/pb_superuser_password_NEW.txt`, identity `chaitanyad301@proton.me`. Pipe secrets via files/env, never echo.

## Review Focus

- A push arrives while the app is backgrounded AND the device is offline at wake: bg-isolate retries must not burn battery or drop the message — expect a bounded retry (≤3, backoff) then a silent handoff to the resume sync, covered in Task 6.
- A DM and a group emit at the same SQLite instant while a chat is open: the fixed mapping must not attribute one conversation's rows to the other — expect per-conversation row routing to stay, covered in Task 4.
- A user logs out mid-upload (pending `_uploadMessage` in flight): the wipe must not crash the upload future and the upload must not resurrect pre-wipe rows — expect a session-generation guard, covered in Task 7.
- A conversation has ZERO messages and the user opens it twice in a row: the cursor must distinguish "synced empty" from "never synced" — expect a `synced_empty_<convId>` marker, covered in Task 2.
- A jump target is a message that was just deleted-for-everyone: expect a "message no longer available" snackbar, not a silent bail — covered in Task 8.

---

### Task 1: Realtime — identity-gated reconnect + quiet token refresh

**Files:**
- Modify: `lib/infrastructure/repositories/auth_repository_impl.dart` (`getCurrentUser` cached path ~line 238, `_backgroundRefresh` ~line 279)
- Modify: `lib/infrastructure/repositories/message_repository_impl.dart` (authStore listener ~lines 43-55)
- Test: `test/auth_realtime_gating_test.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces: repo-private `String? _lastIdentityKey` + `bool _identityChanged(String? recordId, bool valid)` — concept only; Task-local helper `identityChanged(String? prevKey, String? nextKey)` in `lib/core/utils/auth_identity.dart` so it is unit-testable:
  `String identityKey(String? userId, bool valid)` — returns `'none'` when invalid, else `'user:<id>'`.

- [ ] **Step 1: Write the failing test**

```dart
// test/auth_realtime_gating_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/utils/auth_identity.dart';

void main() {
  test('same user + valid stays the same key', () {
    expect(identityKey('u1', true), identityKey('u1', true));
  });

  test('token refresh for same user produces no identity change', () {
    final before = identityKey('u1', true);
    final after = identityKey('u1', true); // new token, same user
    expect(identityChanged(before, after), isFalse);
  });

  test('login changes identity from none', () {
    expect(identityChanged(identityKey(null, false), identityKey('u1', true)),
        isTrue);
  });

  test('logout changes identity to none', () {
    expect(identityChanged(identityKey('u1', true), identityKey(null, false)),
        isTrue);
  });

  test('account switch changes identity', () {
    expect(identityChanged(identityKey('u1', true), identityKey('u2', true)),
        isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/auth_realtime_gating_test.dart`
Expected: FAIL — `auth_identity.dart` / `identityKey` undefined.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/core/utils/auth_identity.dart
/// Identity key for gating realtime reconnects (spec D1). Reacts to WHO is
/// authenticated, never to token-string churn from authRefresh.
String identityKey(String? userId, bool valid) =>
    valid && userId != null && userId.isNotEmpty ? 'user:$userId' : 'none';

bool identityChanged(String? prevKey, String? nextKey) =>
    prevKey != nextKey;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/auth_realtime_gating_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Gate the reconnect on identity**

In `message_repository_impl.dart`, replace the authStore listener body (the block that currently logs `Auth token changed (logged in)` and calls `_reconnect()` unconditionally). The `PocketBase` `authStore.onChange` event carries `event.record` (the authenticated model, or null). Track the last key in a field:

```dart
  // Identity-gated reconnect (spec D1): authRefresh mints a new token
  // every navigation; reconnecting on every token string shredded SSE.
  // Reconnect only when the authenticated identity itself changes.
  String? _lastIdentityKey;

  // ...inside the constructor, replacing the existing listener:
    // Re-subscribe when the authenticated IDENTITY changes (login/logout/
    // account switch). Token-string churn from authRefresh must not touch
    // the SSE lifecycle.
    _lastIdentityKey = identityKey(
        _pb.authStore.record?.id, _pb.authStore.isValid);
    _pb.authStore.onChange.listen((event) {
      final next = identityKey(event.record?.id, event.token.isNotEmpty);
      if (next == _lastIdentityKey) return; // token refresh — ignore
      _lastIdentityKey = next;
      if (event.token.isNotEmpty) {
        debugPrint('[Msg] Identity changed ($next). Reconnecting subscriptions.');
        _reconnect();
      } else {
        debugPrint('[Msg] Identity cleared. Unsubscribing.');
        _pendingJoinEmitConvIds.clear(); // no join polls for the previous user
        for (final t in _rotateDebounce.values) {
          t.cancel();
        }
        _rotateDebounce.clear(); // no stale auto-rotates for the previous user
        _teardown();
      }
    });
```

Add the import: `import '../../core/utils/auth_identity.dart';`

- [ ] **Step 6: Quiet the background refresh**

In `auth_repository_impl.dart`, the cached path of `getCurrentUser()` calls `_backgroundRefresh()` on every navigation. Replace the unconditional call with an interval gate — add a field `DateTime? _lastRefresh` and a 10-minute window:

```dart
    // Quiet refresh (spec D1): the router calls getCurrentUser on every
    // navigation; each authRefresh minted a new token and (pre-gating)
    // shredded SSE. Refresh at most every 10 minutes outside resume.
    final now = DateTime.now();
    if (_lastRefresh == null ||
        now.difference(_lastRefresh!).inMinutes >= 10) {
      _lastRefresh = now;
      _backgroundRefresh();
    }
```

`resyncOnResume` should force a fresh token regardless of the window — add a public passthrough that resets the gate then refreshes:

```dart
  /// Called from resume flows: bypasses the 10-minute quiet-refresh window.
  void refreshSessionNow() {
    _lastRefresh = DateTime.now();
    _backgroundRefresh();
  }
```

And in `message_repository_impl.dart` `resyncOnResume`, call it before reconnecting. `message_repository_impl.dart` does not currently hold the auth repo — reach it via Riverpod the same way `app.dart` reaches the message repo: add a `refreshSessionNow` call in `lib/app.dart`'s `resumed` branch BEFORE `resyncOnResume()`:

```dart
      case AppLifecycleState.resumed:
        presence.goOnline();
        ref.read(authProvider.notifier).refreshSessionNow();
        ref.read(messageRepositoryProvider).resyncOnResume();
```

This requires `authProvider` to expose `refreshSessionNow` — add a notifier passthrough in `auth_provider.dart` next to `signOut`:

```dart
  /// Resume hook: bypasses the quiet-refresh window (spec D1).
  void refreshSessionNow() => _repo.refreshSessionNow();
```

And `refreshSessionNow` must exist on the auth repository interface (`lib/domain/repositories/auth_repository.dart`) — add `void refreshSessionNow();` there and implement it in `auth_repository_impl.dart` as above. If `authProvider`'s `_repo` type is the interface, the interface addition is mandatory for the passthrough to compile; if it is the impl, it still belongs on the interface per the codebase's layer rules.

- [ ] **Step 7: Run verifications**

Run: `flutter analyze`
Expected: 0 errors.

Run: `flutter test`
Expected: all PASS (including the 5 new tests).

- [ ] **Step 8: Commit**

Skipped — standing rule; Task 9 commits.

---

### Task 2: Incremental sync — per-conversation cursor + batch cache

**Files:**
- Modify: `lib/infrastructure/repositories/message_repository_impl.dart` (`_fetchAndCacheMessages` ~line 2182, `_cacheMsg` + `_cacheMsgInner` ~line 2300)
- Modify: `lib/data/local/database/daos/messages_dao.dart` (batch upsert helper)
- Test: `test/sync_cursor_test.dart`

**Interfaces:**
- Consumes: `decryptBatch(keyBytes, items)` from `encryption_service.dart` — signature `Future<Map<String, String?>> decryptBatch(List<int> keyBytes, List<Map<String, String>> items)` where each item map is `{'id': ..., 'iv': ..., 'ciphertext': ...}` and the result maps `id → plaintext or null`.
- Produces: settings-key convention `sync_cursor_<conversationId>` (ISO-8601 string of max server-`created` cached; absent = never synced; literal `'empty'` = synced and server had nothing). Cursor helpers in `lib/core/utils/sync_cursor.dart`: `String cursorKey(String conversationId)` and `DateTime? cursorFromStored(String? stored)` where `'empty'` and null both yield null but are distinguished by the caller.

- [ ] **Step 1: Write the failing test**

```dart
// test/sync_cursor_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/utils/sync_cursor.dart';

void main() {
  test('cursor key is namespaced per conversation', () {
    expect(cursorKey('abc'), 'sync_cursor_abc');
    expect(cursorKey('abc') == cursorKey('xyz'), isFalse);
  });

  test('absent stored value yields null cursor', () {
    expect(cursorFromStored(null), isNull);
  });

  test('empty marker yields null cursor', () {
    expect(cursorFromStored('empty'), isNull);
  });

  test('stored ISO string parses', () {
    final v = cursorFromStored('2026-10-04T12:00:00.000Z');
    expect(v, isNotNull);
    expect(v!.isUtc, isTrue);
  });

  test('garbage stored value yields null, not a throw', () {
    expect(cursorFromStored('not-a-date'), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/sync_cursor_test.dart`
Expected: FAIL — `sync_cursor.dart` undefined.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/core/utils/sync_cursor.dart
/// Per-conversation sync cursor convention (spec D2). Stored in the Drift
/// settings table under `sync_cursor_<conversationId>`:
/// - absent → never synced (cold fetch, latest-40)
/// - 'empty' → synced once and the server had nothing (skip refetch)
/// - ISO-8601 → max server-created cached; fetch only newer.
String cursorKey(String conversationId) => 'sync_cursor_$conversationId';

DateTime? cursorFromStored(String? stored) {
  if (stored == null || stored == 'empty') return null;
  return DateTime.tryParse(stored);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/sync_cursor_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Batch upsert helper in the messages DAO**

Add after `upsertMessage` in `messages_dao.dart`:

```dart
  /// Batch upsert for the incremental sync path (spec D2): one transaction
  /// for a whole fetch window instead of N serial upserts.
  Future<void> upsertMessagesBatch(
      List<MessagesTableCompanion> rows) async {
    if (rows.isEmpty) return;
    await batch((b) {
      for (final row in rows) {
        b.insert(messagesTable, row,
            onConflict: DoUpdate((_) => row, target: [messagesTable.localId]));
      }
    });
  }
```

NOTE: `messagesTable.localId` is the table's primary key (schema line 50: `Set<Column> get primaryKey => {localId}`), so the conflict target is exact — same semantics as the existing `insertOnConflictUpdate`, one transaction.

- [ ] **Step 6: Cursor-aware fetch + batch cache in the repo**

Replace the body of `_fetchAndCacheMessages` (the fetch-then-loop-`_cacheMsg` section) with a cursor-aware version. Keep the method's existing signature, its opening `_myId()` lookup, and its trailing `_syncDeletedForMe` / `_syncStarredMessages` / `_reconcileReceiptsForConversation` calls unchanged:

```dart
  Future<void> _fetchAndCacheMessages(String conversationId) async {
    try {
      final myId = await _myId();
      debugPrint('[Msg] _fetchAndCacheMessages — myId: $myId, convId: $conversationId');
      final stored = await db.settingsDao
          .getSetting(cursorKey(conversationId));
      final isCold = stored == null;
      // No is_deleted_for_everyone filter: deletions that happened while this
      // device was offline must ALSO sync (cacheMsg flips the local flag).
      final res = await _pb.collection('messages').getList(
        filter: isCold
            ? 'conversation_id="$conversationId"'
            : 'conversation_id="$conversationId"&&created>"${stored == 'empty' ? '' : stored}"',
        sort: '-created',
        perPage: isCold ? 40 : 100,
      );
      debugPrint('[Msg] _fetchAndCacheMessages — fetched ${res.items.length} messages from server (cold: $isCold)');

      // ... existing group-key comment block stays as-is ...
      List<int>? key;
      try {
        key = await _getConvKey(conversationId, myId);
      } on MissingKeyException catch (e) {
        debugPrint('[Msg] key not ready during fetch: $e');
        key = null;
      }
      if (key != null) {
        await _cacheMessagesBatch(res.items, myId, key);
      }
      if (res.items.isEmpty && isCold) {
        await db.settingsDao
            .setSetting(cursorKey(conversationId), 'empty');
      } else if (res.items.isNotEmpty) {
        final maxCreated = res.items
            .map((r) => r.created)
            .reduce((a, b) => a.compareTo(b) > 0 ? a : b);
        await db.settingsDao
            .setSetting(cursorKey(conversationId), maxCreated);
      }

      await _syncDeletedForMe(conversationId);
      await _syncStarredMessages(conversationId);
      // Repair any stuck ticks for my own messages in this conversation.
      await _reconcileReceiptsForConversation(conversationId, myId);
    } catch (e) {
      debugPrint('[Msg] fetch error (offline?): $e');
    }
  }
```

Cursor date format note: PB `RecordModel.created` strings are ISO-8601 UTC (e.g. `2026-10-04T12:00:00.000Z`); embedding one in a `created>"…"` filter is valid PB filter syntax. When `stored == 'empty'` the ternary yields `created>""` which matches everything (the `'empty'` optimization: the fetch runs but the server still has nothing until a message arrives). Add the import `import '../../core/utils/sync_cursor.dart';` to `message_repository_impl.dart`.

- [ ] **Step 7: Implement `_cacheMessagesBatch`**

Add next to `_cacheMsgInner`. It performs the same per-record mapping as `_cacheMsgInner` (decrypt via one `decryptBatch` call, statuses, receipts bumps) but writes through `upsertMessagesBatch` once. The reply-preview decryption stays per-row (it uses the same conv key — include the previews in the same batch call by appending `{'id': '<rid>:reply', ...}` entries; afterwards split them back out). Write it as:

```dart
  /// Batch twin of [_cacheMsgInner] (spec D2): one decryptBatch + one Drift
  /// batch write for a whole fetch window instead of N serial awaits.
  /// Non-message side effects are preserved: delivery ack for others'
  /// rows (via [_markDelivered]), conversation lastMessage bump + unread
  /// bump for the newest eligible row only (same guards as _cacheMsgInner).
  Future<void> _cacheMessagesBatch(
      List<RecordModel> records, String myId, List<int> key) async {
    if (records.isEmpty) return;
    final batchItems = <Map<String, String>>[];
    for (final r in records) {
      final encBody = r.getStringValue('encrypted_body');
      final iv = r.getStringValue('iv');
      if (encBody.isNotEmpty &&
          iv.isNotEmpty &&
          encBody != '__pending__') {
        batchItems.add({'id': r.id, 'iv': iv, 'ciphertext': encBody});
      }
      final rawReply = r.getStringValue('reply_preview');
      final idx = rawReply.indexOf(':');
      if (rawReply.isNotEmpty && idx > 0 && encBody != '__pending__') {
        batchItems.add({
          'id': '${r.id}:reply',
          'iv': rawReply.substring(0, idx),
          'ciphertext': rawReply.substring(idx + 1),
        });
      }
    }
    final clear = await encryption.decryptBatch(key, batchItems);

    final companions = <MessagesTableCompanion>[];
    String? newestConvId;
    var newestCreated = DateTime.fromMillisecondsSinceEpoch(0);
    for (final r in records) {
      final existing =
          await db.messagesDao.getMessageByServerId(r.id);
      final isMine = r.getStringValue('sender_id') == myId;
      final existingStatus = existing?.status ?? '';
      String status;
      if (isMine) {
        status = existingStatus.isNotEmpty
            ? existingStatus
            : await _computeSenderStatus(r.id);
      } else {
        status = 'delivered';
      }
      final decrypted = clear[r.id] ?? existing?.decryptedBody;
      final rawReply = r.getStringValue('reply_preview');
      final replyPreview = rawReply.isEmpty
          ? existing?.replyPreview
          : (clear['${r.id}:reply'] ??
              (rawReply.contains(':') ? '🔒' : rawReply));
      final rawMediaId = r.getStringValue('media_id');
      final rawType = r.getStringValue('type');
      final localType = rawType == 'file' ? 'document' : rawType;
      final convId = r.getStringValue('conversation_id');
      final createdAt = DateTime.tryParse(r.created) ?? DateTime.now();
      final expiresAt = await _computeExpiry(convId, createdAt);
      companions.add(MessagesTableCompanion.insert(
        localId:               existing?.localId ?? _uuid.v4(),
        serverId:              Value(r.id),
        conversationId:        convId,
        senderId:              r.getStringValue('sender_id'),
        type:                  localType,
        encryptedBody:         r.getStringValue('encrypted_body'),
        iv:                    r.getStringValue('iv'),
        decryptedBody:         Value(decrypted),
        replyToId:             Value(r.getStringValue('reply_to_id').isEmpty
            ? null
            : r.getStringValue('reply_to_id')),
        replyPreview:          Value(replyPreview),
        isPinned:              Value(r.getBoolValue('is_pinned')),
        isStarred:             Value(existing?.isStarred ?? false),
        isDeletedForMe:        Value(existing?.isDeletedForMe ?? false),
        isDeletedForEveryone:  Value(r.getBoolValue('is_deleted_for_everyone')),
        mediaId:               Value(rawMediaId.isEmpty ? null : rawMediaId),
        status:                Value(status),
        expiresAt:             Value(expiresAt),
        createdAt:             createdAt,
        updatedAt:             DateTime.now(),
      ));
      if (!isMine &&
          !r.getBoolValue('is_deleted_for_everyone') &&
          createdAt.isAfter(newestCreated)) {
        newestCreated = createdAt;
        newestConvId = convId;
      }
      if (!isMine && r.getStringValue('type') != 'system') {
        await _markDelivered(r.id, convId, myId);
      }
    }
    await db.messagesDao.upsertMessagesBatch(companions);

    // Single conversation-list bump for the newest eligible row (same
    // guards as _cacheMsgInner: preview, unread badge, system excluded).
    if (newestConvId != null) {
      try {
        final conv =
            await db.conversationsDao.getConversationById(newestConvId!);
        final currentLast = conv?.lastMessageAt;
        if (currentLast == null || newestCreated.isAfter(currentLast)) {
          final newest = records
              .where((r) =>
                  (DateTime.tryParse(r.created) ?? DateTime.now())
                      .isAtSameMomentAs(newestCreated))
              .firstOrNull;
          final newestType = newest?.getStringValue('type') == 'file'
              ? 'document'
              : (newest?.getStringValue('type') ?? 'text');
          final newestDecrypted = newest != null ? clear[newest.id] : null;
          final preview = switch (newestType) {
            'image'    => '📷 Photo',
            'video'    => '🎬 Video',
            'voice'    => '🎤 Voice message',
            'document' => '📎 Document',
            _          => newestDecrypted ?? 'New message',
          };
          await db.conversationsDao
              .updateLastMessage(newestConvId!, preview, newestCreated);
          if (newestType != 'system' &&
              conv?.lastReadLocalId != null &&
              conv!.lastReadLocalId!.isNotEmpty) {
            await db.conversationsDao
                .bumpUnread(newestConvId!, _uuid.v4());
          }
        }
      } catch (e) {
        debugPrint('[Conv] recipient lastMessage bump: $e');
      }
    }
  }
```

Keep `_cacheMsg`, `_cacheMsgInner`, and `_cacheInFlight` untouched — the single-record paths (SSE subscription, `fetchAndCacheSingleMessage`, `loadMoreMessages`) continue to use them.

- [ ] **Step 8: Run verifications**

Run: `flutter analyze`
Expected: 0 errors.

Run: `flutter test`
Expected: all PASS (including the 5 new tests).

Behavior check (logcat, no device needed beyond a normal open): open any chat, confirm a single `_fetchAndCacheMessages — fetched N messages from server (cold: false)` line on warm opens and that `sync_cursor_<convId>` rows appear in settings (via `adb shell run-as com.chai.kuch_bhi` only if rooted/debug — otherwise trust the fetch line + no crash).

- [ ] **Step 9: Commit**

Skipped — standing rule; Task 9 commits.

---

### Task 3: Throwaway-proof writes — UNIQUE serverId, drop the bandaid

**Files:**
- Modify: `lib/data/local/database/tables/messages_table.dart` (document the index; actual index is created in migration)
- Modify: `lib/data/local/database/app_database.dart` (schemaVersion 5→6, `onUpgrade` `from < 6` creates the partial unique index)
- Modify: `lib/infrastructure/repositories/message_repository_impl.dart` (remove `dedupByServerId` call sites: `watchMessages` ~line 493 and `resyncOnResume` ~line 2159; simplify `getMessageByServerId` tolerant comment — keep the method, it is still used by receipt paths)
- Modify: `lib/data/local/database/daos/messages_dao.dart` (delete `dedupByServerId`)
- Test: extend `test/conversations_dao_test.dart`? No — new file `test/messages_serverid_unique_test.dart` using an in-memory AppDatabase

**Interfaces:**
- Consumes: `upsertMessagesBatch` from Task 2 (conflict-target on `localId` stays valid; serverId uniqueness is enforced by the index, so the batch write can only ever touch one row per serverId).
- Produces: schema v6 with `idx_messages_server_id` partial UNIQUE index (`serverId IS NOT NULL`).

- [ ] **Step 1: Write the failing test**

```dart
// test/messages_serverid_unique_test.dart
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';

AppDatabase _openInMemory() =>
    AppDatabase.forTesting(NativeDatabase.memory());

MessagesTableCompanion _row(String localId, String? serverId) =>
    MessagesTableCompanion.insert(
      localId:        localId,
      serverId:       Value(serverId),
      conversationId: 'c1',
      senderId:       'u1',
      type:           'text',
      encryptedBody:  'ct',
      iv:             'iv',
      createdAt:      DateTime.now(),
      updatedAt:      DateTime.now(),
    );

void main() {
  test('two different localIds can share a null serverId (pending rows)', () async {
    final db = _openInMemory();
    await db.messagesDao.upsertMessage(_row('l1', null));
    await db.messagesDao.upsertMessage(_row('l2', null));
    final rows = await db.messagesDao
        .watchMessages('c1').first;
    expect(rows.length, 2);
    await db.close();
  });

  test('inserting a second row with the same non-null serverId fails', () async {
    final db = _openInMemory();
    await db.messagesDao.upsertMessage(_row('l1', 's1'));
    // Different localId (so no primary-key conflict) + same serverId →
    // the partial UNIQUE index must reject it.
    expect(
      () => db.messagesDao.upsertMessage(_row('l2', 's1')),
      throwsA(anything),
    );
    await db.close();
  });
}
```

Notes for the implementer: `AppDatabase.forTesting` must exist — if it does not, add a testing constructor to `app_database.dart`:

```dart
  /// Testing constructor — in-memory database, runs migrations like prod.
  AppDatabase.forTesting(QueryExecutor e) : super(e);
```

`db.messagesDao` and `db.messagesTable` are the existing accessors. The existing `test/conversations_dao_test.dart` shows the established pattern for opening a test DB — mirror its imports and setup, including `TestWidgetsFlutterBinding.ensureInitialized()` if that file has it (Drift native needs the binding for background isolates; if the existing test works without it, this one works without it).

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/messages_serverid_unique_test.dart`
Expected: FAIL — second test passes today (no unique index → insert succeeds); first test passes. The task is RED only in the sense that the index does not exist yet — to make the failure crisp, temporarily invert: the real gate is Step 4, where the second insert must throw. If both pass at Step 2, that IS the expected failing state (index absent). Proceed.

- [ ] **Step 3: Add the schema migration**

In `app_database.dart`: bump `schemaVersion` to 6 and add to `onUpgrade`:

```dart
          if (from < 6) {
            await m.createIndex(Index(
              'idx_messages_server_id',
              'CREATE UNIQUE INDEX idx_messages_server_id ON messages_table (server_id) WHERE server_id IS NOT NULL',
            ));
          }
```

Verify the actual table name by checking the `@DataClassName` / table class in `messages_table.dart` — the generated table getter in the database is `messagesTable`; the raw SQL table name is the snake_case of the table class name. If `MessagesTable` generates `messages_table`, the statement above is exact. If the project uses a custom `@Table(name: ...)` (check the file), substitute that name.

- [ ] **Step 4: Run test to verify the index works**

Run: `flutter test test/messages_serverid_unique_test.dart`
Expected: PASS — second insert now throws (unique violation).

- [ ] **Step 5: Remove the bandaid**

In `messages_dao.dart`, delete the entire `dedupByServerId` method (lines ~79-111) and its doc comment.

In `message_repository_impl.dart`:
- In `watchMessages`, delete the two lines `// Collapse any duplicate rows…` + `db.messagesDao.dedupByServerId();`.
- In `resyncOnResume`, delete the line `await db.messagesDao.dedupByServerId();` (+ its comment if the comment only covers that line).
- In `getMessageByServerId`'s DAO method, simplify to single-row lookup (keep the tolerant fallback harmless — simplest: leave the method body as-is; duplicates are now impossible by construction. Do NOT touch it — YAGNI).

- [ ] **Step 6: Run verifications**

Run: `flutter analyze`
Expected: 0 errors (no dangling references to `dedupByServerId`).

Run: `flutter test`
Expected: all PASS.

- [ ] **Step 7: Commit**

Skipped — standing rule; Task 9 commits.

---

### Task 4: Storm + crash — sync mapping, cached cutoff

**Files:**
- Modify: `lib/infrastructure/repositories/message_repository_impl.dart` (`watchConversations` ~line 455, `_rowsToMessages` ~line 518, `_messagesStream` ~line 498)
- Test: none new (covered by existing + Task 2/3 tests; verify by logcat)

**Interfaces:**
- Consumes: `watchAllConversations()` DAO stream (unchanged); `isGroupRowVisible` + `joinedAt` logic from the W2 rework (unchanged semantics).
- Produces: per-conversation cached join cutoff `Map<String, DateTime?> _joinCutoffCache`, invalidated by `_invalidateJoinCutoff(conversationId)` called from every member-write site.

- [ ] **Step 1: Replace the asyncMap in `watchConversations`**

Current code:

```dart
  @override
  Stream<List<Conversation>> watchConversations() {
    _syncConversationsBackground(); // Fire-and-forget

    return db.conversationsDao
        .watchAllConversations()
        .asyncMap((rows) => _convRowsToEntities(rows));
  }
```

Replace with a synchronous map. `_convRowsToEntities` is async only because it awaits per-row lookups — check its body first: if it awaits DB reads per row, hoist those reads OUT of the stream (read once per subscription, then map synchronously, and re-read only when the membership stream fires — the membership subscription already calls `_syncConversationsBackground`, which re-emits through the same Drift watch). Minimal correct change:

```dart
  @override
  Stream<List<Conversation>> watchConversations() {
    _syncConversationsBackground(); // Fire-and-forget

    return db.conversationsDao.watchAllConversations().map(_convRowsToEntitiesSync);
  }
```

Implement `_convRowsToEntitiesSync(List<ConversationRowType> rows)` next to `_convRowsToEntities`, where `ConversationRowType` is whatever `watchAllConversations()` emits (check the DAO return type — likely `List<ConversationsTableData>`). The sync version must produce the identical `Conversation` entity shape WITHOUT awaits: peer display name/avatar and member counts come from in-memory caches populated by `_syncConversations` (add `Map<String, User> _userCache` + `Map<String, int> _memberCountCache` fields, filled in `_syncConversations` where `_cacheUserRecord` already runs). If any field cannot be served from cache, fall back to the previously emitted value for that conversation (keep a `Map<String, Conversation> _lastConvById`, updated on every emit, consulted on cache miss). This preserves today's rendered output exactly while removing the async gap that crashed defunct elements.

Exact cache-fill code goes inside `_syncConversations` where members/users are already in hand — the implementer adds two map writes next to the existing `upsertMember`/`_cacheUserRecord` calls; no new queries.

- [ ] **Step 2: Cache the join cutoff**

Add fields:

```dart
  /// Join-time cutoffs per conversation (spec D4): avoids 2 DAO queries on
  /// every watch emit. Invalidated on any member write.
  final Map<String, DateTime?> _joinCutoffCache = {};
```

Add:

```dart
  void _invalidateJoinCutoff(String conversationId) =>
      _joinCutoffCache.remove(conversationId);
```

Call `_invalidateJoinCutoff(convId)` at every member-write site in this file: the three member-sync upsert blocks (the W2 `joinedAt` sites), `promoteMemberToAdmin`/`demoteAdminToMember` role writes, `leaveGroup`/`removeMemberFromGroup` local writes, and `removeStaleMemberRows` call sites (two, from the W2 rejoin fix).

In `_rowsToMessages`, replace the per-emit `getConversationById` + `getAllMembersForConversation` pair with:

```dart
    DateTime? joinedAt;
    final conv = await db.conversationsDao.getConversationById(convId);
    if (conv?.type == 'group') {
      if (_joinCutoffCache.containsKey(convId)) {
        joinedAt = _joinCutoffCache[convId];
      } else {
        final members = await db.conversationsDao
            .getAllMembersForConversation(convId);
        joinedAt =
            members.where((m) => m.userId == myId).firstOrNull?.joinedAt;
        _joinCutoffCache[convId] = joinedAt;
      }
    }
```

(`getConversationById` stays per emit — it is a single indexed row read and the type gate needs it; the expensive member-list read is the cached one.)

- [ ] **Step 3: Run verifications**

Run: `flutter analyze`
Expected: 0 errors.

Run: `flutter test`
Expected: all PASS.

Logcat check (normal chat open on a device): multi-conversation re-emit bursts are gone — opening chat A while subscribed to A+B must not re-emit B's stream; no `_lifecycleState != _ElementLifecycle.defunct` exceptions in a 5-minute session with navigation.

- [ ] **Step 4: Commit**

Skipped — standing rule; Task 9 commits.

---

### Task 5: Unread badge null-guard

**Files:**
- Modify: `lib/infrastructure/repositories/message_repository_impl.dart` (`_cacheMsgInner` recipient bump + the `_cacheMessagesBatch` bump from Task 2)
- Test: none new (behavior verified by user check in Task 9; the bump helpers are thin wrappers over the existing DAO `bumpUnread`, already covered)

**Interfaces:**
- Consumes: Task 2's bump block shape.
- Produces: identical shape with the null-guard removed.

- [ ] **Step 1: Remove the null-guard in `_cacheMsgInner`**

Current guard (in the recipient lastMessage bump):

```dart
          if (localType != 'system' &&
              conv?.lastReadLocalId != null &&
              conv!.lastReadLocalId!.isNotEmpty) {
            await db.conversationsDao.bumpUnread(
                convId, existing?.localId ?? _uuid.v4());
          }
```

Replace with:

```dart
          if (localType != 'system') {
            await db.conversationsDao.bumpUnread(
                convId, existing?.localId ?? _uuid.v4());
          }
```

Check `bumpUnread(convId, localId)` semantics in the DAO first: it must increment `unreadCount` and set `lastMessageAt`-adjacent state regardless of the previous `lastReadLocalId` (fresh convs have null). If `bumpUnread` itself early-returns on null `lastReadLocalId`, remove that early-return instead of (or in addition to) this change — read the DAO method before editing.

- [ ] **Step 2: Mirror the change in `_cacheMessagesBatch` (Task 2's bump)**

Same guard shape exists there:

```dart
          if (newestType != 'system' &&
              conv?.lastReadLocalId != null &&
              conv!.lastReadLocalId!.isNotEmpty) {
```

Replace with:

```dart
          if (newestType != 'system') {
```

- [ ] **Step 3: Run verifications**

Run: `flutter analyze`
Expected: 0 errors.

Run: `flutter test`
Expected: all PASS.

User check moves to Task 9 (fresh conversation badges from the first message).

- [ ] **Step 4: Commit**

Skipped — standing rule; Task 9 commits.

---

### Task 6: bg-isolate network retry (Redmi DNS race)

**Files:**
- Modify: `lib/services/fcm_service.dart` (`_cacheMessageBackground` ~line 448, `_markDelivered` ~line 491)
- Test: none new (isolate + network; verified by user check + logcat in Task 9)

**Interfaces:**
- Consumes: `connectivity_plus` (already a dependency — the repo imports it in `message_repository_impl.dart`; add the import to `fcm_service.dart`).
- Produces: private `Future<T?> _withBgRetry<T>(Future<T> Function() op, String label)` in `fcm_service.dart`.

- [ ] **Step 1: Add the bounded retry helper**

At the top of `FcmService` (near `_ensureNotifications`):

```dart
  /// Bounded retry for background-isolate network calls (spec D5): the
  /// Redmi bg isolate races network init (`Failed host lookup`) and the
  /// current code fails permanently on the first attempt. Waits for
  /// connectivity, retries at most 3 times with backoff, then hands off to
  /// the resume sync (returns null) instead of dropping the message.
  static Future<T?> _withBgRetry<T>(
      Future<T> Function() op, String label) async {
    var delay = const Duration(seconds: 2);
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        return await op();
      } catch (e) {
        debugPrint('[FCM] bg $label attempt $attempt/3 failed: $e');
        if (attempt == 3) return null;
        await Future<void>.delayed(delay);
        delay *= 2;
      }
    }
    return null; // unreachable, satisfies the analyzer
  }
```

- [ ] **Step 2: Wrap the two network calls**

In `_cacheMessageBackground`, wrap the `pb.collection('messages').getOne(messageId)` call:

```dart
      final r = await _withBgRetry(
        () => pb.collection('messages').getOne(messageId),
        'cache $messageId',
      );
      if (r == null) {
        // Resume sync backfills it (spec D5) — never leave a half-row.
        if (_db == null) await localDb.close();
        return;
      }
```

The code after the fetch uses `r` directly — no other change needed since `r` is now non-null after the guard.

In `_markDelivered`, apply the same wrap to its server write (read the method body first — it creates/updates a receipt row server-side; wrap that single PB call identically, label `'deliver $messageId'`, and on null return early without throwing).

- [ ] **Step 3: Run verifications**

Run: `flutter analyze`
Expected: 0 errors.

Run: `flutter test`
Expected: all PASS.

Logcat/user check moves to Task 9 (Redmi cold-open-after-FCM shows the message within 5s; `[FCM] bg cache … attempt 1/3 failed` lines may appear transiently but must be followed by success or a resume-sync backfill — never a permanent miss).

- [ ] **Step 4: Commit**

Skipped — standing rule; Task 9 commits.

---

### Task 7: Logout wipe + session generation guard

**Files:**
- Modify: `lib/infrastructure/repositories/auth_repository_impl.dart` (`signOut` ~line 307)
- Modify: `lib/infrastructure/repositories/message_repository_impl.dart` (`sendMessage`/`_uploadMessage` + `sendMediaMessage`/`_uploadMediaMessage` guards)
- Test: none new (verified by user check in Task 9; DB wipe is destructive and isolate-hostile in unit tests)

**Interfaces:**
- Consumes: existing `db` (AppDatabase), `storage` (SecureStorageService with `clearAll()`), `_pb` client.
- Produces: repo field `int _sessionGeneration = 0` + `void _bumpSession()`.

- [ ] **Step 1: Full wipe in `signOut`**

Replace the body of `signOut()` in `auth_repository_impl.dart`:

```dart
  Future<void> signOut() async {
    await _fcmTokenSubscription?.cancel();
    _fcmTokenSubscription = null;
    pbClient.clearAuth();
    // Full local wipe (spec D5): token-only clearing leaked the previous
    // account's messages into the next login. Order matters — clear auth
    // first so in-flight repo work fails closed, then wipe stores.
    await storage.clearAll();
    await db.settingsDao.setSetting(AppSettingsKeys.authToken, '');
    await db.settingsDao.setSetting(AppSettingsKeys.currentUserId, '');
    try {
      await db.close();
      // Re-create a fresh database file on next access: delete the file.
      // AppDatabase lazily opens via _openConnection, so closing + deleting
      // is enough; the provider keeps working.
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'kuch_bhi.sqlite'));
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('[Auth] DB wipe failed: $e');
    }
  }
```

Required imports in `auth_repository_impl.dart`: `dart:io` (`File`), `package:path/path.dart` as `p`, `path_provider` (`getApplicationDocumentsDirectory`). Check which of these the file already imports — add only the missing ones. The DB filename `kuch_bhi.sqlite` and directory (`getApplicationDocumentsDirectory`) are copied verbatim from `_openConnection` in `app_database.dart` (verified above) — keep them in sync by referencing that function in a comment.

Note on WAL files: `NativeDatabase.createInBackground` uses SQLite WAL mode, which keeps `-wal`/`-shm` sidecars. Deleting only the main file leaves stale sidecars that SQLite will happily replay on next open — delete all three (`kuch_bhi.sqlite`, `kuch_bhi.sqlite-wal`, `kuch_bhi.sqlite-shm`) in the same try block.

- [ ] **Step 2: Session-generation guard in the message repo**

Add to `message_repository_impl.dart`:

```dart
  /// Session generation (spec D5, Review Focus): incremented on logout so
  /// in-flight uploads from the previous account fail closed instead of
  /// writing pre-wipe rows into the fresh database.
  int _sessionGeneration = 0;
```

Expose `void bumpSessionGeneration() { _sessionGeneration++; }` on the message repo (add to the domain interface `message_repository.dart` too), and call it from `auth_repository_impl.signOut()` — the auth repo does not hold the message repo; route the call the same way `app.dart` reaches providers: in the sign-out UI path (`profile_screen.dart` line 34 calls `ref.read(authProvider.notifier).signOut()`), the `authProvider.signOut` implementation calls `_repo.signOut()` — add the message-repo bump inside `authProvider.signOut` AFTER `_repo.signOut()`:

```dart
  Future<void> signOut() async {
    await _repo.signOut();
    try {
      ref.read(messageRepositoryProvider).bumpSessionGeneration();
    } catch (_) {}
  }
```

Check `auth_provider.dart` for the `ref` availability inside the notifier (it is a Riverpod notifier — `ref` is available) and the exact current `signOut` body (line ~156 calls `_repo.signOut()` only) before editing.

Guard the four upload entry points: at the top of `_uploadMessage` and `_uploadMediaMessage`, capture `final gen = _sessionGeneration;` and after EVERY `await` that precedes a DB write, add `if (gen != _sessionGeneration) return;`. The implementer places one guard after the encryption block and one right before the final upsert in each method (minimum two guards per method) — writes never land under a bumped generation.

- [ ] **Step 3: Run verifications**

Run: `flutter analyze`
Expected: 0 errors.

Run: `flutter test`
Expected: all PASS.

Destructive path — user check moves to Task 9 (logout → login-as-other shows zero old data; logout-mid-send does not crash and sends nothing).

- [ ] **Step 4: Commit**

Skipped — standing rule; Task 9 commits.

---

### Task 8: Jump-to-message that lands

**Files:**
- Modify: `lib/features/chat/screens/chat_screen.dart` (`_scrollToMessage` ~line 269, `_scrollToItemIndex`, callers at ~385/456/609)
- Modify: `lib/infrastructure/repositories/message_repository_impl.dart` (reuse existing `fetchAndCacheSingleMessage(messageId, conversationId)` — signature verified above; no repo change needed unless the target row needs a server round-trip the method does not cover — read it first)
- Test: none new (verified by user check in Task 9: 10/10 jumps)

**Interfaces:**
- Consumes: `fetchAndCacheSingleMessage` (existing).
- Produces: `Future<void> _scrollToMessage(Message msg)` with ensure-then-scroll semantics (same signature, new behavior).

- [ ] **Step 1: Rewrite `_scrollToMessage`**

Replace the method body (keep the signature and the localId/serverId matching loop). New behavior:

```dart
  Future<void> _scrollToMessage(Message msg) async {
    // 1. Ensure the row exists locally (search/star/reply targets may be
    //    outside the loaded window or pruned).
    var flatIndex = _indexOfMessage(msg);
    if (flatIndex < 0) {
      final serverId = msg.serverId ?? msg.localId;
      try {
        await ref.read(messageRepositoryProvider).fetchAndCacheSingleMessage(
              serverId,
              _cid,
            );
        // Rebuild items so the new row is addressable.
        if (mounted) setState(() {});
        flatIndex = _indexOfMessage(msg);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not load message: $e')),
          );
        }
        return;
      }
      if (flatIndex < 0) {
        // Deleted-for-everyone (Review Focus): the server row is gone.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('That message is no longer available.')),
          );
        }
        return;
      }
    }

    // 2. Precise scroll (existing fast/slow path, unchanged).
    ... keep the current ensureVisible fast path + proportional slow path verbatim ...
  }
```

Extract the existing matching loop into `int _indexOfMessage(Message msg)` returning the flat index or -1 (move the loop code verbatim). `_cid` is the screen's conversation id in scope (used at line ~340 for providers). `ref` is available (ConsumerState). Add `import '../../../infrastructure/repositories/message_repository_impl.dart';` if the file does not already import it (check for `messageRepositoryProvider`). No silent bail remains: every failure surfaces a snackbar reason.

- [ ] **Step 2: Run verifications**

Run: `flutter analyze`
Expected: 0 errors.

Run: `flutter test`
Expected: all PASS.

User check moves to Task 9 (10/10 jumps land: search for an old message, star-jump, reply-tap, pin-tap).

- [ ] **Step 3: Commit**

Skipped — standing rule; Task 9 commits.

---

### Task 9: Ship — build, install, user 2-device pass, commit

**Files:** none (verification + commit)

- [ ] **Step 1: Full gate**

Run: `flutter analyze` → 0 errors.
Run: `flutter test` → all PASS.
Run: `flutter build apk --debug --target-platform android-arm64` → `✓ Built`.
Verify: `unzip -l build/app/outputs/flutter-apk/app-debug.apk | grep libflutter` shows `lib/arm64-v8a/libflutter.so`.

- [ ] **Step 2: Install both devices**

`adb -s RFCRA047WSJ install -r build/app/outputs/flutter-apk/app-debug.apk` → Success.
`adb -s c7e9f10e install -r build/app/outputs/flutter-apk/app-debug.apk` → Success.
(Redmi drops off USB occasionally — re-check `adb devices`, ask the user to replug if gone.)
Launch both via monkey, confirm process alive + crash buffer empty.

- [ ] **Step 3: Logcat pass criteria (capture during the user test)**

1. 10-min session with navigation: ≤2 `Realtime subscriptions established` lines.
2. Warm chat open: `_fetchAndCacheMessages — fetched N … (cold: false)` with N small, first EMIT <1s after fetch.
3. No `defunct` exceptions; no multi-conv re-emit bursts per single write.
4. No duplicate bubbles for sends during FCM-echo windows.

- [ ] **Step 4: User 2-device pass criteria**

1. Home list updates live on incoming messages (badge + preview) without reopening.
2. Cold-open-after-FCM on Redmi: message visible within 5s of opening the app.
3. Fresh conversation badges from the first message.
4. 10/10 jump-to-message landings (search old message, star-jump, reply-tap, pin-tap).
5. Logout on one phone → login as other account → zero old data visible.
6. Regression sweep of the W2 invite flow (invite/accept/decline/re-invite still work — Tasks 1–8 touched shared plumbing).

- [ ] **Step 5: Commit (only after user PASS)**

```bash
git add -A lib test docs
git commit -m "[Reliability] W1 fix-the-spine — identity-gated SSE, incremental sync, unique serverId, wipe-on-logout

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

Exclude junk files (session transcripts, current_task*.md, stray .txt files in repo root — keep them untracked).
