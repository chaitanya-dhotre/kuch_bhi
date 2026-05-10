import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local/secure_storage/secure_storage_service.dart';

class EncryptResult {
  const EncryptResult({required this.ciphertext, required this.iv});
  final String ciphertext;
  final String iv;
}

class EncryptionService {
  EncryptionService(this._storage);
  final SecureStorageService _storage;

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
}

final encryptionServiceProvider = Provider<EncryptionService>((ref) {
  return EncryptionService(ref.read(secureStorageProvider));
});
