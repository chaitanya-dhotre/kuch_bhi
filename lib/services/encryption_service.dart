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

/// Thrown when a message cannot be encrypted because the peer's key is
/// not yet available. Callers MUST treat this as a hard failure and keep
/// the message pending — never fall back to a zero/placeholder key.
class MissingKeyException implements Exception {
  const MissingKeyException(this.message);
  final String message;
  @override
  String toString() => 'MissingKeyException: $message';
}

// ─────────────────────────────────────────────────────────────────────────
// Isolate entry points. All heavy crypto (AES-GCM, X25519 ECDH, HKDF,
// PBKDF2) runs off the UI isolate via compute(). Args/results are plain
// JSON-sendable maps (List<int>/String) so they cross the isolate boundary.
// ─────────────────────────────────────────────────────────────────────────

Future<Map<String, String>> _isoEncrypt(Map<String, dynamic> args) async {
  final aes = AesGcm.with256bits();
  final key = await aes.newSecretKeyFromBytes(
      (args['key'] as List).cast<int>());
  final nonce = aes.newNonce();
  final box = await aes.encrypt(
    utf8.encode(args['plaintext'] as String),
    secretKey: key,
    nonce: nonce,
  );
  final combined = <int>[...box.cipherText, ...box.mac.bytes];
  return {
    'ciphertext': base64.encode(combined),
    'iv': base64.encode(nonce),
  };
}

/// Encrypts raw bytes (for media). Returns base64 ciphertext (incl. MAC) + iv.
Future<Map<String, String>> _isoEncryptBytes(Map<String, dynamic> args) async {
  final aes = AesGcm.with256bits();
  final key = await aes.newSecretKeyFromBytes(
      (args['key'] as List).cast<int>());
  final nonce = aes.newNonce();
  final box = await aes.encrypt(
    (args['bytes'] as List).cast<int>(),
    secretKey: key,
    nonce: nonce,
  );
  final combined = <int>[...box.cipherText, ...box.mac.bytes];
  return {
    'ciphertext': base64.encode(combined),
    'iv': base64.encode(nonce),
  };
}

/// Batch-decrypts many ciphertexts with one key in a single isolate hop.
/// Input: {'key': List<int>, 'items': [{'id','ciphertext','iv'}...]}.
/// Output: {id: plaintext-or-null}.
Future<Map<String, String?>> _isoDecryptBatch(Map<String, dynamic> args) async {
  final aes = AesGcm.with256bits();
  final keyBytes = (args['key'] as List).cast<int>();
  final items = (args['items'] as List).cast<Map>();
  final out = <String, String?>{};
  // A 32-byte key is required. When the key isn't available yet (e.g. history
  // restore before the peer key syncs) we get an empty/short list — return all
  // nulls so the ciphertext is cached and re-decrypted later, never crash.
  if (keyBytes.length != 32) {
    for (final it in items) {
      out[it['id'] as String] = null;
    }
    return out;
  }
  final key = await aes.newSecretKeyFromBytes(keyBytes);
  for (final it in items) {
    final id = it['id'] as String;
    try {
      final nonce = base64.decode(it['iv'] as String);
      final all = base64.decode(it['ciphertext'] as String);
      final ct = all.sublist(0, all.length - 16);
      final mac = Mac(all.sublist(all.length - 16));
      final clear = await aes.decrypt(
        SecretBox(ct, nonce: nonce, mac: mac),
        secretKey: key,
      );
      out[id] = utf8.decode(clear);
    } catch (_) {
      out[id] = null;
    }
  }
  return out;
}

/// Decrypts raw bytes (for media). Returns the clear bytes, or null on failure.
Future<List<int>?> _isoDecryptBytes(Map<String, dynamic> args) async {
  try {
    final aes = AesGcm.with256bits();
    final key = await aes.newSecretKeyFromBytes((args['key'] as List).cast<int>());
    final nonce = base64.decode(args['iv'] as String);
    final all = (args['bytes'] as List).cast<int>();
    final ct = all.sublist(0, all.length - 16);
    final mac = Mac(all.sublist(all.length - 16));
    final clear = await aes.decrypt(
      SecretBox(ct, nonce: nonce, mac: mac),
      secretKey: key,
    );
    return clear;
  } catch (_) {
    return null;
  }
}

/// X25519 ECDH + HKDF-SHA256 → 32-byte conversation key.
Future<List<int>> _isoDeriveKey(Map<String, dynamic> args) async {
  final x = X25519();
  final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  final myKeyPair = SimpleKeyPairData(
    (args['priv'] as List).cast<int>(),
    publicKey: SimplePublicKey(
      (args['myPub'] as List).cast<int>(),
      type: KeyPairType.x25519,
    ),
    type: KeyPairType.x25519,
  );
  final theirPub = SimplePublicKey(
    (args['theirPub'] as List).cast<int>(),
    type: KeyPairType.x25519,
  );
  final shared = await x.sharedSecretKey(
    keyPair: myKeyPair,
    remotePublicKey: theirPub,
  );
  final derived = await hkdf.deriveKey(
    secretKey: shared,
    nonce: (args['salt'] as List).cast<int>(),
    info: utf8.encode(args['info'] as String),
  );
  return derived.extractBytes();
}

