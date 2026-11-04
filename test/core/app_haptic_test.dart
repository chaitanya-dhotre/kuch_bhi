import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/utils/app_haptic.dart';

void main() {
  testWidgets('goes to the vibrator with touch usage', (tester) async {
    const channel = MethodChannel('haptic_feedback');
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      haptics.add('${call.method}:${(call.arguments as Map)['usage']}');
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    appHaptic(HapticsType.medium);
    appHaptic(HapticsType.selection);
    await tester.pump();

    expect(haptics, ['medium:touch', 'selection:touch']);
  });

  testWidgets('a failing vibrator stays silent', (tester) async {
    const channel = MethodChannel('haptic_feedback');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      _,
    ) async {
      throw PlatformException(code: 'VIBRATION_ERROR');
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    appHaptic(HapticsType.medium);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
