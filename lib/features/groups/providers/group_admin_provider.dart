import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/group_invite.dart';
import '../../../domain/repositories/message_repository.dart';
import '../../../data/local/database/app_database.dart';
import '../../../infrastructure/repositories/message_repository_impl.dart';
import '../../chat/providers/chat_provider.dart';

/// Group Info mutations (checklist A5 / L4: the screen reads domain
/// providers only — `group_settings_screen.dart` must not import
/// `message_repository_impl.dart`). Every call is the EXISTING
/// `MessageRepository` method, unchanged; only the boundary and the busy
/// bookkeeping live here.
///
/// Bounds (E3 / F2 / G2):
/// * 8s on every call — PocketBase's HTTP client has no request timeout, so
///   a blackholed socket would otherwise leave a busy lock stuck forever.
/// * 30s on remove and leave, UI only: `.timeout` never cancels or retries
///   the underlying repository call (E2E boundary), it just releases the UI
///   so the caller can show "Still working — this can take a moment.".
const groupAdminFastBound = Duration(seconds: 8);
const groupAdminSlowBound = Duration(seconds: 30);

/// Admin-side invite list for a conversation. Invalidate after any invite
/// mutation.
final pendingInvitesProvider = FutureProvider.autoDispose
    .family<List<PendingGroupInvite>, String>(
  (ref, conversationId) => ref
      .watch(messageRepositoryProvider)
      .getPendingInvitesForConversation(conversationId),
);

/// Current disappearing-messages duration for a conversation (seconds),
/// straight from the Drift row — the Group Info settings row shows it as its
/// trailing label (G9 / registry C11).
final disappearingDurationProvider = StreamProvider.autoDispose.family<int, String>(
  (ref, conversationId) => ref
      .watch(appDatabaseProvider)
      .conversationsDao
      .watchConversationById(conversationId)
      .map((row) => row?.disappearingDuration ?? 0),
);

/// Busy keys: `member:{id}` · `invite:{id}` · `photo` · `rename` · `switch`
/// · `leave` · `add-sheet`. One key per independently lockable surface, so a
/// busy row never freezes its siblings (E2).
typedef GroupAdminBusy = Set<String>;

class GroupAdminNotifier extends Notifier<GroupAdminBusy> {
  @override
  GroupAdminBusy build() => const <String>{};

  String memberKey(String userId) => 'member:$userId';

  String inviteKey(String inviteId) => 'invite:$inviteId';

  /// Runs [call] under [key]'s busy lock and [bound].
  ///
  /// Returns `false` when the key is already busy — the caller treats that
  /// as a no-op (a second tap must do nothing, E2). Throws on failure so the
  /// screen can show the right toast; the lock is always released in
  /// `finally`, including on a timeout.
  Future<bool> _run(
    String key,
    Future<void> Function(MessageRepository repo) call, {
    Duration bound = groupAdminFastBound,
  }) async {
    if (state.contains(key)) return false;
    state = <String>{...state, key};
    try {
      await call(ref.read(messageRepositoryProvider)).timeout(bound);
      return true;
    } finally {
      if (state.contains(key)) {
        state = <String>{...state}..remove(key);
      }
    }
  }

  // ── Members ────────────────────────────────────────────────────────────

  Future<bool> promote(String conversationId, String userId) async {
    final ok = await _run(
      memberKey(userId),
      (repo) => repo.promoteMemberToAdmin(conversationId, userId),
    );
    if (ok) ref.invalidate(groupMembersProvider(conversationId));
    return ok;
  }

  Future<bool> demote(String conversationId, String userId) async {
    final ok = await _run(
      memberKey(userId),
      (repo) => repo.demoteAdminToMember(conversationId, userId),
    );
    if (ok) ref.invalidate(groupMembersProvider(conversationId));
    return ok;
  }

  /// Bounded at 30s (UI only — the repository call is never cancelled). A
  /// second remove/leave after the bound is safe: the repository queues
  /// key rotations per group.
  Future<bool> remove(String conversationId, String userId) async {
    final ok = await _run(
      memberKey(userId),
      (repo) => repo.removeMemberFromGroup(conversationId, userId),
      bound: groupAdminSlowBound,
    );
    if (ok) ref.invalidate(groupMembersProvider(conversationId));
    return ok;
  }

  /// Bounded at 30s (UI only — the repository call is never cancelled).
  Future<bool> leave(String conversationId) async {
    final ok = await _run(
      'leave',
      (repo) => repo.leaveGroup(conversationId),
      bound: groupAdminSlowBound,
    );
    if (ok) ref.invalidate(groupMembersProvider(conversationId));
    return ok;
  }

  // ── Header ─────────────────────────────────────────────────────────────

  Future<bool> rename(String conversationId, String name) => _run(
        'rename',
        (repo) => repo.updateGroupInfo(conversationId, name: name),
      );

  Future<bool> updatePhoto(String conversationId, {File? iconFile}) => _run(
        'photo',
        (repo) => repo.updateGroupInfo(conversationId, iconFile: iconFile),
      );

  // ── Settings ───────────────────────────────────────────────────────────

  Future<bool> setOnlyAdminsCanMessage(String conversationId, bool value) =>
      _run(
        'switch',
        (repo) => repo.setOnlyAdminsCanMessage(conversationId, value),
      );

  // ── Invites ────────────────────────────────────────────────────────────

  /// Invite statuses for the add sheet. Reads are never busy-locked.
  Future<Map<String, String>> inviteStatuses(String conversationId) => ref
      .read(messageRepositoryProvider)
      .getInviteStatusesForConversation(conversationId)
      .timeout(groupAdminFastBound);

  Future<bool> cancelInvite(String conversationId, String inviteId) async {
    final ok = await _run(
      inviteKey(inviteId),
      (repo) => repo.cancelGroupInvite(inviteId),
    );
    if (ok) ref.invalidate(pendingInvitesProvider(conversationId));
    return ok;
  }

  Future<bool> reInvite(String conversationId, String userId) async {
    final ok = await _run(
      inviteKey(userId),
      (repo) => repo.sendGroupInvite(conversationId, userId),
    );
    if (ok) ref.invalidate(pendingInvitesProvider(conversationId));
    return ok;
  }

  /// The add-sheet send pass: one lock for the whole sheet (F4 — the sheet
  /// stays open and busy while sending), one 8s bound per invite.
  ///
  /// Returns `null` when the sheet is already sending (no-op), otherwise the
  /// `{ok, failed}` counts for the outcome toast.
  Future<({int ok, int failed})?> sendInvites(
    String conversationId,
    List<String> userIds,
  ) async {
    const key = 'add-sheet';
    if (state.contains(key)) return null;
    state = <String>{...state, key};
    var ok = 0;
    var failed = 0;
    try {
      for (final userId in userIds) {
        try {
          await ref
              .read(messageRepositoryProvider)
              .sendGroupInvite(conversationId, userId)
              .timeout(groupAdminFastBound);
          ok += 1;
        } catch (e) {
          failed += 1;
          // Detail stays out of user-visible text (A4).
          debugPrint('[Group] invite send failed: $e');
        }
      }
    } finally {
      if (state.contains(key)) {
        state = <String>{...state}..remove(key);
      }
    }
    ref.invalidate(pendingInvitesProvider(conversationId));
    return (ok: ok, failed: failed);
  }
}

final groupAdminProvider =
    NotifierProvider<GroupAdminNotifier, GroupAdminBusy>(
  GroupAdminNotifier.new,
);