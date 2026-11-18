import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/database/app_database.dart';
import '../../data/local/database/contact_key_store.dart'
    show kOwnKeyMismatchSetting;
import '../../data/local/secure_storage/secure_storage_service.dart';
import '../../infrastructure/repositories/auth_repository_impl.dart'
    show authRepositoryProvider;
import '../auth/providers/encryption_sync_provider.dart';

/// Key-change-warning spec E1, "Keep this phone's code": re-publish this
/// phone's public key. Throws when offline (the screen shows a toast).
Future<void> keepOwnKey(WidgetRef ref) async {
  final local = await ref.read(secureStorageProvider).getLocalPublicKey();
  if (local == null || local.isEmpty) throw StateError('no local key');
  await ref.read(authRepositoryProvider).updatePublicKey(local);
  await ref
      .read(appDatabaseProvider)
      .settingsDao
      .deleteSetting(kOwnKeyMismatchSetting);
  ref.invalidate(encryptionSyncProvider);
}

/// E1, "Restore with recovery key": remove this phone's key; the route then
/// checks the backup and opens Restore (today's path, K3 unchanged).
Future<void> dropOwnKeyForRestore(WidgetRef ref) async {
  await ref.read(secureStorageProvider).deleteKeyPair();
  await ref
      .read(appDatabaseProvider)
      .settingsDao
      .deleteSetting(kOwnKeyMismatchSetting);
  ref.invalidate(encryptionSyncProvider);
}
