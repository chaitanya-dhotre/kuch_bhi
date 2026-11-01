import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/services/media_upload_service.dart';
import 'package:kuch_bhi/core/widgets/busy_spinner.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';
import 'package:kuch_bhi/features/chat/widgets/voice_message_bubble.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';

import '../core/sheet_harness.dart';

/// Media-send review SHOULD 9: the retry tap invalidated the cached failure,
/// then read the provider at once, saw it loading and failed the tap. The
/// first tap after a failed load must wait for the new load.
void main() {
  testWidgets('voice bubble: the first tap after a failed load waits for the '
      'new load', (tester) async {
    var fetches = 0;
    final retry = Completer<LocalMediaFile?>();
    await pumpHost(
      tester,
      const Scaffold(
        body: Center(
          child: VoiceMessageBubble(
            conversationId: 'c1',
            serverId: 'v1',
            isMine: false,
          ),
        ),
      ),
      overrides: [
        mediaFileProvider.overrideWith(
          (ref, r) => ++fetches == 1 ? Future.value(null) : retry.future,
        ),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
      large: true,
    );
    await tester.pump();
    await tester.pump();
    expect(fetches, 1, reason: 'the first load found nothing (cached null)');

    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    await tester.pump();
    expect(fetches, 2, reason: 'the tap dropped the cached null');
    expect(find.byType(BusySpinner), findsOneWidget,
        reason: 'still loading: the tap waits instead of failing');
    expect(find.byIcon(Icons.error_outline), findsNothing);

    retry.complete(null);
    await tester.pump();
    await tester.pump();
    expect(find.byIcon(Icons.error_outline), findsOneWidget,
        reason: 'a load that still finds nothing fails as before');
  });
}
