import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/features/chat/widgets/expiry_badge.dart';

/// Page 9 B6: the viewer's expiry line, same thresholds as the bubble pill.
void main() {
  final now = DateTime(2026, 10, 30, 12);
  String? label(Duration left) => viewerExpiryLabel(now.add(left), now: now);

  test('no date, or a date in the past → no line', () {
    expect(viewerExpiryLabel(null, now: now), isNull);
    expect(label(const Duration(seconds: -1)), isNull);
  });

  test('more than 7 days → the date, year only when it differs', () {
    expect(label(const Duration(days: 30)), 'Expires Nov 29');
    expect(label(const Duration(days: 8)), 'Expires Nov 7');
    expect(label(const Duration(days: 70)), 'Expires Jan 8, 2027');
  });

  test('1–7 days → in N days (7d boundary stays relative)', () {
    expect(label(const Duration(days: 7, hours: 23)), 'Expires in 7 days');
    expect(label(const Duration(days: 3, hours: 5)), 'Expires in 3 days');
    expect(label(const Duration(hours: 24)), 'Expires in 1 day');
  });

  test('under 24 hours → hours, 1 hour under 2 hours', () {
    expect(label(const Duration(hours: 23, minutes: 59)), 'Expires in 23 hours');
    expect(label(const Duration(hours: 5)), 'Expires in 5 hours');
    expect(label(const Duration(hours: 2)), 'Expires in 2 hours');
    expect(label(const Duration(hours: 1, minutes: 59)), 'Expires in 1 hour');
    expect(label(const Duration(minutes: 10)), 'Expires in 1 hour');
  });
}