/// PBKDF2-HMAC-SHA256 (100k iterations) → 32-byte key from a PIN + salt.
Future<List<int>> _isoPbkdf2(Map<String, dynamic> args) async {
  final pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: args['iterations'] as int,
    bits: 256,
  );
  final key = await pbkdf2.deriveKeyFromPassword(
    password: args['pin'] as String,
    nonce: (args['salt'] as List).cast<int>(),
  );
  return key.extractBytes();
}

class EncryptionService {
  EncryptionService(this._storage, this._pbClient);
  final SecureStorageService _storage;
  final PocketBaseClient     _pbClient;

  PocketBase get _pb => _pbClient.pb;

  static final _x25519 = X25519();
  static final _aesGcm = AesGcm.with256bits();

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

  /// Derives (or loads from cache) the AES-256 key for a direct conversation
  /// using X25519 ECDH + HKDF. Runs the heavy math off the UI isolate.
  Future<List<int>> getOrDeriveConversationKey(
    String conversationId,
    String theirPublicKeyBase64,
  ) async {
    final cacheKey = '${conversationId}_$theirPublicKeyBase64';
    final cached = await _storage.getContactEncryptionKey(cacheKey);
    if (cached != null && cached.isNotEmpty) {
      return base64.decode(cached);
    }

    final myKeyPair = await getOrCreateKeyPair();
    final myPub     = await myKeyPair.extractPublicKey();

    debugPrint('[Enc] Deriving key for conv: $conversationId, theirPub: ${theirPublicKeyBase64.substring(0, 10)}...');

    // ECDH + HKDF runs off the UI isolate.
    final keyBytes = await compute(_isoDeriveKey, {
      'priv':     await myKeyPair.extractPrivateKeyBytes(),
      'myPub':    myPub.bytes,
      'theirPub': base64.decode(theirPublicKeyBase64),
      'salt':     utf8.encode(conversationId),
      'info':     'kuchbhi-v1',
    });

    await _storage.saveContactEncryptionKey(
        cacheKey, base64.encode(keyBytes));
    return keyBytes;
  }

  // ── Encrypt ───────────────────────────────────────────────────

  Future<EncryptResult> encryptMessage(
    String plaintext,
    List<int> keyBytes,
  ) async {
    final res = await compute(_isoEncrypt, {
      'plaintext': plaintext,
      'key':       keyBytes,
    });
    return EncryptResult(ciphertext: res['ciphertext']!, iv: res['iv']!);
  }

  /// Encrypts raw bytes (media) off the UI isolate.
  Future<EncryptResult> encryptBytes(
    List<int> bytes,
    List<int> keyBytes,
  ) async {
    final res = await compute(_isoEncryptBytes, {
      'bytes': bytes,
      'key':   keyBytes,
    });
    return EncryptResult(ciphertext: res['ciphertext']!, iv: res['iv']!);
  }

  // ── Decrypt ───────────────────────────────────────────────────

  Future<String?> decryptMessage(
    String ciphertext,
    String iv,
    List<int> keyBytes,
  ) async {
    final out = await decryptBatch(keyBytes, [
      {'id': '_', 'ciphertext': ciphertext, 'iv': iv},
    ]);
    return out['_'];
  }

  /// Batch-decrypts many {id, ciphertext, iv} entries with one key in a
  /// single isolate hop. Returns {id: plaintext-or-null}.
  Future<Map<String, String?>> decryptBatch(
    List<int> keyBytes,
    List<Map<String, String>> items,
  ) async {
    if (items.isEmpty) return {};
    return compute(_isoDecryptBatch, {
      'key':   keyBytes,
      'items': items,
    });
  }

  /// Decrypts raw media bytes off the UI isolate. Null on failure.
  Future<List<int>?> decryptBytes(
    List<int> bytes,
    String iv,
    List<int> keyBytes,
  ) async {
    return compute(_isoDecryptBytes, {
      'bytes': bytes,
      'iv':    iv,
      'key':   keyBytes,
    });
  }
  // ── Group key ─────────────────────────────────────────────────

  /// Returns 32 cryptographically random bytes for use as a group AES key.
  List<int> generateGroupKey() {
    final random = Random.secure();
    return List<int>.generate(32, (_) => random.nextInt(256));
  }

  /// Encrypts [groupKey] for a specific member using X25519 ECDH shared secret.
  /// Returns 'ivBase64:ciphertextBase64'.
  Future<String> encryptGroupKeyForMember(
    List<int> groupKey,
    String memberPublicKeyBase64,
    String conversationId,
  ) async {
    final transportKey = await getOrDeriveConversationKey(
      conversationId + '_gk',
      memberPublicKeyBase64,
    );
    final result = await encryptMessage(base64.encode(groupKey), transportKey);
    return '${result.iv}:${result.ciphertext}';
  }

