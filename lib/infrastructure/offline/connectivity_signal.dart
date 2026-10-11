import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Online/offline signal for UI gating (P4: defined-offline message actions).
///
/// The Connectivity listener lives HERE (gate 13: connectivity_plus is
/// sanctioned under lib/infrastructure/ only). Feature widgets watch
/// [isOnlineProvider] and never import the SDK.
///
/// Fail-safe default is ONLINE (`true`): when the platform channel is
/// missing (unit tests) or the initial probe fails, actions stay enabled —
/// we never wrongly disable controls on an unknown signal. The outbox
/// worker keeps its own listener; this class is UI-only, no FSM coupling.
class ConnectivitySignal {
  ConnectivitySignal({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity() {
    _subscription = _connectivity.onConnectivityChanged.listen(
      _onResults,
      onError: (Object e) =>
          debugPrint('[Connectivity] watch error (staying $_online): $e'),
    );
    // Best-effort initial probe — errors keep the optimistic default.
    _connectivity.checkConnectivity().then(_onResults).catchError((Object e) {
      debugPrint('[Connectivity] initial probe failed (staying $_online): $e');
    });
  }

  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  final _changes = StreamController<bool>.broadcast();
  bool _online = true;

  bool get isOnline => _online;

  /// Emits on every observed transition (after the current value via
  /// [isOnline] — subscribers should seed from that getter).
  Stream<bool> get changes => _changes.stream;

  void _onResults(List<ConnectivityResult> results) {
    final online = results.any((r) => r != ConnectivityResult.none);
    if (online == _online) return;
    _online = online;
    _changes.add(online);
  }

  void dispose() {
    _subscription?.cancel();
    _changes.close();
  }
}

final connectivitySignalProvider = Provider<ConnectivitySignal>((ref) {
  final signal = ConnectivitySignal();
  ref.onDispose(signal.dispose);
  return signal;
});

/// Rebuild-on-change online flag for widgets. Seeded with the current
/// probe result; loading/error resolve to `true` (online, actions enabled).
final isOnlineProvider = StreamProvider<bool>((ref) async* {
  final signal = ref.watch(connectivitySignalProvider);
  yield signal.isOnline;
  yield* signal.changes;
});
