import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:kuch_bhi/data/local/database/app_database.dart';

/// Regression tests for the group-membership gating bug (#17):
/// `getMembersForConversation` filters out `role='left'` rows — correct for
/// the member-list UI — but the chat screen's `isLeft`/`isMeAdmin` gate was
/// reading through that same filtered query, so a removed/left member's own
/// row vanished from the result and `isLeft` could never become true
/// (the "you can't send" gate was dead code). The DAO must expose an
/// UNFILTERED view for gating while keeping the filtered one for display.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.test();
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedGroup() async {
    final now = DateTime.now();
    await db.conversationsDao.upsertConversation(
      ConversationsTableCompanion.insert(
        id: 'g1',
        type: 'group',
        createdById: 'u1',
        createdAt: now,
        updatedAt: now,
      ),
    );
    Future<void> member(String id, String userId, String role) =>
        db.conversationsDao.upsertMember(
          ConversationMembersTableCompanion.insert(
            id: id,
            conversationId: 'g1',
            userId: userId,
            joinedAt: now,
            role: Value(role),
          ),
        );

    await member('m1', 'u1', 'admin');
    await member('m2', 'u2', 'member');
    await member('m3', 'u3', 'left'); // the removed/removed-equivalent member
  }

  test('getMembersForConversation excludes left members (display list)', () async {
    await seedGroup();
    final rows = await db.conversationsDao.getMembersForConversation('g1');
    expect(rows.map((r) => r.userId), unorderedEquals(['u1', 'u2']));
  });

  test('getAllMembersForConversation includes left member (gating source)', () async {
    await seedGroup();
    final rows = await db.conversationsDao.getAllMembersForConversation('g1');
    expect(rows.map((r) => r.userId), unorderedEquals(['u1', 'u2', 'u3']));

    // The gate's core lookup: my own row must surface with role 'left'.
    final mine = rows.where((r) => r.userId == 'u3').first;
    expect(mine.role, 'left');
  });

  test('getAllMembersForConversation is empty for an unknown conversation', () async {
    await seedGroup();
    final rows = await db.conversationsDao.getAllMembersForConversation('missing');
    expect(rows, isEmpty);
  });
}
