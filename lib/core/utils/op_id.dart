import 'dart:math';

/// 15-char client id in PocketBase's id alphabet — becomes the server record id.
final _rng = Random.secure();
const _alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
String generateOpId() =>
    List.generate(15, (_) => _alphabet[_rng.nextInt(_alphabet.length)]).join();
