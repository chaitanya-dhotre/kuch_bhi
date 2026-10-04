import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/utils/group_visibility.dart';

void main() {
  final join = DateTime(2026, 10, 3, 8, 44);
  final before = DateTime(2026, 10, 1);
  final after = DateTime(2026, 10, 3, 9, 0);

  test('pre-join rows are hidden', () {
    expect(isGroupRowVisible(createdAt: before, memberJoinedAt: join,
        decryptedBody: 'hi', type: 'text'), isFalse);
  });

  test('post-join decrypted text is visible', () {
    expect(isGroupRowVisible(createdAt: after, memberJoinedAt: join,
        decryptedBody: 'hi', type: 'text'), isTrue);
  });

  test('undecryptable text rows are hidden (never render ciphertext)', () {
    expect(isGroupRowVisible(createdAt: after, memberJoinedAt: join,
        decryptedBody: null, type: 'text'), isFalse);
    expect(isGroupRowVisible(createdAt: after, memberJoinedAt: join,
        decryptedBody: '', type: 'system'), isFalse);
  });

  test('media rows with null body stay visible (body is optional there)', () {
    expect(isGroupRowVisible(createdAt: after, memberJoinedAt: join,
        decryptedBody: null, type: 'image'), isTrue);
  });

  test('no join time (DM or missing member row) hides nothing by date', () {
    expect(isGroupRowVisible(createdAt: before, memberJoinedAt: null,
        decryptedBody: 'hi', type: 'text'), isTrue);
  });
}
