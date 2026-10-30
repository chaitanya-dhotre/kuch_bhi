import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/local/database/app_database.dart';
import '../../../infrastructure/offline/connectivity_signal.dart';
import '../../../services/encryption_service.dart';
import 'auth_provider.dart';

enum EncryptionSyncStatus {
  keyOk,
  needsSetup,
  needsRestore,
}

/// Pause between the no-key route's backup checks the server did not
/// answer (K3). Tests set it to zero.
@visibleForTesting
Duration backupCheckRetryDelay = const Duration(seconds: 2);

final encryptionSyncProvider = FutureProvider<EncryptionSyncStatus>((ref) async {
  final authState = ref.watch(authProvider).valueOrNull;
  if (authState is! AuthAuthenticated) {
    return EncryptionSyncStatus.keyOk;
  }

  final user = authState.user;
  final enc = ref.read(encryptionServiceProvider);
  final db = ref.read(appDatabaseProvider);

  // 1. Check local key
  final hasLocal = await enc.hasLocalPrivateKey();
  if (!hasLocal) {
    // Reinstall or keyless new account. Unknown is not "no backup" (K3):
    // keep the splash up and re-check through a blip. If the server never
    // answers, Restore is the safe screen — it writes nothing unless the user
    // picks Start Fresh, which is also a new account's way out.
    for (var attempt = 0; attempt < 5; attempt++) {
      if (attempt > 0) await Future<void>.delayed(backupCheckRetryDelay);
      final hasBackup = await enc.tryHasPocketBaseBackup(user.id);
      if (hasBackup != null) {
        return hasBackup
            ? EncryptionSyncStatus.needsRestore
            : EncryptionSyncStatus.needsSetup;
      }
    }
    return EncryptionSyncStatus.needsRestore;
  }

  // 2. Local key exists. Check if backup exists on server — TRI-STATE (P6):
  // an unreachable server is "unknown", not "no backup". A local key means
  // the user can already decrypt offline; only a CONFIRMED absent backup may
  // route into the setup flow.
  // No backup on server: setup is due unless the user skipped it < 7 days ago.
  Future<bool> setupDue() async {
    final skippedStr = await db.settingsDao.getSetting('pin_backup_skipped');
    if (skippedStr != 'true') return true;
    final skippedAtStr =
        await db.settingsDao.getSetting('pin_backup_skipped_at');
    final skippedAt =
        skippedAtStr == null ? null : DateTime.tryParse(skippedAtStr);
    return skippedAt == null || DateTime.now().difference(skippedAt).inDays >= 7;
  }

  final hasBackup = await enc.tryHasPocketBaseBackup(user.id);
  if (hasBackup == null) {
    // Offline / server down: local key stands on its own (user report
    // 2026-10-11 — offline cold start must not ask a set-up user to set up).
    // K3: once back online, re-route only if setup turns out to be due (a
    // new account registered offline); a re-run on every reconnect would
    // bounce users out of an open chat through the splash.
    _recheckOnReconnect(ref, () async {
      final backup = await enc.tryHasPocketBaseBackup(user.id);
      return backup == null ? null : !backup && await setupDue();
    });
    return EncryptionSyncStatus.keyOk;
  }
  if (hasBackup || !await setupDue()) return EncryptionSyncStatus.keyOk;
  return EncryptionSyncStatus.needsSetup;
});

/// Re-runs [encryptionSyncProvider] after an offline→online transition when
/// [shouldReroute] answers true (null = server still unreachable). Retries
/// through the first seconds of a reconnect, when the network is up but
/// requests still fail.
void _recheckOnReconnect(Ref ref, Future<bool?> Function() shouldReroute) {
  final Stream<bool> changes;
  try {
    changes = ref.read(connectivitySignalProvider).changes;
  } catch (_) {
    return; // no platform signal (headless test): no reconnect trigger
  }
  var disposed = false;
  late final StreamSubscription<bool> sub;
  sub = changes.where((online) => online).listen((_) async {
    for (var attempt = 0; attempt < 5 && !disposed; attempt++) {
      if (attempt > 0) await Future<void>.delayed(backupCheckRetryDelay);
      final reroute = await shouldReroute();
      if (reroute == null) continue;
      if (reroute && !disposed) ref.invalidateSelf();
      sub.cancel(); // a definite answer: no more reads on later reconnects
      return;
    }
  });
  ref.onDispose(() {
    disposed = true;
    sub.cancel();
  });
}

/// The "set up a backup" Home banner: the server answers that this account
/// has no backup at all.
final showBackupBannerProvider = FutureProvider<bool>((ref) =>
    _backupBannerDue(ref, BackupKind.none, 'backup_reminder_dismissed_at'));

/// B4: the "get a recovery key" Home banner for a phone still backed up
/// with a legacy 6-digit PIN. Its own 7-day dismissal (decision 12).
final showBackupUpgradeBannerProvider = FutureProvider<bool>((ref) =>
    _backupBannerDue(ref, BackupKind.legacy, 'backup_upgrade_dismissed_at'));

Future<bool> _backupBannerDue(
    Ref ref, BackupKind kind, String dismissedAtKey) async {
  final authState = ref.watch(authProvider).valueOrNull;
  if (authState is! AuthAuthenticated) return false;
  final user = authState.user;
  final enc = ref.read(encryptionServiceProvider);
  final db = ref.read(appDatabaseProvider);

  // If local private key does not exist, they are in the restore/setup flow anyway, so no banner.
  final hasLocal = await enc.hasLocalPrivateKey();
  if (!hasLocal) return false;

  // P6: tri-state — an offline check is unknown (null), and nagging a user
  // to back up a key that is very likely already backed up (server just
  // unreachable) is the same conflation that broke the cold-start route.
  if (await enc.tryGetBackupKind(user.id) != kind) return false;

  // Check if they dismissed the reminder within the last 7 days
  final dismissedAtStr = await db.settingsDao.getSetting(dismissedAtKey);
  if (dismissedAtStr != null) {
    final dismissedAt = DateTime.tryParse(dismissedAtStr);
    if (dismissedAt != null) {
      final difference = DateTime.now().difference(dismissedAt).inDays;
      if (difference < 7) {
        return false; // dismissed within 7 days
      }
    }
  }

  return true;
}
