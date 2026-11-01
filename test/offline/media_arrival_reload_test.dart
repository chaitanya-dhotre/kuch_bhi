/// Device round 1, issue 3: the receiver's photo stayed on "Tap to retry"
/// after the sender came back online and finished the upload. The media
/// provider only waited 45s for the media record; now an empty result also
/// reloads when that message's media lands.
library;

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';
import 'package:kuch_bhi/services/media_upload_service.dart';

import 'char_harness.dart';
import 'media_send_harness.dart';

class _Repo extends MessageRepositoryImpl {
  _Repo(CharHarness h)
      : super(
          pbClient: h.pbClient,
          db: h.db,
          storage: h.storage,
          encryption: h.encryption,
          mediaUploadService: MediaUploadService(h.pbClient, h.encryption),
        );
  final arrived = StreamController<String>.broadcast();
  @override
  Stream<String> get mediaChanges => arrived.stream;
}

void main() {
  test('an empty media load reloads when that message\'s media lands',
      () async {
    final server = FakeMediaServer();
    final h = charHarness(clientFactory: server.client);
    addTearDown(h.close);
    await seedConversationAndKey(h);
    await mockTempDir();
    // 20 minutes old: past the provider's 45s wait, within the store's day.
    final sent = DateTime.now().subtract(const Duration(minutes: 20));
    await h.db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
      localId: 'l1',
      serverId: const Value('srv1'),
      conversationId: 'g1',
      senderId: 'u_friend',
      type: 'image',
      encryptedBody: '',
      iv: '',
      createdAt: sent,
      updatedAt: sent,
    ));
    final repo = _Repo(h);
    final c = ProviderContainer(
        overrides: [messageRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(c.dispose);
    const ref = MediaRef('g1', 'srv1', thumb: true);
    c.listen(mediaFileProvider(ref), (_, __) {});

    expect(await c.read(mediaFileProvider(ref).future), isNull);
    expect(server.mediaLookups, 1);

    repo.arrived.add('other'); // another message's media: no reload
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(server.mediaLookups, 1);

    repo.arrived.add('srv1');
    await until(() async => server.mediaLookups == 2,
        reason: 'the provider fetched again');
  });
}
