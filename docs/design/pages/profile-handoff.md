# Astra brief — Page 5: Profile + Edit Profile + View Profile

Spec PASS by user 2026-10-29 (all 8 deferred decisions = defaults). The pre-implementation PB
gate is done (answers in `profile.md`). Omnirush is down until 2026-11-02 17:30 IST, so **Mimo
implements this** (freebuff has the repo, so paste only the part below the line). After that
date: paste the same text into Omnirush with the listed files attached.

**Attach for Astra (in this order; Mimo skips this list):**
1. `docs/design/pages/profile.md`: the checklist, which is your grading contract
2. `docs/design/pages/profile.html`: the visual spec (P1–P14; P14 = diff vs current code)
3. `docs/design/00-foundation.md` · `docs/design/10-registry.md`
4. `lib/features/profile/screens/` (all 3 files) · `lib/infrastructure/services/profile_update_service.dart`
5. `lib/domain/repositories/auth_repository.dart` · `lib/infrastructure/repositories/auth_repository_impl.dart`
   (only `getCurrentUser` :238-275, `_recordToUser`, `_cacheUserLocally` :436-449 matter) ·
   `lib/features/auth/providers/auth_provider.dart`
6. `lib/core/widgets/` (all 13 files) · `lib/core/theme/tokens.dart` · `lib/core/router/app_router.dart`
7. `lib/features/groups/screens/create_group_screen.dart` :760-790 (the field pattern R13 lifts)
8. `test/grep_gates_test.dart` · `test/groups/group_info_actions_test.dart` (the house test style)

---

You are implementing Page 5 of a Flutter app (Riverpod, Drift, PocketBase) against a written
spec. The checklist `docs/design/pages/profile.md` is the contract and the visual spec is
`docs/design/pages/profile.html`. Every MUST is either done or reported as not done with a
reason. SHOULDs come only after all MUSTs.

## Hard rules

1. **Key boundary.** In `auth_repository_impl.dart`, do NOT edit or call `_initEncryptionKeys`,
   `updatePublicKey`, `refreshSessionThrottled`, `signOut`, `deleteAccount`, or anything in
   secure storage. Do not touch the Backup PIN screens. Your only additions to that file are
   `updateProfile` and the two pure helpers `profileUpdateBody` / `isUsernameTaken` (checklist
   G1). Any other change there is an automatic FAIL.
2. **Never `ref.invalidate(authProvider)`** anywhere in `lib/features/profile/`. It re-reads a
   stale cached user and re-runs a branch that can rotate the user's keys. The save sets the
   notifier state from the saved record instead (G2).
3. **The PB update body** is exactly `display_name`, `username` (lower-cased), `about`, plus the
   `avatar` file, or `'avatar': null` only for Remove photo. Never `public_key` or `friend_code`.
4. **Colours.** Use only `context.t.*` and `WarmPopTokens` radii. No `colorScheme`, no
   `withValues(alpha`, no radius literals, and no accent- or error-coloured **text**
   (accent = fills only; destructive = error icon + ink label).
5. **No `$e`, `e.toString()`** or raw ids in any user-visible string. Debug detail goes to
   `debugPrint` only.
6. **Shared pieces.** Only the registry components are used. The three amendments below are the
   only new shared API.
7. **Don't touch** files outside the list below unless a gate forces it. If one does, say so.

## Work order (run the gates after each wave)

**Wave 1: shared pieces + data path**
- R1a: add `AppAvatar.image` (`ImageProvider?`, default null) to `lib/core/widgets/app_avatar.dart`.
  When it is set, it wins over `url`.
- R1b: export `String initialsOf(String name, {String fallback = '?'})` from the same file:
  the first character of the trimmed name, upper-cased, or `fallback` when the name is empty.
- R13: new `lib/core/widgets/app_field.dart` with
  `InputDecoration appFieldDecoration(BuildContext context, {String? label, String? hint, String? helper, String? prefixText})`.
  It is the page-4 field pattern (`create_group_screen.dart:768`): label 13 inkSoft, hint
  inkFaint, line border, accent 1.5 focus border, radiusMd 16, an error border in `t.error`,
  and an error line in `t.ink` (13/18) with a leading error icon.
- Add rows R1a, R1b and R13 to `docs/design/10-registry.md`.
- `UsernameTakenException` next to `AuthException` in `lib/domain/repositories/auth_repository.dart`.
  Add `Future<User> updateProfile({required String displayName, required String username, String? about, File? avatarFile, bool clearAvatar = false})`
  to the `AuthRepository` interface.
