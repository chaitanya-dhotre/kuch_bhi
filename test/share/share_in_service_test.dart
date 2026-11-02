// 12.1 B1–B7, F3: a share waits until the app can send, then opens the
// picker once; nothing is copied before a chat is chosen.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/router/app_router.dart';
import 'package:kuch_bhi/features/auth/providers/auth_provider.dart';
import 'package:kuch_bhi/features/auth/providers/encryption_sync_provider.dart';
import 'package:kuch_bhi/infrastructure/media/media_blob_store.dart';
import 'package:kuch_bhi/services/share_in_service.dart';

import 'share_harness.dart';

final _photo = shareMap([('image/jpeg', 'a.jpg')]);

void main() {
  testWidgets('cold start: clear, then take; the share waits on splash, '
      'nothing copied; home + keyOk opens Send to once', (tester) async {
    final h = await pumpShareApp(tester, share: _photo);
    await h.start();

    expect(h.methods, ['clearShared', 'takeShare']);
    expect(h.container.read(pendingShareProvider)?.items, hasLength(1));
    expect(find.text('Send to'), findsNothing);

    h.router.go(AppRoutes.home);
    await tester.pumpAndSettle();
    expect(find.text('Send to'), findsOneWidget);
    expect(find.text('1 photo'), findsOneWidget);
    expect(h.copies, 0, reason: 'no copy before a chat is tapped (D7)');

    // Another router notify must not stack a second picker.
    h.router.go(AppRoutes.home);
    await tester.pumpAndSettle();
    expect(find.text('Send to'), findsOneWidget);
  });

  testWidgets('no share at start → nothing pending, no picker', (tester) async {
    final h = await pumpShareApp(tester, initial: AppRoutes.home);
    await h.start();
    await tester.pumpAndSettle();
    expect(h.container.read(pendingShareProvider), isNull);
    expect(find.text('Send to'), findsNothing);
  });

  testWidgets('signed out: login toast once; after sign-in + keyOk the '
      'picker opens', (tester) async {
    final h = await pumpShareApp(
      tester,
      auth: const AuthUnauthenticated(),
      initial: AppRoutes.login,
      share: _photo,
    );
    await h.start();
    await tester.pump();
    expect(find.text('Sign in to share.'), findsOneWidget);

    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(seconds: 1)); // the toast times out
    }
    expect(find.text('Sign in to share.'), findsNothing);
    h.router.go(AppRoutes.register);
    await tester.pumpAndSettle();
    h.router.go(AppRoutes.login);
    await tester.pumpAndSettle();
    expect(find.text('Sign in to share.'), findsNothing, reason: 'once');

    h.auth.set(AuthAuthenticated(me));
    h.router.go(AppRoutes.home);
    await tester.pumpAndSettle();
    expect(find.text('Send to'), findsOneWidget);
  });

  testWidgets('key restore pending: no toast, picker only after keyOk',
      (tester) async {
    final h = await pumpShareApp(
      tester,
      initial: AppRoutes.backupPinRestore,
      share: _photo,
    );
    syncStatus = EncryptionSyncStatus.needsRestore;
    h.container.invalidate(encryptionSyncProvider);
    await tester.pump();
    await h.start();
    await tester.pumpAndSettle();
    expect(find.text('Sign in to share.'), findsNothing);
    expect(find.text('Send to'), findsNothing);

    // Home while the key is still loading: wait.
    syncStatus = null;
    h.container.invalidate(encryptionSyncProvider);
    h.router.go(AppRoutes.home);
    await tester.pump();
    await tester.pump();
    expect(find.text('Send to'), findsNothing);

    syncStatus = EncryptionSyncStatus.keyOk;
    h.container.invalidate(encryptionSyncProvider);
    await tester.pumpAndSettle();
    expect(find.text('Send to'), findsOneWidget);
  });

  testWidgets('a second share replaces a waiting one, and an open picker '
      'shows the newer one', (tester) async {
    final h = await pumpShareApp(
      tester,
      auth: const AuthUnauthenticated(),
      initial: AppRoutes.login,
      share: _photo,
    );
    await h.start();
    await h.arrive(shareMap([('application/pdf', 'a.pdf'), ('text/csv', 'b')]));
    expect(h.container.read(pendingShareProvider)?.items, hasLength(2));

    h.auth.set(AuthAuthenticated(me));
    h.router.go(AppRoutes.home);
    await tester.pumpAndSettle();
    expect(find.text('2 files'), findsOneWidget);

    await h.arrive(shareMap([], text: 'https://example.com/trip'));
    await tester.pumpAndSettle();
    expect(find.text('Link'), findsOneWidget);
    expect(find.text('Send to'), findsOneWidget, reason: 'still one picker');
  });

  testWidgets('all unreadable, no text → toast, no picker', (tester) async {
    final h = await pumpShareApp(
      tester,
      initial: AppRoutes.home,
      share: shareMap([]),
    );
    await h.start();
    await tester.pumpAndSettle();
    expect(find.text("Couldn't open what was shared."), findsOneWidget);
    expect(find.text('Send to'), findsNothing);
    expect(h.container.read(pendingShareProvider), isNull);
  });

  testWidgets('only a known over-100 MB item → too-big toast, no picker',
      (tester) async {
    final big = shareMap([('video/mp4', 'big.mp4')]);
    ((big['items']! as List).single as Map)['size'] = 150 * 1024 * 1024;
    final h = await pumpShareApp(tester, initial: AppRoutes.home, share: big);
    await h.start();
    await tester.pumpAndSettle();
    expect(find.text('Too big to send. The limit is 100 MB.'), findsOneWidget);
    expect(find.text('Send to'), findsNothing);
    expect(h.copies, 0);
  });

  testWidgets('✕ drops the share and clears share_in/ (D11)', (tester) async {
    final h = await pumpShareApp(
      tester,
      initial: AppRoutes.home,
      share: _photo,
    );
    await h.start();
    await tester.pumpAndSettle();
    h.calls.clear();
    await tester.tap(find.byTooltip('Cancel sharing'));
    await tester.pumpAndSettle();
    expect(find.text('Send to'), findsNothing);
    expect(find.text('at /home'), findsOneWidget);
    expect(h.methods, ['clearShared']);
    expect(h.container.read(pendingShareProvider), isNull);
  });

  testWidgets('logout drops a waiting share', (tester) async {
    final h = await pumpShareApp(
      tester,
      initial: AppRoutes.backupPinRestore,
      share: _photo,
    );
    syncStatus = EncryptionSyncStatus.needsRestore;
    h.container.invalidate(encryptionSyncProvider);
    await h.start();
    expect(h.container.read(pendingShareProvider), isNotNull);

    h.auth.set(const AuthUnauthenticated());
    await tester.pump();
    expect(h.container.read(pendingShareProvider), isNull);
  });

  test('logout wipe also deletes share_in/ (F3)', () async {
    final parent = await Directory.systemTemp.createTemp('share_wipe');
    addTearDown(() => parent.delete(recursive: true));
    final copy = File('${parent.path}/share_in/1/report.pdf')
      ..createSync(recursive: true);
    final keep = File('${parent.path}/other/x')..createSync(recursive: true);
    await wipeMediaCache(() async => parent);
    expect(copy.parent.parent.existsSync(), isFalse);
    expect(keep.existsSync(), isTrue);
  });
}
