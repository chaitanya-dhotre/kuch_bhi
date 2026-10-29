# Group Info + Create Group — acceptance checklist (Page 4)

Date: 2026-10-29. Visual ground truth: **`docs/design/pages/group-info.html`** (sections G1–G15,
numbered; G15 = full diff vs current code). Authority: `docs/design/00-foundation.md`
(tokens/laws) → `docs/design/10-registry.md` (shared pieces) → this checklist. Page letters A–K
are page-local ("requests D1" ≠ this page). Line refs: `gs` = `group_settings_screen.dart`,
`cg` = `create_group_screen.dart`, as of `9ee3295`.

**Starting point.** This is not a new screen. Both screens exist and were audited 2026-10-29.
Every item below is a change to existing code (see G15), unless it is marked NEW.

**How Astra uses this:** every MUST must be implemented, or reported as not done with a reason.
SHOULD = stretch, after all MUSTs. A deviation from foundation C1–C4 / L1–L4 that *looks better*
still FAILS (surpass = better inside the system).

**Pass criteria (page complete when):** all MUSTs ✓ · `flutter analyze` 0 errors · `flutter test`
green (pre-change baseline **307/307**, measured 2026-10-29) · mandatory test-gate files below
green · device captures light + dark (M52 if connected, else Redmi S2) of: Group Info admin,
Group Info member, add sheet, member action sheet, Create step 1, Create step 2 · user PASS
(no commit without it).

**Status key:** `[x]` implemented AND verified by code/tests or recorded device evidence;
`[ ]` pending, partial, or blocked.

---

## ⛔ E2E boundary (read first: a breach here is an automatic FAIL)

Do **not** edit, reorder, wrap in a timeout, or re-implement:

- `_createGroup` steps (a)–(f) in `cg:64-344`: key pre-validation, `generateGroupKey`,
  `encryptGroupKeyForMember`, `group_keys` writes, `saveGroupKey`, the system message, rollback.
  **Single allowed edit:** the two `throw StateError('Member $memberId has no encryption key yet.')`
  (`cg:98`, `cg:185`) become `throw MemberKeyMissingError(memberId)`. Same position, same
  condition.
- `removeMemberFromGroup` / `leaveGroup` / `_rotateGroupKey` / `sendGroupInvite` in
  `message_repository_impl.dart`. The UI calls them as they are.
- Lost-keypair orphan rows are a known, accepted gap. Do not try to fix them here. Context:
  `.trail/learnings/2026-10-28-group-key-rotation-keeps-history-only-chaitanya.md` (user ruled
  2026-10-29: not worth it).

## A. Shell, laws, grep-gated hygiene (G1, G3, G12)

- [ ] **A1 MUST** Every Scaffold on both screens (including loading/error) sets
  `backgroundColor: context.t.bg`. App bar title 20/26 w700. Group Info title **Group Info**;
  Create title **New Group** on BOTH steps (step 2 today says "Group Info", `cg:461`).
- [ ] **A2 MUST** C3: no `colorScheme`, `withValues(alpha`, `errorContainer`,
  `surfaceContainerHighest`, or `BorderRadius.circular(<literal>)` / `Radius.circular(<literal>)`
  in `lib/features/groups/`. Use `context.t.*` and the `WarmPopTokens` radii (there are 9
  colorScheme sites today).
- [ ] **A3 MUST** C4: no accent-coloured or error-coloured **text** on either screen (accent on
  light surface = 2.0–2.2:1, error = 3.91:1, both fail). Accent is a fill/track/border only.
  Destructive = error **icon** + ink label.
- [ ] **A4 MUST** No `$e` (or any exception or user id) in user-visible text anywhere in
  `lib/features/groups/`. 8 sites today. Debug detail goes to `debugPrint` only.
