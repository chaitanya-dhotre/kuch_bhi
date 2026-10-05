import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/core/widgets/app_toast.dart';
import 'package:kuch_bhi/core/widgets/empty_state.dart';
import 'package:kuch_bhi/core/widgets/settings_tile.dart';
import 'package:kuch_bhi/core/widgets/skeleton.dart';
import 'package:kuch_bhi/core/widgets/status_banner.dart';
import 'package:kuch_bhi/features/mascot/capybara.dart';

Widget host(Widget child) => MaterialApp(
    theme: warmPopLight(), home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('empty state carries the mascot + copy', (tester) async {
    await tester.pumpWidget(host(
        const EmptyState(title: 'No chats yet', subtitle: 'Add a friend')));
    expect(find.byType(Capybara), findsOneWidget);
    expect(find.text('No chats yet'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('banner + tile render; skeleton survives reduced motion',
      (tester) async {
    await tester.pumpWidget(host(const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusBanner(message: 'Offline'),
          SettingsTile(icon: Icons.settings, title: 'Settings'),
        ])));
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    await tester.pumpWidget(MaterialApp(
        theme: warmPopLight(),
        home: Scaffold(
            body: Center(
                child: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [Skeleton(height: 20)]))))));
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty state accepts a custom mascot slot', (tester) async {
    await tester.pumpWidget(host(const EmptyState(
        title: 'No chats yet', mascot: Text('custom-mascot'))));
    expect(find.text('custom-mascot'), findsOneWidget);
    expect(find.byType(Capybara), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('showToast surfaces the message', (tester) async {
    await tester.pumpWidget(host(const SizedBox()));
    final ctx = tester.element(find.byType(Scaffold));
    showToast(ctx, 'Invite sent');
    await tester.pump();
    expect(find.text('Invite sent'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpWidget(const SizedBox());
  });
}
