/// Pure-Dart token source for the export pipeline (no Flutter imports —
/// this file must stay runnable by `dart run`).
///
/// tokens.dart (the app's runtime source) holds the Color constants; the
/// token_export_test asserts hex(core) == tokens.dart values, so the chain
/// core → design_tokens.json and core → tokens.dart stays in lockstep.
class WarmPopCore {
  WarmPopCore._();

  // Brand + light
  static const accent = '#EFA00B';
  static const accentPressed = '#D98F08';
  static const onAccentLight = '#2A2520';
  static const bg = '#FAF7F1';
  static const surface = '#FFFFFF';
  static const surface2 = '#F1ECE3';
  static const ink = '#2A2520';
  static const inkSoft = '#6E655A';
  static const inkFaint = '#9C9284';
  static const line = '#E4DDD1';
  static const accentSoftLight = '#FFF3DC';

  // Dark
  static const bgDark = '#171512';
  static const surfaceDark = '#211E1A';
  static const surface2Dark = '#2B2823';
  static const inkDark = '#F3EDE3';
  static const inkSoftDark = '#9C9284';
  static const lineDark = '#3B362F';
  static const accentSoftDark = '#3A2E14';
  static const onAccentDark = '#21260F';

  // Semantic
  static const success = '#0E9F6E';
  static const error = '#E5484D';
  static const info = '#4A6FA5';

  // Mascot
  static const mascotBody = '#C6894F';
  static const mascotShade = '#B27A42';
  static const mascotSnout = '#8B5E3E';
  static const mascotNostril = '#5C3B28';
  static const mascotFace = '#3A2E22';
  static const keyGold = '#E8A21D';

  // Layout
  static const radius = {'sm': 10.0, 'md': 16.0, 'lg': 20.0, 'xl': 24.0,
    'bubble': 18.0};
  static const space = [4, 8, 12, 16, 20, 24, 32, 40, 48];
  static const motion = {'fastMs': 150, 'baseMs': 250, 'slowMs': 400};
}
