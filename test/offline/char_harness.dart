import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';

import 'package:kuch_bhi/core/network/pocketbase_client.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/data/local/secure_storage/secure_storage_service.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';
import 'package:kuch_bhi/services/encryption_service.dart';
import 'package:kuch_bhi/services/media_upload_service.dart';

/// Shared 32-byte AES-GCM fixture key (bytes 1..32, const so it can be a
/// default parameter value).
///
/// CORRECTION vs the brief's `[1, 2, 3, 4]`: the real crypto demands 32
/// bytes — `AesGcm.with256bits()` rejects shorter keys and
/// `_isoDecryptBatch` returns all-null for `keyBytes.length != 32`
/// (encryption_service.dart). A 4-byte key can neither encrypt nor decrypt,
/// so the seed and every encrypt call use this fixture instead.
const List<int> fixtureGroupKey = [
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
  17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,
];

/// A structurally valid JWT (3 dot-separated parts, `exp` in the future).
/// PocketBase `AuthStore.isValid` parses the payload's `exp`, so tests that
/// cross `sessionStillValid(...)` (e.g. the cold fetch cache-write) need
/// this in `pb.authStore` — the brief's harness omitted it and the fetch
/// silently aborted pre-cache.
String _fakeJwt() {
  String enc(Map<String, Object> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m)));
  return '${enc(<String, Object>{'alg': 'HS256', 'typ': 'JWT'})}.'
      '${enc(<String, Object>{'exp': 4102444800})}.sig'; // exp 2100-01-01
}

/// One-time test runtime prep, run by every [charHarness] call:
/// - silences connectivity_plus's EventChannel setup so the repository
///   constructor (`_initConnectivityRetry`) does not emit a
///   "Binding has not yet been initialized" report into the test output
///   (the stream then simply never emits — no connectivity churn);
/// - silences drift's multi-instance warning: every harness opens its own
///   NativeDatabase.memory() (genuinely separate executors), but the
///   warning still fires — with a stacktrace — whenever two harnesses
///   overlap (the encrypt-with-`pre`, fetch-with-`h2` pattern).
bool _runtimePrepared = false;
void _prepareTestRuntime() {
  if (_runtimePrepared) return;
  _runtimePrepared = true;
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
    (message) async => null,
  );
}

/// Secure storage whose reads return fixture values (no platform channel).
/// `read` is the raw key-value entry EncryptionService uses for group keys
/// (`group_key_<convId>`) — seeded via [secrets] or [put].
///
/// CORRECTION vs the brief: `write`/`delete` are also overridden. The real
/// repo calls them (self-heal invalidation, group-key cache write); without
/// overrides they hit the `FlutterSecureStorage` platform channel and throw
/// MissingPluginException in tests.
///
/// `implements` (NOT `extends`) + [noSuchMethod] is deliberate: noSuchMethod
/// forwarders only exist for members the class does not implement — with
/// `extends` the concrete base impls would keep running (verified: Dart
/// dispatches inherited methods directly). Now ANY of the 17 non-overridden
/// members throws [UnimplementedError] instead of reaching real storage.
class FakeSecureStorage implements SecureStorageService {
  FakeSecureStorage({this.userId = 'u_test', this.secrets = const {}});
  final String userId;
  final Map<String, String> secrets;
  final _overrides = <String, String?>{};

  int readAllCalls = 0;

  /// Keys written through [write] / [saveContactEncryptionKey] (not [put]).
  final writes = <String>[];

  /// Transport-key cache reads ([getContactEncryptionKey]).
  int contactKeyReads = 0;

  @override
  Future<String?> read({required String key}) async =>
      _overrides.containsKey(key) ? _overrides[key] : secrets[key];

