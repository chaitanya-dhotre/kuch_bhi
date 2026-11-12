/// Capybara stickers (mascot §J). The art ships in the APK as
/// `assets/stickers/<id>.webp`; a sticker message carries only its id, inside
/// the encrypted body as `Sticker: <id>`. Ids and that body are permanent once
/// shipped (T7): add ids, never rename or reuse one.
class Sticker {
  const Sticker(this.id, this.label);

  final String id;
  final String label;

  String get asset => 'assets/stickers/$id.webp';
}

/// Picker order.
const kStickers = [
  Sticker('hi', 'Hi'),
  Sticker('lol', 'LOL'),
  Sticker('sorry', 'Sorry'),
  Sticker('love', 'Love'),
  Sticker('thanks', 'Thanks'),
  Sticker('sleepy', 'Sleepy'),
  Sticker('on-my-way', 'On my way'),
  Sticker('chill', 'Chill'),
  Sticker('guarding', 'Guarding'),
  Sticker('celebrate', 'Celebrate'),
];

Sticker? stickerById(String id) {
  for (final s in kStickers) {
    if (s.id == id) return s;
  }
  return null;
}

/// The wire body (J2.2). Old apps show it as a text line.
String stickerBody(String id) => 'Sticker: $id';

final _bodyPattern = RegExp(r'^Sticker: ([a-z]+(?:-[a-z]+)*)$');

/// The id inside a sticker body, or null when the body is not one.
String? stickerIdOf(String body) => _bodyPattern.firstMatch(body)?.group(1);
