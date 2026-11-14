import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbase/pocketbase.dart';

import '../core/network/pocketbase_client.dart';
import '../core/utils/recovery_key.dart';
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

/// The server answered and no group-key version opened for this device key
/// pair. Retrying cannot help until a new version arrives (G1).
class NoGroupKeyException extends MissingKeyException {
  const NoGroupKeyException(super.message);
}

/// [EncryptionService.restorePrivateKey]'s outcome. Offline is a throw.
enum RestoreResult { restored, restoredLegacy, wrongSecret, noBackup, unsupported }

/// What the server holds for an account: nothing, a legacy 6-digit-PIN
/// backup (v1), or a recovery-key backup (v2 or newer).
enum BackupKind { none, legacy, current }

/// K3: the backup writer refused, because the device key isn't the public
/// key the account publishes.
/// One network walk of a group's `group_keys` rows (restore rev 2 R4): what
/// every caller sharing it needs for its own `requireCurrent` check and merge.
class _GroupKeyWalk {
  _GroupKeyWalk(this.newestVersion, this.newestKey, this.candidates);

  final int? newestVersion;
  final List<int>? newestKey;

  /// Opened keys, newest version first, keyed by base64.
  final Map<String, List<int>> candidates;
}

class KeyMismatchException implements Exception {
  const KeyMismatchException();
}

/// A request that never got an answer: offline, dropped or timed out.
bool isUnreachableError(Object e) =>
    (e is ClientException && e.statusCode == 0) || e is TimeoutException;

// ─────────────────────────────────────────────────────────────────────────
// Isolate entry points. All heavy crypto (AES-GCM, X25519 ECDH, HKDF,
// PBKDF2) runs off the UI isolate via compute(). Args/results are plain
// JSON-sendable maps (List<int>/String) so they cross the isolate boundary.
// ─────────────────────────────────────────────────────────────────────────

Future<Map<String, String>> _isoEncrypt(Map<String, dynamic> args) async {
  final aes = AesGcm.with256bits();
  final key = await aes.newSecretKeyFromBytes(
    (args['key'] as List).cast<int>(),
  );
  final nonce = aes.newNonce();
  final box = await aes.encrypt(
    utf8.encode(args['plaintext'] as String),
    secretKey: key,
    nonce: nonce,
  );
  final combined = <int>[...box.cipherText, ...box.mac.bytes];
  return {'ciphertext': base64.encode(combined), 'iv': base64.encode(nonce)};
}

