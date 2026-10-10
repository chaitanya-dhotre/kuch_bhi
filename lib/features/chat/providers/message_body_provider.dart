import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/decrypt/body_cache.dart';
import '../../../core/decrypt/decrypt_pass.dart';
import '../../../data/local/database/app_database.dart';
import '../../../infrastructure/repositories/message_repository_impl.dart';

/// DecryptPass owned by the repository (T5/T6 ctor pattern) so its epoch
/// seam reads the repo's LIVE `_sessionEpoch` (bumped on logout/account
/// switch — the spec §11 gate matches MediaBlobStore/IngestBoundary).
///
/// The explicit `Provider<DecryptPass>` annotation is LOAD-BEARING: this
/// provider closes a reference loop (`… → messageBodyProvider →
/// bodyCoalescerProvider → …`), and un-annotated top-level inference
/// rejects that cycle ("circularity found during type inference").
final Provider<DecryptPass> decryptPassProvider = Provider<DecryptPass>((ref) {
  // T9 carry-in: arm the drain-stamp → invalidation bridge HERE (not in
  // messageBodyProvider): every null-resolving body read funnels through
  // the coalescer's `ref.read(decryptPassProvider)`, so a provider that
  // could ever be sitting on a placeholder has this wire set — while test
  // containers that OVERRIDE decryptPassProvider (T8 suite) never run
  // this body and never force the repo/provider into their scope.
  ref.read(drainStampWireProvider);
  final pass =
      (ref.read(messageRepositoryProvider) as MessageRepositoryImpl)
          .decryptPass;
  // Spec §8 apply step: after a batch lands bodies, wake providers that
  // already completed (e.g. null while the key was missing) so their
  // watchers re-read from the cache.
  var alive = true;
  ref.onDispose(() => alive = false);
  pass.onApplied = (appliedIds) {
    if (!alive) return;
    for (final id in appliedIds) {
      ref.invalidate(messageBodyProvider(id));
    }
  };
  return pass;
});

/// 50ms coalescing window (spec §19.2 / plan Task 8): per-bubble lazy
/// reads join ONE batch decrypt — fast scroll / post-resume never fires
/// one runFor per row (brief test 1 pins ≤2 invocations for 40 reads).
class BodyCoalescer {
  BodyCoalescer(
    this._runFor, {
    this.window = const Duration(milliseconds: 50),
  });

  final Future<void> Function(List<String> messageIds) _runFor;
  final Duration window;

  final _pending = <String, Completer<String?>>{};
  Timer? _timer;
  bool _disposed = false;

  /// Cache hit → resolves instantly; miss → joins the current window and
  /// resolves once the covering [DecryptPass.runFor] finished (value read
  /// back from [bodyCache] — a dropped/terminal row resolves as null).
  Future<String?> request(String id) {
    final hit = bodyCache.get(id);
    if (hit != null) return Future.value(hit);
    if (_disposed) return Future.value(null);
    final waiter = _pending.putIfAbsent(id, Completer<String?>.new);
    _timer ??= Timer(window, _flush);
    return waiter.future;
  }

  void _flush() {
    _timer = null;
    if (_pending.isEmpty) return;
    final batch = Map<String, Completer<String?>>.of(_pending);
    _pending.clear();
    unawaited(_runAndWait(batch));
  }

  Future<void> _runAndWait(Map<String, Completer<String?>> batch) async {
    try {
      await _runFor(batch.keys.toList(growable: false));
    } catch (e) {
      // A failed pass must not strand waiters (or the providers awaiting
      // them) — they resolve from the cache (null ⇒ placeholder).
      debugPrint('[Body] DecryptPass.runFor failed: $e');
    }
    for (final e in batch.entries) {
      if (!e.value.isCompleted) e.value.complete(bodyCache.get(e.key));
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    for (final e in _pending.entries) {
      if (!e.value.isCompleted) e.value.complete(bodyCache.get(e.key));
    }
    _pending.clear();
  }
}

/// One coalescer per container — its flush reads [decryptPassProvider] at
/// call time, so test overrides (counting decorator) are picked up.
final bodyCoalescerProvider = Provider<BodyCoalescer>((ref) {
  final coalescer = BodyCoalescer(
    (ids) => ref.read(decryptPassProvider).runFor(ids),
  );
  ref.onDispose(coalescer.dispose);
  return coalescer;
});

/// T9 carry-in bridge: the repo fires [MessageRepositoryImpl.onBodyStamped]
/// after the drain/upload writes REAL ciphertext for a row (the optimistic
/// `__pending__` marker is gone) — watchers of that id re-resolve instead
/// of sitting on a stale null (row streams never invalidate the family).
/// Same shape as `decryptPassProvider`'s `onApplied` wiring: one instance
/// per container, alive-guarded, last-writer-wins (ledgered with T8's).
// Explicit `Provider<void>`: without it top-level inference reports
// "circularity found during type inference" (same trap as T8's
// decryptPassProvider — comment there is load-bearing).
final Provider<void> drainStampWireProvider = Provider<void>((ref) {
  final repo =
      (ref.read(messageRepositoryProvider) as MessageRepositoryImpl);
  var alive = true;
  ref.onDispose(() => alive = false);
  void handler(String messageId) {
    if (alive) ref.invalidate(messageBodyProvider(messageId));
  }

  repo.onBodyStamped = handler;
  ref.onDispose(() {
    if (identical(repo.onBodyStamped, handler)) repo.onBodyStamped = null;
  });
});

/// Newest visible message row for a conversation — the conversation-list
/// preview's POINTER into [messageBodyProvider] (T9: previews render a
/// placeholder until the body emits, spec §8). Media/system cases render a
/// CONSTANT type label at the widget layer and a missing row renders the
/// caller's fallback — P7 (spec §3): nothing preview-shaped is stored.
final conversationLastMessageProvider =
    StreamProvider.autoDispose.family<MessagesTableData?, String>((ref, convId) {
  final db = ref.read(appDatabaseProvider);
  return (db.select(db.messagesTable)
        ..where((t) =>
            t.conversationId.equals(convId) &
            t.isDeletedForEveryone.equals(false) &
            t.isDeletedForMe.equals(false))
        ..orderBy([
          (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
          (t) => OrderingTerm(expression: t.serverId, mode: OrderingMode.desc),
          (t) => OrderingTerm(expression: t.localId, mode: OrderingMode.desc),
        ])
        ..limit(1))
      .watchSingleOrNull();
});

/// THE body read path (spec §5.1): cache hit → text; miss → joins the
/// 50ms coalescing window → one `runFor` → emits (null while
/// key_missing/failed → Task 9 renders the placeholder — never blanks).
///
/// autoDispose: an unmounted bubble drops its resolved value (transient
/// plaintext state); a remount rebuilds through the cache first, then
/// re-decrypts — which is exactly the "cleared cache re-decrypts on next
/// provider read" contract (spec §8).
final messageBodyProvider =
    FutureProvider.autoDispose.family<String?, String>((ref, messageId) async {
  final hit = bodyCache.get(messageId);
  if (hit != null) return hit;
  return ref.read(bodyCoalescerProvider).request(messageId);
});
