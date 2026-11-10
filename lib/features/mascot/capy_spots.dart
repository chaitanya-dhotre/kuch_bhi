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
    this.waveOnShow = false,
  });

  final CapyView view;
  final CapyMood mood;
  final double size;
  final bool animated;
  final CapyPose pose;
  final bool waveOnShow;

  Capy build({Key? key, CapyMood? mood, int hops = 0}) => Capy(
    key: key,
    view: view,
    mood: mood ?? this.mood,
    size: size,
    animated: animated,
    pose: pose,
    waveOnShow: waveOnShow,
    hops: hops,
  );
}

/// Phase 2 placements X1–X10 (E1 is [OfflineBathBanner]).
const capySpots = <String, CapySpot>{
  'X1 login': CapySpot(CapyView.sit, CapyMood.chill, 112, waveOnShow: true),
  'X2 home empty': CapySpot(CapyView.sit, CapyMood.chill, 130),
  'X3 home error': CapySpot(CapyView.sit, CapyMood.worried, 120),
  'X4 requests empty': CapySpot(CapyView.sit, CapyMood.chill, 120),
  'X5 requests error': CapySpot(CapyView.sit, CapyMood.worried, 120),
  'X6 chat empty': CapySpot(CapyView.sit, CapyMood.chill, 108, animated: true),
  'X7 chat unavailable': CapySpot(CapyView.front, CapyMood.worried, 72),
  'X8 search nothing': CapySpot(CapyView.sit, CapyMood.sleepy, 72),
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
