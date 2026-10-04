import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/utils/key_gap.dart';

void main() {
  test('members with no key row are missing', () {
    expect(membersMissingCurrentKey(
        memberToMaxVersion: {'a': null, 'b': 7}, currentVersion: 7),
        {'a'});
  });

  test('members with stale versions are missing', () {
    expect(membersMissingCurrentKey(
        memberToMaxVersion: {'a': 6, 'b': 7}, currentVersion: 7),
        {'a'});
  });

  test('current members are not missing', () {
    expect(membersMissingCurrentKey(
        memberToMaxVersion: {'a': 7, 'b': 7}, currentVersion: 7),
        isEmpty);
  });

  test('version 0 counts as no key', () {
    expect(membersMissingCurrentKey(
        memberToMaxVersion: {'a': 0}, currentVersion: 7),
        {'a'});
  });
}
