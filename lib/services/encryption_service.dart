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
    if (cached != null) return base64.decode(cached);

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
}

final encryptionServiceProvider = Provider<EncryptionService>((ref) {
  return EncryptionService(
    ref.read(secureStorageProvider),
    ref.read(pocketbaseClientProvider),
  );
});
