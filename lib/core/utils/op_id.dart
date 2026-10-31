import 'dart:math';

/// 15-char client id in PocketBase's id alphabet — becomes the server record id.
/// 8 base36 chars of a per-process monotonic ms clock, then 7 random: the id
/// is the same-second tiebreak in the message list, so it sorts in send order.
final _rng = Random.secure();
const _alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
var _lastMs = 0;
String generateOpId() {
  final now = DateTime.now().millisecondsSinceEpoch;
  _lastMs = now > _lastMs ? now : _lastMs + 1;
  return _lastMs.toRadixString(36).padLeft(8, '0') +
      List.generate(7, (_) => _alphabet[_rng.nextInt(_alphabet.length)]).join();
}
