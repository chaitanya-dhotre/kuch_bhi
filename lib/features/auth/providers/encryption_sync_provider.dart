import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/local/database/app_database.dart';
import '../../../services/encryption_service.dart';
import 'auth_provider.dart';

enum EncryptionSyncStatus {
  keyOk,
  needsSetup,
  needsRestore,
}

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
    // Reinstall scenario: no local private key
    final hasBackup = await enc.hasPocketBaseBackup(user.id);
    if (hasBackup) {
      return EncryptionSyncStatus.needsRestore;
    } else {
      return EncryptionSyncStatus.needsSetup;
    }
  }

  // 2. Local key exists. Check if backup exists on server — TRI-STATE (P6):
  // an unreachable server is "unknown", not "no backup". A local key means
  // the user can already decrypt offline; only a CONFIRMED absent backup may
  // route into the setup flow.
  final hasBackup = await enc.tryHasPocketBaseBackup(user.id);
  if (hasBackup == null) {
    // Offline / server down: local key stands on its own (user report
    // 2026-10-11 — offline cold start must not ask a set-up user to set up).
    return EncryptionSyncStatus.keyOk;
  }
  if (hasBackup) {
    return EncryptionSyncStatus.keyOk;
  }

  // No backup on server. Check if user skipped it.
  final skippedStr = await db.settingsDao.getSetting('pin_backup_skipped');
  final isSkipped = skippedStr == 'true';
  if (isSkipped) {
    final skippedAtStr = await db.settingsDao.getSetting('pin_backup_skipped_at');
    if (skippedAtStr != null) {
      final skippedAt = DateTime.tryParse(skippedAtStr);
      if (skippedAt != null) {
        final days = DateTime.now().difference(skippedAt).inDays;
        if (days < 7) {
          return EncryptionSyncStatus.keyOk; // still within 7 days
        }
      }
    }
  }

  return EncryptionSyncStatus.needsSetup;
});

final showBackupBannerProvider = FutureProvider<bool>((ref) async {
  final authState = ref.watch(authProvider).valueOrNull;
  if (authState is! AuthAuthenticated) return false;
  final user = authState.user;
  final enc = ref.read(encryptionServiceProvider);
  final db = ref.read(appDatabaseProvider);

  // If local private key does not exist, they are in the restore/setup flow anyway, so no banner.
  final hasLocal = await enc.hasLocalPrivateKey();
  if (!hasLocal) return false;

  // P6: tri-state — an offline check is unknown, and nagging a user to back
  // up a key that is very likely already backed up (server just unreachable)
  // is the same conflation that broke the cold-start route.
  final hasBackup = await enc.tryHasPocketBaseBackup(user.id);
  if (hasBackup != false) return false; // true = backed up; null = unknown

  // Check if they dismissed the reminder within the last 7 days
  final dismissedAtStr = await db.settingsDao.getSetting('backup_reminder_dismissed_at');
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
});
