import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/utils/group_visibility.dart';

/// T9: `decrypted_body` is dropped — the visibility gate takes the row's
/// `decrypt_state` (the projection of "can this body resolve?" post-drop;
/// see group_visibility.dart). Same expectations as the pre-drop suite,
/// restated against the state column.
void main() {
  final join = DateTime(2026, 10, 3, 8, 44);
  final before = DateTime(2026, 10, 1);
  final after = DateTime(2026, 10, 3, 9, 0);

  test('pre-join rows are hidden', () {
    expect(isGroupRowVisible(createdAt: before, memberJoinedAt: join,
        decryptState: 'ready', type: 'text'), isFalse);
  });

  test('post-join decryptable text is visible', () {
    expect(isGroupRowVisible(createdAt: after, memberJoinedAt: join,
        decryptState: 'ready', type: 'text'), isTrue);
  });

  test('undecryptable text rows are hidden (never render ciphertext)', () {
    expect(isGroupRowVisible(createdAt: after, memberJoinedAt: join,
        decryptState: 'key_missing', type: 'text'), isFalse);
    expect(isGroupRowVisible(createdAt: after, memberJoinedAt: join,
        decryptState: 'pending', type: 'system'), isFalse);
  });

  test('media rows with an unresolved body stay visible (optional there)', () {
    expect(isGroupRowVisible(createdAt: after, memberJoinedAt: join,
        decryptState: 'key_missing', type: 'image'), isTrue);
  });

  test('no join time (DM or missing member row) hides nothing by date', () {
    expect(isGroupRowVisible(createdAt: before, memberJoinedAt: null,
        decryptState: 'ready', type: 'text'), isTrue);
  });
}