  /// Decrypts an encrypted group key string ('ivBase64:ciphertextBase64').
  /// [adminPublicKeyBase64] is the public key of the user who encrypted it.
  Future<List<int>> decryptGroupKey(
    String encryptedKey,
    String adminPublicKeyBase64,
    String conversationId,
  ) async {
    final parts      = encryptedKey.split(':');
    final iv         = parts[0];
    final ciphertext = parts[1];
    final transportKey = await getOrDeriveConversationKey(
      conversationId + '_gk',
      adminPublicKeyBase64,
    );
    final result = await decryptMessage(ciphertext, iv, transportKey);
    if (result == null) {
      throw Exception('Failed to decrypt group key');
    }
    return base64.decode(result);
  }

  /// Returns the AES group key for [conversationId].
  /// Checks secure storage cache first; fetches and decrypts from PocketBase
  /// if not cached.
  Future<List<int>> getOrFetchGroupKey(
    String conversationId,
    String myId,
  ) async {
    try {
      final cacheKey = 'group_key_$conversationId';
      final cached   = await _storage.read(key: cacheKey);
      if (cached != null && cached.isNotEmpty) {
        return base64.decode(cached);
      }

      final list = await _pb.collection('group_keys').getList(
        filter: 'conversation_id="$conversationId"&&user_id="$myId"',
        sort: '-key_version',
        perPage: 1,
        expand: 'encrypted_by_user_id',
      );
      if (list.items.isEmpty) {
        throw Exception('No group key found');
      }
      final record = list.items.first;

      final adminRecord  = record.expand['encrypted_by_user_id']?.firstOrNull;
      final adminPubKey = adminRecord?.getStringValue('public_key') ?? '';

      final groupKey = await decryptGroupKey(
        record.getStringValue('encrypted_key'),
        adminPubKey,
        conversationId,
      );

      await _storage.write(key: cacheKey, value: base64.encode(groupKey));
      return groupKey;
    } catch (e) {
      // NEVER fall back to a zero key — that would produce ciphertext
      // under a publicly-known key. Hard-fail so the caller keeps the
      // message pending and retries once the key is available.
      debugPrint('[Enc] Failed to fetch group key: $e');
      throw MissingKeyException('group key unavailable for $conversationId: $e');
    }
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

    // Derive AES-256 key from PIN and salt (off the UI isolate).
    final keyBytes = await compute(_isoPbkdf2, {
      'pin': pin,
      'salt': salt,
      'iterations': 100000,
    });
    final secretKey = await _aesGcm.newSecretKeyFromBytes(keyBytes);

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

      // Re-derive AES-256 key from PIN and salt (off the UI isolate).
      final keyBytes = await compute(_isoPbkdf2, {
        'pin': pin,
        'salt': salt,
        'iterations': 100000,
      });
      final secretKey = await _aesGcm.newSecretKeyFromBytes(keyBytes);

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

      // Re-derive the matching public key. For X25519 the 32-byte private
      // scalar IS the seed accepted by newKeyPairFromSeed, so this
      // reproduces the exact public key that is stored on the server.
      final kp = await _x25519.newKeyPairFromSeed(clear);
      final pubKey = await kp.extractPublicKey();
      await _storage.saveLocalPublicKey(base64.encode(pubKey.bytes));

      // Re-publish the restored public key: the server's copy may have been
      // replaced by a regenerate-on-mismatch during an account switch, and
      // without re-publishing here the login-time mismatch guard would drop
      // the just-restored keypair (and group_keys rows would stay
      // unwrappable). Restore is a rollback to the account's ORIGINAL key —
      // peers' existing DM derivations stay valid.
      try {
        await _pb.collection('users').update(userId, body: {
          'public_key': base64.encode(pubKey.bytes),
        });
      } catch (e) {
        debugPrint('[Enc] Restored pubkey re-upload failed: $e');
      }

      // Invalidate all cached derived keys so they get re-derived with the
      // restored private key. Cover every prefix the app actually uses.
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

  /// P6 (user report 2026-10-11): TRI-STATE backup check — `true`/`false`
  /// when the server answers, `null` when the check could not run (offline,
  /// server down). `hasPocketBaseBackup`'s catch-all `false` conflated
  /// "unreachable" with "no backup", which routed already-set-up users into
  /// the Backup-PIN setup screen on every offline cold start. Callers that
  /// BRANCH on the answer must use this and treat `null` as "unknown".
  Future<bool?> tryHasPocketBaseBackup(String userId) async {
    try {
      final userRecord = await _pb.collection('users').getOne(userId);
      final encrypted = userRecord.getStringValue('private_key_encrypted');
      return encrypted.isNotEmpty;
    } catch (e) {
      debugPrint('[Enc] hasPocketBaseBackup check failed (unknown): $e');
      return null;
    }
  }
}

final encryptionServiceProvider = Provider<EncryptionService>((ref) {
  return EncryptionService(
    ref.read(secureStorageProvider),
    ref.read(pocketbaseClientProvider),
  );
});
