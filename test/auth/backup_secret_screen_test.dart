import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/core/utils/recovery_key.dart';
import 'package:kuch_bhi/core/widgets/app_button.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/domain/entities/user.dart';
import 'package:kuch_bhi/domain/repositories/message_repository.dart';
import 'package:kuch_bhi/features/auth/providers/auth_provider.dart';
import 'package:kuch_bhi/features/auth/screens/backup_pin_screen.dart';
import 'package:kuch_bhi/features/settings/providers/font_provider.dart';
import 'package:kuch_bhi/features/settings/providers/notification_status_provider.dart';
import 'package:kuch_bhi/features/settings/providers/theme_provider.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';
import 'package:kuch_bhi/services/encryption_service.dart';
import 'package:pocketbase/pocketbase.dart' show ClientException;

import '../fakes/fake_message_repository.dart';

/// Records every backup / restore call; results and errors are settable.
class _Enc implements EncryptionService {
  final calls = <String>[];
  RestoreResult restoreResult = RestoreResult.restored;
  Object? restoreError;
  Object? saveError;
  Completer<void>? hold;

  Future<void> _save(String what) async {
    calls.add(what);
    await hold?.future;
    if (saveError != null) throw saveError!;
  }

  @override
  Future<RestoreResult> restorePrivateKey(String secret) async {
    calls.add('restore:$secret');
    if (restoreError != null) throw restoreError!;
    return restoreResult;
  }

  bool hasKey = true;
  @override
  Future<bool> hasLocalPrivateKey() async => hasKey;
  @override
  Future<void> backupPrivateKey(String key) => _save('backup:$key');
  @override
  Future<void> backupOrCreateKey(String pin) => _save('setup:$pin');
  @override
  Future<void> generateAndBackupNewKey(String pin) => _save('fresh:$pin');
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Sync extends FakeMessageRepository {
  int syncs = 0;
  @override
  Future<void> syncAllHistory({
    void Function(HistorySyncProgress)? onProgress,
    ConnectivitySignal? net,
  }) async {
    syncs++;
  }
}

class _Auth extends AuthNotifier {
  @override
  Future<AuthState> build() async => AuthAuthenticated(
    User(
      id: 'u_test',
      displayName: 'Test',
      username: 'test',
      email: 'test@example.com',
      friendCode: 'FRIEND1',
      createdAt: DateTime.utc(2026, 1, 1),
    ),
  );
}

class _Theme implements ThemeController {
  @override
  Future<void> setTheme(AppThemeMode mode) async {}
  @override
  Future<AppThemeMode> current() async => AppThemeMode.system;
}

class _Font implements FontController {
  @override
  Future<void> setFont(AppFont font) async {}
}

const _clipChannel = MethodChannel('kuch_bhi/clipboard');

final _group = RegExp(r'^[0-9A-HJKMNP-TV-Z]{5}$');

class _Screen {
  _Screen(this.tester, this.enc, this.sync, this.router);
  final WidgetTester tester;
  final _Enc enc;
  final _Sync sync;
  final GoRouter router;
  String? clip;
  final native = <String>[];

  List<String> get groups => tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data)
      .whereType<String>()
      .where(_group.hasMatch)
      .toList();
  String get key => groups.join();

  bool enabled(String label) =>
      tester
          .widget<AppButton>(find.widgetWithText(AppButton, label))
          .onPressed !=
      null;

