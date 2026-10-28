import 'dart:convert';

import '../../../data/local/database/daos/settings_dao.dart';
import '../../../domain/entities/friend_request.dart';
import '../../../domain/entities/group_invite.dart';
import '../../../domain/entities/user.dart';

/// Cold-start offline cache for the Requests page (checklist H3).
///
/// H3: "Open-while-offline with stale local cache renders last-good list when
/// available; error state only when nothing to show."
///
/// The Drift tables that back this (`friend_requests_table`, `users_table`)
/// are WRITTEN by the repositories but never READ back for a list, and there
/// is no local table for group invites at all — so before this cache the
/// page had nothing to render on a cold start without the network.
///
/// Storage is the existing key/value `app_settings_table` (one row per
/// user+kind, JSON payload). Deliberately NOT a new Drift table: the
/// project's code generator cannot run in the current toolchain (the locked
/// `analyzer` 7.6 cannot parse the Dart 3.13 SDK's dot-shorthand syntax),
/// and a hand-written table would bypass the schema/migration path that
/// owns every other table in this database.
///
/// Scope limits (deliberate):
/// - Only PENDING requests/invites are cached; accepted/declined rows are
///   dropped on write, so a stale cache can never resurrect a handled row.
/// - The cache is namespaced by the current user id — signing out wipes
///   `app_settings_table` (AuthRepositoryImpl.signOut deletes every table),
///   and a different user never sees the previous user's rows.
/// - No plaintext message content is involved; only names/usernames.
class RequestSnapshotCache {
  RequestSnapshotCache(this._store);

  /// Minimal key/value store seam (SettingsDao in production).
  final SnapshotStore _store;

  static const _keyPrefix = 'requests_snapshot';

  String _key(String kind, String userId) => '$_keyPrefix.$kind.$userId';

  /// Persist the last-good pending list for [userId].
  Future<void> writeRequests(String userId, List<FriendRequest> rows) =>
      _store.write(_key('friends', userId), _encodeRequests(rows));

  /// Persist the last-good pending invite list for [userId].
  Future<void> writeInvites(String userId, List<GroupInvite> rows) =>
      _store.write(_key('invites', userId), _encodeInvites(rows));

