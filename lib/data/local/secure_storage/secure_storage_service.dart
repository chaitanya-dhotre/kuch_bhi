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

  // ── Encryption keys ───────────────────────────────────────────
  Future<void>    savePrivateKey(String b64) => _storage.write(key: _keyPrivateKey, value: b64);
  Future<String?> getPrivateKey()            => _storage.read(key: _keyPrivateKey);

  Future<void>    saveLocalPublicKey(String b64) => _storage.write(key: _keyLocalPublicKey, value: b64);
  Future<String?> getLocalPublicKey()            => _storage.read(key: _keyLocalPublicKey);

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

  // ── Full wipe ─────────────────────────────────────────────────
  Future<void> clearAll() => _storage.deleteAll();
}

final secureStorageProvider = Provider<SecureStorageService>(
  (_) => SecureStorageService(),
);
