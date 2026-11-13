/// Page 10 I4 (mascot spec §K1): night and festival looks.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/features/mascot/capy.dart';
import 'package:kuch_bhi/features/mascot/capy_look.dart';

import 'capy_test.dart' show FakeSource, host;

void main() {
  group('capyLookAt', () {
    final cases = <(DateTime, CapyLook)>[
      (DateTime(2028, 6, 1, 22, 59), CapyLook.none),
      (DateTime(2028, 6, 1, 23), CapyLook.night),
      (DateTime(2028, 6, 2, 4, 59), CapyLook.night),
      (DateTime(2028, 6, 2, 5), CapyLook.none),
      (DateTime(2028, 12, 31, 17, 59), CapyLook.none),
      (DateTime(2028, 12, 31, 18), CapyLook.newYear),
      (DateTime(2029, 1, 1, 3), CapyLook.newYear), // beats night
      (DateTime(2029, 1, 1, 23, 59), CapyLook.newYear),
      (DateTime(2029, 1, 2, 0, 30), CapyLook.night),
      // Diwali 2028 = 17 Oct: −2 … +2.
      (DateTime(2028, 10, 14, 12), CapyLook.none),
      (DateTime(2028, 10, 15, 0), CapyLook.diwali),
      (DateTime(2028, 10, 17, 23, 30), CapyLook.diwali), // beats night
      (DateTime(2028, 10, 19, 12), CapyLook.diwali),
      (DateTime(2028, 10, 20, 12), CapyLook.none),
      // Diwali across a month end (2029: 5 Nov → 3 Nov … 7 Nov).
      (DateTime(2029, 11, 3, 9), CapyLook.diwali),
      (DateTime(2029, 11, 2, 9), CapyLook.none),
      // Holi 2027 = 22 Mar: the eve from 18:00, and the day.
      (DateTime(2027, 3, 21, 17, 59), CapyLook.none),
      (DateTime(2027, 3, 21, 18), CapyLook.holi),
      (DateTime(2027, 3, 22, 23, 30), CapyLook.holi), // beats night
      (DateTime(2027, 3, 23, 12), CapyLook.none),
      // After the table ends, festivals stop silently; night still works.
      (DateTime(2031, 10, 20, 12), CapyLook.none),
      (DateTime(2031, 10, 20, 23, 30), CapyLook.night),
    ];
    for (final (t, want) in cases) {
      test('$t → ${want.name}', () => expect(capyLookAt(t), want));
    }
  });

  test('nextLookBoundary: 05:00, 18:00, 23:00, midnight', () {
    expect(nextLookBoundary(DateTime(2028, 6, 1, 3)), DateTime(2028, 6, 1, 5));
    expect(nextLookBoundary(DateTime(2028, 6, 1, 5)), DateTime(2028, 6, 1, 18));
    expect(
      nextLookBoundary(DateTime(2028, 6, 1, 18, 0, 1)),
      DateTime(2028, 6, 1, 23),
    );
    expect(nextLookBoundary(DateTime(2028, 6, 1, 23)), DateTime(2028, 6, 2));
    expect(nextLookBoundary(DateTime(2028, 12, 31, 23, 59)), DateTime(2029));
  });

  test('CAPY_LOOK override wins over the clock; empty or unknown = clock', () {
    final noon = DateTime(2028, 6, 1, 12);
    expect(resolveCapyLook(noon, 'diwali'), CapyLook.diwali);
    expect(resolveCapyLook(noon, 'newYear'), CapyLook.newYear);
    expect(resolveCapyLook(noon, ''), CapyLook.none);
    expect(resolveCapyLook(noon, 'xmas'), CapyLook.none);
    expect(kCapyLookOverride, isEmpty, reason: 'normal builds use the clock');
  });

  testWidgets('every Capy wears CapyLook.current and follows it', (
    tester,
  ) async {
    final source = FakeSource();
    CapyLoader.debugSource = source;
    final before = CapyLook.current.value;
    addTearDown(() {
      CapyLoader.debugSource = null;
      CapyLook.current.value = before;
    });
    CapyLook.current.value = CapyLook.night;
    await tester.pumpWidget(
      host(const Capy(view: CapyView.head, size: 32, pettable: false)),
    );
    final rig = source.rigs.single;
    expect(rig.look, CapyLook.night);
    CapyLook.current.value = CapyLook.holi;
    expect(rig.look, CapyLook.holi, reason: 'no rebuild needed');
    expect(rig.mood, CapyMood.chill, reason: 'a look is not a mood');
    await tester.pumpWidget(host(const SizedBox()));
    CapyLook.current.value = CapyLook.none;
    expect(rig.look, CapyLook.holi, reason: 'disposed capys stop listening');
  });
}
