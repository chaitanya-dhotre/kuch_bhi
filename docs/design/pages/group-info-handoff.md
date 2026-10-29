# Astra brief — Page 4: Group Info + Create Group

Spec PASS by user 2026-10-29 (all 6 deferred decisions = defaults). Paste everything below the
line into Omnirush, with the listed files attached.

**Attach (in this order):**
1. `docs/design/pages/group-info.md` — the checklist = your grading contract
2. `docs/design/pages/group-info.html` — the visual spec (G1–G15; G15 = diff vs current code)
3. `docs/design/00-foundation.md` · `docs/design/10-registry.md`
4. `lib/features/groups/screens/group_settings_screen.dart` · `lib/features/groups/screens/create_group_screen.dart`
5. `lib/features/chat/widgets/message_context_menu.dart` · `lib/features/chat/screens/chat_screen.dart` (only `_showChatMenu` :992-1070 and `_disappearingDialog` :1173-1216 matter)
6. `lib/core/widgets/` (all 12 files) · `lib/core/theme/tokens.dart`
7. `lib/features/friend_requests/` providers + screen (the house pattern for: notifier-owned mutations, 8s bounds, offline single-dim, R7/R12 states)
8. `test/grep_gates_test.dart` · `test/friend_requests/request_actions_test.dart` (the house test style)

---

You are implementing Page 4 of a Flutter app (Riverpod, Drift, PocketBase) against a written
spec. The attached `group-info.md` checklist is the contract. Every MUST is either done or
reported as not done with a reason. SHOULDs come only after all MUSTs.

## Hard rules

1. **E2E boundary.** Do NOT edit, reorder, or wrap in a timeout:
   - `_createGroup` in `create_group_screen.dart`: its steps (a) to (f), the key validation,
     key generation and wrapping, `group_keys` writes, and rollback.
   - `removeMemberFromGroup`, `leaveGroup`, `_rotateGroupKey` and `sendGroupInvite` in the
     repository.

   The only allowed edit inside `_createGroup`: the two
   `throw StateError('Member $memberId has no encryption key yet.')` become
   `throw MemberKeyMissingError(memberId)`. Define that class in `lib/features/groups/`. Any
   other change there is an automatic FAIL.
2. **Colours.** Use only `context.t.*` and `WarmPopTokens` radii. No `colorScheme`, no
   `withValues(alpha`, no radius literals, and no accent- or error-coloured text.
3. **No `$e`** or raw ids in any user-visible string.
4. **Shared pieces.** Only the registry components are used. The four amendments below are
   the only new shared API.
5. **Don't touch** files outside the list below unless a gate forces it. If one does, say so.

## Work order (run the gates after each wave)

**Wave 1: shared pieces**
- C4a: add `showActionSheet({required BuildContext context, Widget? header, required List<ConversationMenuAction> actions})`
  to `lib/features/chat/widgets/message_context_menu.dart`. `showConversationMenu` calls it,
  and Home's long-press must look exactly the same as before.
- C4b: add `ConversationMenuAction.destructive` (default false). It renders an error icon and
  an ink label.
- C11: move the disappearing dialog to `lib/features/chat/widgets/disappearing_dialog.dart`.
  - Export `showDisappearingDialog(BuildContext, WidgetRef, String conversationId)` and the
    duration-label helper.
  - Chat calls it.
  - The checkmark is ink.
  - The write is awaited with try/catch, and a failure shows the toast "Couldn't update. Try again."
- R10a: add `SettingsTile.destructive` (default false). It renders an error icon in the well
  and an ink title.
- Add rows C4a, C4b, C11 and R10a to `docs/design/10-registry.md`.
- New notifier `lib/features/groups/providers/group_admin_provider.dart` owns every Group Info
  mutation. It calls the existing `MessageRepository` methods unchanged.
  - Timeouts: 8s on every call, but 30s on remove and leave.
  - On a remove/leave timeout, never retry or cancel. Just surface "Still working — this can
    take a moment."

**Wave 2: Group Info** (`group_settings_screen.dart`, checklist A, B, C, D, E, F, G, I, K)
- Remove the `message_repository_impl.dart` import.
- Keep `pendingInvitesProvider` but stop swallowing its error.

**Wave 3: Create Group** (`create_group_screen.dart`, checklist A, H, J, I, K)
- UI shell only, plus the one typed-exception edit.

## Copy (verbatim; the checklist is the source of truth if the two differ)

- Counts and labels: `1 member` / `{n} members` · `Members` · `Invites` · `Settings` · `＋ Add` · `Add to group`
- Sheet empty state: `Everyone's here` + `All your friends are already in this group.`
- Load errors and Retry:
  - `Couldn't load members.` · `Couldn't load invites.` · `Couldn't load friends.`
  - `Check your connection and try again.` · `Retry`
- Create empty state: `No friends yet` + `Add a friend to start a group.` + `Add a Friend`
- Create step 2: `Search friends` · `Group name` · `Enter group name…` · title `New Group` on both steps
- Toasts:
  - `{name} is now an admin` · `{name} is no longer an admin` · `{name} removed`
  - `Invite sent` · `{n} invites sent` · `{ok} sent, {failed} failed. Try again.`
  - `Couldn't update. Try again.` · `Still working — this can take a moment.`
- Create errors:
  - `{name} can't be added yet. They need to open Kuch Bhi once to set up encryption.`
  - `Couldn't create the group. Check your connection and try again.`
- Left-group banner: `You're no longer in this group.`
- Leave confirm, extra line (SHOULD): `{name} will become the admin.`
- Offline: `You're offline — actions are available when you're back.` · `Available online` (use `kOfflineActionHint`)
- Semantics:
  - `Change group photo` · `Edit group name` · `Add group photo`
  - `Options for {name}` · `Double tap for options` · `Remove {name}`
- Keep all existing copy listed in the "Keep" column of G14.

## Files

**Create:**
- `lib/features/groups/providers/group_admin_provider.dart`
- `lib/features/groups/member_key_missing_error.dart`
- `lib/features/chat/widgets/disappearing_dialog.dart`
- `test/groups/group_info_screen_test.dart`
- `test/groups/group_info_actions_test.dart`
- `test/groups/add_members_sheet_test.dart`
- `test/groups/create_group_screen_test.dart`
- `test/chat/disappearing_dialog_test.dart`

**Modify:**
- the two groups screens
- `message_context_menu.dart`
- `chat_screen.dart` (calls the shared dialog; nothing else)
- `lib/core/widgets/settings_tile.dart`
- `test/grep_gates_test.dart`
- `docs/design/10-registry.md`

The test cases each file must cover are listed under "Test gates" in the checklist. In
`create_group_screen_test.dart`, fake the group service: no real key generation, no PocketBase.

## Gates (run them yourself and paste the output)

- `flutter analyze`: 0 errors
- `flutter test`: all green. Baseline is 307/307, so the result must be 307 + your new tests,
  with no existing test changed to pass.
- `git diff --check`: clean
- `grep -rn 'colorScheme\|withValues(alpha\|CircularProgressIndicator\|substring(0, 1)' lib/features/groups/`: empty

Report back with:
1. The checklist, with each item ticked and evidence (test name or file:line).
2. Any MUST not done, with the reason.
3. The full diff.

Claude grades the result. Do not claim PASS.
