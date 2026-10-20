import 'package:characters/characters.dart';

/// Returns true when the entire string is emoji characters —
/// no letters, digits, or punctuation. Used to render emoji-only
/// messages larger without a bubble background.
bool isEmojiOnly(String text) {
  final t = text.trim();
  final glyphCount = t.characters.length;
  if (glyphCount < 1 || glyphCount > 3) return false;
  return !RegExp(
    r'''[a-zA-Z0-9\s!@#\$%^&*()\-_=+\[\]{};:'",.<>/?\\|`~]''',
  ).hasMatch(t);
}

/// Extract the first URL from a string.
RegExp _urlRe = RegExp(r'https?://[^\s]+', caseSensitive: false);

String? extractFirstUrl(String text) => _urlRe.firstMatch(text)?.group(0);
