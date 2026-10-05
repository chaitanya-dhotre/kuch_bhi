import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/utils/realtime_gate.dart';

void main() {
  test('logout always reconnects (teardown)', () {
    expect(shouldReconnectRealtime(
        wasAuthenticated: true, isAuthenticated: false,
        previousUserId: 'a', newUserId: null), isTrue);
  });

  test('login from logged-out reconnects', () {
    expect(shouldReconnectRealtime(
        wasAuthenticated: false, isAuthenticated: true,
        previousUserId: null, newUserId: 'a'), isTrue);
  });

  test('same-user token churn does NOT reconnect', () {
    expect(shouldReconnectRealtime(
        wasAuthenticated: true, isAuthenticated: true,
        previousUserId: 'a', newUserId: 'a'), isFalse);
  });

  test('account switch reconnects', () {
    expect(shouldReconnectRealtime(
        wasAuthenticated: true, isAuthenticated: true,
        previousUserId: 'a', newUserId: 'b'), isTrue);
  });

  test('same user but id unresolvable yet does NOT reconnect', () {
    // authRefresh fires before _saveSession persists the id — treat as
    // same-session churn, not a new login.
    expect(shouldReconnectRealtime(
        wasAuthenticated: true, isAuthenticated: true,
        previousUserId: 'a', newUserId: null), isFalse);
  });
}