- [ ] **A5 MUST** L4: `group_settings_screen.dart` no longer imports `message_repository_impl.dart`.
  All Group Info mutations go through a groups-feature notifier (NEW, e.g.
  `lib/features/groups/providers/group_admin_provider.dart`) that calls the existing
  `MessageRepository` methods unchanged. (Create's `_createGroup` stays where it is: E2E
  boundary.)
- [ ] **A6 MUST** No `CircularProgressIndicator` as page or section content on either screen
  (R3 `busy` and the per-row 18px busy spinner are allowed).

## B. Group Info — load states (G2)

- [ ] **B1 MUST** Loading = R11 skeleton matching the layout: 96 disc + name bar + count bar +
  3 member rows, with the app bar present. Replaces `gs:422-426`.
- [ ] **B2 MUST** Members stream error ≠ empty: R12 **Couldn't load members.** + **Retry**
  (invalidates `groupMembersProvider`). The header renders from the conversation; the count is
  hidden; admin affordances are hidden. Today `?? []` gives "0 members" (`gs:412`).
- [ ] **B3 SHOULD** Left/removed (`groupRole == 'left'`): R12 info banner **You're no longer in
  this group.** above the header. Everything else read-only, as today.

## C. Group Info — header (G4)

- [ ] **C1 MUST** Photo = R1 `AppAvatar` radius 48. The initial falls back through R1, so an
  empty name gives **G** and no `substring` RangeError (`gs:451`). Admin: a 32dp accent camera
  badge, the whole disc is the tap target, semantics **Change group photo**.
- [ ] **C2 MUST** Photo upload: scrim + spinner on the disc, taps blocked until done. Failure →
  R5 **Couldn't update. Try again.** Name: pencil glyph in inkSoft; the row is ≥48h, labelled
  **Edit group name**. The rename dialog: Save = R3 primary, disabled when the trimmed name is
  empty or unchanged; maxLength 50; the controller is disposed. Failure → same toast.
- [ ] **C3 MUST** Count **1 member** / **{n} members** (non-left), inkSoft 13/18. Today it is
  always plural (`gs:513`).

## D. Group Info — members list (G5)

- [ ] **D1 MUST** Deterministic order: **you first**, then admins A→Z, then members A→Z
  (case-insensitive display name). Left members are never listed.
- [ ] **D2 MUST** Row: R1 40 (decorative) · name 16/22 w600 ink (empty → **Unknown**) · Admin
  chip = micro 11/14 w600, accentSoft fill, **ink** text, pill radius · meta inkSoft: **You** for
  yourself, **@username** for others (NEW). Grouped list: surface, radiusMd 16, 1px line
  dividers, ≥60 rows.
- [ ] **D3 MUST** Section headers = R9 `SectionHeader`: **Members** + count; **Invites** + count;
  **Settings**. Delete the hand-rolled `_sectionHeader` (`gs:390`) and the 14px MEMBERS row
  (`gs:525-550`). Admin: **＋ Add** chip (36h visual, 48 hit, accentSoft fill, ink label) in the
  Members header.

## E. Member actions (G6)

- [ ] **E1 MUST** Admin viewer, on a row that is not yours: a 48dp ⋮ (**Options for {name}**),
  and tapping or long-pressing the row opens the sheet. Uses the C4 action-sheet chrome via
  registry amendments **C4a** (`showActionSheet({header, actions})` pulled out of
  `showConversationMenu`, which then calls it) and **C4b** (`ConversationMenuAction.destructive`).
  Sheet header = R1 + name + `@username · Admin|Member`. Rows: **Make Admin** (member target) /
  **Remove Admin** (admin target AND admins > 1) / **Remove from Group** (destructive).
  Never on your own row. `PopupMenuButton` deleted.
- [ ] **E2 MUST** Per-row busy: an 18px spinner replaces the trailing area and the row ignores
  taps; a second tap does nothing (test). Other rows stay live. Remove → confirm dialog (copy
  kept), destructive button = R3 secondary + error icon + ink label.