- `AuthRepositoryImpl.updateProfile`: PB `users.update` (multipart when there is a file, the
  same call `ProfileUpdateService` makes today) → `_recordToUser(record)` →
  `_cacheUserLocally(user)` → return `user`. On a `ClientException` where `isUsernameTaken` is
  true, throw `UsernameTakenException`; rethrow anything else.
- `AuthNotifier.updateProfile(...)`: await the repository, then
  `state = AsyncData(AuthAuthenticated(user))`.
- Delete `lib/infrastructure/services/profile_update_service.dart` (its only user is the editor).

**Wave 2: screens** (checklist A–I, K)
- `profile_screen.dart`: B, C, D.
- `edit_profile_screen.dart`: E, F, G, I. The save timeout is 8s, or 30s with a photo; it lives in
  the editor around the notifier call. Use `PopScope` for discard and busy.
- `view_profile_screen.dart`: H1–H3.
- `app_router.dart`: H5 only (the `/view-profile` extra guard). Nothing else in the router.

**Wave 3: SHOULDs** (only after every MUST is green): F3 photo sheet, H4 live data, H6 chat route,
H7 Group Info → profile, K4 fade, R1b/R13 migration of the other call sites.

## Copy (verbatim; the checklist and P13 win if they differ)

- Titles: `Profile` (own and others) · `Edit profile`
- Profile: `Edit profile` · `YOUR FRIEND CODE` · `Friend code copied` · `Scan to add me on Kuch Bhi`
  · section `Account` · `Change Backup PIN` · `Sign out`
- Sign-out dialog: `Sign out?` + `This clears your chats from this phone. You can sign back in any time.`
  + `Cancel` / `Sign out`
- Fields: `Display name` · `Username` (prefix `@`, helper `Letters, numbers and underscores`)
  · `About` (hint `A line about you`)
- Validation: `Enter a display name` · `Enter a username` · `At least 3 characters`
  · `Letters, numbers and underscores only` · `That username is taken.`
- Toasts: `Profile updated` · `Couldn't save. Try again.` · `Couldn't open your photos.`
- Discard dialog: `Discard changes?` + `Your edits won't be saved.` + `Keep editing` / `Discard`
- Photo sheet (SHOULD): `Choose from gallery` · `Take photo` · `Remove photo` · meta `Not saved yet`
- View profile: `Friend code` row · `Unknown` (empty name) · `Profile unavailable` + `Go back`
- Offline: `You're offline — actions are available when you're back.` · `Available online`
  (import `kOfflineActionHint`; never retype it)
- Semantics: `Settings` · `Edit profile` · `Change profile photo` · `Copy friend code`
  · `QR code for your friend code` · `Friend code K B 7 Q 2 X` (each character spaced)

## Files

**Create:**
- `lib/core/widgets/app_field.dart`
- `test/fakes/fake_auth_repository.dart`
- `test/profile/profile_screen_test.dart`
- `test/profile/edit_profile_screen_test.dart`
- `test/profile/view_profile_screen_test.dart`
- `test/auth/update_profile_test.dart`

**Modify:**
- the three `lib/features/profile/screens/` files
- `lib/core/widgets/app_avatar.dart`
- `lib/domain/repositories/auth_repository.dart`
- `lib/infrastructure/repositories/auth_repository_impl.dart` (additions only, per hard rule 1)
- `lib/features/auth/providers/auth_provider.dart` (add `updateProfile`; nothing else)
- `lib/core/router/app_router.dart` (H5 only)
- `test/grep_gates_test.dart`
- `docs/design/10-registry.md`
- SHOULD only: `lib/features/chat/screens/chat_screen.dart` (H6), `lib/features/groups/screens/group_settings_screen.dart` (H7)

**Delete:** `lib/infrastructure/services/profile_update_service.dart`

The test cases each file must cover are under "Test gates" in the checklist. Fake the auth
repository/notifier in every widget test: no PocketBase and no secure storage. For the picker,
replace `ImagePickerPlatform.instance` with a fake in the test (the plugin's own test seam). Do
not add a picker provider just for tests.

## Gates (run them yourself and paste the output)

- `flutter analyze`: 0 errors
- `flutter test`: all green. The baseline is 366/366, so the result must be 366 + your new
  tests, with no existing test changed to pass.
- `git diff --check`: clean
- `grep -rn 'colorScheme\|withValues(alpha\|CircularProgressIndicator\|substring(0, 1)\|invalidate(authProvider)\|e.toString()' lib/features/profile/`: empty
- `git diff --stat`: no files outside the list above
- Do not commit.

Report back with:
1. The checklist, with each item ticked and evidence (test name or file:line).
2. Any MUST not done, with the reason.
3. The full diff.

Claude grades the result. Do not claim PASS.
