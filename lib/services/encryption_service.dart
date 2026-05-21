import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbase/pocketbase.dart';

import '../core/network/pocketbase_client.dart';
import '../data/local/secure_storage/secure_storage_service.dart';

class EncryptResult {
  const EncryptResult({required this.ciphertext, required this.iv});
  final String ciphertext;
  final String iv;
}

class EncryptionService {
  EncryptionService(this._storage, this._pbClient);
  final SecureStorageService _storage;
  final PocketBaseClient     _pbClient;

  PocketBase get _pb => _pbClient.pb;

  static final _x25519 = X25519();
  static final _aesGcm = AesGcm.with256bits();
  static final _hkdf   = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  // ── Key pair ──────────────────────────────────────────────────

  Future<SimpleKeyPairData> getOrCreateKeyPair() async {
    final privB64 = await _storage.getPrivateKey();
    final pubB64  = await _storage.getLocalPublicKey();

    if (privB64 != null && pubB64 != null) {
      return SimpleKeyPairData(
        base64.decode(privB64),
        publicKey: SimplePublicKey(
          base64.decode(pubB64),
          type: KeyPairType.x25519,
        ),
        type: KeyPairType.x25519,
      );
    }

    // Generate fresh key pair.
    final keyPair   = await _x25519.newKeyPair();
    final privBytes = await keyPair.extractPrivateKeyBytes();
    final pubKey    = await keyPair.extractPublicKey();

    await _storage.savePrivateKey(base64.encode(privBytes));
    await _storage.saveLocalPublicKey(base64.encode(pubKey.bytes));

    return SimpleKeyPairData(
      privBytes,
      publicKey: pubKey,
      type: KeyPairType.x25519,
    );
  }

  Future<String> getPublicKeyBase64() async {
    final kp  = await getOrCreateKeyPair();
    final pub = await kp.extractPublicKey();
    return base64.encode(pub.bytes);
  }

  // ── Conversation key ───────────────────────────────────────────

  Future<List<int>> getOrDeriveConversationKey(
    String conversationId,
    String theirPublicKeyBase64,
  ) async {
    final cached = await _storage.getContactEncryptionKey(conversationId);
    if (cached != null && cached.isNotEmpty) return base64.decode(cached);

    final myKeyPair   = await getOrCreateKeyPair();
    final theirPubKey = SimplePublicKey(
      base64.decode(theirPublicKeyBase64),
      type: KeyPairType.x25519,
    );

    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair:         myKeyPair,
      remotePublicKey: theirPubKey,
    );

