import 'dart:io' show HttpDate;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kuch_bhi/core/network/server_clock.dart';

void main() {
  final server = DateTime.utc(2026, 11, 7, 8);

  test('knows nothing until a server response', () {
    expect(ServerClock().now, isNull);
  });

  test('takes the time from any response, and ignores the device clock', () async {
    final clock = ServerClock();
    final client = ServerClockClient(
      MockClient((_) async => http.Response('{}', 200,
          headers: {'date': HttpDate.format(server)})),
      clock,
    );

    await client.get(Uri.parse('http://pocketbase.test/api/health'));

    expect(clock.now!.difference(server).inSeconds, lessThan(2));
  });

  test('keeps counting from the last reading', () async {
    final clock = ServerClock()..observe(HttpDate.format(server));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(clock.now!.isAfter(server), isTrue);
  });

  test('after deep sleep a clock starts from the device, a purge stays late', () {
    var device = server;
    final clock = ServerClock(deviceClock: () => device)
      ..observe(HttpDate.format(server));
    // The stopwatch pauses in deep sleep; the device's own time does not.
    device = server.add(const Duration(hours: 20));

    expect(clock.latest!.difference(device).inSeconds.abs(), lessThan(2));
    expect(clock.now!.difference(server).inSeconds, lessThan(2));
  });

  test('a device clock set back cannot backdate a start', () {
    var device = server;
    final clock = ServerClock(deviceClock: () => device)
      ..observe(HttpDate.format(server));
    device = server.subtract(const Duration(days: 10));

    expect(clock.latest!.isBefore(server), isFalse);
  });

  test('a missing or malformed date changes nothing', () {
    final clock = ServerClock()
      ..observe(null)
      ..observe('not a date');
    expect(clock.now, isNull);

    clock.observe(HttpDate.format(server));
    clock.observe('not a date');
    expect(clock.now!.difference(server).inSeconds, lessThan(2));
  });
}
