import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/utils/session_epoch.dart';

void main() {
  test('same epoch + valid auth → writes allowed', () {
    expect(sessionStillValid(epochAtStart: 3, currentEpoch: 3,
        authValid: true), isTrue);
  });

  test('epoch bumped (logout/login) → writes blocked', () {
    expect(sessionStillValid(epochAtStart: 3, currentEpoch: 4,
        authValid: true), isFalse);
  });

  test('auth store cleared → writes blocked even with same epoch', () {
    expect(sessionStillValid(epochAtStart: 3, currentEpoch: 3,
        authValid: false), isFalse);
  });
}
