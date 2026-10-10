// Task 12 — USE_FAKES dev seam boot test (spec §10 mock-build strategy).
//
// Proves: app screens (real HomeScreen) read from FakeMessageRepository
// with pocketbaseClientProvider left on its DEFAULT (throws StateError by
// design — home_screen's dependency graph must not reach it once the
// message-repo seam + the screen-level providers the error names are
// overridden).
//
// The test proves THE SEAM, not the whole app: only providers the actual
// failure names get overridden (brief Step 1 note).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/domain/entities/conversation.dart';
import 'package:kuch_bhi/features/home/screens/home_screen.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart'
    show messageRepositoryProvider;

import '../fakes/fake_message_repository.dart';

/// Group row (no otherUser) — survives home_screen's direct-conv filter
/// (`type == 'direct' && otherUser == null` drops peer DMs).
const _fakeConversation = Conversation(
  id: 'fake-conv-1',
  type: 'group',
  name: 'Fake Boot Chat',
  lastMessageAt: null,
);

void main() {
  testWidgets('app screens read from FakeMessageRepository with NO PocketBase',
      (tester) async {
    final fake = FakeMessageRepository();
    fake.seedConversation(_fakeConversation);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        messageRepositoryProvider.overrideWithValue(fake),
        // Carry-3 (audit F): ConversationPreviewText watches
        // conversationLastMessageProvider, whose body reads the DEFAULT
        // appDatabaseProvider (real file DB + path_provider — Missing-
        // PluginException swallowed as AsyncError). In-memory DB keeps the
        // seam hermetic; no message rows ⇒ preview falls back to the stored
        // string, so the decryptPass/media hard-cast path (carry-1) is never
        // entered either.
        appDatabaseProvider.overrideWithValue(AppDatabase.test()),
      ],
      child: MaterialApp(
        theme: warmPopLight(),
        home: const HomeScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'default pocketbaseClientProvider throws — fake seam must avoid it');

    // Seam proof: the seeded fake row renders — data came from the fake,
    // not from PocketBase / the real repository.
    expect(find.text('Fake Boot Chat'), findsOneWidget,
        reason: 'home renders conversation seeded into FakeMessageRepository');

    // Drift schedules a Timer.run (0ms) when a query stream closes
    // (stream_queries.dart markAsClosed) — same flush the read_paths
    // widget test uses: unmount BEFORE the pending-timer invariant runs,
    // then elapse 1ms to fire the dispose-time timer.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
