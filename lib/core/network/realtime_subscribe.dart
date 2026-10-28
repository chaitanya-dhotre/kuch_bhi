import 'dart:async';

import 'package:pocketbase/pocketbase.dart' show PocketBase;

/// How long a realtime subscribe may take before the caller gives up on it.
///
/// PocketBase's SSE client retries INDEFINITELY (`maxRetry =
/// double.infinity`), so `await collection.subscribe(...)` never completes
/// when the device has no network — a screen that awaits it hangs on its
/// skeleton forever instead of rendering cached data. This bound turns "no
/// network" into "no live updates", which is the correct degradation: the
/// data load still decides what the screen shows.
const realtimeSubscribeTimeout = Duration(seconds: 4);

/// A realtime subscription the caller owns.
///
/// [cancel] removes EXACTLY this listener — never the topic-less
/// `collection.unsubscribe()`, which maps to `realtime.unsubscribeByPrefix`
/// and removes EVERY listener on that collection (including listeners owned
/// by other screens).
class RealtimeSubscription {
  RealtimeSubscription(this._unsubscribe);

  final Future<void> Function() _unsubscribe;

  Future<void> cancel() async {
    try {
      await _unsubscribe();
    } catch (_) {
      // PocketBase's unsubscribe POSTs the new subscription list; offline
      // that POST fails. The local listener removal already happened, so a
      // failed POST must not surface as an unhandled error.
    }
  }
}

/// Subscribe to a realtime topic, bounded by [realtimeSubscribeTimeout].
///
/// The subscription is made on [pb].realtime directly (not through
/// `collection.subscribe`) for one reason: PocketBase registers the
/// listener BEFORE the SSE handshake completes, and the `UnsubscribeFunc`
/// only materialises once the handshake settles — which, offline, may be
/// never. Calling the realtime service directly gives this helper the
/// listener identity up front, so an orphaned listener can ALWAYS be
/// removed, whether the handshake later succeeds, fails, or never lands.
///
/// The scoped unsubscribe matters: the topic-less
/// `collection.unsubscribe()` removes every listener on the collection,
/// including listeners owned by other screens.
///
/// Returns the subscription handle on success, or null when the handshake
/// timed out or failed — the caller then proceeds without live updates and
/// re-subscribes on its next successful build.
///
/// [isAbandoned] reports whether the caller has gone away (its provider was
/// disposed). It MUST be per-build scoped: riverpod REUSES a notifier
/// instance across `invalidateSelf`, so a flag stored in a field would stay
/// `true` after the first rebuild and the helper would drop a listener that
/// belongs to a LIVE provider — re-creating the very symptom this helper
/// exists to prevent.
Future<RealtimeSubscription?> subscribeWithTimeout(
  PocketBase pb,
  String collection,
  void Function() onEvent,
  void Function(void Function() callback) registerDispose, {
  bool Function()? isAbandoned,
  Duration? timeout,
}) async {
  final realtime = pb.realtime;
  final topic = '$collection/*';

  // The listener identity is ours from the start, so an orphan can always
  // be cleaned up — even if the handshake never lands.
  var cancelled = false;

  void listener(dynamic _) {
    if (cancelled) return;
    onEvent();
  }

  Future<void> cancel() async {
    if (cancelled) return;
    cancelled = true;
    try {
      await realtime.unsubscribeByTopicAndListener(topic, listener);
    } catch (_) {
      // The local removal already happened; a failed POST (offline) must not
      // surface as an unhandled error.
    }
  }

  final future = realtime.subscribe(topic, listener);

  // If the caller goes away before the handshake lands, the listener must
  // not survive: an orphan keeps firing into a dead provider. The listener
  // is registered inside PocketBase from the start, so this branch is what
  // makes the offline case leak-free.
  future.then((_) {
    if (isAbandoned?.call() ?? false) {
      unawaited(cancel());
    }
  }).catchError((Object _) {
    // The handshake failed outright. The listener is STILL registered inside
    // PocketBase (it is registered before the handshake), so it must be
    // removed here or it leaks forever.
    if (isAbandoned?.call() ?? false) {
      unawaited(cancel());
    }
  });

  try {
    await future.timeout(timeout ?? realtimeSubscribeTimeout);
  } catch (_) {
    // Timed out or the handshake failed. The caller proceeds without live
    // updates.
    if (isAbandoned?.call() ?? false) {
      // The caller is gone and nothing will ever dispose this listener.
      await cancel();
      return null;
    }
    // The caller is alive: keep the listener (it delivers events as soon as
    // the handshake lands) and register its disposal.
    try {
      registerDispose(() => unawaited(cancel()));
    } catch (_) {
      // The provider was disposed between the check and the registration.
      await cancel();
    }
    return null;
  }

  // The handshake landed.
  try {
    registerDispose(() => unawaited(cancel()));
  } catch (_) {
    // The provider was disposed while the handshake was in flight, so
    // `registerDispose` throws. Nobody owns this listener — drop it.
    await cancel();
    return null;
  }
  return RealtimeSubscription(cancel);
}