- [ ] **E3 MUST** Bounded and honest outcomes:
  - Promote/demote are bounded at 8s.
  - Remove/leave are bounded at **30s** at the UI only. On timeout: unlock + toast **Still
    working — this can take a moment.** The repository call is never cancelled or retried.
  - Success toasts: **{name} is now an admin** / **{name} is no longer an admin** /
    **{name} removed** (plus a live-region announce for removal).
  - Failure toast: **Couldn't update. Try again.**
- [ ] **E4 SHOULD** Leave confirm, when you are the only admin and others exist: the extra line
  **{name} will become the admin.**, naming the earliest-joined other member (read-only mirror
  of `leaveGroup`'s rule).

## F. Invites & add-to-group (G7, G8)

- [ ] **F1 MUST** The Invites section renders when there are ≥1 non-accepted rows OR an error.
  Error → R12 **Couldn't load invites.** + **Retry** (invalidates `pendingInvitesProvider`).
  Today the error is swallowed by `?? const []` (`gs:613`). Shows nothing while loading.
  Offline: hidden, with no error banner.
- [ ] **F2 MUST** Invite row: R1 40 + name (fallback **@username** → **Unknown**) + inkSoft meta
  **Invite pending** / **Declined**. R3 text **Cancel** / **Re-invite**, per-row busy lock, 8s
  bound. Cancel exits silently; Re-invite toasts **Invite sent**; failure toasts **Couldn't
  update. Try again.**
- [ ] **F3 MUST** The add sheet opens **immediately** and loads inside it: friends loading → R11
  rows; friends error → R12 **Couldn't load friends.** + Retry; invite-status fetch failure
  still degrades to no statuses. **Everyone's here** + **All your friends are already in this
  group.** only when friends have loaded and none are available. Today `valueOrNull ?? []`
  (`gs:135`) shows that message while friends are still loading or have failed.
- [ ] **F4 MUST** Sheet: theme radiusLg 20 + handle, title **Add to group** 20/26 w700, round
  accent checks, inkSoft status meta (**Invite pending** / **Declined — invite again?** /
  **@username**). **Invite {n}** = R3 primary; the **sheet stays open and busy while sending**,
  with rows dimmed 38%. Then it closes and toasts **Invite sent** / **{n} invites sent** /
  **{ok} sent, {failed} failed. Try again.** Each send is bounded at 8s; invites are invalidated.
- [ ] **F5 SHOULD** R8 **Search friends** in the sheet when there are more than 8 friends.

## G. Settings rows (G9)

- [ ] **G1 MUST** Visibility matrix (G9): Only Admins Can Message = admin; Disappearing = admin +
  member; Media & Docs = admin + member + left; Leave = admin + member. Today Media & Docs and
  Disappearing are admin-only (`gs:700`).
- [ ] **G2 MUST** Rows = R10 `SettingsTile` in grouped lists. The switch is the trailing slot,
  with the whole row toggling. It is busy-locked, bounded at 8s and wrapped in **try/catch**
  (today an unhandled error, `gs:707`). On failure it toasts and snaps back to the stream value.
- [ ] **G3 MUST** Registry **C11**: extract chat's `_disappearingDialog` (`chat_screen.dart:1173`)
  into `lib/features/chat/widgets/disappearing_dialog.dart` as
  `showDisappearingDialog(context, ref, conversationId)`. Chat AND Group Info call it, and
  Group Info's copy (`gs:102-132`) is deleted. The checkmark is **ink**. The write is awaited
  with try/catch → failure toast. Group Info's row shows the current value trailing (the label
  helper is exported). Chat N1/N2 behaviour is otherwise unchanged.
- [ ] **G4 MUST** Leave = R10 with registry amendment **R10a** `destructive: true` (error icon in
  the well, ink title), in its own grouped list at the bottom. Confirm → busy → pop (unchanged
  destination). The red `OutlinedButton` (`gs:738`) is deleted.

