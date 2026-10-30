import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/widgets/app_sheet.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';
import 'package:kuch_bhi/features/media/screens/media_docs_screen.dart';
import 'package:kuch_bhi/infrastructure/services/media_gallery_service.dart';
import 'package:pocketbase/pocketbase.dart';

import '../core/sheet_harness.dart';

/// H3: a voice note that fails to load shows the error + Try again, and
/// Try again really fetches again (mediaFileProvider is not auto-disposed).
void main() {
  testWidgets('failed voice note: error line, Try again re-fetches',
      (tester) async {
    var fetches = 0;
    await pumpHost(
      tester,
      const MediaDocsScreen(conversationId: 'c1'),
      overrides: [
        mediaPageProvider.overrideWith((ref, key) async => [
              if (key.mediaType == 'voice')
                RecordModel({
                  'id': 'm1',
                  'message_id': 'srv1',
                  'duration_seconds': 29,
                  'created': '2026-10-01 10:00:00Z',
                }),
            ]),
        mediaFileProvider.overrideWith((ref, r) async {
          fetches++;
          return null; // offline / never landed
        }),
      ],
    );
    await tester.tap(find.text('Voice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voice message · 0:29'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(AppSheetChrome), findsOneWidget);
    expect(find.text("Couldn't load this voice message."), findsOneWidget);
    expect(fetches, 1);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(fetches, 2, reason: 'Try again must not reuse the cached failure');
    expect(find.text("Couldn't load this voice message."), findsOneWidget);
    expect(find.text('0:29'), findsOneWidget,
        reason: 'total falls back to the passed duration');
  });
}