  Future<void> tap(String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> type(String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
  }

  List<String> get visibleText => tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
      .toList();
}

Future<_Screen> _pump(
  WidgetTester tester,
  BackupPinMode mode, {
  bool online = true,
  bool narrow = false,
  bool reduceMotion = false,
  bool optional = false,
}) async {
  if (narrow) {
    tester.view.physicalSize = const Size(1080, 1920); // 360×640dp
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }
  final enc = _Enc();
  final sync = _Sync();
  final screen = BackupPinScreen(mode: mode, isOptionalSetup: optional);
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => mode == BackupPinMode.change
            ? const Scaffold(body: Text('page:/profile'))
            : screen,
        routes: [GoRoute(path: 'change', builder: (_, __) => screen)],
      ),
      GoRoute(
        path: '/home',
        builder: (_, __) => const Scaffold(body: Text('page:/home')),
      ),
    ],
  );
  final db = AppDatabase.test();
  addTearDown(db.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        encryptionServiceProvider.overrideWithValue(enc),
        messageRepositoryProvider.overrideWithValue(sync),
        authProvider.overrideWith(_Auth.new),
        appDatabaseProvider.overrideWithValue(db),
        isOnlineProvider.overrideWith((ref) => Stream.value(online)),
        themeModeProvider.overrideWith(
          (ref) => Stream.value(AppThemeMode.system),
        ),
        themeControllerProvider.overrideWithValue(_Theme()),
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
            disableAnimations: reduceMotion,
          ),
          child: child!,
        ),
      ),
    ),
  );
  final s = _Screen(tester, enc, sync, router);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        s.clip = (call.arguments as Map)['text'] as String?;
      }
      if (call.method == 'Clipboard.getData') {
        return s.clip == null ? null : {'text': s.clip};
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  // MainActivity's side of the recovery-key clipboard channel.
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_clipChannel, (
    call,
  ) async {
    s.native.add(call.method);
    if (call.method == 'copySensitive') {
      s.clip = (call.arguments as Map)['text'] as String?;
    }
    if (call.method == 'clear') s.clip = '';
    return null;
  });
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _clipChannel,
      null,
    ),
  );
  if (mode == BackupPinMode.change) router.push('/change');
  await tester.pumpAndSettle();
  return s;
}