## H. Create step 1 (G10)

- [ ] **H1 MUST** Loading = R11 rows ×6 with the app bar. Error = R7 **Couldn't load friends.** +
  **Check your connection and try again.** + **Retry** (invalidates `friendshipsProvider`), with
  the app bar. Empty = R7 neutral Capybara + **No friends yet** + **Add a friend to start a
  group.** + **Add a Friend** (dispatches the existing Add-Friend entry; the sheet is page 8).
  Replaces `cg:352-358` and `cg:396`.
- [ ] **H2 MUST** Row: round accent check, R1 40, name w600 (empty → **Unknown**, no RangeError
  at `cg:418`), **@username** inkSoft. The whole row is a ≥56h toggle.
- [ ] **H3 MUST** Selected chips = R4 `AppChip(selected: true)`: R1 28 + name + ✕, tap removes,
  semantics **Remove {name}**. No RangeError (`cg:610`). Replaces Material `Chip` +
  `surfaceContainerHighest`.
- [ ] **H4 MUST** **Next** = R3 `text`, disabled at 0 selected (R3 disabled tokens).
- [ ] **H5 SHOULD** R8 **Search friends** filters the list, never the selection. The chip strip
  scrolls horizontally past one row.

## J. Create step 2 (G11)

- [ ] **J1 MUST** The system back gesture AND the app-bar back on step 2 return to step 1 with
  the selection kept (`PopScope`). Today the system back exits the whole flow.
- [ ] **J2 MUST** While creating: `PopScope(canPop: false)`, app-bar back disabled, field
  read-only. Create = R3 primary expanded, busy **Creating…**.