  @override
  Future<void> write({required String key, required String value}) async {
    writes.add(key);
    _overrides[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    // Tombstone (not remove): mirrors real delete semantics even when the
    // fixture seed lives in [secrets].
    _overrides[key] = null;
  }

  /// Live view of every slot the harness is holding (fixture seeds +
  /// writes, tombstones dropped). P8 needs this to prove the device-local
  /// key is written to secure storage and later wiped with the session —
  /// the real [SecureStorageService.readAll] semantics, minus the platform
  /// channel. Without it, `noSuchMethod` throws UnimplementedError.
  @override
  Future<Map<String, String>> readAll() async {
    readAllCalls++;
    return {
      for (final k in secrets.keys) k: secrets[k]!,
      for (final e in _overrides.entries)
        if (e.value != null) e.key: e.value!,
    };
  }

  @override
  Future<void> clearSession() async {
    final all = await readAll();
    for (final key in all.keys) {
      if (key == 'private_key' ||
          key.startsWith('private_key_') ||
          key == 'local_public_key' ||
          key.startsWith('local_public_key_')) {
        continue;
      }
      await delete(key: key);
    }
  }

  @override
  Future<void> clearAll() async {
    for (final key in (await readAll()).keys) {
      await delete(key: key);
    }
  }

  @override
  Future<void> clearCurrentGroupKey(String conversationId) async {
    final prefix = 'group_key_${conversationId}_';
    final keys = (await readAll()).keys
        .where((key) => key.startsWith(prefix))
        .toList()
      ..sort((a, b) {
        final av = int.tryParse(a.substring(prefix.length)) ?? -1;
        final bv = int.tryParse(b.substring(prefix.length)) ?? -1;
        return bv.compareTo(av);
      });
    await delete(key: 'group_key_$conversationId');
    if (keys.isNotEmpty) await delete(key: keys.first);
  }

  void put(String key, String value) => _overrides[key] = value;
  void removeKey(String key) => _overrides[key] = null;

  @override
  Future<String?> getCurrentUserId() async => userId;
  @override
  Future<String?> getAuthToken() async => 'test-token';
  @override
  Future<String?> getPbAuthStore() async =>
      '{"token":"test-token","model":{"id":"$userId"}}';
  @override
  Future<String?> getPrivateKey() async => _overrides['private_key'];
  @override
  Future<String?> getLocalPublicKey() async => _overrides['local_public_key'];
  // Keypair persistence for tests that drive real ECDH round-trips
  // (group_key_local_first_test's envelope fixture calls
  // EncryptionService.getOrCreateKeyPair).
  @override
  Future<void> savePrivateKey(String b64) async => put('private_key', b64);
  @override
  Future<void> saveLocalPublicKey(String b64) async =>
      put('local_public_key', b64);
  // generateAndBackupNewKey's cache wipe (K3 setup with no key).
  @override
  Future<void> clearAllConversationKeys() async {}
  // Derived conversation-key cache (ECDH round-trip fixtures —
  // group_key_local_first_test drives encryptGroupKeyForMember).
  @override
  Future<void> saveContactEncryptionKey(String contactOrConvId, String keyB64) async {
    writes.add('contact_enc_$contactOrConvId');
    put('contact_enc_$contactOrConvId', keyB64);
  }
  @override
  Future<String?> getContactEncryptionKey(String contactOrConvId) {
    contactKeyReads++;
    return read(key: 'contact_enc_$contactOrConvId');
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError(
      'FakeSecureStorage.${i.memberName} — override before use '
      '(handoff.md lists all 17)');
}

class CharHarness {
  CharHarness(this.db, this.pbClient, this.storage, this.encryption);
  final AppDatabase db;
  final PocketBaseClient pbClient;
  final FakeSecureStorage storage;
  final EncryptionService encryption;
  Future<void> close() => db.close();
}

/// Builds a harness whose PocketBase answers with [clientFactory] for every
/// HTTP call, and whose auth store holds a structurally valid JWT (see
/// [_fakeJwt]).
CharHarness charHarness({http.Client Function()? clientFactory}) {
  _prepareTestRuntime();
  final pb = PocketBase(
    'http://pocketbase.test',
    httpClientFactory: clientFactory ?? http.Client.new,
  );
  pb.authStore.save(_fakeJwt(), null);
  final client = PocketBaseClient.forTest(pb);
  final storage = FakeSecureStorage();
  final db = AppDatabase.test();
  return CharHarness(db, client, storage, EncryptionService(storage, client));
}

/// Seeds the fixture every offline test shares: group conversation `g1`,
/// member row for the fake session user, (optionally) a cached group key.
/// Conversation + member live in Drift; the key lives in secure storage under
/// `group_key_g1` (see EncryptionService.getOrFetchGroupKey cache path).
///
/// CORRECTION vs the brief: timestamps are a fixed date in the PAST instead
/// of `DateTime.now()`. The group-history cutoff (`isGroupRowVisible`)
/// hides rows created before the member's `joinedAt`; the canned server
/// record is stamped `2026-10-07T10:00:00Z`, so seeding `joinedAt=now`
/// made row visibility depend on the wall clock vs that stamp.
Future<void> seedConversationAndKey(
  CharHarness h, {
  bool withKey = true,
  List<int> key = fixtureGroupKey,
}) async {
  final at = DateTime.utc(2026, 1, 1);
  await h.db.conversationsDao.upsertConversation(
    ConversationsTableCompanion.insert(
      id: 'g1',
      type: 'group',
      createdById: 'u_test',
      createdAt: at,
      updatedAt: at,
    ),
  );
  await h.db.conversationsDao.upsertMember(
    ConversationMembersTableCompanion.insert(
      id: 'm1',
      conversationId: 'g1',
      userId: 'u_test',
      joinedAt: at,
    ),
  );
  if (withKey) {
    h.storage.put('group_key_g1', base64.encode(key));
  }
}

/// The REAL repository wired to the harness — every offline test shares it.
MessageRepositoryImpl buildRepo(CharHarness h) => MessageRepositoryImpl(
      pbClient: h.pbClient,
      db: h.db,
      storage: h.storage,
      encryption: h.encryption,
      mediaUploadService: MediaUploadService(h.pbClient, h.encryption),
    );
