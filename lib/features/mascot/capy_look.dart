import 'dart:async';

import 'package:flutter/widgets.dart';

/// Page 10 I4 (spec docs/design/pages/mascot.md §K1): what the capybara wears.
/// Names = the rig's `look` enum values. From the phone's own clock and the
/// tables below only (V4: no network, no server date).
enum CapyLook {
  none,
  night,
  diwali,
  holi,
  newYear;

  /// The look every [Capy] wears now. Kept current by [startCapyLookClock].
  static final current = ValueNotifier<CapyLook>(
    resolveCapyLook(DateTime.now()),
  );
}

/// Lakshmi Puja and Holi (Dhulandi) days, New Delhi panchang (drikpanchang,
/// checked 2026-11-12).
// shortcut: dates end 2030, add years when the table runs out.
const kDiwali = {2027: (10, 29), 2028: (10, 17), 2029: (11, 5), 2030: (10, 26)};
const kHoli = {2027: (3, 22), 2028: (3, 11), 2029: (3, 1), 2030: (3, 20)};

/// Device checks set this (`--dart-define=CAPY_LOOK=diwali`) instead of the
/// phone's date, which would break sign-in tokens. Empty in normal builds.
const kCapyLookOverride = String.fromEnvironment('CAPY_LOOK');

/// Days from [day] (month, day of [t]'s year) to [t]'s date.
int? _daysFrom((int, int)? day, DateTime t) => day == null
    ? null
    : DateTime.utc(t.year, t.month, t.day)
        .difference(DateTime.utc(t.year, day.$1, day.$2))
        .inDays;

/// Priority newYear > diwali > holi > night (decision 3).
CapyLook capyLookAt(DateTime t) {
  if ((t.month == 12 && t.day == 31 && t.hour >= 18) ||
      (t.month == 1 && t.day == 1)) {
    return CapyLook.newYear;
  }
  final d = _daysFrom(kDiwali[t.year], t);
  if (d != null && d.abs() <= 2) return CapyLook.diwali;
  final h = _daysFrom(kHoli[t.year], t);
  if (h == 0 || (h == -1 && t.hour >= 18)) return CapyLook.holi;
  if (t.hour >= 23 || t.hour < 5) return CapyLook.night;
  return CapyLook.none;
}

/// [capyLookAt], unless [override] names a look.
CapyLook resolveCapyLook(DateTime t, [String override = kCapyLookOverride]) =>
    CapyLook.values.asNameMap()[override] ?? capyLookAt(t);

/// The next time a look can change: 05:00, 18:00, 23:00 or midnight.
DateTime nextLookBoundary(DateTime t) => const [5, 18, 23, 24]
    .map((h) => DateTime(t.year, t.month, t.day, h))
    .firstWhere((b) => b.isAfter(t));

Timer? _timer;
AppLifecycleListener? _life;

/// Re-evaluates [CapyLook.current] at each boundary and on resume (the phone
/// may have slept past one). Called once from main(), after the binding.
void startCapyLookClock() {
  if (kCapyLookOverride.isNotEmpty) return;
  _life ??= AppLifecycleListener(onResume: _tick);
  _tick();
}

void _tick() {
  final now = DateTime.now();
  CapyLook.current.value = capyLookAt(now);
  _timer?.cancel();
  _timer = Timer(nextLookBoundary(now).difference(now), _tick);
}
