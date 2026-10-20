import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/domain/entities/message.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';
import 'package:kuch_bhi/features/chat/providers/message_body_provider.dart';
import 'package:kuch_bhi/features/chat/providers/outbox_status_provider.dart';
import 'package:kuch_bhi/features/chat/widgets/image_message_bubble.dart';
import 'package:kuch_bhi/features/chat/widgets/link_preview_card.dart';
import 'package:kuch_bhi/features/chat/widgets/message_bubble.dart';
import 'package:kuch_bhi/features/chat/widgets/message_input.dart';
import 'package:kuch_bhi/infrastructure/services/link_preview_service.dart';
import 'package:kuch_bhi/services/media_upload_service.dart';
import 'package:shimmer/shimmer.dart';

Widget _host({required Widget child, List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: warmPopLight(),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('LinkPreviewCard', () {
    const url = 'https://example.com/article';

    testWidgets('keeps a domain fallback when metadata is unavailable', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          child: const LinkPreviewCard(url: url),
          overrides: [
            linkPreviewServiceProvider(url).overrideWith((ref) async => null),
          ],
        ),
      );
      await tester.pump();

      try {
        expect(find.text('example.com'), findsNWidgets(2));
        expect(find.byIcon(Icons.link), findsOneWidget);
        expect(
          find.bySemanticsLabel(RegExp(r'Open link example\.com')),
          findsOneWidget,
        );
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('keeps a domain fallback after preview failure', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          child: const LinkPreviewCard(url: url),
          overrides: [
            linkPreviewServiceProvider(url).overrideWith((ref) async {
              throw StateError('offline');
            }),
          ],
        ),
      );
      await tester.pump();

      expect(find.text('example.com'), findsNWidgets(2));
      expect(find.byIcon(Icons.link), findsOneWidget);
    });
  });

  group('MessageInput', () {
    testWidgets('parks pulse under reduced motion and resumes when enabled', (
      tester,
    ) async {
      const input = MessageInput(
        conversationId: 'composer-motion',
        onSend: _noop,
      );

      await tester.pumpWidget(
        _host(
          child: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: input,
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(tester.hasRunningAnimations, isFalse);

      await tester.pumpWidget(
        _host(
          child: MediaQuery(
            data: const MediaQueryData(disableAnimations: false),
            child: input,
          ),
        ),
      );
      await tester.pump();
      expect(tester.hasRunningAnimations, isTrue);
    });

    testWidgets('uses distinct 48dp controls and morphs mic to send', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          child: const MessageInput(
            conversationId: 'composer-morph',
            onSend: _noop,
          ),
        ),
      );

      expect(find.byIcon(Icons.attach_file), findsOneWidget);
      expect(find.byKey(const ValueKey('mic-action')), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('send-action')), findsOneWidget);
      expect(find.byKey(const ValueKey('mic-action')), findsNothing);
      expect(
        tester.getSize(find.byKey(const ValueKey('send-action'))),
        const Size(48, 48),
      );
    });

    testWidgets('shows the real send loading path', (tester) async {
      await tester.pumpWidget(
        _host(
          child: const MessageInput(
            conversationId: 'composer-loading',
            onSend: _noop,
            isLoading: true,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.send_rounded), findsNothing);
    });

    testWidgets('renders the styled restriction state', (tester) async {
      await tester.pumpWidget(
        _host(
          child: const MessageInput(
            conversationId: 'composer-restricted',
            onSend: _noop,
            canSendMessages: false,
          ),
        ),
      );

      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.text('Only admins can send messages'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });
  });

  group('ImageMessageBubble', () {
    testWidgets('parks the image skeleton under reduced motion', (
      tester,
    ) async {
      final pending = Completer<LocalMediaFile?>();
      const mediaRef = MediaRef('image-motion', 'pending-image', thumb: true);

      Widget image({required bool disableAnimations}) {
        return MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: const ImageMessageBubble(
            conversationId: 'image-motion',
            serverId: 'pending-image',
            isMine: false,
            isDark: false,
          ),
        );
      }

      await tester.pumpWidget(
        _host(
          child: image(disableAnimations: false),
          overrides: [
            mediaFileProvider(mediaRef).overrideWith((ref) => pending.future),
          ],
        ),
      );
      await tester.pump();
      expect(find.byType(Shimmer), findsOneWidget);

      await tester.pumpWidget(
        _host(
          child: image(disableAnimations: true),
          overrides: [
            mediaFileProvider(mediaRef).overrideWith((ref) => pending.future),
          ],
        ),
      );
      await tester.pump();
      expect(find.byType(Shimmer), findsNothing);
    });
  });

  group('Optimistic media placeholders', () {
    Message message(String type) => Message(
      localId: 'optimistic-$type',
      conversationId: 'optimistic-conversation',
      senderId: 'u_test',
      type: type,
      status: 'pending',
      createdAt: DateTime(2026, 10, 21),
    );

    Widget bubble(String type, {required bool disableAnimations}) => MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: MessageBubble(message: message(type), isMine: true),
    );

    testWidgets(
      'parks optimistic image/video/voice shimmer under reduced motion',
      (tester) async {
        for (final type in ['image', 'video', 'voice']) {
          await tester.pumpWidget(
            _host(
              child: bubble(type, disableAnimations: false),
              overrides: [
                messageBodyProvider.overrideWith((ref, id) async => null),
                outboxStatusProvider.overrideWith(
                  (ref, conversationId) => Stream.value(const []),
                ),
              ],
            ),
          );
          await tester.pump();
          expect(
            find.byType(Shimmer),
            findsOneWidget,
            reason: '$type should shimmer with animations enabled',
          );

          await tester.pumpWidget(
            _host(
              child: bubble(type, disableAnimations: true),
              overrides: [
                messageBodyProvider.overrideWith((ref, id) async => null),
                outboxStatusProvider.overrideWith(
                  (ref, conversationId) => Stream.value(const []),
                ),
              ],
            ),
          );
          await tester.pump();
          expect(
            find.byType(Shimmer),
            findsNothing,
            reason: '$type must use a static surface under reduced motion',
          );
          expect(tester.takeException(), isNull);
        }
      },
    );
  });
}

void _noop(String _) {}
