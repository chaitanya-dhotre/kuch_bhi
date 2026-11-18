import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import 'app_database.dart';
import 'tables/app_settings_table.dart';

/// One contact's pinned key (key-change-warning spec §4 A1). `key` is the
/// accepted X25519 public key; `pendingKey` is a different key the server
/// showed later and the user has not accepted yet.
class ContactKey {
  const ContactKey({
    required this.userId,
    required this.key,
    this.previousKeys = const [],
    this.pendingKey,
    this.pendingSince,
    this.verified = false,
    this.notifiedKey,
  });

  final String userId;
  final String key;

  /// Earlier accepted keys, newest first. Old messages still open with them.
  final List<String> previousKeys;
  final String? pendingKey;
  final DateTime? pendingSince;
  final bool verified;

  /// The pending key the "security code changed" lines were written for.
  final String? notifiedKey;

  bool get isPending => pendingKey != null;

  /// Every key this phone has accepted for the contact, current first.
  List<String> get acceptedKeys => [key, ...previousKeys];
}

/// Settings key (spec E1): the server key for ME that differs from this
/// phone's, set at sign-in, cleared when the user keeps or restores.
const kOwnKeyMismatchSetting = 'own_key_mismatch';

/// Local "security code changed" lines (spec A4, D6) carry the contact in
/// their id: `sys_kc_<userId>_<uuid>`. PocketBase ids have no underscore.
const kKeyChangeLinePrefix = 'sys_kc_';

String keyChangeLineId(String userId, String unique) =>
    '$kKeyChangeLinePrefix${userId}_$unique';

/// The contact a key-change line is about, or null for any other row.
String? keyChangeLineUserId(String localId) {
  if (!localId.startsWith(kKeyChangeLinePrefix)) return null;
  final rest = localId.substring(kKeyChangeLinePrefix.length);
  final cut = rest.indexOf('_');
  return cut <= 0 ? null : rest.substring(0, cut);
}

String keyChangeLineText(String? name) {
  final who = (name == null || name.trim().isEmpty) ? 'A contact' : name.trim();
  return "$who's security code changed. Tap to compare.";
}

/// What [ContactKeyStore.observe] did with a server key.
enum KeyObservation { ignored, firstSeen, same, cleared, stillPending, changed }

/// Trust-on-first-use pins per contact (audit F3). A raw-SQL table, not a
/// generated drift table: drift_dev cannot run on this toolchain (see the
/// requests and media-send work logs). Encryption reads only the pin, never
/// the server's `users.public_key`.
class ContactKeyStore {
  ContactKeyStore(this._db);

  final AppDatabase _db;

  static const createSql =
      'CREATE TABLE IF NOT EXISTS contact_keys ('
      'user_id TEXT NOT NULL PRIMARY KEY, '
      'key TEXT NOT NULL, '
      "previous_keys TEXT NOT NULL DEFAULT '[]', "
      'pending_key TEXT, '
      'pending_since INTEGER, '
      'verified INTEGER NOT NULL DEFAULT 0, '
      'notified_key TEXT, '
      'updated_at INTEGER NOT NULL)';

  /// Migration 14 → 15 (spec F1): one pin per cached key, me excluded,
  /// unverified, silent. Guarded for the minimal migration fixtures.
  static Future<void> seedFromUsers(AppDatabase db) async {
    final hasUsers = await db
        .customSelect(
          "SELECT 1 FROM sqlite_master WHERE type='table' AND name='users_table'",
        )
        .getSingleOrNull();
    if (hasUsers == null) return;
    final hasSettings = await db
        .customSelect(
          "SELECT 1 FROM sqlite_master WHERE type='table' "
          "AND name='app_settings_table'",
        )
        .getSingleOrNull();
    final notMe = hasSettings == null
        ? ''
        : ' AND id NOT IN (SELECT value FROM app_settings_table '
              "WHERE key = '${AppSettingsKeys.currentUserId}')";
    await db.customStatement(
      'INSERT OR IGNORE INTO contact_keys (user_id, key, updated_at) '
      'SELECT id, public_key, ${DateTime.now().millisecondsSinceEpoch} '
      "FROM users_table WHERE public_key IS NOT NULL AND public_key != ''"
      '$notMe',
    );
  }

  final _changes = StreamController<String>.broadcast();

  /// User ids whose pin row changed in this process.
  Stream<String> get changes => _changes.stream;

  Stream<ContactKey?> watch(String userId) async* {
    yield await get(userId);
    yield* changes.where((id) => id == userId).asyncMap((_) => get(userId));
  }