- [ ] **J3 MUST** Errors in an inline box (surface, 3px error left rule, error icon, ink text):
  `MemberKeyMissingError(memberId)` → **{name} can't be added yet. They need to open Kuch Bhi
  once to set up encryption.** (memberId mapped to the friend's display name; never a raw id).
  Anything else → **Couldn't create the group. Check your connection and try again.** Typed
  exception = the single allowed `_createGroup` edit (E2E boundary).
- [ ] **J4 MUST** The `setState` in the create catch (`cg:339`) is guarded by `mounted`. There is
  no setState after dispose on any path.
- [ ] **J5 MUST** Photo = R1 radius 48 + camera badge, **Add group photo**. Field label **Group
  name**, hint **Enter group name…**, radiusMd 16, ONE counter (drop the duplicate
  `counterText`), no `prefixIcon`. **{n} member(s) selected** in inkSoft.

## I. Offline (G12)

- [ ] **I1 MUST** Both screens: an accentSoft strip under the bar showing **You're offline —
  actions are available when you're back.** (the Requests H1 string), driven by
  `isOnlineProvider`. It clears 250ms after reconnect.
- [ ] **I2 MUST** Offline, every network mutation is disabled with exactly ONE 38% dim + ONE
  **Available online** (`kOfflineActionHint`) per surface: photo, rename, ＋ Add, member ⋮ and
  row tap, Cancel/Re-invite, switch, Disappearing row, Leave, Create. Media & Docs and
  Create step 1 stay usable. Double dim = FAIL.

## K. A11y (G13)

- [ ] **K1 MUST** Member row merged label **{name}, admin, you** / **{name}, @{username}** (role
  and self only when true), avatar excluded. Admin viewer hint **Double tap for options**. Create
  friend row = checkbox semantics with its checked state.
- [ ] **K2 MUST** 48dp floor on every target (⋮, ＋ Add, text buttons, chips' remove, camera,
  back). Name is a heading. Live-region announcements for **{name} removed** and the invite-send
  result.
- [ ] **K3 SHOULD** Row exit (remove/cancel) 250ms fade + collapse; instant under reduced motion.
  Spinners stop under reduced motion.

## Registry amendments (same PR, L2)

| ID | Amendment |
|---|---|
| C4a | `showActionSheet({required BuildContext context, Widget? header, required List<ConversationMenuAction> actions})` in `message_context_menu.dart`. `showConversationMenu` calls it (no visual change to Home's long-press). |
| C4b | `ConversationMenuAction.destructive` (default false): error icon, ink label. |
| C11 | `showDisappearingDialog` + exported duration label helper: `lib/features/chat/widgets/disappearing_dialog.dart`. |
| R10a | `SettingsTile.destructive` (default false): error icon in the well, ink title. |

## Test gates (mandatory; there are NO group tests today)

- [ ] `test/groups/group_info_screen_test.dart`: skeleton (no spinner) · members error → banner,
  not "0 members" · order (you → admins → members) · **1 member** singular · empty group name
  and empty member name don't crash · visibility matrix for admin / member / left · invites
  error banner · offline strip + single dim + hint · no `$e` text rendered on any failure.
- [ ] `test/groups/group_info_actions_test.dart`: per-row busy + double-tap no-op · failure toast
  for promote/demote/remove/cancel/re-invite/switch/rename/photo/leave · a blackholed
  promote releases at 8s · a blackholed remove releases at 30s with **Still working…** and the
  repository is NOT called again · Remove Admin hidden at 1 admin · no actions on your own row ·
  switch snaps back on failure.
- [ ] `test/groups/add_members_sheet_test.dart`: friends loading ≠ "Everyone's here" (false-empty
  regression) · friends error → banner + Retry · status meta · sheet stays open + busy while
  sending · all / partial failure toast copy · invites invalidated.
- [ ] `test/groups/create_group_screen_test.dart`: skeleton · error copy + Retry (no `$e`) ·
  R7 empty + CTA · empty display name → no RangeError (list + chip) · step-2 system back → step 1
  with selection kept · back blocked while creating · `MemberKeyMissingError` → copy shows the
  NAME, never the id · generic failure copy · offline Create disabled + hint · no setState after
  dispose. **Fake the group service: no real key generation or PB in this test.**
- [ ] `test/chat/disappearing_dialog_test.dart`: checkmark on the persisted value · both entry
  points open the same dialog · failed write → failure toast.
- [ ] `test/grep_gates_test.dart` extended for `lib/features/groups/`: no `colorScheme`,
  `withValues(alpha`, `CircularProgressIndicator`, `.substring(0, 1)`, `circular(<digit>`, `$e}`
  / `: $e'` in strings **except on `debugPrint(` lines** (A4 keeps debug detail there; the
  gate must not push it out), and no `message_repository_impl.dart` import in
  `group_settings_screen.dart`.
- [ ] Full suite green (307 + new) · analyze 0 errors · `git diff --check` clean.

## Out of scope (do NOT build on this page)

Anything in the E2E boundary above · moving `_createGroup` orchestration out of the widget
(backlog: L4-correct but it relocates key-distribution code) · a timeout on `_createGroup` (it
would race its own rollback; backlog) · member tap → profile (page 5) · Add-Friend sheet
internals (page 8) · invitee accept/decline card (page 3) · Media & Docs screen · group
description / mute / notifications / invite links / member search / pagination · offline cache
for invites.

---

### Deferred decisions (user may override at review)

1. **Create = direct add, ＋ Add = invite.** Kept. Making create send invites is a repository
   and E2E change, so it would be a separate task.
2. **Disappearing for non-admins:** shown to all members, matching the chat menu, which
   already allows it. Alternative: admin-only in both places (needs a server-rule check).
3. **Destructive colour:** error text fails 4.5:1 in light (3.91). Default: error icon + ink
   label. Alternative: add an `errorText` token (foundation amendment).
4. **Media & Docs for left members:** shown, since the media is local. Flag to hide.
5. **Remove/Leave 30s UI bound + "Still working" copy.** Alternative: no UI bound on those two.
6. **Row tap opens the member action sheet** (admin). Alternative: ⋮ only.
