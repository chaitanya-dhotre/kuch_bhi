import 'dart:io' show HttpDate;

import 'package:http/http.dart' as http;

/// Server time, for decisions a phone's clock must not be able to change:
/// anyone can set their clock ahead, and a disappearing message would then be
/// deleted early and for good. Runs on a monotonic stopwatch from the last
/// server response, so moving the device clock has no effect.
class ServerClock {
  ServerClock({DateTime Function() deviceClock = DateTime.now})
      : _deviceClock = deviceClock;

  final DateTime Function() _deviceClock;
  DateTime? _base;
  DateTime? _deviceAtBase;
  final _since = Stopwatch();

  /// For judging whether a clock has run out. Null until a server response
  /// has been seen in this process. The stopwatch can pause in deep sleep, so
  /// this may run late, which only makes a message stay longer.
  DateTime? get now => _base?.add(_since.elapsed);

  /// For starting a clock, where running late would backdate it and shorten
  /// the message: the later of [now] and the device's own elapsed time. A
  /// device clock moved ahead here only makes a message stay longer.
  DateTime? get latest {
    final monotonic = now;
    if (monotonic == null) return null;
    final byDevice = _base!.add(_deviceClock().difference(_deviceAtBase!));
    return byDevice.isAfter(monotonic) ? byDevice : monotonic;
  }

  void observe(String? httpDate) {
    if (httpDate == null) return;
    try {
      _base = HttpDate.parse(httpDate);
      _deviceAtBase = _deviceClock();
      _since
        ..reset()
        ..start();
    } on Exception {
      // A malformed header teaches nothing; keep the last good reading.
    }
  }
}

/// Feeds every response's `Date` header to [clock].
class ServerClockClient extends http.BaseClient {
  ServerClockClient(this._inner, this.clock);

  final http.Client _inner;
  final ServerClock clock;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request);
    clock.observe(response.headers['date']);
    return response;
  }

  @override
  void close() => _inner.close();
}
