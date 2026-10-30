import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/app_field.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/busy_spinner.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/search_field.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/settings_tile.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_banner.dart';
import '../../../domain/entities/conversation.dart';
import '../../../domain/entities/friendship.dart';
import '../../../domain/entities/group_invite.dart';
import '../../../domain/entities/user.dart';
import '../../../features/chat/message_offline_policy.dart';
import '../../../features/chat/providers/chat_provider.dart';
import '../../../features/chat/widgets/disappearing_dialog.dart';
import '../../../features/chat/widgets/message_context_menu.dart';
import '../../../features/home/providers/friends_provider.dart';
import '../../../features/media/screens/media_docs_screen.dart';
import '../../../infrastructure/offline/connectivity_signal.dart';
import '../providers/group_admin_provider.dart';

/// Requests H1 string, verbatim (I1).
const _offlineCopy = "You're offline — actions are available when you're back.";

/// Stable mutation-failure copy (R5, shared with the Requests page).
const _updateFailed = "Couldn't update. Try again.";

/// Remove/Leave 30s UI bound outcome (E3).
const _stillWorking = "Still working — this can take a moment.";

String _safeName(String? raw) {
  final value = (raw ?? '').trim();
  return value.isEmpty ? 'Unknown' : value;
}

/// First letter WITHOUT a range-taking call (grep gate) and without a
/// RangeError on an empty name (C1/H2).
String _initial(String value, {required String fallback}) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? fallback : trimmed[0].toUpperCase();
}

Duration _motionDuration(BuildContext context, Duration duration) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;

/// Admin-side Group Info screen (checklist A–K).
class GroupSettingsScreen extends ConsumerStatefulWidget {
  const GroupSettingsScreen({super.key, required this.conversation});

  final Conversation conversation;

  @override
  ConsumerState<GroupSettingsScreen> createState() =>
      _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends ConsumerState<GroupSettingsScreen> {
  /// Optimistic switch value. Cleared on failure so the row snaps back to
  /// the stream value (G2).
  bool? _switchValue;
  bool _leaving = false;

  String get _cid => widget.conversation.id;

  // ── Mutation plumbing ────────────────────────────────────────────────

  /// Runs one notifier mutation with the house toast contract: success toast
  /// and optional announcement, `Still working…` on a slow-bound timeout,
  /// `Couldn't update. Try again.` on any other failure. Never renders `$e`.
  Future<bool> _guard(
    Future<bool> Function() action, {
    String? success,
    bool announce = false,
    String timeoutCopy = _updateFailed,
    VoidCallback? onSuccess,
  }) async {
    try {
      final started = await action();
      if (!started || !mounted) return false;
      if (success != null) {
        showToast(context, success);
        if (announce) _announce(success);
      }
      onSuccess?.call();
      return true;
    } on TimeoutException {
      debugPrint('[Group] mutation hit its UI bound');
      if (mounted) showToast(context, timeoutCopy, error: true);
      return false;
    } catch (e) {
      debugPrint('[Group] mutation failed: $e');
      if (mounted) showToast(context, _updateFailed, error: true);
      return false;
    }
  }

  void _announce(String message) {
    if (!mounted) return;
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
    );
  }

