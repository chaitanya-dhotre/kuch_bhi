import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/decrypt/body_cache.dart';
import '../../../core/decrypt/decrypt_pass.dart';
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
