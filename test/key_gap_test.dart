import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/utils/key_gap.dart';

void main() {
  test('members with no key row are missing', () {
    expect(
      membersMissingCurrentKey(
        memberToMaxVersion: {'a': null, 'b': 7},
        currentVersion: 7,
      ),
      {'a'},
    );
  });

  test('members with stale versions are missing', () {
    expect(
      membersMissingCurrentKey(
        memberToMaxVersion: {'a': 6, 'b': 7},
        currentVersion: 7,
      ),
      {'a'},
    );
  });

  test('current members are not missing', () {
    expect(
      membersMissingCurrentKey(
        memberToMaxVersion: {'a': 7, 'b': 7},
        currentVersion: 7,
      ),
      isEmpty,
    );
  });

  group('keyHoldersNotMembers (leave-rotation gates 1-4)', () {
    Set<String> stale(
      List<(String, int)> rows,
      Set<String> members,
      int current,
    ) => keyHoldersNotMembers(
      keyRows: [for (final r in rows) (userId: r.$1, version: r.$2)],
      memberIds: members,
      currentVersion: current,
    );

    test('1: a current-key holder who is not a member is stale', () {
      expect(stale([('a', 3), ('b', 3)], {'a'}, 3), {'b'});
    });
    test('2: a non-member whose newest row is older is not stale', () {
      expect(stale([('a', 4), ('b', 3), ('a', 3)], {'a'}, 4), isEmpty);
    });
    test('3: a member at current is not stale', () {
      expect(stale([('a', 3)], {'a'}, 3), isEmpty);
    });
    test('4: no rows (current 0) is empty', () {
      expect(stale([], {'a'}, 0), isEmpty);
    });
  });

  test('version 0 counts as no key', () {
    expect(
      membersMissingCurrentKey(memberToMaxVersion: {'a': 0}, currentVersion: 7),
      {'a'},
    );
  });
}
