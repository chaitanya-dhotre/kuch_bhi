# Profile + Edit Profile + View Profile — acceptance checklist (Page 5)

Date: 2026-10-29. Visual ground truth: **`docs/design/pages/profile.html`** (sections P1–P14,
numbered; P14 = full diff vs current code). Authority: `docs/design/00-foundation.md`
(tokens/laws) → `docs/design/10-registry.md` (shared pieces) → this checklist. Page letters A–K
are page-local ("group-info D1" ≠ this page). Line refs: `ps` = `profile_screen.dart`,
`ep` = `edit_profile_screen.dart`, `vp` = `view_profile_screen.dart`,
`ar` = `auth_repository_impl.dart`, as of `6c98a8d`.

**Starting point.** This is not a new screen. All three screens exist and were audited
2026-10-29 (201 + 228 + 143 lines). None has a widget test; the only coverage is the colour grep
gate in `test/grep_gates_test.dart:18`. Every item below changes existing code (see P14), unless
it is marked NEW.

**Two bugs the audit found, which this page fixes first:**

1. **Edit Profile cannot be reached.** `AppRoutes.editProfile` is registered
   (`app_router.dart:163`) but nothing in `lib/` pushes it. → B4.
2. **A successful save does not show up.** `_save` writes PocketBase, then
   `ref.invalidate(authProvider)` (`ep:70`). `AuthNotifier.build` reads the **cached Drift user**
   (`ar:257`), which nothing updated, so the old name/photo comes back until a resume refresh.
   The invalidate also re-runs the reinstall-detection branch of `getCurrentUser` (`ar:266-270`),
   which can generate and upload a new key pair. A profile save must never reach that. → G1–G3.

**How Astra uses this:** every MUST must be implemented, or reported as not done with a reason.
SHOULD = stretch, after all MUSTs. A deviation from foundation C1–C4 / L1–L4 that *looks better*
still FAILS (surpass = better inside the system).

**Pass criteria (page complete when):** all MUSTs ✓ · `flutter analyze` 0 errors · `flutter test`
green (pre-change baseline **366/366**, measured 2026-10-29) · mandatory test-gate files below
green · device captures light + dark (M52 if connected, else Redmi S2) of: Profile, Profile
sign-out confirm, Edit Profile idle, Edit Profile username-taken, Edit Profile saving, photo
sheet, View Profile · user PASS (no commit without it).

**Spec status: user PASS 2026-10-29. Every deferred decision = its default.**

**Pre-implementation gate: DONE 2026-10-29** (read-only query of live PB 0.37.5 `_collections`):
- `users.updateRule` = `@request.auth.id = id`, so the owner may change `username`. E2 stands.
- `CREATE UNIQUE INDEX idx_qyziz88x9t ON users (username)` exists, so a duplicate fails with
  `validation_not_unique` on `username` (G1). The index is **case-sensitive** and the server has
  **no pattern** on `username` (min 3 only). The client lower-casing (E2) and the regex are the
  only guards against `Avni`/`avni` twins: keep both.
