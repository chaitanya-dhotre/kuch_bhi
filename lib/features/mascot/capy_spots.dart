import 'package:flutter/widgets.dart';

import 'capy.dart';

/// One placement of the mascot (spec §E table). Keeping them as data makes
/// the F2 budget (≤ 2 animated per screen) checkable in one place.
class CapySpot {
  const CapySpot(
    this.view,
    this.mood,
    this.size, {
    this.animated = false,
    this.pose = CapyPose.none,
    this.playOnShow,
  });

  final CapyView view;
  final CapyMood mood;
  final double size;
  final bool animated;
  final CapyPose pose;
  final CapyOneShot? playOnShow;

  /// [oneShot] false skips [playOnShow] (X8 under reduced motion).
  Capy build({Key? key, CapyMood? mood, int hops = 0, bool oneShot = true}) =>
      Capy(
        key: key,
        view: view,
        mood: mood ?? this.mood,
        size: size,
        animated: animated,
        pose: pose,
        playOnShow: oneShot ? playOnShow : null,
        hops: hops,
      );
}

/// Phase 2 placements X1–X10 (E1 is [OfflineBathBanner]).
const capySpots = <String, CapySpot>{
  'X1 login': CapySpot(
    CapyView.sit,
    CapyMood.chill,
    112,
    playOnShow: CapyOneShot.wave,
  ),
  'X2 home empty': CapySpot(CapyView.sit, CapyMood.chill, 130),
  'X3 home error': CapySpot(CapyView.sit, CapyMood.worried, 120),
  'X4 requests empty': CapySpot(CapyView.sit, CapyMood.chill, 120),
  'X5 requests error': CapySpot(CapyView.sit, CapyMood.worried, 120),
  'X6 chat empty': CapySpot(CapyView.sit, CapyMood.chill, 108, animated: true),
  'X7 chat unavailable': CapySpot(CapyView.front, CapyMood.worried, 72),
  'X8 search nothing': CapySpot(
    CapyView.sit,
    CapyMood.active,
    72,
    playOnShow: CapyOneShot.lookAround,
  ),
  // §H: still searching. Animated: the glass sweeps (E1 banner + this = 2).
  'X8b searching': CapySpot(
    CapyView.sit,
    CapyMood.focused,
    72,
    animated: true,
    pose: CapyPose.search,
  ),
  'X9 chat load error': CapySpot(
    CapyView.front,
    CapyMood.focused,
    72,
    pose: CapyPose.guard,
  ),
  'X10 empty default': CapySpot(CapyView.sit, CapyMood.chill, 120),
};

CapySpot capySpot(String id) =>
    capySpots.entries.firstWhere((e) => e.key.startsWith('$id ')).value;

/// K2 (spec §G1): the lock capybara's face follows the PIN dots. No digits =
/// looks at you; dot 1 = −1 … dot 6 = +1.
double pinLookX(int digits) => digits <= 0 ? 0 : -1 + (digits - 1) * 0.4;