  /// Read the cached pending requests for [userId].
  ///
  /// Returns **null when no snapshot exists** and a (possibly empty) list when
  /// one does. The distinction matters: "no snapshot" means we could not
  /// determine the list (the page shows the error state), while an EMPTY
  /// snapshot means the last known state was "you have nothing pending" (the
  /// page shows the empty state). Collapsing the two would show an error
  /// where the user should see "No pending requests".
  Future<List<FriendRequest>?> readRequests(String userId) async {
    final raw = await _store.read(_key('friends', userId));
    if (raw == null) return null;
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(_decodeRequest)
          .whereType<FriendRequest>()
          .toList();
    } catch (_) {
      // A corrupt snapshot must never break the page — treat it as absent.
      return null;
    }
  }

  /// Read the cached pending invites for [userId] — null when no snapshot
  /// exists (see [readRequests]).
  Future<List<GroupInvite>?> readInvites(String userId) async {
    final raw = await _store.read(_key('invites', userId));
    if (raw == null) return null;
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(_decodeInvite)
          .whereType<GroupInvite>()
          .toList();
    } catch (_) {
      return null;
    }
  }

  /// Drop one handled row from the snapshot.
  ///
  /// Called when the user accepts or declines: the server has already
  /// handled that row, so it must not come back from the snapshot if the
  /// next fetch fails. Without this, a declined request would reappear on
  /// screen (and be re-actionable) after a network drop.
  Future<void> removeRequest(String userId, String requestId) async {
    final rows = await readRequests(userId);
    if (rows == null) return;
    final kept = rows.where((r) => r.id != requestId).toList();
    if (kept.length == rows.length) return; // already absent
    await _store.write(_key('friends', userId), _encodeRequests(kept));
  }

  /// Drop one handled invite from the snapshot — see [removeRequest].
  Future<void> removeInvite(String userId, String inviteId) async {
    final rows = await readInvites(userId);
    if (rows == null) return;
    final kept = rows.where((r) => r.id != inviteId).toList();
    if (kept.length == rows.length) return;
    await _store.write(_key('invites', userId), _encodeInvites(kept));
  }

  /// Drop both snapshots for [userId] (used when the server says the list is
  /// empty, so an empty server list does not keep a stale cache alive).
  Future<void> clear(String userId) async {
    await _store.delete(_key('friends', userId));
    await _store.delete(_key('invites', userId));
  }

  static String _encodeRequests(List<FriendRequest> rows) => jsonEncode(
        rows
            .where((r) => r.isPending)
            .map(
              (r) => {
                'id': r.id,
                'status': r.status,
                'createdAt': r.createdAt.toIso8601String(),
                'fromUser': _encodeUser(r.fromUser),
                'toUser': _encodeUser(r.toUser),
              },
            )
            .toList(),
      );

  static String _encodeInvites(List<GroupInvite> rows) => jsonEncode(
        rows
            .where((r) => r.isPending)
            .map(
              (r) => {
                'id': r.id,
                'conversationId': r.conversationId,
                'conversationName': r.conversationName,
                'status': r.status,
                'createdAt': r.createdAt.toIso8601String(),
                'invitedBy': _encodeUser(r.invitedBy),
              },
            )
            .toList(),
      );

  static Map<String, dynamic> _encodeUser(User u) => {
        'id': u.id,
        'displayName': u.displayName,
        'username': u.username,
        'email': u.email,
        'friendCode': u.friendCode,
        'avatarUrl': u.avatarUrl,
        'about': u.about,
        'publicKey': u.publicKey,
        'isOnline': u.isOnline,
        'lastSeen': u.lastSeen?.toIso8601String(),
        'createdAt': u.createdAt.toIso8601String(),
      };

  static User? _decodeUser(Map<String, dynamic> m) {
    final id = m['id'];
    if (id is! String || id.isEmpty) return null;
    return User(
      id: id,
      displayName: m['displayName'] is String ? m['displayName'] as String : '',
      username: m['username'] is String ? m['username'] as String : '',
      email: m['email'] is String ? m['email'] as String : '',
      friendCode: m['friendCode'] is String ? m['friendCode'] as String : '',
      avatarUrl: m['avatarUrl'] is String ? m['avatarUrl'] as String : null,
      about: m['about'] is String ? m['about'] as String : null,
      publicKey: m['publicKey'] is String ? m['publicKey'] as String : null,
      isOnline: m['isOnline'] == true,
      lastSeen: DateTime.tryParse('${m['lastSeen']}'),
      createdAt: DateTime.tryParse('${m['createdAt']}') ?? DateTime.now(),
    );
  }

  static FriendRequest? _decodeRequest(Map<String, dynamic> m) {
    final id = m['id'];
    if (id is! String || id.isEmpty) return null;
    final from = m['fromUser'];
    if (from is! Map<String, dynamic>) return null;
    final fromUser = _decodeUser(from);
    if (fromUser == null) return null;
    final to = m['toUser'];
    final toUser = to is Map<String, dynamic> ? _decodeUser(to) : null;
    return FriendRequest(
      id: id,
      fromUser: fromUser,
      toUser: toUser ?? fromUser,
      status: m['status'] is String ? m['status'] as String : 'pending',
      createdAt: DateTime.tryParse('${m['createdAt']}') ?? DateTime.now(),
    );
  }

  static GroupInvite? _decodeInvite(Map<String, dynamic> m) {
    final id = m['id'];
    if (id is! String || id.isEmpty) return null;
    final by = m['invitedBy'];
    if (by is! Map<String, dynamic>) return null;
    final invitedBy = _decodeUser(by);
    if (invitedBy == null) return null;
    return GroupInvite(
      id: id,
      conversationId: m['conversationId'] is String
          ? m['conversationId'] as String
          : '',
      conversationName: m['conversationName'] is String
          ? m['conversationName'] as String
          : 'Group',
      invitedBy: invitedBy,
      status: m['status'] is String ? m['status'] as String : 'pending',
      createdAt: DateTime.tryParse('${m['createdAt']}') ?? DateTime.now(),
    );
  }
}

/// Key/value seam over `app_settings_table`.
abstract class SnapshotStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Production store backed by the app's Drift settings table.
class SettingsSnapshotStore implements SnapshotStore {
  SettingsSnapshotStore(this._dao);

  final SettingsDao _dao;

  @override
  Future<String?> read(String key) => _dao.getSetting(key);

  @override
  Future<void> write(String key, String value) => _dao.setSetting(key, value);

  @override
  Future<void> delete(String key) => _dao.deleteSetting(key);
}
