import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../data/local/secure_storage/secure_storage_service.dart';
import 'decrypt_pass.dart';

/// Device-local outbox key (P8, user ruling): the AES-256 key that wraps a
/// message body at enqueue time when the conversation's GROUP key does not
/// resolve yet.
///
/// WHY THIS EXISTS
/// A `decrypt_state='ready'` row is sealed under the conversation key, so a
/// kill loses nothing (C1: the ciphertext is durable). A KEYLESS enqueue
/// used to store the interim `__pending__` marker and keep the plaintext
/// only in the in-memory body cache — a force-stop then destroyed the only
/// copy, so the outbox "never loses a send" contract (spec §5.2) was broken
/// for exactly that path.
///
/// The user ruling resolves it: §3 forbids durable PLAINTEXT, not durable
/// SEALED text. This key wraps the pending body, so the outbox row survives
/// a kill with no plaintext at rest, and the drain re-encrypts to the group
/// key the moment it arrives.
///
/// WHERE THE KEY LIVES
/// Secure storage, through the app's EXISTING [SecureStorageService] — the
/// same mechanism that already holds `private_key_<uid>`, `group_key_<convId>`
/// and `contact_key_*` (§11: "keys remain in secure storage"). No new crypto
/// dependency: the key feeds [EncryptionService.encryptMessage] (AES-256-GCM)
/// like every other key in the app.
///
/// SESSION SCOPE
/// The slot is NOT one of the keypair slots [SecureStorageService.clearSession]
/// keeps, so logout wipes it with the session. A sealed row would otherwise
/// stay unwrappable forever, which is precisely what §11's logout wipe closes.
///
/// STABILITY
/// The key is generated ONCE per install and reused — rotating it would
/// orphan every already-sealed row, and there is nowhere to re-wrap them
/// from. [keyId] therefore carries `device:` + the sha256 fingerprint so a
/// raw reader knows which key wrapped a row without touching storage.

/// Secure-storage slot holding the device-local outbox key (base64, 32 bytes).
const kDeviceKeySlot = 'device_outbox_key';

/// `key_id` prefix marking a row sealed under the device key rather than a
/// conversation/group key.
const kDeviceKeyIdPrefix = 'device:';

/// `decrypt_state` a keyless enqueue writes: the body IS present and
/// decryptable, just under the DEVICE key. Distinct from `key_missing`,
/// which means no key of any kind resolves yet.
const kDeviceSealedState = 'device_sealed';

/// Owner of [kDeviceKeySlot] — resolves, and if needed lazily creates, the
/// device-local outbox key.
class DeviceKeyStore {
  DeviceKeyStore(this._storage);

  final SecureStorageService _storage;

  List<int>? _key;

  /// The device-local key, generating and securely storing it on first use.
  /// Idempotent: after the first call every later call is a cache/storage
  /// read, so the same key seals every row for the life of the install.
  Future<List<int>> resolve() async {
    final cached = _key;
    if (cached != null) return cached;

    final stored = await _storage.read(key: kDeviceKeySlot);
    if (stored != null && stored.isNotEmpty) {
      try {
        final bytes = base64.decode(stored);
        if (bytes.length == 32) {
          _key = bytes;
          return bytes;
        }
        debugPrint('[P8] Device key slot malformed (len ${bytes.length}) — '
            'regenerating: rows sealed with the old key are unrecoverable');
      } catch (e) {
        debugPrint('[P8] Device key slot undecodable — regenerating: $e');
      }
    }

    // Fresh 256-bit key from the platform CSPRNG. A malformed/replaced slot
    // is treated identically: the new key cannot open old sealed rows, which
    // is the honest outcome — that ciphertext is unrecoverable either way.
    final fresh = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    _key = fresh;
    await _storage.write(key: kDeviceKeySlot, value: base64.encode(fresh));
    return fresh;
  }

  /// `key_id` for a device-sealed row: `device:<sha256(key) hex>`. Uses the
  /// SAME fingerprint [DecryptPass] writes for a decrypted row, so the two
  /// namespaces stay comparable (one corrupted the rotation rule, §8).
  String keyId(List<int> key) =>
      '$kDeviceKeyIdPrefix${DecryptPass.fingerprintOf(key)}';

  /// Forget the in-memory copy (logout / epoch change). The
  /// SECURE-STORAGE slot itself is wiped by
  /// [SecureStorageService.clearSession]; this stops the next half of a
  /// session from silently reusing a key whose slot was wiped.
  void forget() => _key = null;
}
