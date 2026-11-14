// Chat calm D-3 A: 36 voice levels ride in the encrypted body as a fixed
// suffix; every place that shows a voice body strips it.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/domain/entities/message.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';
import 'package:kuch_bhi/features/chat/voice_body.dart';
import 'package:kuch_bhi/features/chat/widgets/reply_quote.dart';
import 'package:kuch_bhi/features/chat/widgets/voice_message_bubble.dart';
import 'package:kuch_bhi/features/chat/widgets/voice_waveform.dart';
import 'package:kuch_bhi/features/media/providers/media_viewer_providers.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:kuch_bhi/services/media_upload_service.dart';

final _glyph = RegExp('[▁▂▃▄▅▆▇█]');

void main() {
  final levels = [for (var i = 0; i < 120; i++) (i % 10) / 9];
  final body = voiceBodyWithLevels('0:12', levels);

  test('the suffix is one space + exactly 36 glyphs', () {
    expect(body.length, '0:12'.length + kVoiceLevelsSuffixLength);
    expect(body.startsWith('0:12 '), isTrue);
    expect(
      voiceBodyWithLevels('12:34', [0.5]).length,
      '12:34'.length + kVoiceLevelsSuffixLength,
      reason: 'fewer levels than bars still gives 36',
    );
  });

  test('round trip: duration back, 36 levels in 0..1', () {
    final p = parseVoiceBody(body);
    expect(p.duration, '0:12');
    expect(p.levels, hasLength(kVoiceBubbleBars));
    expect(p.levels!.every((l) => l > 0 && l <= 1), isTrue);
  });

  test('no suffix, malformed suffix or null → whole text, no levels', () {
    expect(parseVoiceBody('0:12'), (duration: '0:12', levels: null));
    expect(parseVoiceBody(null).levels, isNull);
    final wrongLength = '0:12 ${'▃' * 35}';
    expect(parseVoiceBody(wrongLength).levels, isNull);
    final notGlyphs = '0:12 ${'a' * 36}';
    expect(parseVoiceBody(notGlyphs).levels, isNull);
    final noSpace = '0:12${'▃' * 37}';
    expect(parseVoiceBody(noSpace).levels, isNull);
    expect(voiceBodyWithLevels('0:12', const []), '0:12');
  });

  testWidgets('voice bubble: shows the duration, never the glyphs', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mediaFileProvider.overrideWith(
            (ref, r) async => LocalMediaFile(file: File('/nonexistent/v')),
          ),
          mediaBlobStatusProvider.overrideWith(
            (ref, r) async => MediaBlobStatus.other,
          ),
          isOnlineProvider.overrideWith((ref) => Stream.value(true)),
        ],
        child: MaterialApp(
          theme: warmPopLight(),
          home: Scaffold(
            body: VoiceMessageBubble(
              conversationId: 'c1',
              serverId: 'v1',
              isMine: true,
              durationText: body,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('0:12'), findsOneWidget);
    expect(find.textContaining(_glyph), findsNothing);
    final wave = tester.widget<VoiceWaveform>(
      find.byKey(const ValueKey('voice-bubble-wave')),
    );
    expect(wave.levels, parseVoiceBody(body).levels, reason: 'real levels');
  });

  test('reply quote preview strips the suffix (legacy 🎤 body too)', () {
    final quote = ReplyQuote.fromMessage(
      Message(
        localId: 'l1',
        conversationId: 'c1',
        senderId: 'u1',
        type: 'voice',
        status: 'read',
        decryptedBody: voiceBodyWithLevels('🎤 0:12', levels),
        createdAt: DateTime(2026, 11, 14),
      ),
      'Asha',
    );
    expect(quote.preview, '🎤 0:12');
  });

  // Every reader of a voice body (bubble, reply quote ×2, pinned banner,
  // starred, chat search) goes through the helper. Home shows a constant
  // label; notification text comes from the server payload; there is no
  // forward. shortcut: a source check for the private readers; upgrade to
  // widget tests if one of them grows real logic.
  test('every voice-body reader uses parseVoiceBody / voiceBodyText', () {
    const readers = {
      'lib/features/chat/widgets/voice_message_bubble.dart': 1,
      'lib/features/chat/widgets/reply_quote.dart': 2,
      'lib/features/chat/widgets/pinned_message_banner.dart': 1,
      'lib/features/starred_messages/screens/starred_messages_screen.dart': 1,
      'lib/features/chat/screens/chat_screen.dart': 1,
      'lib/features/chat/widgets/message_input.dart': 1,
    };
    readers.forEach((path, n) {
      final src = File(path).readAsStringSync();
      final uses = RegExp(
        r'(parseVoiceBody|voiceBodyText|voiceBodyWithLevels)\(',
      ).allMatches(src).length;
      expect(uses, greaterThanOrEqualTo(n), reason: path);
    });
  });
}