/// Encrypts raw bytes (for media). Returns base64 ciphertext (incl. MAC) + iv.
Future<Map<String, String>> _isoEncryptBytes(Map<String, dynamic> args) async {
  final aes = AesGcm.with256bits();
  final key = await aes.newSecretKeyFromBytes(
    (args['key'] as List).cast<int>(),
  );
  final nonce = aes.newNonce();
  final box = await aes.encrypt(
    (args['bytes'] as List).cast<int>(),
    secretKey: key,
    nonce: nonce,
  );
  final combined = <int>[...box.cipherText, ...box.mac.bytes];
  return {'ciphertext': base64.encode(combined), 'iv': base64.encode(nonce)};
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
    final key = await aes.newSecretKeyFromBytes(
      (args['key'] as List).cast<int>(),
    );
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
  final PocketBaseClient _pbClient;

  PocketBase get _pb => _pbClient.pb;

  static final _x25519 = X25519();
  static final _aesGcm = AesGcm.with256bits();

  // ── Key pair ──────────────────────────────────────────────────

  /// The stored device key pair, or null. Read-only: decrypt/derive paths use
  /// this, because a key created during sign-in sync hides the Backup PIN
  /// restore (K1). Only first-time setup (getPublicKeyBase64) may create one.
  Future<SimpleKeyPairData?> _readKeyPair() async {
    final privB64 = await _storage.getPrivateKey();
    final pubB64 = await _storage.getLocalPublicKey();
    if (privB64 == null) return null;
    if (pubB64 == null) {
      // Crash between restore's two writes: the public half follows from the seed.
      return (await _x25519.newKeyPairFromSeed(base64.decode(privB64))).extract();
    }
    return SimpleKeyPairData(
      base64.decode(privB64),
      publicKey: SimplePublicKey(
        base64.decode(pubB64),
        type: KeyPairType.x25519,
      ),
      type: KeyPairType.x25519,
    );
  }

  Future<SimpleKeyPairData> getOrCreateKeyPair() async {
    final existing = await _readKeyPair();
    if (existing != null) return existing;

    // Generate fresh key pair.
    final keyPair = await _x25519.newKeyPair();
    final privBytes = await keyPair.extractPrivateKeyBytes();
    final pubKey = await keyPair.extractPublicKey();

    await _storage.savePrivateKey(base64.encode(privBytes));
    await _storage.saveLocalPublicKey(base64.encode(pubKey.bytes));

    return SimpleKeyPairData(
      privBytes,
      publicKey: pubKey,
      type: KeyPairType.x25519,
    );
  }

  Future<String> getPublicKeyBase64() async {
    final kp = await getOrCreateKeyPair();
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

    final myKeyPair = await _readKeyPair();
    if (myKeyPair == null) {
      throw const MissingKeyException('no device key pair (restore pending)');
    }
    final myPub = await myKeyPair.extractPublicKey();

    debugPrint(
      '[Enc] Deriving key for conv: $conversationId, theirPub: ${theirPublicKeyBase64.substring(0, 10)}...',
    );

    // ECDH + HKDF runs off the UI isolate.
    final keyBytes = await compute(_isoDeriveKey, {
      'priv': await myKeyPair.extractPrivateKeyBytes(),
      'myPub': myPub.bytes,
      'theirPub': base64.decode(theirPublicKeyBase64),
      'salt': utf8.encode(conversationId),
      'info': 'kuchbhi-v1',
    });

    await _storage.saveContactEncryptionKey(cacheKey, base64.encode(keyBytes));
    return keyBytes;
  }

  // ── Encrypt ───────────────────────────────────────────────────

  Future<EncryptResult> encryptMessage(
    String plaintext,
    List<int> keyBytes,
  ) async {
    final res = await compute(_isoEncrypt, {
      'plaintext': plaintext,
      'key': keyBytes,
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
      'key': keyBytes,
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
    return compute(_isoDecryptBatch, {'key': keyBytes, 'items': items});
  }

  /// Decrypts raw media bytes off the UI isolate. Null on failure.
  Future<List<int>?> decryptBytes(
    List<int> bytes,
    String iv,
    List<int> keyBytes,
  ) async {
    return compute(_isoDecryptBytes, {
      'bytes': bytes,
      'iv': iv,
      'key': keyBytes,
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

  /// Returns the current AES group key for [conversationId].
  /// Uses the newest server version when reachable; cached versioned keys are
  /// a transport-failure fallback only.
  Future<List<int>> getOrFetchGroupKey(
    String conversationId,
    String myId,
  ) async {
    try {
      final candidates = await getOrFetchGroupKeyCandidates(
        conversationId,
        myId,
        requireCurrent: true,
      );
      if (candidates.isEmpty) throw Exception('No group key found');
      return candidates.first;
    } catch (e) {
      // NEVER fall back to a zero key — that would produce ciphertext under a
      // publicly-known key. Hard-fail so the caller keeps the message pending.
      debugPrint('[Enc] Failed to fetch group key: $e');
      if (e is MissingKeyException) rethrow;
      throw MissingKeyException(
        'group key unavailable for $conversationId: $e',
      );
    }
  }

  // ── C (2026-10-14): process-lifetime group-key memory ────────────
  //
  // Spec §3 governs keys AT REST. The decrypted body cache already keeps
  // strictly more sensitive plaintext in RAM for the process lifetime, so
  // caching decoded key material here is inside the threat model. ONE
  // readAll() per process replaces the per-conversation platform-channel
  // reads that cost M52 ~30s per warm prefetch and 1–5s per focus return
  // (each decrypt resolve used to re-read secure storage).
  //
  // INVARIANTS:
  // - Every reader goes through _ensureGroupKeyMemLoaded (single-flight).
  // - Every writer is write-through: disk first, then the memory slot.
  //   saveGroupKey awaits the load first so a write can never be swallowed
  //   by an in-flight initial load.
  // - Session-scoped wipes MUST call clearAllGroupKeyCache(): the message
  //   repo session-epoch bump does (logout / account switch — fires on any
  //   auth identity change, including the null transition after signOut's
  //   clearSession wipe), and the in-service key wipes below do.

  /// convId → slot → base64. Slot `''` is the compatibility base slot,
  /// digits are rotation versions. PB record ids contain no underscores,
  /// so the LAST underscore separates conv id from version slot (a suffix
  /// that does not parse as int belongs to the conv id itself).
  Map<String, Map<String, String>> _memGroupKeys = {};
  Future<void>? _memLoad;
  int _memGen = 0;
  bool _memLoaded = false;

  Future<void> _ensureGroupKeyMemLoaded() {
    if (_memLoaded) return Future<void>.value();
    final pending = _memLoad;
    if (pending != null) return pending;
    late final Future<void> self;
    self = _loadGroupKeyMem().whenComplete(() {
      // Failed loads must retry; on success _memLoaded short-circuits.
      // Never clobber a newer load started after clearAllGroupKeyCache.
      if (identical(_memLoad, self)) _memLoad = null;
    });
    _memLoad = self;
    return self;
  }

  Future<void> _loadGroupKeyMem() async {
    final gen = _memGen;
    final all = await _storage.readAll();
    if (gen != _memGen) return; // cleared mid-load — discard stale snapshot
    final parsed = <String, Map<String, String>>{};
    for (final entry in all.entries) {
      if (!entry.key.startsWith('group_key_')) continue;
      final rest = entry.key.substring('group_key_'.length);
      final i = rest.lastIndexOf('_');
      final suffix = i < 0 ? null : rest.substring(i + 1);
      final versioned = suffix != null && int.tryParse(suffix) != null;
      final conv = versioned ? rest.substring(0, i) : rest;
      final slot = versioned ? (suffix as String) : '';
      (parsed[conv] ??= {})[slot] = entry.value;
    }
    _memGroupKeys = parsed;
    _memLoaded = true;
  }

  /// Write-through into memory. Callers must have awaited
  /// [_ensureGroupKeyMemLoaded] first (every hydrate path does, via
  /// _readLocalCandidates at entry) so the write is visible.
  void _memPut(String conversationId, String slot, String value) {
    (_memGroupKeys[conversationId] ??= {})[slot] = value;
  }

  /// G3: write-through that skips the storage write when memory already
  /// holds [value] (every revalidation used to rewrite every good version).
  Future<void> _putSlotIfChanged(
    String conversationId,
    String slot,
    String value,
  ) async {
    if (_memGroupKeys[conversationId]?[slot] == value) return;
    await _storage.write(
      key: slot.isEmpty
          ? 'group_key_$conversationId'
          : 'group_key_${conversationId}_$slot',
      value: value,
    );
    _memPut(conversationId, slot, value);
  }

  /// G5: only what the walk reads.
  static const groupKeyFields =
      'key_version,encrypted_key,expand.encrypted_by_user_id.public_key';

  /// G2 test seam: decrypt isolate hops spent by group-key walks.
  @visibleForTesting
  int groupKeyHops = 0;

  /// Network walks started (one `group_keys` request each). The history
  /// sync reads the delta for its per-chat request count (restore rev 2 R5).
  int groupKeyWalks = 0;

  /// R4 (D4): background refreshes skip a group walked this recently.
  static const groupKeyFreshFor = Duration(seconds: 60);

  /// R4 test seam: the clock the freshness window reads.
  @visibleForTesting
  DateTime Function() now = DateTime.now;

  /// R4: the walk running per group; later callers await it (single-flight).
  final Map<String, Future<_GroupKeyWalk>> _groupKeyWalksInFlight = {};
  final Map<String, int> _groupKeyWalkJoins = {};

  /// R4: when each group's last walk opened a key. Cleared with key memory.
  final Map<String, DateTime> _groupKeyWalkedAt = {};

  Future<Map<String, String>> _slotsOf(String conversationId) async {
    await _ensureGroupKeyMemLoaded();
    return _memGroupKeys[conversationId] ?? const <String, String>{};
  }

  /// Fast local-only lookup used by optimistic enqueue. It must never perform
  /// network I/O on the UI path; the durable outbox drain revalidates the
  /// current server key before publishing ciphertext.
  Future<List<int>?> getCachedGroupKey(String conversationId) async {
    final candidates = await _readLocalCandidates(conversationId);
    return candidates.isEmpty ? null : candidates.values.first;
  }

  /// Conversations with a background server revalidation already running —
  /// dedupes the fire-and-forget refresh so one chat open cannot stampede
  /// duplicate `group_keys.getFullList` calls for the same conversation.
  final Set<String> _groupKeyRefreshInFlight = {};

  /// Fired after a successful server-side group-key hydration with `grew`
  /// = the local candidate set gained versions the previous local-first
  /// answer did not have. DecryptPass wires this to re-run rows the stale
  /// key set could not open (rotation-while-closed edge).
  void Function(String conversationId, bool grew)? onGroupKeysRefreshed;

  /// Fire-and-forget server revalidation for the local-first decrypt path.
  /// Failures are swallowed (offline is the normal case); success flows
  /// through the network path below, which fires [onGroupKeysRefreshed].
  void _scheduleGroupKeyRefresh(String conversationId, String myId) {
    // R4 (D4): a walk that succeeded moments ago already holds the answer.
    final walkedAt = _groupKeyWalkedAt[conversationId];
    if (walkedAt != null && now().difference(walkedAt) < groupKeyFreshFor) {
      return;
    }
    if (!_groupKeyRefreshInFlight.add(conversationId)) return;
    unawaited(() async {
      try {
        await getOrFetchGroupKeyCandidates(
          conversationId,
          myId,
          refreshFromServer: true,
        );
      } catch (e) {
        debugPrint(
          '[Enc] background group-key refresh failed for $conversationId: $e',
        );
      } finally {
        _groupKeyRefreshInFlight.remove(conversationId);
      }
    }());
  }

  /// Local candidates for [conversationId] — base compatibility slot +
  /// versioned rotation slots (deduped by bytes, malformed slots ignored).
  /// No network. C (2026-10-14): served entirely from the process-lifetime
  /// memory map — zero platform-channel touches after the first load.
  Future<Map<String, List<int>>> _readLocalCandidates(
    String conversationId,
  ) async {
    final slots = await _slotsOf(conversationId);
    final cachedCandidates = <String, List<int>>{};
    final base = slots[''];
    if (base != null && base.isNotEmpty) {
      try {
        final key = base64.decode(base);
        if (key.length == 32) cachedCandidates[base] = key;
      } catch (_) {}
    }
    // Versioned slots survive rotation and allow offline recovery even when
    // the single compatibility slot was evicted. Newest version first.
    final versioned = slots.entries.where((e) => e.key.isNotEmpty).toList()
      ..sort((a, b) {
        final av = int.tryParse(a.key) ?? -1;
        final bv = int.tryParse(b.key) ?? -1;
        return bv.compareTo(av);
      });
    for (final entry in versioned) {
      try {
        final key = base64.decode(entry.value);
        if (key.length == 32) {
          cachedCandidates.putIfAbsent(entry.value, () => key);
        }
      } catch (_) {}
    }
    return cachedCandidates;
  }

  /// True when at least one key for [conversationId] is already resident in
  /// secure storage — pure local read, no network. The app-start prefetch
  /// (MessageRepositoryImpl.prefetchGroupKeys) uses this to touch only COLD
  /// conversations; warm ones cost one storage scan and zero requests.
  Future<bool> hasLocalGroupKey(String conversationId) async {
    return (await _readLocalCandidates(conversationId)).isNotEmpty;
  }

  /// Finds warm group-key caches for [conversationIds]. C (2026-10-14):
  /// pure memory-map lookup after the one-time process load — the startup
  /// prefetch no longer scans secure storage at all.
  Future<Set<String>> getLocalGroupKeyConversationIds(
    Iterable<String> conversationIds,
  ) async {
    final ids = conversationIds.toSet();
    if (ids.isEmpty) return const <String>{};

    await _ensureGroupKeyMemLoaded();
    final warm = <String>{};
    for (final conversationId in ids) {
      final slots = _memGroupKeys[conversationId];
      if (slots == null) continue;
      for (final value in slots.values) {
        try {
          if (base64.decode(value).length == 32) {
            warm.add(conversationId);
            break;
          }
        } catch (_) {
          // Ignore malformed slots; another retained version may be valid.
        }
      }
    }
    return warm;
  }

  /// Returns every group-key version currently available to this member.
  ///
  /// A conversation has one active cache slot for backwards compatibility,
  /// but historical messages may require an older key after rotation.  The
  /// server's descending version order is authoritative when online; the
  /// cached key is only an offline fallback. Older rows are retained.
  ///
  /// **Display-path latency contract** (loading-issue fix, 2026-10-13): when
  /// the caller does NOT require the current server key (`requireCurrent:
  /// false` — every decrypt/repair/read path) and a local candidate exists,
  /// this returns the local set IMMEDIATELY and revalidates from the server
  /// in the background (deduped per conversation via
  /// [_scheduleGroupKeyRefresh]). Blocking the UI decrypt on a
  /// `group_keys.getFullList` round-trip measured 1–5s per chat open even
  /// though every key was cached. Send paths pass `requireCurrent: true`
  /// and keep the old network-first behavior (freshness is load-bearing
  /// there — see [getOrFetchGroupKey]).
  Future<List<List<int>>> getOrFetchGroupKeyCandidates(
    String conversationId,
    String myId, {
    bool requireCurrent = false,
    bool refreshFromServer = false,
  }) async {
    final cachedCandidates = await _readLocalCandidates(conversationId);

    // LOCAL-FIRST (decrypt/display path): a resident candidate answers the
    // caller now; the server is contacted in the background so rotation
    // freshness still lands (notify → onGroupKeysRefreshed → stuck-row
    // re-run). requireCurrent (send/outbox) and explicit
    // refreshFromServer callers keep the blocking server-authoritative
    // flow below.
    if (!requireCurrent &&
        !refreshFromServer &&
        cachedCandidates.isNotEmpty &&
        myId.isNotEmpty) {
      debugPrint(
        '[Enc] local-first group keys for $conversationId '
        '(${cachedCandidates.length}) — network deferred to background',
      );
      _scheduleGroupKeyRefresh(conversationId, myId);
      return cachedCandidates.values.toList();
    }

    // Bare/offline callers may not have a resolved account id yet. Do not
    // turn a valid local key into a network request with user_id=""; the
    // normal authenticated path always supplies [myId] and can hydrate the
    // retained history below.
    if (myId.isEmpty && cachedCandidates.isNotEmpty) {
      return cachedCandidates.values.toList();
    }

    try {
      // G4: every version would fail without the device key pair (restore
      // pending), so do not spend a request and per-row reads on it. Only
      // with no cache: a cache keeps today's offline fallback below.
      if (cachedCandidates.isEmpty && await _readKeyPair() == null) {
        throw const MissingKeyException('no device key pair (restore pending)');
      }
      // R4: shared request, unwrap and slot writes; the checks below are
      // this caller's own (send keeps requireCurrent, G-B3).
      final walk = await _sharedGroupKeyWalk(conversationId, myId);
      final newestVersion = walk.newestVersion;
      if (requireCurrent && newestVersion != null && walk.newestKey == null) {
        throw MissingKeyException(
          'current group key version $newestVersion is unavailable',
        );
      }
      final serverCandidates = walk.candidates;
      if (serverCandidates.isNotEmpty) {
        final merged = <String, List<int>>{};
        merged.addAll(serverCandidates);
        for (final entry in cachedCandidates.entries) {
          merged.putIfAbsent(entry.key, () => entry.value);
        }
        // A hydration that landed MORE versions than the local-first answer
        // held (or than we held at entry) must wake the decrypt layer: rows
        // the stale set could not open are re-run (DecryptPass wires the
        // handler and owns the stuck-row retry).
        final grew = merged.length > cachedCandidates.length;
        onGroupKeysRefreshed?.call(conversationId, grew);
        return merged.values.toList();
      }
      // A successful empty/undecryptable server response is not an offline
      // condition. Do not silently send under a stale cached key.
      throw NoGroupKeyException('no decryptable group key for $conversationId');
    } catch (e) {
      if (e is MissingKeyException) rethrow;
      if (cachedCandidates.isEmpty) rethrow;
      debugPrint('[Enc] Group-key history fetch failed; using cache: $e');
    }

    if (cachedCandidates.isEmpty) {
      throw MissingKeyException('group key unavailable for $conversationId');
    }
    return cachedCandidates.values.toList();
  }

  /// R4: one network walk per group at a time; a caller arriving mid-walk
  /// awaits the same one.
  Future<_GroupKeyWalk> _sharedGroupKeyWalk(String conversationId, String myId) {
    final running = _groupKeyWalksInFlight[conversationId];
    if (running != null) {
      _groupKeyWalkJoins[conversationId] =
          (_groupKeyWalkJoins[conversationId] ?? 0) + 1;
      return running;
    }
    _groupKeyWalkJoins[conversationId] = 0;
    final walk = _walkGroupKeys(conversationId, myId)
        // Block body: returning the removed Future would make the walk wait
        // on itself.
        .whenComplete(() {
          _groupKeyWalksInFlight.remove(conversationId);
        });
    return _groupKeyWalksInFlight[conversationId] = walk;
  }

  Future<_GroupKeyWalk> _walkGroupKeys(
    String conversationId,
    String myId,
  ) async {
    groupKeyWalks++;
    final watch = Stopwatch()..start();
    // Do not cap this at 200. A long-lived group can have more rotations
    // than one page; truncation silently loses oldest decrypt keys.
    final list = await _pb
        .collection('group_keys')
        .getFullList(
          filter: 'conversation_id="$conversationId"&&user_id="$myId"',
          sort: '-key_version',
          expand: 'encrypted_by_user_id',
          fields: groupKeyFields,
        );
    // G2: one transport key and one isolate hop per wrapper public key.
    // Item ids are list indexes (`fields` leaves the record id out).
    final byWrapper = <String, List<Map<String, String>>>{};
    for (var i = 0; i < list.length; i++) {
      final record = list[i];
      final admin = record.expand['encrypted_by_user_id']?.firstOrNull;
      final adminPubKey = admin?.getStringValue('public_key') ?? '';
      if (adminPubKey.isEmpty) continue;
      final parts = record.getStringValue('encrypted_key').split(':');
      if (parts.length != 2) continue;
      (byWrapper[adminPubKey] ??= []).add(
        {'id': '$i', 'iv': parts[0], 'ciphertext': parts[1]},
      );
    }
    final opened = <String, String?>{};
    var hops = 0;
    for (final entry in byWrapper.entries) {
      try {
        final transportKey = await getOrDeriveConversationKey(
          '${conversationId}_gk',
          entry.key,
        );
        hops++;
        groupKeyHops++;
        opened.addAll(await decryptBatch(transportKey, entry.value));
      } catch (e) {
        debugPrint('[Enc] Skipping undecryptable group key wrapper: $e');
      }
    }
    final serverCandidates = <String, List<int>>{};
    final newestVersion = list.isEmpty
        ? null
        : list.first.getIntValue('key_version');
    List<int>? newestKey;
    var cachedCurrent = false;
    var openedCount = 0;
    // Server order (newest version first), as before G2.
    for (var i = 0; i < list.length; i++) {
      final plain = opened['$i'];
      if (plain == null) continue;
      final List<int> key;
      try {
        key = base64.decode(plain);
      } catch (_) {
        continue;
      }
      if (key.length != 32) continue;
      openedCount++;
      final encoded = base64.encode(key);
      serverCandidates.putIfAbsent(encoded, () => key);
      final version = list[i].getIntValue('key_version');
      if (version == newestVersion && newestKey == null) {
        newestKey = key;
      }
      await _putSlotIfChanged(conversationId, '$version', encoded);
      if (!cachedCurrent) {
        await _putSlotIfChanged(conversationId, '', encoded);
        cachedCurrent = true;
      }
    }
    if (serverCandidates.isNotEmpty) {
      // The server list is sorted by key_version descending.
      final newestEncoded = base64.encode(serverCandidates.values.first);
      await _putSlotIfChanged(conversationId, '', newestEncoded);
      _groupKeyWalkedAt[conversationId] = now();
    }
    debugPrint(
      '[Enc] group keys versions=${list.length} opened=$openedCount '
      'hops=$hops joined=${_groupKeyWalkJoins[conversationId] ?? 0} '
      'ms=${watch.elapsedMilliseconds}',
    );
    return _GroupKeyWalk(newestVersion, newestKey, serverCandidates);
  }

  // ── Public group-key slot writers (C write-through API) ────────
  //
  // External writers must go through these instead of raw storage.write /
  // storage.delete — otherwise the process-lifetime memory map serves stale
  // keys for the rest of the session. Known writers: create-group screen,
  // _rotateGroupKey (message repo), leaveGroup, removal verdict, and the
  // base-slot self-heal.

  /// Write-through save of one group-key slot (base when [version] is null,
  /// a rotation version otherwise). Disk first, then memory.
  Future<void> saveGroupKey(
    String conversationId,
    List<int> key, {
    int? version,
  }) async {
    await _ensureGroupKeyMemLoaded();
    final slot = version?.toString() ?? '';
    final value = base64.encode(key);
    await _storage.write(
      key: slot.isEmpty
          ? 'group_key_$conversationId'
          : 'group_key_${conversationId}_$slot',
      value: value,
    );
    _memPut(conversationId, slot, value);
  }

  /// Mirror of [SecureStorageService.clearCurrentGroupKey] with memory
  /// write-through: drops the base slot and the NEWEST versioned slot on
  /// both sides, retaining older versions for historical decrypt (leave /
  /// member-removal paths).
  Future<void> clearCurrentGroupKey(String conversationId) async {
    await _ensureGroupKeyMemLoaded();
    final slots = _memGroupKeys[conversationId];
    if (slots == null) return; // nothing on either side
    await _storage.delete(key: 'group_key_$conversationId');
    slots.remove('');
    var newest = -1;
    for (final s in slots.keys) {
      final v = int.tryParse(s);
      if (v != null && v > newest) newest = v;
    }
    if (newest >= 0) {
      await _storage.delete(key: 'group_key_${conversationId}_$newest');
      slots.remove('$newest');
    }
    if (slots.isEmpty) _memGroupKeys.remove(conversationId);
  }

  /// Self-heal hook: the base compatibility slot alone was stale/corrupt —
  /// drop it from disk AND memory; versioned slots stay (the follow-up
  /// refetch re-hydrates a fresh base).
  Future<void> invalidateGroupKeyBase(String conversationId) async {
    await _ensureGroupKeyMemLoaded();
    await _storage.delete(key: 'group_key_$conversationId');
    final slots = _memGroupKeys[conversationId];
    if (slots == null) return;
    slots.remove('');
    if (slots.isEmpty) _memGroupKeys.remove(conversationId);
  }

  /// Session-scoped eviction: forget every cached group key in RAM (disk
  /// untouched). Called from the message-repo session-epoch bump (logout /
  /// account switch) and from the in-service key wipes below. A load
  /// already in flight is discarded via the generation counter.
  void clearAllGroupKeyCache() {
    _groupKeyWalkedAt.clear();
    _memGen++;
    _memLoad = null;
    _memGroupKeys = {};
    _memLoaded = false;
  }

  // ── Key backup (recovery key) ──────────────────────────────────
  // Note: Drift AppSettingsTable (including 'pin_backup_skipped' setting) is wiped on reinstall.
  // This is correct as it forces a new PIN setup or key restoration for security.

  // SECURITY: the private key is backed up on the user's PocketBase record,
  // which an owner-only hook hides from other accounts. Anyone holding a
  // copy can guess offline, so only the v2 format is ever written:
  //   v2 = "v2:" + base64(nonce‖ct‖tag), AES-GCM under HKDF-SHA256 of a
  //        generated 125-bit recovery key, AAD bound to the user id.
  //   v1 = unprefixed, PBKDF2-100k of a 6-digit PIN (legacy, read-only:
  //        one GPU guesses it in seconds).
  // [backupPrivateKey] is the only writer, and it refuses to back up a key
  // that isn't the account's published one (K3).

  static const _v2Info = 'kuch_bhi key backup v2';

  static Future<SecretKey> _v2Key(String recoveryKey, List<int> salt) =>
      Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
        secretKey: SecretKey(ascii.encode(recoveryKey)),
        nonce: salt,
        info: utf8.encode(_v2Info),
      );

  static List<int> _v2Aad(String userId) => utf8.encode('$_v2Info $userId');

  Future<void> backupPrivateKey(String recoveryKey) async {
    final key = parseRecoveryKey(recoveryKey);
    if (key == null) throw ArgumentError('Not a recovery key.');
    final userId = await _storage.getCurrentUserId();
    if (userId == null) {
      throw Exception('[Enc] No current user ID stored locally.');
    }

    final privB64 = await _storage.getPrivateKey();
    if (privB64 == null) {
      throw Exception('[Enc] No local private key to backup.');
    }
    final privBytes = base64.decode(privB64);

    // K3: back up only the key peers encrypt to. Fresh read, never a cache.
    final devicePub = await (await _x25519.newKeyPairFromSeed(privBytes))
        .extractPublicKey();
    final record = await _pb.collection('users').getOne(userId);
    final serverPub = record.getStringValue('public_key');
    if (serverPub.isNotEmpty && serverPub != base64.encode(devicePub.bytes)) {
      throw const KeyMismatchException();
    }

    final rng = Random.secure();
    final salt = List<int>.generate(16, (_) => rng.nextInt(256));
    final nonce = _aesGcm.newNonce();
    final box = await _aesGcm.encrypt(
      privBytes,
      secretKey: await _v2Key(key, salt),
      nonce: nonce,
      aad: _v2Aad(userId),
    );

    // One update: blob and salt land together or not at all.
    await _pb.collection('users').update(userId, body: {
      'private_key_encrypted':
          'v2:${base64.encode([...nonce, ...box.cipherText, ...box.mac.bytes])}',
      'private_key_salt': base64.encode(salt),
    });

    debugPrint('[Enc] Private key backed up to PocketBase (v2)');
  }

  /// Decrypts the backup with [secret] (a recovery key, or a legacy 6-digit
  /// PIN for a v1 blob) and installs it as the device key. The blob's format
  /// picks how [secret] is read. Throws when the record can't be read (K3:
  /// offline is an error to show, not a wrong secret).
  Future<RestoreResult> restorePrivateKey(String secret) async {
    final userId = await _storage.getCurrentUserId();
    if (userId == null) {
      throw Exception('[Enc] No current user ID stored locally.');
    }

    final userRecord = await _pb.collection('users').getOne(userId);
    final blob = userRecord.getStringValue('private_key_encrypted');
    final saltB64 = userRecord.getStringValue('private_key_salt');
    if (blob.isEmpty || saltB64.isEmpty) {
      debugPrint('[Enc] No backup exists on PocketBase for user: $userId');
      return RestoreResult.noBackup;
    }

    final version = RegExp(r'^v(\d+):').firstMatch(blob)?.group(1);
    if (version != null && version != '2') return RestoreResult.unsupported;

    final List<int> clear;
    try {
      final salt = base64.decode(saltB64);
      if (version == '2') {
        final key = parseRecoveryKey(secret);
        if (key == null) return RestoreResult.wrongSecret;
        clear = await _openBackup(
          base64.decode(blob.substring(3)),
          await _v2Key(key, salt),
          aad: _v2Aad(userId),
        );
      } else {
        // v1: PBKDF2-HMAC-SHA256 off the UI isolate (seconds on slow phones).
        final keyBytes = await compute(_isoPbkdf2, {
          'pin': secret.trim(),
          'salt': salt,
          'iterations': 100000,
        });
        clear = await _openBackup(
          base64.decode(blob),
          await _aesGcm.newSecretKeyFromBytes(keyBytes),
        );
      }
    } on SecretBoxAuthenticationError {
      // Only a failed tag means a wrong secret (or a tampered / moved blob);
      // a malformed record throws, so it isn't retyped forever.
      debugPrint('[Enc] Backup did not open: wrong secret');
      return RestoreResult.wrongSecret;
    }

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
      await _pb
          .collection('users')
          .update(userId, body: {'public_key': base64.encode(pubKey.bytes)});
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
    clearAllGroupKeyCache(); // C: disk wipe must evict the RAM map too

    debugPrint(
      '[Enc] Private key successfully restored and cached keys cleared',
    );
    return version == null
        ? RestoreResult.restoredLegacy
        : RestoreResult.restored;
  }

  /// App lock's Forgot PIN: opens the backup with [secret] exactly as
  /// [restorePrivateKey] does, then stops. Writes nothing (no storage, no
  /// server, no cache). Throws when the record can't be read.
  // Duplicates restorePrivateKey's open on purpose so that path stays
  // byte-identical (app lock spec J1, follow-up F-a).
  Future<RestoreResult> checkBackupSecret(String secret) async {
    final userId = await _storage.getCurrentUserId();
    if (userId == null) {
      throw Exception('[Enc] No current user ID stored locally.');
    }

    final userRecord = await _pb.collection('users').getOne(userId);
    final blob = userRecord.getStringValue('private_key_encrypted');
    final saltB64 = userRecord.getStringValue('private_key_salt');
    if (blob.isEmpty || saltB64.isEmpty) return RestoreResult.noBackup;

    final version = RegExp(r'^v(\d+):').firstMatch(blob)?.group(1);
    if (version != null && version != '2') return RestoreResult.unsupported;

    final List<int> clear;
    try {
      final salt = base64.decode(saltB64);
      if (version == '2') {
        final key = parseRecoveryKey(secret);
        if (key == null) return RestoreResult.wrongSecret;
        clear = await _openBackup(
          base64.decode(blob.substring(3)),
          await _v2Key(key, salt),
          aad: _v2Aad(userId),
        );
      } else {
        final keyBytes = await compute(_isoPbkdf2, {
          'pin': secret.trim(),
          'salt': salt,
          'iterations': 100000,
        });
        clear = await _openBackup(
          base64.decode(blob),
          await _aesGcm.newSecretKeyFromBytes(keyBytes),
        );
      }
    } on SecretBoxAuthenticationError {
      return RestoreResult.wrongSecret;
    }

    clear.fillRange(0, clear.length, 0);
    return version == null
        ? RestoreResult.restoredLegacy
        : RestoreResult.restored;
  }

  /// nonce 12 ‖ ciphertext ‖ GCM tag 16 → plaintext; throws on a bad tag.
  Future<List<int>> _openBackup(List<int> bytes, SecretKey key,
      {List<int> aad = const []}) {
    if (bytes.length < 12 + 16) throw const FormatException('short backup');
    final rest = bytes.sublist(12);
    return _aesGcm.decrypt(
      SecretBox(
        rest.sublist(0, rest.length - 16),
        nonce: bytes.sublist(0, 12),
        mac: Mac(rest.sublist(rest.length - 16)),
      ),
      secretKey: key,
      aad: aad,
    );
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

    // Upload first (K3): offline, this throws before the device holds a key
    // the server never saw (a cold start would then route that key to keyOk).
    await _pb
        .collection('users')
        .update(userId, body: {'public_key': base64.encode(pubKey.bytes)});

    // Store in Secure Storage
    await _storage.savePrivateKey(base64.encode(privBytes));
    await _storage.saveLocalPublicKey(base64.encode(pubKey.bytes));

    // Backup the new key with the new PIN
    await backupPrivateKey(pin);

    // Clear all cached conversation keys
    await _storage.clearAllConversationKeys();
    clearAllGroupKeyCache(); // C: disk wipe must evict the RAM map too

    debugPrint(
      '[Enc] Generated, uploaded, and backed up fresh key pair; cleared cached conversation keys.',
    );
  }

  /// Backup PIN setup (not Start Fresh). Backs up the device key; with no
  /// key (K3: key init skips generation while the backup state is unknown)
  /// it creates one only on a CONFIRMED "no backup". Otherwise it writes
  /// nothing and the caller's re-route sends the user to Restore or to the
  /// splash re-check.
  Future<void> backupOrCreateKey(String pin) async {
    if (await hasLocalPrivateKey()) return backupPrivateKey(pin);
    final userId = await _storage.getCurrentUserId();
    if (userId == null) {
      throw Exception('[Enc] No current user ID stored locally.');
    }
    final hasBackup = await tryHasPocketBaseBackup(userId);
    if (hasBackup == null) {
      throw Exception("Can't reach the server. Check your connection.");
    }
    if (!hasBackup) await generateAndBackupNewKey(pin);
  }

  Future<bool> hasLocalPrivateKey() async {
    final priv = await _storage.getPrivateKey();
    return priv != null && priv.isNotEmpty;
  }

  /// P6 (user report 2026-10-11): TRI-STATE backup check — `true`/`false`
  /// when the server answers, `null` when the check could not run (offline,
  /// server down, ANY error incl. a 403). The old catch-all `false` conflated
  /// "unreachable" with "no backup": it routed set-up users into Backup-PIN
  /// setup offline, and let key init upload a new public key over a backed-up
  /// one on a sign-in blip (K3). Treat `null` as "unknown", never as "no".
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

  /// Tri-state like [tryHasPocketBaseBackup]: null on ANY error.
  Future<BackupKind?> tryGetBackupKind(String userId) async {
    try {
      final userRecord = await _pb.collection('users').getOne(userId);
      final encrypted = userRecord.getStringValue('private_key_encrypted');
      if (encrypted.isEmpty) return BackupKind.none;
      return RegExp(r'^v\d+:').hasMatch(encrypted)
          ? BackupKind.current
          : BackupKind.legacy;
    } catch (e) {
      debugPrint('[Enc] backup kind check failed (unknown): $e');
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
