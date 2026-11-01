import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';

import 'package:kuch_bhi/features/chat/widgets/media_upload_disc.dart';
import 'package:kuch_bhi/features/chat/providers/upload_progress_provider.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';
import 'package:kuch_bhi/domain/repositories/message_repository.dart';
import 'package:kuch_bhi/core/widgets/busy_spinner.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';
import 'package:kuch_bhi/features/chat/widgets/document_message_bubble.dart';
import 'package:kuch_bhi/features/chat/widgets/image_message_bubble.dart';
import 'package:kuch_bhi/features/chat/widgets/voice_message_bubble.dart';
import 'package:kuch_bhi/features/media/providers/media_viewer_providers.dart';

import '../core/sheet_harness.dart';

void main() {
  testWidgets(
    'upload disc exposes the progress and cancel action to semantics',
    (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: warmPopLight(),
          home: const Scaffold(
            body: MediaUploadDisc(
              progress: .4,
              label: 'Photo, sending, 40 percent. Cancel',
            ),
          ),
        ),
      );
      expect(
        tester.getSemantics(find.byType(MediaUploadDisc)),
        matchesSemantics(
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          label: 'Photo, sending, 40 percent. Cancel',
        ),
      );
      handle.dispose();
    },
  );

  testWidgets('waiting disc has no progress arc', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: warmPopLight(),
        home: const Scaffold(
          body: MediaUploadDisc(label: 'Photo, Waiting for connection. Cancel'),
        ),
      ),
    );
    expect(find.byKey(const Key('upload-progress-arc')), findsNothing);
  });

  for (final kind in ['Photo', 'Video', 'Voice', 'Document']) {
    testWidgets('$kind own upload states expose retry and cancel', (
      tester,
    ) async {
      final repo = _UploadRepo();
      var generation = 0;
      Future<void> pump(
        String? status, {
        required bool online,
        double? progress,
      }) async {
        final localId = 'op${generation++}';
        await tester.pumpWidget(
          ProviderScope(
            key: ValueKey(localId),
            overrides: [
              uploadProgressProvider(
                localId,
              ).overrideWith((ref) => Stream.value(progress)),
              isOnlineProvider.overrideWith((ref) => Stream.value(online)),
              messageRepositoryProvider.overrideWithValue(repo),
            ],
            child: MaterialApp(
              theme: warmPopLight(),
              home: Scaffold(
                body: MediaUploadControl(
                  localId: localId,
                  status: status,
                  kind: kind,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
      }

      await pump(null, online: true, progress: .4);
      expect(find.byKey(const Key('upload-progress-arc')), findsOneWidget);
      await pump(null, online: true);
      expect(find.byKey(const Key('upload-progress-arc')), findsNothing);
      await pump('failed', online: false);
      expect(find.text('Available online'), findsOneWidget);
      expect(find.text('Not sent · Try again'), findsNothing);
      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.byType(MediaUploadDisc)).label,
        '$kind not sent. Try again',
      );
      handle.dispose();
      await pump('failed', online: true);
      await tester.tap(find.byType(MediaUploadDisc));
      await tester.pump();
      expect(repo.retries, 1);
      await pump(null, online: true);
      await tester.tap(find.byType(MediaUploadDisc));
      await tester.pump();
      expect(repo.cancels, 1);
      expect(find.text('Upload cancelled'), findsOneWidget);
    });
  }

  // E3/E4: the three ended captions, no retry anywhere; 360dp at 200% text
  // (pumpHost large) with the system font.
  for (final (status, caption) in [
    (MediaBlobStatus.expired, 'Media expired'),
    (MediaBlobStatus.deadLink, 'No longer available'),
    (MediaBlobStatus.cantDecrypt, "Can't decrypt"),
  ]) {
    for (final (kind, bubble) in <(String, Widget)>[
      ('photo', const ImageMessageBubble(
          conversationId: 'c1', serverId: 's1', isMine: false, isDark: false)),
      ('document', const DocumentMessageBubble(
          conversationId: 'c1', serverId: 's1', isMine: false, isDark: false)),
      ('voice', const VoiceMessageBubble(
          conversationId: 'c1', serverId: 's1', isMine: false)),
    ]) {
      testWidgets('$kind ${status.name}: "$caption", no retry', (tester) async {
        await pumpHost(
          tester,
          Scaffold(body: Center(child: bubble)),
          overrides: [
            mediaFileProvider.overrideWith((ref, r) async => null),
            isOnlineProvider.overrideWith((ref) => Stream.value(true)),
            mediaBlobStatusProvider.overrideWith((ref, r) async => status),
          ],
          large: true,
        );
        await tester.pump();
        await tester.pump();
        expect(find.textContaining(caption), findsOneWidget);
        expect(find.textContaining('Tap to retry'), findsNothing);
        expect(find.byType(BusySpinner), findsNothing);
        if (status == MediaBlobStatus.cantDecrypt) {
          expect(find.byIcon(Icons.lock_outline), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}

class _UploadRepo implements MessageRepository {
  int cancels = 0, retries = 0;
  @override
  Future<bool> cancelMediaUpload(String localId) async {
    cancels++;
    return true;
  }

  @override
  Future<void> retryMessage(String localId) async {
    retries++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
