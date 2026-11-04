import 'dart:async';

import 'package:haptic_feedback/haptic_feedback.dart';

export 'package:haptic_feedback/haptic_feedback.dart' show HapticsType;

/// Not Flutter's HapticFeedback: its impact and selection types are touch
/// haptics that Samsungs like the M52 drop (flutter/flutter#73987). This calls
/// the vibrator itself. A haptic must never fail what it decorates, so errors
/// stop here.
void appHaptic(HapticsType type) => unawaited(
  Haptics.vibrate(type, usage: HapticsUsage.touch).catchError((Object _) {}),
);
