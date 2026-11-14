import 'widgets/voice_waveform.dart' show bucketLevels, kVoiceBubbleBars;

/// D-3 A (chat calm E3): a voice message's encrypted body is its duration
/// text plus a fixed suffix of [kVoiceBubbleBars] level glyphs, e.g.
/// "0:12 ▁▃▅▇█▆…". Old builds show the suffix after the duration (it reads
/// like a little waveform); every reader here strips it via [parseVoiceBody].
const _glyphs = '▁▂▃▄▅▆▇█';

/// The suffix: one space + exactly [kVoiceBubbleBars] glyphs.
const kVoiceLevelsSuffixLength = 1 + kVoiceBubbleBars;

/// [duration] + the level suffix. Levels are 0..1 (recorder `waveLevel`);
/// none recorded → the duration alone.
String voiceBodyWithLevels(String duration, List<double> levels) {
  if (levels.isEmpty) return duration;
  final bars = levels.length >= kVoiceBubbleBars
      ? bucketLevels(levels, kVoiceBubbleBars)
      : [
          for (var i = 0; i < kVoiceBubbleBars; i++)
            levels[i * levels.length ~/ kVoiceBubbleBars],
        ];
  final glyphs = [
    for (final l in bars)
      _glyphs[(l.clamp(0.0, 1.0) * (_glyphs.length - 1)).round()],
  ].join();
  return '$duration $glyphs';
}

/// Splits a voice body into its duration text and levels. A body with no
/// suffix, or a malformed one, keeps the whole text and returns null levels
/// (the bubble then draws generated bars).
({String duration, List<double>? levels}) parseVoiceBody(String? body) {
  final b = body ?? '';
  if (b.length >= kVoiceLevelsSuffixLength) {
    final cut = b.length - kVoiceLevelsSuffixLength;
    final suffix = b.substring(cut + 1);
    if (b[cut] == ' ' && suffix.split('').every((c) => _glyphs.contains(c))) {
      return (
        duration: b.substring(0, cut).trimRight(),
        levels: [
          for (final c in suffix.split(''))
            (_glyphs.indexOf(c) + 1) / _glyphs.length,
        ],
      );
    }
  }
  return (duration: b, levels: null);
}

/// The duration text only, for every place that shows a voice body.
String voiceBodyText(String? body) => parseVoiceBody(body).duration;
