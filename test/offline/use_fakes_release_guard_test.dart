// P3 — USE_FAKES release fail-loud guard (spec §10 mock-build seam).
//
// kReleaseMode/kDebugMode are compile-time consts pinned by the framework
// (flutter_test always runs with kDebugMode=true), so a widget test CANNOT
// simulate a release context. The honest seam is the pure function
// `assertFakesAllowed(release:, useFakes:)` in core/config/data_source.dart:
// main.dart calls it as its FIRST statement with kReleaseMode + useFakes.
// These tests pin the function both ways AND pin the main.dart wiring
// (guard call exists and precedes runApp / ProviderScope).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:kuch_bhi/core/config/data_source.dart';

void main() {
  group('assertFakesAllowed — release fail-loud guard', () {
    test('RED/GREEN: release + useFakes=true throws StateError', () {
      expect(
        () => assertFakesAllowed(release: true, useFakes: true),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('USE_FAKES must never be enabled in a release build'),
        )),
        reason: 'a release binary built with USE_FAKES=true must fail loud '
            'before ProviderScope runs',
      );
    });

    test('release + useFakes=false passes (normal release build)', () {
      expect(() => assertFakesAllowed(release: true, useFakes: false),
          returnsNormally);
    });

    test('debug + useFakes=true passes (dev mock-build seam stays open)',
        () {
      expect(() => assertFakesAllowed(release: false, useFakes: true),
          returnsNormally);
    });

    test('debug + useFakes=false passes (dev default)', () {
      expect(() => assertFakesAllowed(release: false, useFakes: false),
          returnsNormally);
    });
  });

  group('main.dart wiring — guard fires before ProviderScope', () {
    final mainSrc = File('lib/main.dart').readAsStringSync();

    test('main.dart calls assertFakesAllowed', () {
      expect(mainSrc.contains('assertFakesAllowed('), isTrue,
          reason: 'main() must invoke the release guard');
    });

    test('guard call precedes runApp (ProviderScope mount)', () {
      final guardAt = mainSrc.indexOf('assertFakesAllowed(');
      final runAppAt = mainSrc.indexOf('runApp(');
      expect(guardAt, greaterThanOrEqualTo(0));
      expect(runAppAt, greaterThan(guardAt),
          reason: 'guard must run BEFORE ProviderScope mounts');
    });

    test('guard passes kReleaseMode and useFakes (not hard-coded args)', () {
      final guardAt = mainSrc.indexOf('assertFakesAllowed(');
      final guardLine = mainSrc
          .substring(guardAt, mainSrc.indexOf(')', guardAt) + 1)
          .replaceAll(RegExp(r'\s+'), ' ');
      expect(guardLine, contains('kReleaseMode'));
      expect(guardLine, contains('useFakes'));
    });
  });
}
