import 'dart:convert';

import 'package:cryptography/dart.dart';
import 'package:flutter/foundation.dart';

/// QR payload prefix for a security code (spec D2).
const kSecurityCodeQrPrefix = 'kuchbhi-sc0:';

/// 30 digits for one side (key-change-warning spec D1): SHA-512 over
/// `0x0000 ‖ key ‖ utf8(userId)`, then 5199 more rounds over `hash ‖ key`;
/// the first 30 bytes as six 5-byte big-endian chunks, each mod 100000.
String fingerprintDigits(String userId, String publicKeyB64) {
  final key = base64.decode(publicKeyB64);
  const sha = DartSha512();
  var hash = sha.hashSync([0, 0, ...key, ...utf8.encode(userId)]).bytes;
  for (var i = 1; i < 5200; i++) {
    hash = sha.hashSync([...hash, ...key]).bytes;
  }
  final out = StringBuffer();
  for (var c = 0; c < 6; c++) {
    var n = 0;
    for (var b = 0; b < 5; b++) {
      n = n * 256 + hash[c * 5 + b];
    }
    out.write((n % 100000).toString().padLeft(5, '0'));
  }
  return out.toString();
}

/// The 60-digit code both phones show: the two halves ordered, joined.
String securityCode(
  String myId,
  String myKeyB64,
  String theirId,
  String theirKeyB64,
) {
  final a = fingerprintDigits(myId, myKeyB64);
  final b = fingerprintDigits(theirId, theirKeyB64);
  return a.compareTo(b) <= 0 ? '$a$b' : '$b$a';
}

/// [securityCode] off the UI isolate (10,400 hashes).
Future<String> computeSecurityCode(
  String myId,
  String myKeyB64,
  String theirId,
  String theirKeyB64,
) => compute((List<String> a) => securityCode(a[0], a[1], a[2], a[3]), [
  myId,
  myKeyB64,
  theirId,
  theirKeyB64,
]);

/// 12 groups of 5 (D1/D9).
List<String> securityCodeGroups(String code) => [
  for (var i = 0; i + 5 <= code.length; i += 5) code.substring(i, i + 5),
];
