import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/domain/repositories/message_repository.dart';
import 'package:kuch_bhi/features/auth/screens/backup_pin_screen.dart';
import 'package:kuch_bhi/features/settings/providers/font_provider.dart';
import 'package:kuch_bhi/features/settings/providers/notification_status_provider.dart';
import 'package:kuch_bhi/features/settings/providers/theme_provider.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';
import 'package:kuch_bhi/services/encryption_service.dart';

import '../fakes/fake_message_repository.dart';

class _Enc implements EncryptionService {
  @override
  Future<bool> restorePrivateKey(String pin) async => true;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// syncAllHistory reports through [progress] and finishes on [done].
class _Sync extends FakeMessageRepository {
  void Function(HistorySyncProgress)? progress;
  final done = Completer<void>();
  @override
  Future<void> syncAllHistory(
      {void Function(HistorySyncProgress)? onProgress}) {
    progress = onProgress;
    return done.future;
  }
}

class _Theme implements ThemeController {
  final calls = <AppThemeMode>[];
  @override
  Future<void> setTheme(AppThemeMode mode) async => calls.add(mode);
  @override
  Future<AppThemeMode> current() async => AppThemeMode.system;
}

class _Font implements FontController {
  @override
  Future<void> setFont(AppFont font) async {}
}

Future<(_Sync, _Theme)> _startRestore(WidgetTester tester,
    {bool narrow = false, bool reduceMotion = false}) async {
  if (narrow) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }
  final sync = _Sync();
  final theme = _Theme();
  final router = GoRouter(routes: [
    GoRoute(
        path: '/',
        builder: (_, __) => const BackupPinScreen(mode: BackupPinMode.restore)),
    GoRoute(path: '/home', builder: (_, __) => const Text('page:/home')),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      encryptionServiceProvider.overrideWithValue(_Enc()),
      messageRepositoryProvider.overrideWithValue(sync),
      themeModeProvider.overrideWith((ref) => Stream.value(AppThemeMode.system)),
      themeControllerProvider.overrideWithValue(theme),
      fontFamilyProvider.overrideWith((ref) => Stream.value(AppFont.system)),
      fontControllerProvider.overrideWithValue(_Font()),
      notificationsEnabledProvider.overrideWith((ref) async => true),
      openSystemSettingsProvider.overrideWithValue(() async => true),
    ],
    child: MaterialApp.router(
      theme: warmPopLight(),
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(narrow ? 2 : 1),
            disableAnimations: reduceMotion),
        child: child!,
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 400));
  for (var i = 0; i < 6; i++) {
    await tester.enterText(find.byType(TextField).at(i), '${i + 1}');
  }
  await tester.pump();
  await tester.ensureVisible(find.text('Restore'));
  await tester.tap(find.text('Restore'));
  await tester.pump();
  await tester.pump();
  return (sync, theme);
}

const _p = HistorySyncProgress(
  phase: HistorySyncPhase.downloadingMessages,
  conversationIndex: 3,
  conversationCount: 12,
  messageCurrent: 410,
  messageTotal: 3100,
);

void main() {
  testWidgets('card counts the real progress; bar carries its value',
      (tester) async {
    final (sync, _) = await _startRestore(tester);
    expect(find.text('Unlocking your chats'), findsOneWidget);
    sync.progress!(_p);
    await tester.pump();
    expect(find.text('3 of 12 chats · 410 of 3,100 messages'), findsOneWidget);
    expect(find.text('Keep the app open. This takes a minute or two.'),
        findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator));
    expect(bar.value, .25);
    final handle = tester.ensureSemantics();
    expect(tester.getSemantics(find.byType(LinearProgressIndicator)),
        isSemantics(value: '25%'));
    handle.dispose();
    sync.done.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('While you wait: theme rows, font, notifications; Dark mid-'
      'restore writes once and the restore still reaches home',
      (tester) async {
    final (sync, theme) = await _startRestore(tester);
    expect(find.text('While you wait'), findsOneWidget);
    for (final m in AppThemeMode.values) {
      expect(find.text(m.label), findsWidgets);
    }
    expect(find.text('Plus Jakarta Sans'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    sync.progress!(_p);
    await tester.pump();
    await tester.tap(find.text('Dark'));
    await tester.pump();
    expect(theme.calls, [AppThemeMode.dark]);
    expect(sync.done.isCompleted, isFalse, reason: 'no restart, no wait');
    sync.progress!(const HistorySyncProgress(phase: HistorySyncPhase.complete));
    await tester.pump();
    expect(find.text('Your chats are ready'), findsOneWidget);
    sync.done.complete();
    await tester.pumpAndSettle();
    expect(find.text('page:/home'), findsOneWidget);
  });

  testWidgets('reduced motion parks the indeterminate bar at 30%',
      (tester) async {
    final (sync, _) = await _startRestore(tester, reduceMotion: true);
    final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator));
    expect(bar.value, .3);
    sync.done.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('360dp x 200% text: no overflow', (tester) async {
    final (sync, _) = await _startRestore(tester, narrow: true);
    sync.progress!(_p);
    await tester.pump();
    expect(tester.takeException(), isNull);
    sync.done.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('J6: one chat still announces message counts; parked bar '
      'says In progress', (tester) async {
    final (sync, _) = await _startRestore(tester, reduceMotion: true);
    final handle = tester.ensureSemantics();
    expect(tester.getSemantics(find.byType(LinearProgressIndicator)),
        isSemantics(value: 'In progress'));
    sync.progress!(const HistorySyncProgress(
        phase: HistorySyncPhase.downloadingMessages,
        conversationIndex: 1,
        conversationCount: 1,
        messageCurrent: 410,
        messageTotal: 3100));
    await tester.pump();
    expect(find.bySemanticsLabel('1 of 1 chats · 410 of 3,100 messages'),
        findsOneWidget);
    handle.dispose();
    sync.done.complete();
    await tester.pumpAndSettle();
  });
}
