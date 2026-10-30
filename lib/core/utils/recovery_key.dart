import 'dart:math';

/// Crockford base-32: no I, L, O, U, so a hand-copied key can't be misread.
const kRecoveryKeyAlphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// 25 symbols × 5 bits = 125 bits, about the X25519 key's own strength.
const kRecoveryKeyLength = 25;

/// A new canonical key (25 alphabet characters, no dashes).
String generateRecoveryKey([Random? rng]) {
  final r = rng ?? Random.secure();
  return String.fromCharCodes([
    for (var i = 0; i < kRecoveryKeyLength; i++)
      kRecoveryKeyAlphabet.codeUnitAt(r.nextInt(kRecoveryKeyAlphabet.length)),
  ]);
}

/// The canonical key in [input] (any case, dashes and whitespace ignored,
/// O→0 and I/L→1), or null when it isn't exactly 25 alphabet characters.
String? parseRecoveryKey(String input) {
  final key = input
      .toUpperCase()
      .replaceAll(RegExp(r'[\s-]'), '')
      .replaceAll('O', '0')
      .replaceAll(RegExp('[IL]'), '1');
  if (key.length != kRecoveryKeyLength) return null;
  return key.split('').every(kRecoveryKeyAlphabet.contains) ? key : null;
}

/// `7KQ2M-9XHMA-…`: groups of 5 joined by dashes.
String formatRecoveryKey(String key) => recoveryKeyGroups(key).join('-');

List<String> recoveryKeyGroups(String key) => [
  for (var i = 0; i < key.length; i += 5)
    key.substring(i, min(i + 5, key.length)),
];
