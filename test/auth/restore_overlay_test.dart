import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/domain/repositories/message_repository.dart';
import 'package:kuch_bhi/features/auth/screens/backup_pin_screen.dart';
import 'package:kuch_bhi/features/mascot/capy.dart';
import 'package:kuch_bhi/features/settings/providers/font_provider.dart';
import 'package:kuch_bhi/features/settings/providers/notification_status_provider.dart';
import 'package:kuch_bhi/features/settings/providers/theme_provider.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';
import 'package:kuch_bhi/services/encryption_service.dart';

import '../fakes/fake_message_repository.dart';
import '../mascot/capy_test.dart' show FakeSource;

class _Enc implements EncryptionService {
  _Enc([this.gate]);

  /// Holds the key check open so the overlay shows `deriving`.
  final Completer<void>? gate;
  @override
  Future<RestoreResult> restorePrivateKey(String pin) async {
    await gate?.future;
    return RestoreResult.restored;
  }
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
    {bool narrow = false, bool reduceMotion = false,
    Completer<void>? keyGate}) async {
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
      encryptionServiceProvider.overrideWithValue(_Enc(keyGate)),
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
  await tester.enterText(find.byType(TextField), '123456');
  await tester.pump();
  await tester.ensureVisible(find.text('Restore'));
  await tester.tap(find.text('Restore'));
  await tester.pump();
  await tester.pump();
  // K1b: past the key check the card shows once the capybara has docked.
  if (keyGate == null) {
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump(const Duration(milliseconds: 500));
  }
  return (sync, theme);
}

Future<FakeSource> _fakeCapys() async {
  final capys = FakeSource();
  CapyLoader.debugSource = capys;
  addTearDown(() => CapyLoader.debugSource = null);
  return capys;
}

Size _capySize(WidgetTester tester) => tester.getSize(find.byType(Capy));