  // ── Header actions ───────────────────────────────────────────────────

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    await _guard(
      () => ref
          .read(groupAdminProvider.notifier)
          .updatePhoto(_cid, iconFile: File(picked.path)),
    );
  }

  Future<void> _rename(String currentName) async {
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => _RenameDialog(currentName: currentName),
    );
    if (newName == null || !mounted) return;
    await _guard(
      () => ref.read(groupAdminProvider.notifier).rename(_cid, newName),
    );
  }

  // ── Member actions ───────────────────────────────────────────────────

  void _openMemberActions(User target) {
    final name = _safeName(target.displayName);
    final handle = target.username.trim();
    final isAdminTarget = target.groupRole == 'admin';
    final members =
        ref.read(groupMembersProvider(_cid)).valueOrNull ?? const <User>[];
    final adminCount =
        members.where((m) => m.groupRole == 'admin').length;

    showActionSheet(
      context: context,
      header: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            AppAvatar(
              url: target.avatarUrl,
              initials: _initial(name, fallback: '?'),
              radius: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: context.t.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    handle.isEmpty
                        ? (isAdminTarget ? 'Admin' : 'Member')
                        : '$handle · ${isAdminTarget ? 'Admin' : 'Member'}',
                    style: TextStyle(fontSize: 13, color: context.t.inkSoft),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (!isAdminTarget)
          ConversationMenuAction(
            label: 'Make Admin',
            icon: Icons.add_moderator_outlined,
            callback: () => unawaited(_promote(target)),
          )
        else if (adminCount > 1)
          ConversationMenuAction(
            label: 'Remove Admin',
            icon: Icons.remove_moderator_outlined,
            callback: () => unawaited(_demote(target)),
          ),
        ConversationMenuAction(
          label: 'Remove from Group',
          icon: Icons.person_remove_outlined,
          destructive: true,
          callback: () => unawaited(_confirmRemove(target)),
        ),
      ],
    );
  }

  Future<void> _promote(User target) async {
    final name = _safeName(target.displayName);
    await _guard(
      () => ref.read(groupAdminProvider.notifier).promote(_cid, target.id),
      success: '$name is now an admin',
    );
  }

  Future<void> _demote(User target) async {
    final name = _safeName(target.displayName);
    await _guard(
      () => ref.read(groupAdminProvider.notifier).demote(_cid, target.id),
      success: '$name is no longer an admin',
    );
  }

  Future<void> _confirmRemove(User target) async {
    final name = _safeName(target.displayName);
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Remove from Group',
      body: 'Remove $name from the group?',
      confirmLabel: 'Remove',
      confirmIcon: Icons.person_remove_outlined,
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    await _guard(
      () => ref.read(groupAdminProvider.notifier).remove(_cid, target.id),
      success: '$name removed',
      announce: true,
      timeoutCopy: _stillWorking,
    );
  }

  Future<void> _confirmLeave() async {
    final members =
        ref.read(groupMembersProvider(_cid)).valueOrNull ?? const <User>[];
    final myId = ref.read(currentUserIdProvider).asData?.value ?? '';
    final admins = members.where((m) => m.groupRole == 'admin').toList();
    final others = members.where((m) => m.id != myId).toList();

    // Read-only mirror of leaveGroup's sole-admin promotion rule: the
    // earliest-joined other member inherits the role (E4 SHOULD).
    String? nextAdminName;
    if (admins.length == 1 &&
        admins.firstOrNull?.id == myId &&
        others.isNotEmpty) {
      final next = others.reduce((a, b) => a.createdAt.isBefore(b.createdAt)
          ? a
          : b);
      nextAdminName = _safeName(next.displayName);
    }

    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Leave Group?',
      body: nextAdminName == null
          ? 'You will lose access to this group and its messages.'
          : 'You will lose access to this group and its messages.\n'
              '$nextAdminName will become the admin.',
      confirmLabel: 'Leave',
      confirmIcon: Icons.logout,
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _leaving = true);
    await _guard(
      () => ref.read(groupAdminProvider.notifier).leave(_cid),
      timeoutCopy: _stillWorking,
      onSuccess: () {
        if (mounted) Navigator.of(context).pop(); // back to ChatScreen
      },
    );
    if (mounted && _leaving) setState(() => _leaving = false);
  }

  // ── Invites ──────────────────────────────────────────────────────────

  Future<void> _cancelInvite(PendingGroupInvite invite) async {
    await _guard(
      () => ref
          .read(groupAdminProvider.notifier)
          .cancelInvite(_cid, invite.inviteId),
    );
  }

  Future<void> _reInvite(PendingGroupInvite invite) async {
    await _guard(
      () => ref
          .read(groupAdminProvider.notifier)
          .reInvite(_cid, invite.user.id),
      success: 'Invite sent',
    );
  }

  void _openAddSheet(Iterable<User> members) {
    showAppSheet<void>(
      context: context,
      builder: (_) => _AddMembersSheet(
        conversationId: _cid,
        existingMemberIds: members.map((m) => m.id).toSet(),
      ),
    );
  }

  // ── Settings ─────────────────────────────────────────────────────────

  Future<void> _toggleSwitch(bool value) async {
    final previous = _switchValue;
    setState(() => _switchValue = value);
    final ok = await _guard(
      () => ref
          .read(groupAdminProvider.notifier)
          .setOnlyAdminsCanMessage(_cid, value),
    );
    if (!ok && mounted) {
      // Snap back to the stream value (G2).
      setState(() => _switchValue = previous);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final online = ref.watch(isOnlineProvider).valueOrNull ?? true;
    final busy = ref.watch(groupAdminProvider);
    final convAsync = ref.watch(conversationStreamProvider(_cid));
    final membersAsync = ref.watch(groupMembersProvider(_cid));

    final convLoading =
        convAsync.isLoading && convAsync.valueOrNull == null;
    final membersLoading =
        membersAsync.isLoading && membersAsync.valueOrNull == null;

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        surfaceTintColor: t.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Semantics(
          header: true,
          child: Text(
            'Group Info',
            style: TextStyle(
              color: t.ink,
              fontSize: 20,
              height: 1.3,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          _OfflineStrip(visible: !online),
          Expanded(
            child: convLoading || membersLoading
                ? const _GroupInfoSkeleton()
                : _buildBody(online: online, busy: busy),
          ),
        ],
      ),
    );
  }

  Widget _buildBody({
    required bool online,
    required Set<String> busy,
  }) {
    final t = context.t;
    final myId = ref.watch(currentUserIdProvider).asData?.value ?? '';
    final convAsync = ref.watch(conversationStreamProvider(_cid));
    final membersAsync = ref.watch(groupMembersProvider(_cid));
    final conv = convAsync.valueOrNull ?? widget.conversation;

    final membersError =
        membersAsync.hasError && membersAsync.valueOrNull == null;
    final members = membersAsync.valueOrNull ?? const <User>[];

    // D1: you first, then admins A→Z, then members A→Z; left never listed.
    final active = members.where((m) => m.groupRole != 'left').toList()
      ..sort((a, b) {
        int rank(User u) =>
            u.id == myId ? 0 : (u.groupRole == 'admin' ? 1 : 2);
        final byRank = rank(a).compareTo(rank(b));
        if (byRank != 0) return byRank;
        return _safeName(a.displayName)
            .toLowerCase()
            .compareTo(_safeName(b.displayName).toLowerCase());
      });

    final myMember = members.where((m) => m.id == myId).firstOrNull;
    final isLeft = myMember?.groupRole == 'left';
    // B2: an error hides every admin affordance instead of faking "member".
    final isAdmin = !membersError && myMember?.groupRole == 'admin';

    final rawName = (conv.name ?? '').trim();
    final groupName = rawName.isEmpty ? 'Group' : rawName;

    final children = <Widget>[
      if (isLeft)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: StatusBanner(message: "You're no longer in this group."),
        ),
      if (membersError)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: StatusBanner(
            message: "Couldn't load members.",
            onRetry: () => ref.invalidate(groupMembersProvider(_cid)),
          ),
        ),
      _header(
        conv: conv,
        name: groupName,
        isAdmin: isAdmin,
        isLeft: isLeft,
        online: online,
        busy: busy,
        count: active.length,
        showCount: !membersError,
      ),
    ];

    if (!membersError) {
      children.add(
        _membersSection(
          active: active,
          myId: myId,
          isAdmin: isAdmin,
          isLeft: isLeft,
          online: online,
          busy: busy,
        ),
      );
    }

    children.addAll(_invitesSection(isAdmin: isAdmin, isLeft: isLeft));
    children.addAll(_settingsSection(
      conv: conv,
      isAdmin: isAdmin,
      isLeft: isLeft,
      online: online,
      busy: busy,
    ));

    if (!online) {
      // I2: exactly ONE hint for the screen — each surface above carries
      // exactly one 38% dim of its own.
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              kOfflineActionHint,
              style: TextStyle(fontSize: 12, color: t.inkSoft),
            ),
          ),
        ),
      );
    }
    children.add(const SizedBox(height: 32));

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  // ── Header (C1–C3) ───────────────────────────────────────────────────

  Widget _header({
    required Conversation conv,
    required String name,
    required bool isAdmin,
    required bool isLeft,
    required bool online,
    required Set<String> busy,
    required int count,
    required bool showCount,
  }) {
    final t = context.t;
    final canEdit = isAdmin && !isLeft;
    final uploading = busy.contains('photo');
    final photoLive = canEdit && online && !uploading;

    final disc = Stack(
      alignment: Alignment.center,
      children: [
        AppAvatar(
          url: conv.iconUrl,
          initials: _initial(name, fallback: 'G'),
          radius: 48,
          accentSoft: true,
        ),
        if (uploading)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: t.ink.withAlpha(115),
                shape: BoxShape.circle,
              ),
              child: const Center(child: BusySpinner()),
            ),
          ),
        if (canEdit && !uploading)
          Positioned(
            right: 2,
            bottom: 2,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: t.accent,
                shape: BoxShape.circle,
                border: Border.all(color: t.bg, width: 2),
              ),
              child: Icon(Icons.camera_alt, size: 16, color: t.onAccent),
            ),
          ),
      ],
    );

    final photo = Semantics(
      container: true,
      button: canEdit,
      label: canEdit ? 'Change group photo' : null,
      excludeSemantics: true,
      onTap: photoLive ? _pickPhoto : null,
      child: GestureDetector(
        onTap: photoLive ? _pickPhoto : null,
        child: disc,
      ),
    );

    final nameStyle = TextStyle(
      fontSize: 20,
      height: 1.3,
      fontWeight: FontWeight.w700,
      color: t.ink,
    );
    final nameWidget = canEdit
        ? Semantics(
            container: true,
            header: true,
            button: true,
            label: 'Edit group name',
            excludeSemantics: true,
            onTap: online ? () => unawaited(_rename(name)) : null,
            child: InkWell(
              onTap: online ? () => unawaited(_rename(name)) : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: nameStyle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.edit_outlined, size: 18, color: t.inkSoft),
                    ],
                  ),
                ),
              ),
            ),
          )
        : Semantics(
            header: true,
            excludeSemantics: true,
            label: name,
            child: Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: nameStyle,
            ),
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Opacity(
        opacity: online || !canEdit ? 1 : .38,
        child: Column(
          children: [
            photo,
            const SizedBox(height: 16),
            nameWidget,
            if (showCount) ...[
              const SizedBox(height: 4),
              Text(
                count == 1 ? '1 member' : '$count members',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.38,
                  color: t.inkSoft,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Members (D1–D3, E1–E2) ───────────────────────────────────────────

  Widget _membersSection({
    required List<User> active,
    required String myId,
    required bool isAdmin,
    required bool isLeft,
    required bool online,
    required Set<String> busy,
  }) {
    final t = context.t;
    final canAdd = isAdmin && !isLeft;
    final live = online; // reads stay live; actions are gated below

    return Opacity(
      opacity: canAdd && !online ? .38 : 1,
      child: IgnorePointer(
        ignoring: canAdd && !online,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 24, 0, 0),
              child: Row(
                children: [
                  Expanded(
                    child: SectionHeader('Members', count: active.length),
                  ),
                  if (canAdd) _addChip(onTap: live ? _openAddSheetRow : null),
                  const SizedBox(width: 16),
                ],
              ),
            ),
            if (active.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(
                  'No members yet',
                  style: TextStyle(fontSize: 13, color: t.inkSoft),
                ),
              )
            else
              _groupedList([
                for (final member in active)
                  _memberRow(
                    member: member,
                    myId: myId,
                    isAdmin: isAdmin && !isLeft,
                    online: online,
                    busy: busy,
                  ),
              ]),
          ],
        ),
      ),
    );
  }

  void _openAddSheetRow() {
    final members =
        ref.read(groupMembersProvider(_cid)).valueOrNull ?? const <User>[];
    _openAddSheet(members);
  }

  Widget _addChip({required VoidCallback? onTap}) {
    final t = context.t;
    return Semantics(
      button: true,
      label: 'Add member',
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 48,
          width: 64,
          child: Center(
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: ShapeDecoration(
                color: t.accentSoft,
                shape: const StadiumBorder(),
              ),
              child: Center(
                child: Text(
                  '＋ Add',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: t.ink,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _memberRow({
    required User member,
    required String myId,
    required bool isAdmin,
    required bool online,
    required Set<String> busy,
  }) {
    final t = context.t;
    final name = _safeName(member.displayName);
    final isSelf = member.id == myId;
    final isAdm = member.groupRole == 'admin';
    final key = ref.read(groupAdminProvider.notifier).memberKey(member.id);
    final rowBusy = busy.contains(key);
    final canAct = isAdmin && !isSelf && online && !rowBusy;

    final label = <String>[
      name,
      if (isAdm) 'admin',
      if (isSelf)
        'you'
      else if (member.username.trim().isNotEmpty)
        '@${member.username.trim()}',
    ].join(', ');

    final meta = isSelf ? 'You' : '@${member.username.trim()}';

    return Row(
      children: [
        Expanded(
          child: Semantics(
            container: true,
            button: canAct,
            label: label,
            hint: canAct ? 'Double tap for options' : null,
            excludeSemantics: true,
            onTap: canAct ? () => _openMemberActions(member) : null,
            child: InkWell(
              onTap: canAct ? () => _openMemberActions(member) : null,
              onLongPress: canAct ? () => _openMemberActions(member) : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 60),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      AppAvatar(
                        url: member.avatarUrl,
                        initials: _initial(name, fallback: '?'),
                        radius: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 16,
                                      height: 1.375,
                                      fontWeight: FontWeight.w600,
                                      color: t.ink,
                                    ),
                                  ),
                                ),
                                if (isAdm) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: ShapeDecoration(
                                      color: t.accentSoft,
                                      shape: const StadiumBorder(),
                                    ),
                                    child: Text(
                                      'Admin',
                                      style: TextStyle(
                                        fontSize: 11,
                                        height: 1.27,
                                        fontWeight: FontWeight.w600,
                                        color: t.ink,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              meta,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.38,
                                color: t.inkSoft,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (rowBusy)
          const SizedBox(width: 48, child: Center(child: BusySpinner()))
        else if (isAdmin && !isSelf)
          Semantics(
            container: true,
            button: true,
            label: 'Options for $name',
            excludeSemantics: true,
            onTap: online ? () => _openMemberActions(member) : null,
            child: IconButton(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              padding: EdgeInsets.zero,
              onPressed: online ? () => _openMemberActions(member) : null,
              icon: Icon(Icons.more_vert, color: online ? t.inkSoft : t.inkFaint),
            ),
          ),
      ],
    );
  }

  // ── Invites (F1–F2) ──────────────────────────────────────────────────

  List<Widget> _invitesSection({
    required bool isAdmin,
    required bool isLeft,
  }) {
    if (!isAdmin || isLeft) return const [];
    // F1: hidden offline (the strip already explains why).
    if (!(ref.watch(isOnlineProvider).valueOrNull ?? true)) return const [];

    final invitesAsync = ref.watch(pendingInvitesProvider(_cid));
    final rows = (invitesAsync.valueOrNull ?? const <PendingGroupInvite>[])
        .where((i) => i.status != 'accepted')
        .toList();
    final hasError = invitesAsync.hasError && invitesAsync.valueOrNull == null;

    if (rows.isEmpty && !hasError) return const [];

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(0, 24, 0, 0),
        child: Row(
          children: [
            Expanded(child: SectionHeader('Invites', count: rows.length)),
            const SizedBox(width: 16),
          ],
        ),
      ),
      if (hasError)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
          child: StatusBanner(
            message: "Couldn't load invites.",
            onRetry: () => ref.invalidate(pendingInvitesProvider(_cid)),
          ),
        ),
      if (rows.isNotEmpty)
        _groupedList([
          for (final invite in rows) _inviteRow(invite),
        ]),
    ];
  }

  Widget _inviteRow(PendingGroupInvite invite) {
    final t = context.t;
    final notifier = ref.read(groupAdminProvider.notifier);
    final pending = invite.status == 'pending';
    final key = notifier.inviteKey(
      pending ? invite.inviteId : invite.user.id,
    );
    final rowBusy = ref.watch(groupAdminProvider).contains(key);
    final name = _inviteName(invite);

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            AppAvatar(
              url: invite.user.avatarUrl,
              initials: _initial(name, fallback: '?'),
              radius: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.375,
                      fontWeight: FontWeight.w600,
                      color: t.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    pending ? 'Invite pending' : 'Declined',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.38,
                      color: t.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
            if (rowBusy)
              const SizedBox(width: 48, child: Center(child: BusySpinner()))
            else
              SizedBox(
                height: 48,
                child: AppButton(
                  variant: AppButtonVariant.text,
                  onPressed: () => unawaited(
                    pending ? _cancelInvite(invite) : _reInvite(invite),
                  ),
                  child: Text(pending ? 'Cancel' : 'Re-invite'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _inviteName(PendingGroupInvite invite) {
    final name = invite.user.displayName.trim();
    if (name.isNotEmpty) return name;
    final handle = invite.user.username.trim();
    if (handle.isNotEmpty) return '@$handle';
    return 'Unknown';
  }

  // ── Settings (G1–G4) ─────────────────────────────────────────────────

  List<Widget> _settingsSection({
    required Conversation conv,
    required bool isAdmin,
    required bool isLeft,
    required bool online,
    required Set<String> busy,
  }) {
    final t = context.t;
    final switchBusy = busy.contains('switch');
    final switchValue = _switchValue ?? conv.onlyAdminsCanMessage;
    final rows = <Widget>[];

    if (isAdmin) {
      rows.add(
        Opacity(
          opacity: online ? 1 : .38,
          child: IgnorePointer(
            ignoring: !online || switchBusy,
            child: SettingsTile(
              icon: Icons.lock_outline,
              title: 'Only Admins Can Message',
              subtitle: 'Members cannot send messages',
              trailing: switchBusy
                  ? const BusySpinner()
                  : IgnorePointer(
                      child: Switch(
                        value: switchValue,
                        onChanged: (v) => unawaited(_toggleSwitch(v)),
                        activeTrackColor: t.accent,
                        inactiveTrackColor: t.surface2,
                      ),
                    ),
              onTap: switchBusy || !online
                  ? null
                  : () => unawaited(_toggleSwitch(!switchValue)),
            ),
          ),
        ),
      );
    }

    if (!isLeft) {
      final duration = ref
              .watch(disappearingDurationProvider(_cid))
              .valueOrNull ??
          0;
      rows.add(
        Opacity(
          opacity: online ? 1 : .38,
          child: IgnorePointer(
            ignoring: !online,
            child: SettingsTile(
              icon: Icons.timer_outlined,
              title: 'Disappearing Messages',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    disappearingDurationLabel(duration),
                    style: TextStyle(fontSize: 13, color: t.inkSoft),
                  ),
                  Icon(Icons.chevron_right, size: 18, color: t.inkFaint),
                ],
              ),
              onTap: online
                  ? () => unawaited(
                      showDisappearingDialog(context, ref, _cid),
                    )
                  : null,
            ),
          ),
        ),
      );
    }

    final children = <Widget>[];
    // Media & Docs is local — visible to admin, member AND left (G1).
    rows.add(
      SettingsTile(
        icon: Icons.photo_library_outlined,
        title: 'Media & Docs',
        trailing: Icon(Icons.chevron_right, size: 18, color: t.inkFaint),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MediaDocsScreen(conversationId: _cid),
          ),
        ),
      ),
    );

    if (rows.isNotEmpty) {
      children.add(SectionHeader('Settings'));
      children.add(_groupedList(rows));
    }

    if (!isLeft) {
      children.add(const SizedBox(height: 16));
      children.add(
        Opacity(
          opacity: online ? 1 : .38,
          child: IgnorePointer(
            ignoring: !online || _leaving,
            child: _groupedList([
              SettingsTile(
                destructive: true,
                icon: Icons.logout,
                title: 'Leave Group',
                trailing: _leaving ? const BusySpinner() : null,
                onTap: !online || _leaving
                    ? null
                    : () => unawaited(_confirmLeave()),
              ),
            ]),
          ),
        ),
      );
    }

    return children;
  }

  // ── Grouped list chrome (D2) ─────────────────────────────────────────

  Widget _groupedList(List<Widget> rows) {
    final t = context.t;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd),
        border: Border.all(color: t.line, width: 1),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            rows[i],
          ],
        ],
      ),
    );
  }
}

