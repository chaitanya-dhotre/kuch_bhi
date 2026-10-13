import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SecureStorageService {
  SecureStorageService() : _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  final FlutterSecureStorage _storage;

  static const _keyAuthToken       = 'auth_token';
  static const _keyCurrentUserId   = 'current_user_id';
  static const _keyPrivateKey      = 'private_key';
  static const _keyLocalPublicKey  = 'local_public_key';
  static const _keyPbAuthStore     = 'pb_auth_store';
  static const _prefixContactKey   = 'contact_key_';

  // ── Auth ──────────────────────────────────────────────────────
  Future<void>    saveAuthToken(String t)   => _storage.write(key: _keyAuthToken, value: t);
  Future<String?> getAuthToken()            => _storage.read(key: _keyAuthToken);
  Future<void>    deleteAuthToken()         => _storage.delete(key: _keyAuthToken);

  Future<void>    saveCurrentUserId(String id) => _storage.write(key: _keyCurrentUserId, value: id);
  Future<String?> getCurrentUserId()           => _storage.read(key: _keyCurrentUserId);

  Future<void>    savePbAuthStore(String json) => _storage.write(key: _keyPbAuthStore, value: json);
  Future<String?> getPbAuthStore()             => _storage.read(key: _keyPbAuthStore);
  Future<void>    deletePbAuthStore()          => _storage.delete(key: _keyPbAuthStore);

  // ── Encryption keys (per-user scoped slots) ───────────────────
  //
  // Keys are namespaced `private_key_<userId>` / `local_public_key_<userId>`
  // so account switching on one device never collides: logout keeps the
  // keypair under its owner's slot, another account gets its own slot, and
  // the owner returns to a fully intact slot. The pre-scoping GLOBAL slots
  // are only readable via getLegacy* for the one-time adoption in
  // _initEncryptionKeys (and only for the account whose published key
  // matches).

  Future<String?> _scoped(String base) async {
    final uid = await getCurrentUserId();
    if (uid == null || uid.isEmpty) return null;
    return '${base}_$uid';
  }

  Future<void> savePrivateKey(String b64) async {
    final sk = await _scoped(_keyPrivateKey);
    await _storage.write(key: sk ?? _keyPrivateKey, value: b64);
  }

  Future<String?> getPrivateKey() async {
    final sk = await _scoped(_keyPrivateKey);
    if (sk == null) return null;
    return _storage.read(key: sk);
  }

  Future<void> saveLocalPublicKey(String b64) async {
    final sk = await _scoped(_keyLocalPublicKey);
    await _storage.write(key: sk ?? _keyLocalPublicKey, value: b64);
  }

  Future<String?> getLocalPublicKey() async {
    final sk = await _scoped(_keyLocalPublicKey);
    if (sk == null) return null;
    return _storage.read(key: sk);
  }

  /// Pre-scoping global slots (migration source only).
  Future<String?> getLegacyPrivateKey() => _storage.read(key: _keyPrivateKey);
  Future<String?> getLegacyLocalPublicKey() =>
      _storage.read(key: _keyLocalPublicKey);

  Future<void> saveContactEncryptionKey(String contactOrConvId, String keyB64) =>
      _storage.write(key: '$_prefixContactKey$contactOrConvId', value: keyB64);

  Future<String?> getContactEncryptionKey(String contactOrConvId) =>
      _storage.read(key: '$_prefixContactKey$contactOrConvId');

  // ── Generic passthrough ───────────────────────────────────────
  Future<void>    write({required String key, required String value}) =>
      _storage.write(key: key, value: value);
  Future<String?> read({required String key}) => _storage.read(key: key);
  Future<Map<String, String>> readAll() => _storage.readAll();
  Future<void> delete({required String key}) => _storage.delete(key: key);

  // ── Derived key cache invalidation ───────────────────────────
  /// Clears all cached derived conversation keys (contact_key_* entries).
  /// Call when the remote peer's public key has changed (e.g. they reinstalled).
  Future<void> clearAllContactKeys() async {
    final all = await _storage.readAll();
    for (final key in all.keys) {
      if (key.startsWith(_prefixContactKey)) {
        await _storage.delete(key: key);
      }
    }
  }

  /// Clears all cached derived conversation keys (contact_key_, conv_key_, and group_key_ prefixes).
  Future<void> clearAllConversationKeys() async {
    final all = await _storage.readAll();
    for (final key in all.keys) {
      if (key.startsWith(_prefixContactKey) || 
          key.startsWith('conv_key_') ||
          key.startsWith('group_key_')) {
        await _storage.delete(key: key);
      }
    }
  }

  /// Removes the active group-key cache while retaining older versioned
  /// entries. Historical group messages remain readable after a member leaves
  /// or is removed, but the just-active key is not left in the local cache.
  Future<void> clearCurrentGroupKey(String conversationId) async {
    final prefix = 'group_key_${conversationId}_';
    final all = await _storage.readAll();
    await _storage.delete(key: 'group_key_$conversationId');

    var newestVersion = -1;
    String? newestKey;
    for (final key in all.keys) {
      if (!key.startsWith(prefix)) continue;
      final version = int.tryParse(key.substring(prefix.length));
      if (version != null && version > newestVersion) {
        newestVersion = version;
        newestKey = key;
      }
    }
    if (newestKey != null) await _storage.delete(key: newestKey);
  }

  // ── Full wipe ─────────────────────────────────────────────────
  Future<void> clearAll() => _storage.deleteAll();

  /// Sign-out wipe: EVERYTHING except the local keypair. With the Drift DB
  /// wiped there is no ciphertext left for the keypair to open, and keeping
  /// it means the same account re-logging in keeps its decryptability
  /// (history re-syncs readable). A DIFFERENT account logging in is caught
  /// by the pubkey-mismatch guard in _initEncryptionKeys, which drops the
  /// foreign keypair and restores-or-generates for the new account.
  Future<void> clearSession() async {
    final all = await _storage.readAll();
    for (final key in all.keys) {
      // Keep every keypair slot (legacy + per-user scoped variants).
      if (key == _keyPrivateKey ||
          key.startsWith('${_keyPrivateKey}_') ||
          key == _keyLocalPublicKey ||
          key.startsWith('${_keyLocalPublicKey}_')) {
        continue;
      }
      await _storage.delete(key: key);
    }
  }

  /// Drops THIS user's stored keypair (account-mismatch guard). Never
  /// touches the legacy global slot — that belongs to whichever account
  /// still has to be migrated.
  Future<void> deleteKeyPair() async {
    final sk1 = await _scoped(_keyPrivateKey);
    final sk2 = await _scoped(_keyLocalPublicKey);
    if (sk1 != null) await _storage.delete(key: sk1);
    if (sk2 != null) await _storage.delete(key: sk2);
  }
}

final secureStorageProvider = Provider<SecureStorageService>(
  (_) => SecureStorageService(),
);