HistorySyncProgress _at(int conv, int msg) => HistorySyncProgress(
      phase: HistorySyncPhase.downloadingMessages,
      conversationIndex: conv,
      conversationCount: 12,
      messageCurrent: msg,
      messageTotal: 3100,
    );

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

  // Bug wave 2 §3.1: the history sync outlives the screen (a redirect or the
  // back gesture can pop it); its progress ticks must not touch a disposed
  // State.
  testWidgets('progress after the screen is gone throws nothing',
      (tester) async {
    final (sync, _) = await _startRestore(tester);
    await tester.pumpWidget(const SizedBox());
    sync.progress!(_p);
    sync.progress!(const HistorySyncProgress(phase: HistorySyncPhase.complete));
    sync.done.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  test('restoreCapy: guard + focused while checking, happy toss, then the '
      'vault: active, happy when ready', () {
    for (final p in [RestorePhase.idle, RestorePhase.deriving]) {
      expect(restoreCapy(p, docked: false), (CapyPose.guard, CapyMood.focused));
    }
    expect(restoreCapy(RestorePhase.finalisingKey, docked: false),
        (CapyPose.guard, CapyMood.happy));
    for (final p in [
      RestorePhase.finalisingKey,
      RestorePhase.fetchingConvs,
      RestorePhase.downloadingMsgs,
      RestorePhase.decrypting,
    ]) {
      expect(restoreCapy(p, docked: true), (CapyPose.vault, CapyMood.active));
    }
    expect(restoreCapy(RestorePhase.ready, docked: true),
        (CapyPose.vault, CapyMood.happy));
  });

  testWidgets('K1b: centre check, one toss, dock after 1 s, envelopes only '
      'while the counts move', (tester) async {
    final capys = await _fakeCapys();
    final keyGate = Completer<void>();
    final (sync, _) = await _startRestore(tester, keyGate: keyGate);
    final rig = capys.rigs.single;
    expect(capys.views.single, CapyView.front);
    expect(rig.bools['still'], isFalse);
    expect((rig.pose, rig.mood), (CapyPose.guard, CapyMood.focused));
    expect(_capySize(tester), const Size(200, 200));
    expect(find.text('Checking your key…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing,
        reason: 'the card comes with the dock (decision 7)');
    expect(find.text('While you wait'), findsNothing);

    keyGate.complete();
    await tester.pump();
    await tester.pump();
    expect(rig.fired, ['tossKey']);
    expect((rig.pose, rig.mood), (CapyPose.guard, CapyMood.happy));
    sync.progress!(_at(3, 410));
    await tester.pump();
    expect(rig.fired, ['tossKey'], reason: 'no envelopes before the dock');

    await tester.pump(const Duration(milliseconds: 1000));
    expect((rig.pose, rig.mood), (CapyPose.vault, CapyMood.active));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    expect(_capySize(tester), const Size(120, 120));

    await tester.pump(const Duration(milliseconds: 1600));
    expect(rig.fired, ['tossKey'], reason: 'counts still: it waits');
    sync.progress!(_at(3, 900));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1600));
    expect(rig.fired, ['tossKey', 'envelope']);
    sync.progress!(_at(4, 1200));
    sync.progress!(_at(5, 1500));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1600));
    expect(rig.fired, ['tossKey', 'envelope', 'envelope'],
        reason: 'a pace, never a backlog');
    await tester.pump(const Duration(milliseconds: 3200));
    expect(rig.fired.where((f) => f == 'envelope').length, 2);

    sync.progress!(const HistorySyncProgress(phase: HistorySyncPhase.complete));
    await tester.pump();
    expect(rig.mood, CapyMood.happy);
    sync.progress!(_at(12, 3100));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 3200));
    expect(rig.fired.where((f) => f == 'envelope').length, 2,
        reason: 'none after ready');
    expect(rig.fired.where((f) => f == 'tossKey').length, 1);
    sync.done.complete();
    await tester.pumpAndSettle();
    expect(find.text('page:/home'), findsOneWidget);
  });

  testWidgets('K1b: an overlay first shown past the key check starts docked, '
      'no toss', (tester) async {
    final capys = await _fakeCapys();
    // No gate: the key check resolves before the overlay's first frame, as
    // after the legacy-PIN upgrade (§I1 late mount).
    final (sync, _) = await _startRestore(tester);
    final rig = capys.rigs.single;
    expect(rig.fired, isEmpty);
    expect(rig.pose, CapyPose.vault);
    expect(_capySize(tester), const Size(120, 120));
    sync.done.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('K1b reduced motion: the dock is a cut, no envelopes',
      (tester) async {
    final capys = await _fakeCapys();
    final keyGate = Completer<void>();
    final (sync, _) =
        await _startRestore(tester, keyGate: keyGate, reduceMotion: true);
    final rig = capys.rigs.single;
    keyGate.complete();
    await tester.pump();
    await tester.pump();
    expect(rig.mood, CapyMood.happy, reason: 'same 1 s beat, the rig is still');
    await tester.pump(const Duration(milliseconds: 1000));
    expect(_capySize(tester), const Size(120, 120), reason: 'no in-between');
    expect(rig.pose, CapyPose.vault);
    sync.progress!(_at(3, 410));
    await tester.pump(const Duration(milliseconds: 1600));
    sync.progress!(_at(4, 900));
    await tester.pump(const Duration(milliseconds: 3200));
    expect(rig.fired.contains('envelope'), isFalse);
    sync.done.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('K1b: 360dp x 200% text, check stage and docked: no overflow',
      (tester) async {
    await _fakeCapys();
    final keyGate = Completer<void>();
    final (sync, _) =
        await _startRestore(tester, narrow: true, keyGate: keyGate);
    expect(tester.takeException(), isNull);
    keyGate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull, reason: 'mid-slide');
    await tester.pump(const Duration(milliseconds: 300));
    sync.progress!(_p);
    await tester.pump();
    expect(tester.takeException(), isNull);
    sync.done.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('K1b: a header in both stages', (tester) async {
    final keyGate = Completer<void>();
    final (sync, _) = await _startRestore(tester, keyGate: keyGate);
    final handle = tester.ensureSemantics();
    expect(tester.getSemantics(find.text('Unlocking your chats')),
        isSemantics(isHeader: true, label: 'Unlocking your chats'));
    keyGate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('Unlocking your chats'), findsOneWidget);
    handle.dispose();
    sync.done.complete();
    await tester.pumpAndSettle();
  });
}