- `display_name`: required, server max 255 (the client's 50 is stricter). `about`: no max on the
  server. `avatar`: file, maxSelect 1, maxSize 10 MB, images incl. HEIC/WebP (the 1024 cap keeps
  uploads far below the limit).
- Clearing a file (F3 Remove photo): PB 0.23+ deletes a single-file field when the update body
  sets it to `null` → send `'avatar': null`. This comes from the PB docs, not a live write, so
  F3 gets a device check.
- Pre-existing and out of scope: the owner rule makes every own field writable, `public_key`
  and `friend_code` included. G1's whitelist keeps the app from sending them; a server
  field-lock would be its own task.

**Status key:** `[x]` implemented AND verified by code/tests or recorded device evidence;
`[ ]` pending, partial, or blocked.

---

## ⛔ E2E / key boundary (read first: a breach here is an automatic FAIL)

Do **not** edit, call, reorder or re-implement:

- `_initEncryptionKeys`, `updatePublicKey`, `refreshSessionThrottled`, `signOut`,
  `deleteAccount`, or anything in secure storage, in `auth_repository_impl.dart`.
- The Backup PIN screens behind `AppRoutes.backupPinChange`. Profile only **navigates** there.
- The new `AuthRepository.updateProfile` (G1) sends **only** `display_name`, `username`, `about`
  and `avatar`. Never `public_key`. It maps the returned record with the existing
  `_recordToUser` and writes it with the existing `_cacheUserLocally`. Nothing else.
- No `ref.invalidate(authProvider)` anywhere in `lib/features/profile/` (it re-runs the
  reinstall branch that can rotate keys, `ar:266-270`).

Key context, for reading only (do not re-solve):
`.trail/learnings/2026-10-28-group-key-rotation-keeps-history-only-chaitanya.md`,
`.trail/learnings/2026-10-28-group-key-re-wrap-recovers-rows-chaitanya.md`,
`.trail/learnings/2026-10-29-one-device-rotates-a-group-s-chaitanya.md`. Key-loss re-wrap stays
in the backlog.

## A. Shell, laws, grep-gated hygiene (P1, P3)

- [ ] **A1 MUST** Every Scaffold on the three screens (including loading) sets
  `backgroundColor: context.t.bg`. App bar title 20/26 w700. Titles: **Profile** (own),
  **Edit profile**, **Profile** (someone else). Today View's title is the person's name, which
  repeats the header and is blank for an empty name (`vp:16`).
- [ ] **A2 MUST** C3: no `colorScheme`, `withValues(alpha`, `surfaceContainerHighest`,
  `Theme.of(context).textTheme`, or `BorderRadius.circular(<literal>)` /
  `Radius.circular(<literal>)` in `lib/features/profile/`. Use `context.t.*` and the
  `WarmPopTokens` radii. Sites today: 9 `colorScheme` (`ps:75` · `ep:169-216` ×6 ·
  `vp:67,79`) and 9 radius literals (`circular(12)` ×6 in `ep`, `circular(20)` at `ps:88,161`,
  `vp:91`).
- [ ] **A3 MUST** C4: no accent-coloured or error-coloured **text or glyph-as-text** on any of the
  three screens. Measured: accent on accentSoft **1.97:1**, accent on white **2.16:1**, error on
  white **3.91:1**. All fail. Accent is a fill/border/badge only. Destructive = error **icon** +
  ink label (R10a). Sites today: Sign Out (`ps:37`), "Your Friend Code" + the code + copy icon
  (`ps:96,109,127`), Backup PIN label (`ps:144`), avatar initials (`ps:58`, `ep:133`, `vp:35`),
  "Friend Code" + code + copy (`vp:99,112,130`).
- [ ] **A4 MUST** No `$e`, `e.toString()`, or user id in user-visible text anywhere in
  `lib/features/profile/`. Today `ep:77` shows the raw exception. Debug detail goes to
  `debugPrint` only.
- [ ] **A5 MUST** Type: foundation §3 only. The friend code is **display 28/34 w700** (today 32
  w800, `ps:106`, `vp:109`: neither the size nor the weight exists in §3). Name 20/26 w700,
  `@username` 15/22 inkSoft, about 15/22 ink, meta 13/18 inkSoft.
- [ ] **A6 MUST** L4: the profile screens read only `authProvider` / domain providers and call
  only `AuthNotifier` methods. `edit_profile_screen.dart` no longer imports
  `profile_update_service.dart`. Delete `ProfileUpdateService` and its provider once nothing uses
  it (G1 replaces it).
- [ ] **A7 MUST** No `CircularProgressIndicator` as page or section content. R3 `busy` and R3a
  `BusySpinner` are allowed. Today the Save action builds its own (`ep:100-104`).
- [ ] **A8 MUST** No `.substring(0, 1)` in `lib/features/profile/`. Initials come from the R1b
  helper (`initialsOf`). Today an empty display name throws a RangeError on all three screens
  (`ps:54`, `ep:91`, `vp:31`).

## B. Own profile (P2, P4)

- [ ] **B1 MUST** `user == null` (signed-out frame or auth still loading) renders the Scaffold +
  app bar + an R11 skeleton of the header (96 disc, name bar, username bar, card block). Today it
  is a bare `SizedBox.shrink()` with no Scaffold (`ps:20`).
- [ ] **B2 MUST** Header: R1 `AppAvatar(url: user.avatarUrl, radius: 48, accentSoft: true)`.
  **Today the profile never shows the user's photo** (`ps:50` ignores `avatarUrl`), so an
  uploaded photo is invisible on the user's own profile.
- [ ] **B3 MUST** Name 20/26 w700 ink, centred, max 2 lines, ellipsis. `@username` 15/22 inkSoft.
  About (NEW on this screen): 15/22 ink, centred, max 4 lines, only when non-empty. When empty,
  show nothing (no placeholder).
- [ ] **B4 MUST** NEW **Edit profile** = R3 `secondary`, 48h, centred under the header, pushes
  `AppRoutes.editProfile`. Tapping the avatar does the same (semantics **Edit profile**).

## C. Friend code + QR card (P5)

- [ ] **C1 MUST** One card (surface, radiusLg 20, T1 `cardShadow(t.shadow)`, 20 padding)
  replaces the accentSoft code card and the separate QR card (`ps:83-134` + `ps:157-195`).
  Kicker **YOUR FRIEND CODE** micro 11/14 w600 inkSoft. Code display 28/34 w700 **ink**,
  letterSpacing 4, monospaced digits (`FontFeature.tabularFigures()`). Copy = 48dp icon button,
  ink icon, semantics **Copy friend code**.
- [ ] **C2 MUST** Copy → R5 `showToast` **Friend code copied** (replaces the raw `SnackBar`,
  `ps:118`). Also a light haptic (`HapticFeedback.selectionClick`).
- [ ] **C3 MUST** QR: a fixed-white well (radiusMd 16, `WarmPopTokens.surface`, both themes, as
  today) with the QR at 200. **Every module and eye is `WarmPopTokens.ink`.** Today the eyes are
  accent (`ps:178`): 2.16:1 on white, too weak for some scanners to find the finder pattern.
  Caption **Scan to add me on Kuch Bhi** 13/18 `WarmPopTokens.inkSoft`, inside the white well.
  The QR payload `kuchbhi://add/{friendCode}` is unchanged.

## D. Account rows (P6)

- [ ] **D1 MUST** R9 `SectionHeader` **Account**, then a grouped list (surface, radiusMd 16, 1px
  line dividers): **Change Backup PIN** = R10 `SettingsTile` (lock-reset icon in the surface2
  well, chevron), pushes `AppRoutes.backupPinChange`. Plain navigation row. Replaces the
  accentSoft `ElevatedButton` (`ps:138-151`). Nothing about the PIN flow changes.
- [ ] **D2 MUST** **Sign out** = R10a `SettingsTile(destructive: true)` (error icon, ink title),
  last row of its own grouped list. Removed from the app bar (today red text, `ps:32-39`, one
  tap with no confirm).
- [ ] **D3 MUST** Sign out asks first. Dialog (theme, radiusXl 24): title **Sign out?**, body
  **This clears your chats from this phone. You can sign back in any time.**, actions **Cancel**
  (R3 text) and **Sign out** (R3 secondary, error icon + ink label). Confirm calls the existing
  `ref.read(authProvider.notifier).signOut()` unchanged. Reason: `signOut` wipes every Drift
  table (`ar:331-344`), so one stray tap in the app bar is destructive today.
- [ ] **D4 MUST** The settings gear stays in the app bar: 48dp, ink, semantics **Settings**.

## E. Edit profile — form (P7)

- [ ] **E1 MUST** Fields use the shared R13 field decoration (registry amendment below): label
  13 inkSoft, input 15/22 ink, hint inkFaint, surface fill, line border, accent 1.5 focus
  border, radiusMd 16. Field error: the border turns `t.error` (non-text, 3.91:1 passes 3:1);
  the error **line is `t.ink` 13/18 with a leading error icon** (C4: error text fails). One
  counter per field, from `maxLength`.
- [ ] **E2 MUST** NEW **Username** field between name and about. Prefix **@** (inkSoft), no
  autocorrect, lower-cased on save. Validation = the register rule (`register_screen.dart:162`):
  empty → **Enter a username**; under 3 → **At least 3 characters**; pattern
  `^[a-zA-Z0-9_]+$` fails → **Letters, numbers and underscores only**. Helper **Letters, numbers
  and underscores**. Server `validation_not_unique` on `username` → that field's error **That
  username is taken.** (not a toast). Skip the uniqueness round-trip when the username is
  unchanged.
- [ ] **E3 MUST** **Display name**: maxLength 50, required → **Enter a display name**, words
  capitalisation. **About**: maxLength 150, 3 lines, hint **A line about you**, optional.
- [ ] **E4 MUST** **Save** = R3 `text` in the app bar, 48 hit area. Enabled only when the form is
  **dirty** (trimmed name / lower-cased username / trimmed about differ from the user, or the
  photo changed) AND valid AND online. Busy = R3 busy (no hand-built spinner, `ep:100`).
- [ ] **E5 MUST** Leaving with unsaved changes (app-bar back or system back, `PopScope`): dialog
  **Discard changes?** / **Your edits won't be saved.** / **Keep editing** (R3 text) /
  **Discard** (R3 secondary, ink label). Not dirty → pops with no dialog.
- [ ] **E6 MUST** While saving: `PopScope(canPop: false)`, back disabled, fields read-only,
  photo tap disabled.

## F. Avatar picker + upload (P8)

- [ ] **F1 MUST** Avatar = R1 radius 48 with the R1a `image:` slot showing, in order: the picked
  file (`FileImage`), else `user.avatarUrl`, else initials. **Today the editor never shows the
  existing photo** (`ep:124` only shows a picked file). Camera badge 32dp, accent fill,
  onAccent glyph, 2px bg ring. The whole 96 disc is the tap target, semantics **Change profile
  photo**.
- [ ] **F2 MUST** Picking: `pickImage(source: gallery, maxWidth: 1024, maxHeight: 1024,
  imageQuality: 80)` (today no size cap, `ep:45`, so a 12 MP photo uploads whole). Cancel = no
  change. `PlatformException` (permission denied, no gallery) → R5 **Couldn't open your photos.**
  Today it is an unhandled async error.
- [ ] **F3 SHOULD** Tap opens the C4a action sheet: **Choose from gallery** · **Take photo**
  (camera source, same caps) · **Remove photo** (C4b destructive; only when there is a current
  or picked photo). Remove marks the photo cleared; Save sends the PB clear (exact form from the
  pre-implementation gate). Without F3 the tap goes straight to the gallery (F2).
- [ ] **F5 MUST** (added 2026-10-29 at the user's request, after device check 1) **Crop and
  zoom before use.** After a pick, a full-screen **Move and scale** step opens: the photo inside a
  square viewport with a circular guide, the area outside the circle under a `t.bg` 65% veil,
  pinch to zoom (1–4×) and drag to pan. The photo always covers the viewport (no empty edges).
  It opens centred. **Cancel** (R3 text, also back) keeps the previous photo; **Use photo** (R3
  primary) renders the visible square at 512×512 into a temp PNG, which becomes the picked file.
  That output carries no EXIF; Save still re-encodes without EXIF anyway. Crop failure → R5
  **Couldn't use that photo.** The crop maths is a pure function with a unit test. In-app
  (Flutter) by design: no new dependency, no native crop activity, Warm Pop tokens, both themes.
- [ ] **F4 MUST** The photo is uploaded only on **Save**, together with the text fields, as
  today. No separate upload, no upload on pick.

## G. Save path (P9)

- [ ] **G1 MUST** NEW `AuthRepository.updateProfile({required String displayName, required
  String username, String? about, File? avatarFile, bool clearAvatar = false}) → Future<User>`
  in `auth_repository_impl.dart`: PB `users.update` (multipart when there is a file, the same
  call `ProfileUpdateService` makes today) → `_recordToUser(record)` → `_cacheUserLocally(user)`
  → return `user`. It throws a typed `UsernameTakenException` when PB answers 400 with
  `data.username.code == 'validation_not_unique'` (reuse the field-error parsing pattern at
  `message_repository_impl.dart:43-59`); anything else rethrows. The body comes from a pure
  top-level `profileUpdateBody({displayName, username, about, clearAvatar})` and the error test
  from a pure top-level `isUsernameTaken(ClientException)`, both in the same file, so they can be
  tested without PB. `UsernameTakenException` lives next to `AuthException` in
  `lib/domain/repositories/auth_repository.dart`.
- [ ] **G2 MUST** NEW `AuthNotifier.updateProfile(...)` awaits G1 and then sets
  `state = AsyncData(AuthAuthenticated(user))`. No `invalidate`. Home's `_ProfileButton`, Profile
  and the editor update in the same frame.
- [ ] **G3 MUST** The editor awaits the notifier with a bound: **8s** without a photo, **30s**
  with one. Success → pop + R5 **Profile updated**. `UsernameTakenException` → E2 field error, no
  pop. Timeout or any other error → R5 **Couldn't save. Try again.**, stays on the screen with
  every edit kept. (A late PB write that lands after a timeout is harmless: it has the same
  values, and the next save or resume refresh reconciles Drift.)
- [ ] **G4 MUST** Every `setState` after an `await` in the editor is behind `mounted`. No
  setState after dispose on any path (picker return, save, timeout).

## H. View someone else's profile (P10)

- [ ] **H1 MUST** Same header as B2/B3 (R1 radius 48, name, `@username`, about) from the `User`
  it is given. Empty name → **Unknown** + initials **?**.
- [ ] **H2 MUST** The online dot is removed (`vp:44-53`). It reads `isOnline` from a snapshot
  passed through the route `extra`, so it shows whatever was true when the chat list last
  loaded. (Deferred decision 3.)
- [ ] **H3 MUST** Friend code = one R10 `SettingsTile`: title **Friend code**, subtitle the code
  (inkSoft 13/18), trailing 48dp copy icon (**Copy friend code**, R5 **Friend code copied**).
  Replaces the accent card (`vp:86-137`). No QR for other people. (Deferred decision 4.)
- [ ] **H4 SHOULD** Live data: watch the cached user row by id (via a domain provider over
  `usersDao.watchUserById`, L4), falling back to the passed `User` until the first event, so a
  friend's rename shows without leaving the screen.
- [ ] **H5 MUST** The `/view-profile` route builder no longer hard-casts `state.extra as User`
  (`app_router.dart:169`). When `extra` is not a `User` (restored route, bad deep link) it shows
  the A1 Scaffold with R7 **Profile unavailable** + **Go back**, instead of crashing.
- [ ] **H6 SHOULD** One way in: chat's `_openConversationInfo` pushes `AppRoutes.viewProfile`
  like Home does, instead of its own `MaterialPageRoute` (`chat_screen.dart:1080-1085`).
- [ ] **H7 SHOULD** Group Info → member profile (deferred from page 4): a non-admin tapping a
  member row, or an admin choosing the new first sheet row **View profile**, pushes
  `AppRoutes.viewProfile` with that member. Your own row pushes `AppRoutes.profile`.

## I. Offline (P11)

- [ ] **I1 MUST** Edit Profile shows the accentSoft strip under the app bar, **You're offline —
  actions are available when you're back.**, driven by `isOnlineProvider`. It clears 250ms after
  reconnect.
- [ ] **I2 MUST** Offline, **Save** is disabled with exactly ONE 38% dim and ONE **Available
  online** (`kOfflineActionHint`) line under the app bar. Fields and the photo picker stay
  usable (local only). Double dim = FAIL.
- [ ] **I3 MUST** Profile and View Profile work offline unchanged (they read cached data). Copy,
  QR, Edit profile and Change Backup PIN stay enabled. Sign out stays enabled (it is local;
  deferred decision 5). No offline strip on these two screens.

## K. A11y & motion (P12)

- [ ] **K1 MUST** Header merged semantics **{name}, @{username}** (+ about when present), avatar
  excluded unless it is a button (B4/F1). Name is a heading. Friend code reads digit by digit:
  semantics label **Friend code {c o d e}** (spaced).
- [ ] **K2 MUST** 48dp floor on every target: copy, gear, Save, camera disc, back, sheet rows,
  dialog buttons.
- [ ] **K3 MUST** Field errors are announced (`TextFormField` error text + a live region for
  **That username is taken.**). Save result toasts are announced.
- [ ] **K4 SHOULD** Photo preview swap = 150ms fade; instant under reduced motion.

## Registry amendments (same PR, L2)

| ID | Amendment |
|---|---|
| R1a | `AppAvatar.image` (`ImageProvider?`, default null): when set it wins over `url`. For local previews (picked file). |
| R1b | `initialsOf(String name, {String fallback = '?'})` exported from `app_avatar.dart`: first character of the trimmed name, upper-cased, or `fallback` when empty. The profile files use it. Moving the 5 private copies (`home_screen.dart:1253`, `chat_tile.dart:188`, `message_context_menu.dart:414`, `request_card.dart:150`, `group_invite_card.dart:183`) onto it is a SHOULD. |
| R13 | `appFieldDecoration(BuildContext context, {String? label, String? hint, String? helper, String? prefixText})` in `lib/core/widgets/app_field.dart`: the page-4 field pattern (`create_group_screen.dart:768`) as one function. Profile uses it for its 3 fields. Migrating the 2 group fields is a SHOULD. |

## Test gates (mandatory; there are NO profile tests today)

- [ ] `test/profile/profile_screen_test.dart`: null user → skeleton (no spinner, no blank) ·
  avatarUrl renders an image, not initials · empty display name doesn't crash (initials **?**) ·
  about shown only when non-empty · **Edit profile** pushes `/edit-profile` · copy → toast
  **Friend code copied** · QR eye colour is ink · Sign out shows the dialog, Cancel does NOT call
  `signOut`, confirm calls it once · no accent/error-coloured `Text` on the screen.
- [ ] `test/profile/edit_profile_screen_test.dart`: shows the existing `avatarUrl` · Save disabled
  when not dirty / invalid / offline (single dim + hint) · username validator messages ·
  `UsernameTakenException` → field error, screen stays · generic failure → **Couldn't save. Try
  again.** and no `$e` text · a blackholed save releases at 8s (30s with a photo) with edits
  kept · back while dirty → discard dialog; back while saving → blocked · picker
  `PlatformException` → toast · no setState after dispose. **Fake the AuthNotifier / repository:
  no PB in this test.**
- [ ] `test/profile/view_profile_screen_test.dart`: header + **Unknown** fallback · no online dot ·
  friend-code row copy · bad route `extra` → **Profile unavailable**, no crash.
- [ ] `test/auth/update_profile_test.dart` (no PB: `AuthRepositoryImpl` needs a live client, so
  G1 keeps its logic in two pure top-level helpers in `auth_repository_impl.dart` and the test
  covers those plus the notifier):
  `profileUpdateBody(...)` returns exactly `display_name`, `username` (lower-cased), `about`, plus
  `avatar: null` only when `clearAvatar`, and never `public_key` / `friend_code` ·
  `isUsernameTaken(ClientException)` is true only for a 400 with `data.username.code ==
  'validation_not_unique'` · with a NEW `test/fakes/fake_auth_repository.dart`, the notifier
  state becomes `AuthAuthenticated` with the new values, `getCurrentUser` is NOT called again
  (no `build()` re-run), and `updatePublicKey` is never called. The Drift write
  (`_cacheUserLocally`) is graded by reading the code.
- [ ] `test/grep_gates_test.dart` extended for `lib/features/profile/`: no `colorScheme`,
  `withValues(alpha`, `CircularProgressIndicator`, `.substring(0, 1)`, `circular(<digit>`,
  `e.toString()` or `$e` in strings **except on `debugPrint(` lines**, no
  `invalidate(authProvider)`, no `profile_update_service.dart` import.
- [ ] Full suite green (366 + new) · analyze 0 errors · `git diff --check` clean.

## Out of scope (do NOT build on this page)

Anything in the key boundary above · the Backup PIN screens themselves · Settings content
(page 6) · auth / onboarding screens (page 7) · the Add-Friend sheet and QR scanner (page 8) ·
full-screen avatar viewer (page 9) · image cropping (needs a new dependency) · email or password
change · delete account · block / report / mute from View Profile · a **Message** button on View
Profile (both entry points are already the chat) · presence / last seen · shared groups or shared
media on View Profile · migrating the other 5 `_initials` copies or the 2 group fields (SHOULDs
under R1b / R13, never MUST here).

---

### Deferred decisions (user may override at review)

1. **Username is editable** (the scope says name/username/bio). It depends on the PB rule check.
   Friends see the new `@username` after their next sync. Alternative: read-only username with a
   **Usernames can't be changed** helper.
2. **Sign out moves from the app bar to an Account row with a confirm.** Alternative: keep it in
   the app bar as an ink text button, with the confirm.
3. **Online dot removed from View Profile** (stale snapshot). Alternative: a live presence line
   via H4, which is a presence feature, so it would be its own task.
4. **Friend code on someone else's profile:** kept as a compact copy row, no QR. Alternatives:
   hide it (a friend code is an "add me" handle), or keep the big card.
5. **Sign out while offline:** allowed, because it is local. The cost: signing back in needs a
   connection. Alternative: disable it offline with the single dim + hint.
6. **Display name max 50** (matches the group name). Register has no max today.
7. **Save bound 30s when a photo is attached** (8s for text only). Alternative: 8s everywhere.
8. **Destructive colour:** same as page 4 (error icon + ink label). Alternative: an `errorText`
   token (foundation amendment).
