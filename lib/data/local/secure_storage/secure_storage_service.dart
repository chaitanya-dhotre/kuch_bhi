import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Wraps flutter_secure_storage with typed accessors.
/// All sensitive data — auth tokens, encryption keys — lives here.
/// On Android, this uses the hardware-backed Android Keystore.
class SecureStorageService {
  SecureStorageService() : _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  final FlutterSecureStorage _storage;

  // ── Key constants ──────────────────────────────────────────────
  static const _keyAuthToken    = 'auth_token';
  static const _keyCurrentUserId = 'current_user_id';
  static const _keyPrivateKey   = 'private_key';
  static const _keyPbAuthStore  = 'pb_auth_store';

  /// Prefix for per-contact derived encryption keys.
  static const _prefixContactKey = 'contact_key_';

  // ── Auth token ─────────────────────────────────────────────────

  Future<void> saveAuthToken(String token) =>
      _storage.write(key: _keyAuthToken, value: token);

  Future<String?> getAuthToken() =>
      _storage.read(key: _keyAuthToken);

  Future<void> deleteAuthToken() =>
      _storage.delete(key: _keyAuthToken);

  // ── Current user ───────────────────────────────────────────────

  Future<void> saveCurrentUserId(String userId) =>
      _storage.write(key: _keyCurrentUserId, value: userId);

  Future<String?> getCurrentUserId() =>
      _storage.read(key: _keyCurrentUserId);

  // ── PocketBase auth store (full JSON) ──────────────────────────
  // PocketBase SDK needs to persist its full auth model to survive
  // app restarts. We store it as a JSON string here.

  Future<void> savePbAuthStore(String json) =>
      _storage.write(key: _keyPbAuthStore, value: json);

  Future<String?> getPbAuthStore() =>
      _storage.read(key: _keyPbAuthStore);

  Future<void> deletePbAuthStore() =>
      _storage.delete(key: _keyPbAuthStore);

  // ── Encryption keys ────────────────────────────────────────────

  /// Store this user's X25519 private key (base64 encoded).
  Future<void> savePrivateKey(String privateKeyBase64) =>
      _storage.write(key: _keyPrivateKey, value: privateKeyBase64);

  Future<String?> getPrivateKey() =>
      _storage.read(key: _keyPrivateKey);

  /// Store the derived AES encryption key for a specific contact.
  /// Key is derived from X25519 ECDH + HKDF and cached here.
  Future<void> saveContactEncryptionKey(
    String contactUserId,
    String keyBase64,
  ) =>
      _storage.write(
        key: '$_prefixContactKey$contactUserId',
        value: keyBase64,
      );

  Future<String?> getContactEncryptionKey(String contactUserId) =>
      _storage.read(key: '$_prefixContactKey$contactUserId');

  // ── Full wipe ──────────────────────────────────────────────────

  /// Called on logout or account deletion.
  /// Removes all app secrets from the keystore.
  Future<void> clearAll() => _storage.deleteAll();
}

final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});
