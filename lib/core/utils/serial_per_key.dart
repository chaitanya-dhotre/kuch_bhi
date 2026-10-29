import 'dart:async';

/// Runs async tasks one at a time per key: a task starts only after the
/// previous task on the same key has settled (success or failure).
///
/// The wait for a predecessor is capped at [maxWait], so a task stuck on a
/// blackholed socket (PocketBase HTTP has no timeout) cannot block its key
/// forever. Callers must therefore still tolerate the rare overlap — group-key
/// rotation does: a version collision retries at the next version.
class SerialPerKey {
  SerialPerKey({this.maxWait = const Duration(minutes: 2)});

  final Duration maxWait;
  final _tails = <String, Future<void>>{};

  Future<T> run<T>(String key, Future<T> Function() task) {
    final prev = _tails[key];
    final result = (prev == null
            ? Future<void>.value()
            : prev.timeout(maxWait, onTimeout: () {}))
        .then((_) => task());
    // The tail never errors: a failure belongs to this task's caller only.
    final tail = result.then<void>((_) {}, onError: (_) {});
    _tails[key] = tail;
    tail.whenComplete(() {
      if (identical(_tails[key], tail)) _tails.remove(key);
    });
    return result;
  }
}