  Future<ContactKey?> get(String userId) async {
    final row = await _db
        .customSelect(
          'SELECT * FROM contact_keys WHERE user_id = ?',
          variables: [Variable.withString(userId)],
        )
        .getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  /// Contacts with a key waiting for the user, oldest change first.
  Future<List<ContactKey>> pending() async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM contact_keys WHERE pending_key IS NOT NULL '
          'ORDER BY pending_since',
        )
        .get();
    return rows.map(_fromRow).toList();
  }

  Future<String?> _me() =>
      _db.settingsDao.getSetting(AppSettingsKeys.currentUserId);

  /// Spec A2: the one entry point every server key passes through.
  Future<KeyObservation> observe(String userId, String? serverKey) async {
    if (serverKey == null || serverKey.isEmpty || userId.isEmpty) {
      return KeyObservation.ignored;
    }
    if (userId == await _me()) return KeyObservation.ignored;
    final now = DateTime.now().millisecondsSinceEpoch;
    final row = await get(userId);
    if (row == null) {
      await _db.customStatement(
        'INSERT OR IGNORE INTO contact_keys (user_id, key, updated_at) '
        'VALUES (?, ?, ?)',
        [userId, serverKey, now],
      );
      _changes.add(userId);
      return KeyObservation.firstSeen;
    }
    if (serverKey == row.key) {
      if (!row.isPending) return KeyObservation.same;
      // D-14: back to the pin, pending clears silently.
      await _db.customStatement(
        'UPDATE contact_keys SET pending_key = NULL, pending_since = NULL, '
        'notified_key = NULL, updated_at = ? WHERE user_id = ?',
        [now, userId],
      );
      _changes.add(userId);
      return KeyObservation.cleared;
    }
    if (serverKey == row.pendingKey) return KeyObservation.stillPending;
    // A key from `previous_keys` is still a change (spec A2).
    await _db.customStatement(
      'UPDATE contact_keys SET pending_key = ?, pending_since = ?, '
      'updated_at = ? WHERE user_id = ?',
      [serverKey, now, now, userId],
    );
    _changes.add(userId);
    return KeyObservation.changed;
  }

  /// Spec C2: keys a group-key wrap by [wrapperId] may be opened with. Me →
  /// my own local key only; anyone else → their accepted keys after the
  /// server key passed [observe] (a pending key is never among them).
  Future<List<String>> keysForWrapper(
    String wrapperId,
    String serverKey, {
    required Future<String?> Function() myLocalKey,
  }) async {
    if (wrapperId == await _me()) {
      final local = await myLocalKey();
      return [if (local != null && local.isNotEmpty) local];
    }
    await observe(wrapperId, serverKey);
    return (await get(wrapperId))?.acceptedKeys ?? const [];
  }

  /// Spec A5: the pending key becomes the pin; the old one moves to history.
  /// Returns false when nothing was pending.
  Future<bool> accept(String userId, {bool verified = false}) async {
    final row = await get(userId);
    final pending = row?.pendingKey;
    if (row == null || pending == null) return false;
    final previous = [row.key, ...row.previousKeys.where((k) => k != pending)];
    await _db.customStatement(
      'UPDATE contact_keys SET key = ?, previous_keys = ?, pending_key = NULL, '
      'pending_since = NULL, notified_key = NULL, verified = ?, updated_at = ? '
      'WHERE user_id = ?',
      [
        pending,
        jsonEncode(previous),
        verified ? 1 : 0,
        DateTime.now().millisecondsSinceEpoch,
        userId,
      ],
    );
    _changes.add(userId);
    return true;
  }

  Future<void> setVerified(String userId, bool verified) async {
    await _db.customStatement(
      'UPDATE contact_keys SET verified = ?, updated_at = ? WHERE user_id = ?',
      [verified ? 1 : 0, DateTime.now().millisecondsSinceEpoch, userId],
    );
    _changes.add(userId);
  }

  /// Records that the lines for [pendingKey] were written (spec A4).
  Future<void> markNotified(String userId, String pendingKey) async {
    await _db.customStatement(
      'UPDATE contact_keys SET notified_key = ? WHERE user_id = ? '
      'AND pending_key = ?',
      [pendingKey, userId, pendingKey],
    );
  }

  Future<void> clear() async {
    await _db.customStatement('DELETE FROM contact_keys');
  }

  ContactKey _fromRow(QueryRow r) {
    List<String> previous;
    try {
      previous = (jsonDecode(r.read<String>('previous_keys')) as List)
          .cast<String>();
    } catch (_) {
      previous = const [];
    }
    final since = r.read<int?>('pending_since');
    return ContactKey(
      userId: r.read<String>('user_id'),
      key: r.read<String>('key'),
      previousKeys: previous,
      pendingKey: r.read<String?>('pending_key'),
      pendingSince: since == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(since),
      verified: r.read<int>('verified') == 1,
      notifiedKey: r.read<String?>('notified_key'),
    );
  }
}