// ── Add-to-group sheet (F3–F5) ─────────────────────────────────────────

class _AddMembersSheet extends ConsumerStatefulWidget {
  const _AddMembersSheet({
    required this.conversationId,
    required this.existingMemberIds,
  });

  final String conversationId;
  final Set<String> existingMemberIds;

  @override
  ConsumerState<_AddMembersSheet> createState() => _AddMembersSheetState();
}

class _AddMembersSheetState extends ConsumerState<_AddMembersSheet> {
  final _selected = <String>{};
  final _searchController = TextEditingController();
  bool _sending = false;
  var _query = '';

  @override
  void initState() {
    super.initState();
    // F3: statuses are a best-effort enrichment; failures degrade to none.
    unawaited(_loadStatuses());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadStatuses() async {
    try {
      final statuses = await ref
          .read(groupAdminProvider.notifier)
          .inviteStatuses(widget.conversationId);
      if (mounted) _statuses = statuses;
    } catch (e) {
      debugPrint('[Group] invite status fetch failed: $e');
    }
  }

  Map<String, String> _statuses = const {};

  List<Friendship> _available(List<Friendship> friends) {
    final query = _query.trim().toLowerCase();
    return friends.where((f) {
      if (widget.existingMemberIds.contains(f.friend.id)) return false;
      if (query.isEmpty) return true;
      return f.displayName.toLowerCase().contains(query) ||
          f.friend.username.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _send(List<Friendship> available) async {
    if (_sending) return;
    final ids = available
        .where((f) => _selected.contains(f.friend.id))
        .map((f) => f.friend.id)
        .toList();
    if (ids.isEmpty) return;
    setState(() => _sending = true);
    final result = await ref
        .read(groupAdminProvider.notifier)
        .sendInvites(widget.conversationId, ids);
    if (!mounted) return;

    final message = switch ((result?.ok ?? 0, result?.failed ?? 0)) {
      (final ok, 0) when ok == 1 => 'Invite sent',
      (final ok, 0) => '$ok invites sent',
      (final ok, final failed) => '$ok sent, $failed failed. Try again.',
    };
    showToast(context, message);
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final friendsAsync = ref.watch(friendshipsProvider);
    final friends = friendsAsync.valueOrNull ?? const <Friendship>[];
    final available = _available(friends);
    final loaded = friendsAsync.valueOrNull != null;
    final selectedCount = available
        .where((f) => _selected.contains(f.friend.id))
        .length;

    return AppSheetChrome(
      key: const Key('add-members-sheet'),
      title: 'Add to group',
      titleAction: AppButton(
        busy: _sending,
        onPressed: selectedCount == 0 || _sending
            ? null
            : () => unawaited(_send(available)),
        child: Text('Invite $selectedCount'),
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (friends.length > 8)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SearchField(
                controller: _searchController,
                hint: 'Search friends',
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
          Flexible(
            child: _sheetBody(friendsAsync, available, loaded),
          ),
        ],
      ),
    );
  }

  Widget _sheetBody(
    AsyncValue<List<Friendship>> friendsAsync,
    List<Friendship> available,
    bool loaded,
  ) {
    if (!loaded && friendsAsync.isLoading) {
      return ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          for (var i = 0; i < 4; i++)
            const Padding(
              padding: EdgeInsets.only(bottom: 14),
              child: Row(
                children: [
                  Skeleton(width: 40, height: 40, radius: 999),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Skeleton(width: 140, height: 14, radius: 7),
                        SizedBox(height: 8),
                        Skeleton(width: 90, height: 11, radius: 6),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }
    if (friendsAsync.hasError && !loaded) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: StatusBanner(
          message: "Couldn't load friends.",
          onRetry: () => ref.invalidate(friendshipsProvider),
        ),
      );
    }
    if (available.isEmpty) {
      // Only reached once friends have actually loaded (F3).
      return EmptyState(
        withMascot: false,
        title: "Everyone's here",
        subtitle: 'All your friends are already in this group.',
      );
    }
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        for (final friendship in available) _friendRow(friendship),
      ],
    );
  }

  Widget _friendRow(Friendship friendship) {
    final t = context.t;
    final user = friendship.friend;
    final selected = _selected.contains(user.id);
    final status = _statuses[user.id];
    final meta = status == 'pending'
        ? 'Invite pending'
        : status == 'declined'
            ? 'Declined — invite again?'
            : '@${user.username.trim()}';
    final name = _safeName(friendship.displayName);

    return Opacity(
      opacity: _sending ? .38 : 1,
      child: IgnorePointer(
        ignoring: _sending,
        child: InkWell(
          onTap: () => setState(() {
            if (selected) {
              _selected.remove(user.id);
            } else {
              _selected.add(user.id);
            }
          }),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Semantics(
                    container: true,
                    checked: selected,
                    label: name,
                    excludeSemantics: true,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected ? t.accent : null,
                        border: Border.all(
                          color: selected ? t.accent : t.line,
                          width: 1.5,
                        ),
                      ),
                      child: selected
                          ? Icon(Icons.check, size: 16, color: t.onAccent)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  AppAvatar(
                    url: user.avatarUrl,
                    initials: _initial(name, fallback: '?'),
                    radius: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: t.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.38,
                            color: t.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Offline strip (I1) ─────────────────────────────────────────────────

class _OfflineStrip extends StatelessWidget {
  const _OfflineStrip({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return AnimatedSwitcher(
      duration: _motionDuration(context, WarmPopTokens.motionBase),
      child: visible
          ? Semantics(
              key: const ValueKey('group-info-offline-strip'),
              container: true,
              label: _offlineCopy,
              child: Container(
                width: double.infinity,
                color: t.accentSoft,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(Icons.cloud_off_outlined, size: 18, color: t.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _offlineCopy,
                        style: TextStyle(fontSize: 13, color: t.ink),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : const SizedBox.shrink(key: ValueKey('group-info-online-space')),
    );
  }
}

// ── Loading skeleton (B1) ──────────────────────────────────────────────

class _GroupInfoSkeleton extends StatelessWidget {
  const _GroupInfoSkeleton();

  static const _duration = Duration(milliseconds: 1400);

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
            child: Column(
              children: [
                const Skeleton(
                  width: 96,
                  height: 96,
                  radius: 999,
                  duration: _duration,
                ),
                const SizedBox(height: 14),
                const Skeleton(
                  width: 150,
                  height: 18,
                  radius: 9,
                  duration: _duration,
                ),
                const SizedBox(height: 8),
                const Skeleton(
                  width: 80,
                  height: 12,
                  radius: 6,
                  duration: _duration,
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(0, 24, 0, 0),
            child: SectionHeader('Members'),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd),
              border: Border.all(color: t.line, width: 1),
            ),
            child: Column(
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        Skeleton(
                          width: 40,
                          height: 40,
                          radius: 999,
                          duration: _duration,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Skeleton(
                                width: 140,
                                height: 14,
                                radius: 7,
                                duration: _duration,
                              ),
                              SizedBox(height: 8),
                              Skeleton(
                                width: 90,
                                height: 11,
                                radius: 6,
                                duration: _duration,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Edit-name dialog. It OWNS its [TextEditingController]: `showDialog`'s
/// future completes when the route pops, but the dialog subtree only
/// unmounts after the exit transition. Disposing the controller at the
/// future (the inline pattern) hit "A TextEditingController was used after
/// being disposed" on the next frame, which aborted that frame — the
/// rename failure toast never got presented. Owned here, disposal happens
/// in the dialog's own `dispose()`, after the transition.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.currentName});

  final String currentName;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final value = _controller.text.trim();
    final canSave = value.isNotEmpty && value != widget.currentName.trim();
    return AlertDialog(
      title: const Text('Edit Group Name'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 50,
        onChanged: (_) => setState(() {}),
        style: TextStyle(fontSize: 15, color: t.ink),
        decoration: appFieldDecoration(
          context,
          label: 'Group name',
          hint: 'Enter group name…',
        ),
      ),
      actions: [
        AppButton(
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        AppButton(
          onPressed: canSave ? () => Navigator.pop(context, value) : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
