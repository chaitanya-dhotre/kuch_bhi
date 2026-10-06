// Group sender name: plan Review Focus — labels ≥ w600 12px, and no
// low-contrast palette entries (accent/keyGold are ~2.2:1 on light
// surface). Light theme must map sender hash to dark-enough colors.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/core/theme/tokens.dart';
import 'package:kuch_bhi/domain/entities/message.dart';
import 'package:kuch_bhi/features/chat/widgets/message_bubble.dart';

Message _msg(String senderId) => Message(
      localId: 'l1',
      conversationId: 'c1',
      senderId: senderId,
      type: 'text',
      decryptedBody: 'hello group',
      status: 'sent',
      createdAt: DateTime(2026, 10, 6),
    );

/// Sender id that the legacy 5-slot palette (accent, info, success, error,
/// keyGold) maps to accent (index 0) or keyGold (index 4) — the
/// light-theme-unreadable entries. Guarantees RED against the old code.
String _senderIdOnBannedColor() {
  var i = 0;
  while (true) {
    final id = 'sender_$i';
    final slot = id.hashCode.abs() % 5;
    if (slot == 0 || slot == 4) return id;
    i++;
  }
}

Future<Text> _pumpSenderLabel(WidgetTester tester, ThemeData theme) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: theme,
        home: Scaffold(
          body: ListView(
            children: [
              MessageBubble(
                message: _msg(_senderIdOnBannedColor()),
                isMine: false,
                senderName: 'Zeta Sender',
                isGroup: true,
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return tester.widget<Text>(find.text('Zeta Sender'));
}

void main() {
  testWidgets('light theme: sender label ≥12px, no accent/keyGold',
      (tester) async {
    final label = await _pumpSenderLabel(tester, warmPopLight());
    expect(label.style!.fontSize, greaterThanOrEqualTo(12.0),
        reason: 'plan floor: labels ≥ w600 12px');
    expect(label.style!.fontWeight, FontWeight.w600);
    expect(label.style!.color, isNot(WarmPopTokens.accent),
        reason: 'accent #EFA00B is 2.2:1 on light surface');
    expect(label.style!.color, isNot(WarmPopTokens.keyGold),
        reason: 'keyGold #E8A21D is 2.2:1 on light surface');
  });

  testWidgets('dark theme: sender label ≥12px', (tester) async {
    final label = await _pumpSenderLabel(tester, warmPopDark());
    expect(label.style!.fontSize, greaterThanOrEqualTo(12.0));
    expect(label.style!.fontWeight, FontWeight.w600);
  });
}
