import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/utils/recovery_key.dart';

void main() {
  test('1,000 keys: 25 alphabet characters, parse to themselves, distinct', () {
    final keys = List.generate(1000, (_) => generateRecoveryKey());
    for (final k in keys) {
      expect(k, matches(RegExp(r'^[0-9A-HJKMNP-TV-Z]{25}$')));
      expect(parseRecoveryKey(k), k);
      expect(parseRecoveryKey(formatRecoveryKey(k)), k);
    }
    expect(keys.toSet(), hasLength(1000));
  });

  test('a seeded Random gives a fixed key', () {
    expect(generateRecoveryKey(Random(1)), generateRecoveryKey(Random(1)));
    expect(
      generateRecoveryKey(Random(1)),
      isNot(generateRecoveryKey(Random(2))),
    );
  });

  test('parse accepts lowercase, dashes, spaces and O/I/L look-alikes', () {
    const k = '7KQ2M9XHMA4TRBC8D1WZP6YVN';
    expect(parseRecoveryKey('7kq2m-9xhma-4trbc-8d1wz-p6yvn'), k);
    expect(parseRecoveryKey(' 7KQ2M 9XHMA\n4TRBC\t8D1WZ P6YVN '), k);
    expect(parseRecoveryKey('7KQ2M9XHMA4TRBC8DIWZP6YVN'), k); // I → 1
    expect(parseRecoveryKey('7KQ2M9XHMA4TRBC8DlWZP6YVN'), k); // l → 1
    expect(parseRecoveryKey('OOOOO-00000-00000-00000-00000'), '0' * 25);
  });

  test('parse rejects U, 24 and 26 characters, empty', () {
    expect(parseRecoveryKey('7KQ2M9XHMA4TRBC8D1WZP6YVU'), isNull);
    expect(parseRecoveryKey('7KQ2M9XHMA4TRBC8D1WZP6YV'), isNull);
    expect(parseRecoveryKey('7KQ2M9XHMA4TRBC8D1WZP6YVNN'), isNull);
    expect(parseRecoveryKey(''), isNull);
    expect(parseRecoveryKey('123456'), isNull);
  });

  test('format gives 5 groups of 5', () {
    expect(
      formatRecoveryKey('7KQ2M9XHMA4TRBC8D1WZP6YVN'),
      '7KQ2M-9XHMA-4TRBC-8D1WZ-P6YVN',
    );
  });
}
