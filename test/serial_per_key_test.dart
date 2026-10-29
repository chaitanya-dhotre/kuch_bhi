import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/utils/serial_per_key.dart';

void main() {
  test('tasks on the same key run one at a time, in order', () async {
    final queue = SerialPerKey();
    final first = Completer<void>();
    final log = <String>[];

    final a = queue.run('g1', () async {
      log.add('a start');
      await first.future;
      log.add('a end');
    });
    final b = queue.run('g1', () async => log.add('b'));

    await Future<void>.delayed(Duration.zero);
    expect(log, ['a start']);
    first.complete();
    await Future.wait([a, b]);
    expect(log, ['a start', 'a end', 'b']);
  });

  test('different keys do not wait for each other', () async {
    final queue = SerialPerKey();
    final hang = Completer<void>();
    unawaited(queue.run('g1', () => hang.future));
    var ran = false;
    await queue.run('g2', () async => ran = true);
    expect(ran, isTrue);
    hang.complete();
  });

  test('a failed task reaches its caller and does not block the next',
      () async {
    final queue = SerialPerKey();
    final a = queue.run<void>('g1', () async => throw StateError('boom'));
    final b = queue.run('g1', () async => 42);
    await expectLater(a, throwsStateError);
    expect(await b, 42);
  });

  test('a hung task holds the key for at most maxWait', () async {
    final queue = SerialPerKey(maxWait: const Duration(milliseconds: 200));
    unawaited(queue.run('g1', () => Completer<void>().future));
    var ran = false;
    unawaited(queue.run('g1', () async => ran = true));

    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(ran, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(ran, isTrue);
  });
}
