import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

/// The user tapped ✕ on an uploading bubble.
class UploadCancelled implements Exception {
  const UploadCancelled();
  @override
  String toString() => 'UploadCancelled';
}

/// How long an upload may pull no bytes before it counts as offline (the
/// download stall bound's twin).
const uploadStallBound = Duration(seconds: 8);

/// After the last byte is pulled the socket still drains its send buffer
/// (megabytes on a slow link) and the server writes the file, so silence
/// there is not a stall.
const uploadDrainBound = Duration(seconds: 60);

const _chunk = 128 * 1024;

/// One upload attempt of one media message: counts the encrypted bytes the
/// HTTP client pulls, and aborts the request on cancel or stall.
class UploadTicket {
  UploadTicket(this._onProgress);

  final void Function() _onProgress;
  int total = 0;
  int sent = 0;
  Object? _failure;
  Timer? _timer;
  Completer<Never>? _abort;

  bool get cancelled => _failure is UploadCancelled;

  /// 0–1 once the sizes are known; 0 before.
  double get progress => total == 0 ? 0 : math.min(1, sent / total);

  void cancel() => _fail(const UploadCancelled());

  void _fail(Object error) {
    _failure ??= error;
    _timer?.cancel();
    final abort = _abort;
    if (abort != null && !abort.isCompleted) abort.completeError(_failure!);
  }

  void _arm() {
    _timer?.cancel();
    _timer = Timer(sent >= total ? uploadDrainBound : uploadStallBound,
        () => _fail(TimeoutException('media upload stalled', uploadStallBound)));
  }

  /// [bytes] as a chunked stream; each pull counts and re-arms the stall
  /// bound. Errors with the cancel/stall reason on the next pull.
  Stream<List<int>> counted(Uint8List bytes) async* {
    for (var i = 0; i < bytes.length; i += _chunk) {
      if (_failure != null) throw _failure!;
      final end = math.min(i + _chunk, bytes.length);
      yield Uint8List.sublistView(bytes, i, end);
      sent += end - i;
      _onProgress();
      if (_abort != null) _arm();
    }
  }

  /// Runs [request] under the stall bound and the cancel switch. The
  /// request future is raced, not awaited, once either fires.
  // shortcut: a raced request keeps its socket until the OS gives up; the
  // SDK has no abort hook. Re-runs look the media record up first, so a
  // late success is never uploaded twice.
  Future<T> guard<T>(Future<T> request) {
    if (_failure != null) return Future.error(_failure!);
    _abort = Completer<Never>();
    _arm();
    return Future.any<T>([request, _abort!.future]).whenComplete(() {
      _timer?.cancel();
      _abort = null;
    });
  }
}

/// In-memory registry of running media uploads, keyed by message localId.
/// A row with no ticket and status `pending` is waiting (offline/queued).
class UploadTracker {
  final _tickets = <String, UploadTicket>{};
  final _events = StreamController<(String, double?)>.broadcast();

  UploadTicket? ticket(String localId) => _tickets[localId];

  /// Null when an upload for [localId] is already running.
  UploadTicket? start(String localId) {
    if (_tickets.containsKey(localId)) return null;
    late final UploadTicket t;
    t = UploadTicket(() => _events.add((localId, t.progress)));
    _tickets[localId] = t;
    _events.add((localId, 0));
    return t;
  }

  void end(String localId, UploadTicket ticket) {
    if (!identical(_tickets[localId], ticket)) return;
    _tickets.remove(localId);
    _events.add((localId, null));
  }

  /// Current progress, then every change; null = not uploading right now.
  Stream<double?> watch(String localId) {
    late final StreamController<double?> out;
    StreamSubscription<(String, double?)>? sub;
    out = StreamController<double?>(
      onListen: () {
        sub = _events.stream
            .where((e) => e.$1 == localId)
            .listen((e) => out.add(e.$2));
        out.add(_tickets[localId]?.progress);
      },
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }
}

final uploadTracker = UploadTracker();