    final derived = await _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce:     utf8.encode(conversationId),
      info:      utf8.encode('kuchbhi-v1'),
    );

    final keyBytes = await derived.extractBytes();
    await _storage.saveContactEncryptionKey(
        conversationId, base64.encode(keyBytes));
    return keyBytes;
  }

  // ── Encrypt ───────────────────────────────────────────────────

  Future<EncryptResult> encryptMessage(
    String plaintext,
    List<int> keyBytes,
  ) async {
    final secretKey = await _aesGcm.newSecretKeyFromBytes(keyBytes);
    final nonce     = _aesGcm.newNonce();

    final secretBox = await _aesGcm.encrypt(
      utf8.encode(plaintext),
      secretKey: secretKey,
      nonce:     nonce,
    );

    final combined = [...secretBox.cipherText, ...secretBox.mac.bytes];

    return EncryptResult(
      ciphertext: base64.encode(combined),
      iv:         base64.encode(nonce),
    );
  }

  // ── Decrypt ───────────────────────────────────────────────────

  Future<String?> decryptMessage(
    String ciphertext,
    String iv,
    List<int> keyBytes,
  ) async {
    try {
      final secretKey = await _aesGcm.newSecretKeyFromBytes(keyBytes);
      final nonce     = base64.decode(iv);
      final allBytes  = base64.decode(ciphertext);
      final cipherTxt = allBytes.sublist(0, allBytes.length - 16);
      final mac       = Mac(allBytes.sublist(allBytes.length - 16));

      final clear = await _aesGcm.decrypt(
        SecretBox(cipherTxt, nonce: nonce, mac: mac),
        secretKey: secretKey,
      );
      return utf8.decode(clear);
    } catch (e) {
      debugPrint('[Enc] Decrypt failed: $e');
      return null;
    }
  }
  // ── Group key ─────────────────────────────────────────────────

  /// Returns 32 cryptographically random bytes for use as a group AES key.
  List<int> generateGroupKey() {
    final rng = Random.secure();
    return List<int>.generate(32, (_) => rng.nextInt(256));
  }

  /// Encrypts [groupKey] for a specific member using X25519 ECDH shared secret.
  /// Returns 'ivBase64:ciphertextBase64'.
  Future<String> encryptGroupKeyForMember(
    List<int> groupKey,
    String memberPublicKeyBase64,
    String conversationId,
  ) async {
    final sharedKey = await getOrDeriveConversationKey(
      '${conversationId}_groupkey',
      memberPublicKeyBase64,
    );
    final secretKey = await _aesGcm.newSecretKeyFromBytes(sharedKey);
    final nonce     = _aesGcm.newNonce();
    final secretBox = await _aesGcm.encrypt(
      groupKey,
      secretKey: secretKey,
      nonce:     nonce,
    );
    final combined = [...secretBox.cipherText, ...secretBox.mac.bytes];
    return '${base64.encode(nonce)}:${base64.encode(combined)}';
  }

  /// Decrypts an encrypted group key string ('ivBase64:ciphertextBase64').
  /// [adminPublicKeyBase64] is the public key of the user who encrypted it.
  Future<List<int>> decryptGroupKey(
    String encryptedKey,
    String adminPublicKeyBase64,
    String conversationId,
  ) async {
    final parts     = encryptedKey.split(':');
    final nonce     = base64.decode(parts[0]);
    final allBytes  = base64.decode(parts[1]);
    final cipherTxt = allBytes.sublist(0, allBytes.length - 16);
    final mac       = Mac(allBytes.sublist(allBytes.length - 16));

    final sharedKey = await getOrDeriveConversationKey(
      '${conversationId}_groupkey',
      adminPublicKeyBase64,
    );
    final secretKey = await _aesGcm.newSecretKeyFromBytes(sharedKey);
    final clear     = await _aesGcm.decrypt(
      SecretBox(cipherTxt, nonce: nonce, mac: mac),
      secretKey: secretKey,
    );
    return clear;
  }

  /// Returns the AES group key for [conversationId].
  /// Checks secure storage cache first; fetches and decrypts from PocketBase
  /// if not cached.
  Future<List<int>> getOrFetchGroupKey(
    String conversationId,
    String myId,
  ) async {
    final cacheKey = 'group_key_$conversationId';
    final cached   = await _storage.read(key: cacheKey);
    if (cached != null) return base64.decode(cached);

    final record = await _pb.collection('group_keys').getFirstListItem(
      'conversation_id="$conversationId"&&user_id="$myId"',
      expand: 'encrypted_by_user_id',
    );

    final encryptedKey    = record.getStringValue('encrypted_key');
    final encryptedByUser = record.expand['encrypted_by_user_id']?.firstOrNull;
    final adminPublicKey  = encryptedByUser?.getStringValue('public_key') ?? '';

    if (adminPublicKey.isEmpty) {
      debugPrint('[Enc] getOrFetchGroupKey: admin public key is empty');
      return List.filled(32, 0);
    }

    final groupKey = await decryptGroupKey(encryptedKey, adminPublicKey, conversationId);
    await _storage.write(key: cacheKey, value: base64.encode(groupKey));
    return groupKey;
  }

  // ── PIN Backup & Restore ───────────────────────────────────────
  // Note: Drift AppSettingsTable (including 'pin_backup_skipped' setting) is wiped on reinstall.
  // This is correct as it forces a new PIN setup or key restoration for security.

  // SECURITY: The private key is backed up to PocketBase encrypted with
  // a PIN-derived AES key. This means: (a) the PIN must remain secret,
  // (b) the PocketBase server admin can see the encrypted blob but cannot
  // decrypt without the PIN, (c) brute-forcing the PIN offline is possible
  // if the encrypted blob is leaked — use a strong PIN and rotate it
  // periodically via profile settings.

  Future<void> backupPrivateKey(String pin) async {
    final userId = await _storage.getCurrentUserId();
    if (userId == null) {
      throw Exception('[Enc] No current user ID stored locally.');
    }

    final privB64 = await _storage.getPrivateKey();
    if (privB64 == null) {
      throw Exception('[Enc] No local private key to backup.');
    }
    final privBytes = base64.decode(privB64);

    // Generate 32 random bytes as salt
    final rng = Random.secure();
    final salt = List<int>.generate(32, (_) => rng.nextInt(256));

    // Derive AES-256 key from PIN and salt
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 100000,
      bits: 256,
    );
    final secretKey = await pbkdf2.deriveKeyFromPassword(
      password: pin,
      nonce: salt,
    );

    // Encrypt private key with AES-GCM
    final nonce = _aesGcm.newNonce();
    final secretBox = await _aesGcm.encrypt(
      privBytes,
      secretKey: secretKey,
      nonce: nonce,
    );

    // Prepend the 12-byte IV/nonce to ciphertext + MAC
    final encryptedBytes = [
      ...nonce,
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ];

    // Store to PocketBase
    await _pb.collection('users').update(userId, body: {
      'private_key_encrypted': base64.encode(encryptedBytes),
      'private_key_salt': base64.encode(salt),
    });

    debugPrint('[Enc] Private key backed up to PocketBase');
  }

  Future<bool> restorePrivateKey(String pin) async {
    final userId = await _storage.getCurrentUserId();
    if (userId == null) {
      debugPrint('[Enc] Cannot restore private key: No current user ID');
      return false;
    }

    try {
      final userRecord = await _pb.collection('users').getOne(userId);
      final encryptedB64 = userRecord.getStringValue('private_key_encrypted');
      final saltB64 = userRecord.getStringValue('private_key_salt');

      if (encryptedB64.isEmpty || saltB64.isEmpty) {
        debugPrint('[Enc] No backup exists on PocketBase for user: $userId');
        return false;
      }

      final encryptedBytes = base64.decode(encryptedB64);
      final salt = base64.decode(saltB64);

      // Re-derive AES-256 key from PIN and salt
      final pbkdf2 = Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: 100000,
        bits: 256,
      );
      final secretKey = await pbkdf2.deriveKeyFromPassword(
        password: pin,
        nonce: salt,
      );

      if (encryptedBytes.length < 12 + 16) {
        debugPrint('[Enc] Invalid backup length');
        return false;
      }

      // Separate IV (12 bytes), Ciphertext, and MAC (16 bytes)
      final nonce = encryptedBytes.sublist(0, 12);
      final rest = encryptedBytes.sublist(12);
      final cipherText = rest.sublist(0, rest.length - 16);
      final mac = Mac(rest.sublist(rest.length - 16));

      // Attempt AES-GCM Decryption
      final clear = await _aesGcm.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: mac),
        secretKey: secretKey,
      );

      // Store private key in secure storage
      await _storage.savePrivateKey(base64.encode(clear));

      // Derive corresponding public key and save it to sync states
      final keyPair = SimpleKeyPairData(
        clear,
        publicKey: SimplePublicKey(
          await _x25519.newKeyPairFromSeed(clear).then((kp) => kp.extractPublicKey().then((pk) => pk.bytes)),
          type: KeyPairType.x25519,
        ),
        type: KeyPairType.x25519,
      );
      final pubKey = await keyPair.extractPublicKey();
      await _storage.saveLocalPublicKey(base64.encode(pubKey.bytes));

      // Invalidate all cached conversation keys
      final allKeys = await _storage.readAll();
      for (final key in allKeys.keys) {
        if (key.startsWith('conv_key_') || 
            key.startsWith('group_key_') ||
            key.startsWith('contact_key_')) {
          await _storage.delete(key: key);
        }
      }

      debugPrint('[Enc] Private key successfully restored and cached keys cleared');
      return true;
    } catch (e) {
      debugPrint('[Enc] Decryption/restore failed: $e');
      return false;
    }
  }

  Future<void> generateAndBackupNewKey(String pin) async {
    final userId = await _storage.getCurrentUserId();
    if (userId == null) {
      throw Exception('[Enc] No current user ID stored locally.');
    }

    // Generate fresh key pair
    final keyPair = await _x25519.newKeyPair();
    final privBytes = await keyPair.extractPrivateKeyBytes();
    final pubKey = await keyPair.extractPublicKey();

    // Store in Secure Storage
    await _storage.savePrivateKey(base64.encode(privBytes));
    await _storage.saveLocalPublicKey(base64.encode(pubKey.bytes));

    // Upload public key to PocketBase
    await _pb.collection('users').update(userId, body: {
      'public_key': base64.encode(pubKey.bytes),
    });

    // Backup the new key with the new PIN
    await backupPrivateKey(pin);

    // Clear all cached conversation keys
    await _storage.clearAllConversationKeys();

    debugPrint('[Enc] Generated, uploaded, and backed up fresh key pair; cleared cached conversation keys.');
  }

  Future<bool> hasLocalPrivateKey() async {
    final priv = await _storage.getPrivateKey();
    return priv != null && priv.isNotEmpty;
  }

  Future<bool> hasPocketBaseBackup(String userId) async {
    try {
      final userRecord = await _pb.collection('users').getOne(userId);
      final encrypted = userRecord.getStringValue('private_key_encrypted');
      return encrypted.isNotEmpty;
    } catch (e) {
      debugPrint('[Enc] hasPocketBaseBackup check failed: $e');
      return false;
    }
  }
}

final encryptionServiceProvider = Provider<EncryptionService>((ref) {
  return EncryptionService(
    ref.read(secureStorageProvider),
    ref.read(pocketbaseClientProvider),
  );
});
