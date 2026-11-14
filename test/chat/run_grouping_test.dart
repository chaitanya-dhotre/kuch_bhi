import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/domain/entities/message.dart';
import 'package:kuch_bhi/features/chat/chat_run_grouping.dart';

Message _message({
  required String id,
  required String sender,
  required DateTime createdAt,
  String type = 'text',
}) {
  return Message(
    localId: id,
    conversationId: 'conversation',
    senderId: sender,
    type: type,
    status: 'sent',
    createdAt: createdAt,
  );
}

void main() {
  final base = DateTime(2026, 10, 17, 12);

  test('groups adjacent sender messages within two minutes', () {
    final flags = computeChatRunFlags([
      _message(
        id: 'new',
        sender: 'a',
        createdAt: base.add(const Duration(minutes: 2)),
      ),
      _message(
        id: 'middle',
        sender: 'a',
        createdAt: base.add(const Duration(minutes: 1)),
      ),
      _message(id: 'old', sender: 'a', createdAt: base),
    ]);

    expect(flags[0].runStart, isFalse);
    expect(flags[0].runEnd, isTrue);
    expect(flags[1].runStart, isFalse);
    expect(flags[1].runEnd, isFalse);
    expect(flags[2].runStart, isTrue);
    expect(flags[2].runEnd, isFalse);
  });

  // Chat calm gate 4 (B3, D-6): a 4 min gap joins, 6 min splits.
  test('joins across a four-minute gap', () {
    final flags = computeChatRunFlags([
      _message(
        id: 'new',
        sender: 'a',
        createdAt: base.add(const Duration(minutes: 4)),
      ),
      _message(id: 'old', sender: 'a', createdAt: base),
    ]);
    expect(flags[0].runStart, isFalse);
    expect(flags[1].runEnd, isFalse);
  });

  test('sender name once per streak: a long gap splits the run, not the '
      'streak; another sender or a new day starts a new streak', () {
    final flags = computeChatRunFlags([
      _message(
        id: 'b',
        sender: 'b',
        createdAt: base.add(const Duration(minutes: 40)),
      ),
      _message(
        id: 'a-late',
        sender: 'a',
        createdAt: base.add(const Duration(minutes: 30)),
      ),
      _message(id: 'a-early', sender: 'a', createdAt: base),
      _message(
        id: 'a-yesterday',
        sender: 'a',
        createdAt: base.subtract(const Duration(days: 1)),
      ),
    ]);
    // a-late starts its own run (30 min gap) but not a new streak.
    expect(flags[1].runStart, isTrue);
    expect(flags[1].streakStart, isFalse);
    expect(flags[2].streakStart, isTrue);
    expect(flags[0].streakStart, isTrue);
    expect(flags[3].streakStart, isTrue);
  });

  test('breaks after a six-minute gap and across a date separator', () {
    final flags = computeChatRunFlags([
      _message(
        id: 'new',
        sender: 'a',
        createdAt: base.add(const Duration(minutes: 6)),
      ),
      _message(id: 'old', sender: 'a', createdAt: base),
      _message(
        id: 'yesterday',
        sender: 'a',
        createdAt: base.subtract(const Duration(days: 1)),
      ),
    ]);

    expect(flags[0].runStart, isTrue);
    expect(flags[0].runEnd, isTrue);
    expect(flags[1].runStart, isTrue);
    expect(flags[1].runEnd, isTrue);
    expect(flags[2].runStart, isTrue);
    expect(flags[2].runEnd, isTrue);
  });

  test('sender changes and system rows always reset runs', () {
    final flags = computeChatRunFlags([
      _message(
        id: 'new',
        sender: 'a',
        createdAt: base.add(const Duration(minutes: 1)),
      ),
      _message(id: 'system', sender: 'a', type: 'system', createdAt: base),
      _message(
        id: 'old',
        sender: 'a',
        createdAt: base.subtract(const Duration(minutes: 1)),
      ),
      _message(
        id: 'other',
        sender: 'b',
        createdAt: base.subtract(const Duration(minutes: 2)),
      ),
    ]);

    for (final flag in flags) {
      expect(flag.runStart, isTrue);
      expect(flag.runEnd, isTrue);
    }
  });
}
