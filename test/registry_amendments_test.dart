import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/core/theme/tokens.dart';
import 'package:kuch_bhi/core/widgets/app_avatar.dart';
import 'package:kuch_bhi/core/widgets/app_badge.dart';
import 'package:kuch_bhi/domain/entities/conversation.dart';
import 'package:kuch_bhi/features/chat/widgets/message_context_menu.dart';

Widget _host(Widget child) => MaterialApp(
  theme: warmPopLight(),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('shared registry amendments', () {
    testWidgets('AppBadge hides <=0, preserves 1-99, and clamps at 99+', (
      tester,
    ) async {
      for (final count in [-1, 0]) {
        await tester.pumpWidget(_host(AppBadge(count: count)));
        expect(find.byType(Text), findsNothing);
      }

      await tester.pumpWidget(_host(const AppBadge(count: 1)));
      expect(find.text('1'), findsOneWidget);
      expect(find.text('99+'), findsNothing);

      await tester.pumpWidget(_host(const AppBadge(count: 99)));
      expect(find.text('99'), findsOneWidget);
      expect(find.text('99+'), findsNothing);

      await tester.pumpWidget(_host(const AppBadge(count: 100)));
      expect(find.text('100'), findsNothing);
      expect(find.text('99+'), findsOneWidget);
      final badge = tester.widget<Container>(
        find.ancestor(of: find.text('99+'), matching: find.byType(Container)),
      );
      expect(badge.constraints?.minWidth, 22);
      expect(badge.constraints?.minHeight, 22);
      expect(
        (badge.decoration as BoxDecoration).borderRadius,
        BorderRadius.circular(999),
      );
    });

    testWidgets('AppAvatar initials sit on surface2 (calm-rest A2)', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const AppAvatar(initials: 'A')));
      expect(
        tester.widget<CircleAvatar>(find.byType(CircleAvatar)).backgroundColor,
        ColorTokens.light.surface2,
      );
    });

    testWidgets('conversation menu shares chrome and renders action rows', (
      tester,
    ) async {
      var invoked = false;
      final conversation = Conversation(
        id: 'conversation-1',
        type: 'group',
        name: 'Design Crew',
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: warmPopLight(),
            home: Scaffold(
              body: Builder(
                builder: (context) => Consumer(
                  builder: (context, ref, _) => Center(
                    child: ElevatedButton(
                      key: const Key('open-conversation-menu'),
                      onPressed: () => showConversationMenu(
                        context: context,
                        ref: ref,
                        conversation: conversation,
                        preview: 'Latest message',
                        actions: [
                          ConversationMenuAction(
                            label: 'Pin conversation',
                            icon: Icons.push_pin_outlined,
                            callback: () => invoked = true,
                            trailing: 'Off',
                            semanticsLabel: 'Pin this conversation',
                          ),
                          ConversationMenuAction(
                            label: 'Unavailable',
                            icon: Icons.block_outlined,
                            callback: () {},
                            enabled: false,
                            trailing: 'Soon',
                          ),
                        ],
                      ),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('open-conversation-menu')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('conversation-context-menu')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('conversation-menu-handle')), findsOneWidget);
      expect(
        find.byKey(const Key('conversation-menu-preview')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('conversation-menu-preview-avatar')),
        findsOneWidget,
      );
      expect(find.byType(AppAvatar), findsOneWidget);
      expect(find.text('Design Crew'), findsOneWidget);
      expect(find.text('Latest message'), findsOneWidget);

      final pinTile = tester.widget<ListTile>(
        find.byKey(const Key('conversation-menu-action-0')),
      );
      expect(pinTile.enabled, isTrue);
      expect(pinTile.onTap, isNotNull);
      expect(find.text('Off'), findsOneWidget);
      expect(find.bySemanticsLabel('Pin this conversation'), findsOneWidget);

      final disabledTile = tester.widget<ListTile>(
        find.byKey(const Key('conversation-menu-action-1')),
      );
      expect(disabledTile.enabled, isFalse);
      expect(disabledTile.onTap, isNull);
      expect(find.text('Soon'), findsOneWidget);

      await tester.tap(find.text('Pin conversation'));
      await tester.pumpAndSettle();
      expect(invoked, isTrue);
      expect(find.byKey(const Key('conversation-context-menu')), findsNothing);
    });
  });
}
