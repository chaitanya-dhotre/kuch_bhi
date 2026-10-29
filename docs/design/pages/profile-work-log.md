# Profile + Edit Profile + View Profile — implementation work log

Date: 2026-10-29.
Scope: Page 5, checklist `docs/design/pages/profile.md`, spec `profile.html`, brief
`profile-handoff.md`.

## Status

| Step | Result |
|---|---|
| Audit of the 3 existing screens + callers | DONE 2026-10-29 (P14 diff, 34 rows) |
| Spec + checklist | user PASS 2026-10-29, all 8 deferred decisions = defaults |
| Pre-implementation PB gate | DONE 2026-10-29 (owner may change `username`; unique index is case-sensitive; file clear = `'avatar': null`, from docs, so F3 needs a device check) |
| Implementation | DONE 2026-10-29 by Claude Sonnet (user-run, from `profile-handoff.md`): every MUST. SHOULDs F3, H4, H6, H7 and the R1b/R13 migration not done. K4 fade done |
| Grading | CODE-LEVEL PASS 2026-10-29 (Claude) after 4 fixes, below. Stand-in checks clean: no commits; only the brief's files (+ `pubspec.yaml`/`.lock` for fix 3); `auth_repository_impl.dart` vs HEAD = additions only (`profileUpdateBody`, `isUsernameTaken`, `updateProfile`, `dart:io`); no key method called |
| Gates after fixes | `flutter test` **398/398** (HEAD baseline re-measured in a clean worktree: 366; +31 page tests, +1 gate) · `flutter analyze` 0 errors (87 issues, all pre-existing) · `git diff --check` clean (tracked + new files) · forbidden-pattern grep over `lib/features/profile/` empty |
| Device check | Check 1: 2 findings (see below). Check 2: **PASS** (user, M52, 2026-10-29) |
| Commit | one commit with spec + handoff + work log + learning `2026-10-29-never-refresh-the-signed-in-user-chaitanya.md` + implementation |

Baseline before implementation: `flutter test` 366/366.

## Grading fixes (Claude)

1. **The page-5 grep gate never ran.** It had been pasted after `return hits;` inside the
   `bannedPaletteHits` helper, so `test()` was dead code. That was the missing test in the
   implementer's 397 (expected 398). Moved into `main()`; it runs and passes.
2. **Save would fail after a cold start.** `updateProfile` read `_pb.authStore.record!.id`, but
   `getCurrentUser` restores the token with a null record (`authStore.save(driftToken, null)`).
   It now falls back to the cached `currentUserId` setting. This is graded by reading the code:
   the repository needs a live PB, so it has no unit test.
3. `image_picker_platform_interface` added to `dev_dependencies` (^2.11.1, the locked version).
   The profile test imports it as the picker's test seam; this clears the
   `depend_on_referenced_packages` lint.
4. **K1 on View Profile.** The friend-code row is now one semantics node,
   **Friend code K B 7 Q 2 X**, button, with the hint **Copy friend code**, and tapping the row
   copies.

## Device check 1 (user, M52, 2026-10-29): 2 findings

1. **Photo blank after save.** Root cause on live PB: `users.avatar` is a **protected** file
   field, so `/api/files/users/{id}/{file}` without a file token returns **404** (confirmed with
   curl on the server). User avatars have never loaded; the user is the only one with one. Group
   icons work because `conversations.icon` is not protected. R1 then showed an empty accentSoft
   disc, because it hid the initials whenever a URL was set.
   - Fixed client-side: R1 now paints the photo as `foregroundImage` over the initials, so a slow
     or failed load shows initials (test updated).
   - **Open:** making avatars load needs a server change (unprotect the field) or file tokens in
     the client. User decision pending.
2. **The app bar was a separate surface band.** Fixed: `profileAppBar` (bg, no tint, no
   scroll-under elevation, the Page 4 Group Info bar) on all four profile scaffolds, plus a test.

**Privacy finding from the same upload:** the stored JPEG still had **EXIF with GPS data**
(image_picker's resize keeps EXIF). `updateProfile` now re-encodes the photo with
`flutter_image_compress` (`keepExif: false`, JPEG q80, `avatar.jpg`) and never falls back to the
original bytes. The avatar already on the server still has GPS until it is replaced. Group
photos, Google-onboarding avatars and chat images take the same unstripped path: backlog.

Suite after these fixes: **399/399**, analyze 0 errors.

## After device check 1 (user-approved, 2026-10-29)

- **Live PB: `users.avatar` unprotected.** The DB was backed up first to
  `/home/ubuntu/pb_backups/data.db.20261029-avatar-unprotect-pre`. Migration
  `pb_migrations/1793269388_updated_users_avatar_public.js` (with a down step that restores
  `protected = true`) ran on a PocketBase restart and is recorded in `_migrations`. Verified:
  the field reads `protected: False`, the user's photo URL returns **200 image/jpeg**, health 200.
- **F5 crop and zoom** (user request): `lib/features/profile/screens/crop_photo_screen.dart`.
  After a pick, the **Move and scale** step offers pinch 1–4× and drag inside a circular guide
  (`t.bg` 65% veil); **Use photo** writes a 512×512 PNG; Cancel or back keeps the old photo. In
  Flutter, with no new dependency. The crop maths is a pure `cropRectInImage` with 4 unit tests;
  2 widget tests cover load + Cancel and the unreadable-file toast. Checklist F5 added.
- Suite **405/405**, analyze 0 errors.

Checked and left as is: Save offline = one `Opacity(.38)` over R3's disabled style, plus a
12px hint. That is the Page 4 Create pattern, which passed on device, so it is not a double dim.
Live PB has 0 mixed-case usernames, so the editor's lower-cased dirty check can't falsely mark a
form dirty today. Google onboarding doesn't lower-case, so that could change later; see the
backlog line below.

Backlog: the offline strip string is now retyped in 4 screens (requests, group info, create
group, edit profile); export one constant next to `kOfflineActionHint`. Google onboarding should
lower-case usernames the way register does.

## Found during the audit (why this page is more than a restyle)

- Edit Profile was unreachable: `/edit-profile` is registered and never pushed.
- A save didn't show: `invalidate(authProvider)` re-read the stale Drift user and re-ran the
  reinstall key branch. Fixed by design in G1–G2 (see the learning above).
- `signOut` wipes every Drift table, and it was a one-tap red text button with no confirm.
