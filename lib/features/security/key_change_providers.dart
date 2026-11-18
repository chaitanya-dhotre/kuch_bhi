import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/database/app_database.dart';
import '../../data/local/database/contact_key_store.dart';
import '../../infrastructure/repositories/message_repository_impl.dart';

/// The pin store (audit F3).
final contactKeyStoreProvider = Provider<ContactKeyStore>(
  (ref) => ref.watch(appDatabaseProvider).contactKeys,
);

/// One contact's pin, live.
final contactKeyProvider = StreamProvider.family<ContactKey?, String>(
  (ref, userId) => ref.watch(contactKeyStoreProvider).watch(userId),
);

/// Ids of contacts whose security code changed and is not accepted yet.
final pendingKeyUserIdsProvider = StreamProvider<Set<String>>((ref) async* {
  final store = ref.watch(contactKeyStoreProvider);
  Future<Set<String>> read() async => {
    for (final k in await store.pending()) k.userId,
  };
  yield await read();
  yield* store.changes.asyncMap((_) => read());
});

/// Spec A5/A6 through the repository (catch-up wraps, decrypt re-run).
Future<void> acceptContactKey(
  WidgetRef ref,
  String userId, {
  bool verified = false,
}) => (ref.read(messageRepositoryProvider) as MessageRepositoryImpl)
    .acceptContactKey(userId, verified: verified);