void main() {
  testWidgets('key step: 5 groups, read out character by character', (t) async {
    final s = await _pump(t, BackupPinMode.setup);
    expect(find.text('Save your recovery key'), findsOneWidget);
    expect(s.groups, hasLength(5));
    expect(parseRecoveryKey(s.key), s.key);
    final handle = t.ensureSemantics();
    final g = s.groups;
    expect(
      find.bySemanticsLabel(
        g.map((x) => x.split('').join(', ')).join(', then '),
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('Copy puts the grouped key on the clipboard + toast', (t) async {
    final s = await _pump(t, BackupPinMode.setup);
    await s.tap('Copy');
    expect(s.clip, formatRecoveryKey(s.key));
    expect(find.text('Recovery key copied.'), findsOneWidget);
  });

  testWidgets('check step: Turn on backup only on the shown key; mismatch '
      'copy; Show the key again keeps the key', (t) async {
    final s = await _pump(t, BackupPinMode.setup);
    final key = s.key;
    await s.tap("I've saved it");
    expect(find.text('Check your recovery key'), findsOneWidget);
    expect(s.enabled('Turn on backup'), isFalse);

    await s.type(key.substring(0, 20));
    expect(s.enabled('Turn on backup'), isFalse);
    expect(find.text(kKeyMismatchCopy), findsNothing);

    await s.type(generateRecoveryKey());
    expect(find.text(kKeyMismatchCopy), findsOneWidget);
    expect(s.enabled('Turn on backup'), isFalse);

    await s.type(recoveryKeyGroups(key).join(' ').toLowerCase());
    expect(find.text(kKeyMismatchCopy), findsNothing);
    expect(s.enabled('Turn on backup'), isTrue);

    await s.tap('Show the key again');
    expect(s.key, key);
    expect(s.enc.calls, isEmpty);
  });

  testWidgets('setup save: one backup call, clipboard cleared, Home', (
    t,
  ) async {
    final s = await _pump(t, BackupPinMode.setup);
    final key = s.key;
    await s.tap('Copy');
    await s.tap("I've saved it");
    await s.type(formatRecoveryKey(key));
    await s.tap('Turn on backup');
    expect(s.enc.calls, ['setup:$key']);
    expect(s.clip, '');
    expect(find.text('page:/home'), findsOneWidget);
    expect(find.text('Backup is on.'), findsOneWidget);
  });

  testWidgets('Copy goes through the sensitive-flag channel; the save '
      'clears it natively', (t) async {
    final s = await _pump(t, BackupPinMode.setup);
    final key = s.key;
    await s.tap('Copy');
    expect(s.native, ['copySensitive']);
    await s.tap("I've saved it");
    await s.type(key);
    await s.tap('Turn on backup');
    expect(s.native, ['copySensitive', 'clear']);
  });

  testWidgets('a clipboard that no longer holds the key is left alone', (
    t,
  ) async {
    final s = await _pump(t, BackupPinMode.setup);
    final key = s.key;
    await s.tap("I've saved it");
    s.clip = 'something else';
    await s.type(key);
    await s.tap('Turn on backup');
    expect(s.clip, 'something else');
  });

  testWidgets('optional setup: prefix line and Skip for now', (t) async {
    final s = await _pump(t, BackupPinMode.setup, optional: true);
    expect(
      find.text('Set up a recovery key to protect your messages.'),
      findsOneWidget,
    );
    await s.tap('Skip for now');
    expect(find.text('page:/home'), findsOneWidget);
    expect(s.enc.calls, isEmpty);
  });

  testWidgets('restore: malformed input → C6 copy, no call', (t) async {
    final s = await _pump(t, BackupPinMode.restore);
    expect(s.enabled('Restore'), isFalse);
    await s.type('7KQ2M-9XHMA-4TRBC-8D1WZ-P6YV'); // 24
    expect(s.enabled('Restore'), isTrue);
    await s.tap('Restore');
    expect(find.text(kMalformedKeyCopy), findsOneWidget);
    expect(s.enc.calls, isEmpty);
  });

  testWidgets('restore: wrongSecret keeps the field; each result has its '
      'own copy; no Exception or \$ on screen', (t) async {
    final s = await _pump(t, BackupPinMode.restore);
    const typed = '7kq2m 9xhma 4trbc 8d1wz p6yvn';
    await s.type(typed);
    s.enc.restoreResult = RestoreResult.wrongSecret;
    await s.tap('Restore');
    expect(find.text(kWrongSecretCopy), findsOneWidget);
    expect(find.text(typed), findsOneWidget);
    expect(s.enc.calls, ['restore:${typed.trim()}']);

    final cases = <Object, String>{
      RestoreResult.noBackup: kNoBackupCopy,
      RestoreResult.unsupported: kUnsupportedBackupCopy,
      ClientException():
          "Can't reach the server. Check your connection and "
          'try again.',
      Exception(r'boom $x'): "Couldn't restore your messages. Try again.",
    };
    for (final MapEntry(key: c, value: copy) in cases.entries) {
      if (c is RestoreResult) {
        s.enc
          ..restoreResult = c
          ..restoreError = null;
      } else {
        s.enc.restoreError = c;
      }
      await s.tap('Restore');
      expect(find.text(copy), findsOneWidget, reason: '$c');
      for (final text in s.visibleText) {
        expect(
          text.contains('Exception') || text.contains(r'$'),
          isFalse,
          reason: text,
        );
      }
    }
  });

  testWidgets('legacy PIN: upgrade step; Not now syncs with no backup call', (
    t,
  ) async {
    final s = await _pump(t, BackupPinMode.restore);
    s.enc.restoreResult = RestoreResult.restoredLegacy;
    await s.type('123456');
    await s.tap('Restore');
    expect(find.text('Make your backup stronger'), findsOneWidget);
    expect(s.sync.syncs, 0, reason: 'the sync waits for the upgrade step');
    await s.tap('Not now');
    expect(s.sync.syncs, 1);
    expect(s.enc.calls, ['restore:123456']);
    expect(find.text('page:/home'), findsOneWidget);
  });

  testWidgets('legacy PIN: system back on the upgrade step = Not now', (
    t,
  ) async {
    final s = await _pump(t, BackupPinMode.restore);
    s.enc.restoreResult = RestoreResult.restoredLegacy;
    await s.type('123456');
    await s.tap('Restore');
    expect(find.text('123456'), findsNothing, reason: 'PIN cleared');
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(s.sync.syncs, 1);
    expect(find.text('page:/home'), findsOneWidget);
  });

  testWidgets('setup that wrote nothing claims no saved key', (t) async {
    final s = await _pump(t, BackupPinMode.setup);
    s.enc.hasKey = false;
    final key = s.key;
    await s.tap('Copy');
    await s.tap("I've saved it");
    await s.type(key);
    await s.tap('Turn on backup');
    expect(find.text('Backup is on.'), findsNothing);
    expect(s.clip, formatRecoveryKey(key));
  });

  testWidgets('legacy PIN: upgrade save = one backup call, then the sync', (
    t,
  ) async {
    final s = await _pump(t, BackupPinMode.restore);
    s.enc.restoreResult = RestoreResult.restoredLegacy;
    await s.type('123456');
    await s.tap('Restore');
    final key = s.key;
    await s.tap("I've saved it");
    await s.type(key);
    await s.tap('Turn on backup');
    expect(s.enc.calls, ['restore:123456', 'backup:$key']);
    expect(s.sync.syncs, 1);
    expect(find.text('page:/home'), findsOneWidget);
  });

  testWidgets('change never restores; a guard refusal shows its copy, the '
      'retry with the same key works', (t) async {
    final s = await _pump(t, BackupPinMode.change);
    expect(find.text('Recovery key'), findsOneWidget); // app bar
    await s.tap('Make a new key');
    expect(find.text('Your new recovery key'), findsOneWidget);
    final key = s.key;
    await s.tap("I've saved it");
    await s.type(key);
    s.enc.saveError = const KeyMismatchException();
    await s.tap('Turn on backup');
    expect(
      find.text(
        "This phone's key isn't your account's current key, so "
        "your backup wasn't changed.",
      ),
      findsOneWidget,
    );
    s.enc.saveError = null;
    await s.tap('Turn on backup');
    expect(s.enc.calls, ['backup:$key', 'backup:$key']);
    expect(s.enc.calls.where((c) => c.startsWith('restore')), isEmpty);
    expect(find.text('page:/profile'), findsOneWidget);
    expect(find.text('New recovery key saved.'), findsOneWidget);
  });

  testWidgets('Start Fresh makes the key pair only after the check step', (
    t,
  ) async {
    final s = await _pump(t, BackupPinMode.restore);
    await s.tap('I lost it');
    expect(find.text('Start fresh?'), findsOneWidget);
    await s.tap('Start fresh');
    expect(
      find.text('Start fresh: save your new recovery key'),
      findsOneWidget,
    );
    final key = s.key;
    await s.tap("I've saved it");
    expect(s.enc.calls, isEmpty);
    await s.type(key);
    await s.tap('Turn on backup');
    expect(s.enc.calls, ['fresh:$key']);
  });

  testWidgets('offline: the key step works; save and restore are disabled '
      'with Available online; fields stay editable', (t) async {
    final s = await _pump(t, BackupPinMode.setup, online: false);
    expect(s.enabled('Copy'), isTrue);
    final key = s.key;
    await s.tap("I've saved it");
    await s.type(key);
    expect(find.text(key), findsOneWidget);
    expect(s.enabled('Turn on backup'), isFalse);
    expect(find.text('Available online'), findsOneWidget);

    final r = await _pump(t, BackupPinMode.restore, online: false);
    await r.type('123456');
    expect(r.enabled('Restore'), isFalse);
    expect(r.enabled('I lost it'), isTrue);
    expect(find.text('Available online'), findsOneWidget);
  });

  testWidgets('360dp at 200% text: key, check, restore, upgrade, change '
      'with no overflow', (t) async {
    final s = await _pump(t, BackupPinMode.setup, narrow: true);
    expect(t.takeException(), isNull);
    await s.tap("I've saved it");
    expect(t.takeException(), isNull);

    final r = await _pump(t, BackupPinMode.restore, narrow: true);
    expect(t.takeException(), isNull);
    r.enc.restoreResult = RestoreResult.restoredLegacy;
    await r.type('123456');
    await r.tap('Restore');
    expect(find.text('Make your backup stronger'), findsOneWidget);
    expect(t.takeException(), isNull);

    final c = await _pump(t, BackupPinMode.change, narrow: true);
    expect(t.takeException(), isNull);
    await c.tap('Make a new key');
    expect(t.takeException(), isNull);
  });

  testWidgets('reduced motion: the saving card pulse is parked', (t) async {
    final s = await _pump(t, BackupPinMode.change, reduceMotion: true);
    await s.tap('Make a new key');
    final key = s.key;
    await s.tap("I've saved it");
    await s.type(key);
    s.enc.hold = Completer(); // the saving card stays up
    await t.tap(find.text('Turn on backup'));
    await t.pump();
    // Past the one-off ripple / field transitions: nothing loops.
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Locking your backup…'), findsOneWidget);
    expect(t.hasRunningAnimations, isFalse);
    s.enc.hold!.complete();
    await t.pumpAndSettle();
  });
}
