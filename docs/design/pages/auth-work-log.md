# Auth (splash, login, register, forgot, Google onboarding, restore wait, font) — implementation work log

Date: 2026-10-29.
Scope: Page 7, checklist `docs/design/pages/auth.md` (A–J, L, registry R15–R18 + P1), board
`auth.html` (S1–S15). Routed to Claude end to end (Omnirush down until 2026-11-02 17:30 IST); no
handoff brief. K1–K5 are separate sessions/tasks and were not touched.

## Status

| Step | Result |
|---|---|
| Spec + checklist | user PASS 2026-10-29, every deferred decision = its default, + decision 23 (font, section L) |
| Implementation | DONE 2026-10-29 by Claude, every MUST in A–J and L |
| Gates | `flutter test` **496/496** (baseline 421 + **75** new; see count below); re-run on top of K1+K3 (`850fe34`, 430): **505/505** · `flutter analyze` 0 errors, no new warnings in changed files · `git diff --check` clean, no trailing whitespace in new files · page-7 grep gate RED (planted `$e`, planted `pocketbase` import) then GREEN · `trail check` no conflicts · key-method diff vs HEAD: all 13 frozen pieces byte-identical (re-checked against `850fe34`) |
| Independent review | fresh-context reviewer subagent: **FAIL → fixed**. Its 1 BLOCK was a test it read mid-edit (already green); 5 SHOULDs + 3 NITs fixed, each proven by a test; 4 NITs recorded, not fixed (below). Key boundary confirmed clean by the reviewer independently |
| Device check | user PASS 2026-10-29 (all 16 items) |
| Commit | one commit on main after the device PASS with spec (`auth.html`, `auth.md`) + this log + the two 2026-10-29 auth learnings + implementation |

## What changed

- **Repository** (`auth_repository_impl.dart`, network legs only): `_bounded()` = 8s on
  `authWithPassword` (sign in + register), `users.create`, both `google-auth` POSTs and the new
  `requestPasswordReset`; timeout → `AuthException(code: 'timeout')`, `SocketException` →
  `code: '0'`. The Google picker and `googleUser.authentication` are not bounded. `register` maps
  `validation_not_unique` on `username` → `UsernameTakenException`, on `email` →
  `AuthException(code: 'email_taken')` (`isFieldTaken`, `isUsernameTaken` now delegates).
  `registerWithGoogle` maps a hook 400 username field error → `UsernameTakenException` (ready for
  decision 18's hook fix; today's 500 stays the generic toast). NEW `requestPasswordReset`,
  `forgetGoogleAccount` (best effort, logs only). `signInWithEmailPassword` gained
  `on AuthException { rethrow; }` so the timeout code survives its catch-all.
- **Domain**: `AuthRepository.requestPasswordReset` / `forgetGoogleAccount`;
  `GoogleAuthResult.photoFailed`.
- **Notifier** (`auth_provider.dart`): G1 `authErrorMessage(error, AuthAction)` (pure);
  `AuthError(message, {field, code})`; every catch goes through `_fail` (G1 copy or field copy,
  detail to `debugPrint`). `registerWithGoogle(…, avatarFile)` uploads the photo through
  `updateProfile` (EXIF strip) bounded at 30s BEFORE publishing `AuthAuthenticated`; failure
  publishes the hook's user with `photoFailed: true`. NEW `requestPasswordReset` (returns G1 copy
  or null; auth state untouched) and `forgetGoogleAccount`.
- **Screens**: login, register, forgot, onboarding rewritten on R3 / R13 / R14 / R5 + tokens;
  NEW `splash_screen.dart` (logic moved verbatim from the router, R15 + name, R3a after 1s with a
  150ms fade). Each screen awaits its own action and reads the resulting state (G4), with a
  screen-local busy flag (C3). NEW `widgets/auth_ui.dart`: `AuthTitle` (h1 + header semantics),
  `authBodyStyle`, `OfflineDim` (single 38%), `OfflineActionHint`, `AuthFooter` (Wrap),
  `PasswordToggle` (tooltips). `AuthTextField` is now a `FormField` over a `TextField` with the R13
  decoration, so validator and server errors both render through `appFieldError`.
  `GoogleSignInButton` = R3 secondary + the 4-colour G.
- **Router**: splash route → `SplashScreen`; register route has no `extra`; onboarding falls back to
  `LoginScreen` when `extra` is not a `GoogleAuthResult` (H2). `redirect` and
  `RouterRefreshNotifier` untouched.
- **Deleted**: `lib/infrastructure/services/auth_onboarding_service.dart` (raw bytes with EXIF;
  only caller was onboarding).
- **Restore wait** (`backup_pin_screen.dart`, `_RestoreOverlay` only): in restore mode a full-page
  progress card (title, phase line from the frozen `RestorePhase` copy, determinate chats bar with
  `semanticsValue`, tabular counts `3 of 12 chats · 410 of 3,100 messages`, keep-open line;
  **Your chats are ready** + success check on `ready`) and **While you wait**: R16, R9 Font + R18,
  R17. Setup / change keep today's saving card unchanged (the overlay reads the screen's `mode`;
  the stopwatch/pulse now start only in those modes). Count line announced at most per 10% step;
  reduced motion parks the indeterminate bar at 30%.
- **Section L**: NEW `font_provider.dart` (T1 shape + `fontFamily` getter);
  `warmPopLight/warmPopDark({fontFamily})` → `ThemeData(fontFamily:)`; `app.dart` watches the
  provider for all three theme builds. NEW R18 `FontChoiceGroup` (titles in their own font; the
  System row uses the platform Typography family so it previews correctly while Jakarta is on).
  Settings: Appearance · Font · Notifications · About.
- **Registry pieces**: R15 `AppLogoTile` (About uses it), R16 `ThemeModeGroup` + `CheckDisc`,
  R17 `NotificationsStatusRow`, P1 `pickCroppedPhoto` (Edit Profile uses it). Rows added to
  `docs/design/10-registry.md`.
- **Native launch** (B4): both `launch_background.xml` paint `@color/launch_bg`; NEW
  `values/colors.xml` `#FAF7F1`, `values-night/colors.xml` `#171512`.
- **Outside the page, needed by its tests** (each one line):
  - `section_header.dart` (R9): title wrapped in `Flexible`. The restore-wait 360dp × 200% test
    overflowed 29px on **While you wait** (Ahem test glyphs exaggerate it, but the fixed-width
    Text in a Row is a real large-text risk). Recorded on the R9 registry row.
  - `app.dart`: `PresenceService` read once in `initState`; `dispose()` called `ref.read`, which
    Riverpod forbids and which threw on teardown (found by the L `KuchBhiApp` test).
- **pubspec**: dev dependency `google_sign_in_platform_interface` (already in the lock as
  transitive; fakes the Google picker in the timeout test, same precedent as
  `image_picker_platform_interface`).

## Decisions taken while building

- E1 says the screen calls the repository provider; Forgot calls
  `authProvider.notifier.requestPasswordReset`, which reads `authRepositoryProvider`. Same layer
  rule (no PocketBase in screens), one fake for all screen tests.
- G4 is met by "await your own action, then read state" instead of a listener per screen, so no
  screen ever reacts to another screen's action.
- Login identity field autofill hints = `username` + `email` (C4 and C6 differ; C4 is specific).
- The onboarding `photoFailed` toast is shown from `rootNavigatorKey.currentContext` when the
  redirect already replaced the screen.
- L7: sign-out wipes Drift, so font (like theme) resets on sign-out. Kept (key boundary).

## Tests: 421 + 75 = 496

| File | New tests |
|---|---|
| `test/auth/auth_error_message_test.dart` | 3 (503/401 cases added in place) |
| `test/auth/login_screen_test.dart` | 12 |
| `test/auth/register_screen_test.dart` | 12 |
| `test/auth/forgot_password_screen_test.dart` | 7 |
| `test/auth/google_onboarding_screen_test.dart` | 11 |
| `test/auth/register_with_google_test.dart` | 6 |
| `test/auth/auth_timeout_test.dart` | 6 (4 timeouts + 2 hook answers) |
| `test/auth/onboarding_router_test.dart` | 2 |
| `test/auth/splash_screen_test.dart` | 3 |
| `test/auth/restore_overlay_test.dart` | 5 |
| `test/settings/font_choice_test.dart` | 7 |
| `test/grep_gates_test.dart` (page-7 gate, inside `main()`) | 1 |

Helper (no tests): `test/auth/auth_harness.dart` (`FakeAuthNotifier`, `pumpAuth` with 360dp ×
200% option). `test/fakes/fake_auth_repository.dart`: additive `registerWithGoogle` override.

Existing test edits (sanctioned by L4, all in `test/settings/settings_screen_test.dart`, all a
consequence of the new Font section):
1. `_pump` overrides `fontFamilyProvider` (the new group reads it).
2. `_pump` sets an 800×1200 surface: the longer list pushed **About** below 800×600, so the
   section-order and About-tap tests could not find it.
3. Section order: `AMOLED < Notifications` became `AMOLED < Font < Plus Jakarta Sans <
   Notifications`.
4. Selected rows `findsOneWidget` → `findsNWidgets(2)` (theme + font), same for the check icons.
5. Mutually-exclusive rows: `AppThemeMode.values.length` → `+ AppFont.values.length`.

Edit Profile tests: unchanged (P1 extraction kept the picker options and the toast copy).

## Key boundary proof

Function-level diff vs HEAD (script in the session scratchpad): SAME for `_initEncryptionKeys`,
`updatePublicKey`, `_saveSession`, `signOut`, `deleteAccount`, `getCurrentUser`, `updateProfile`,
`_avatarJpegWithoutExif`, `_BackupPinScreenState`, `RestorePhase`, `_RestorePhaseCopy`, router
`redirect`, `RouterRefreshNotifier`. `encryption_service.dart`, `encryption_sync_provider.dart`,
secure storage and `lib/core/decrypt/` untouched.

## Review findings and fixes

| # | Sev | Finding | Outcome |
|---|---|---|---|
| 1 | BLOCK | `onboarding_router_test` red | Reviewer read it mid-edit; green before the report landed (prefill cache + reset seam) |
| 2 | SHOULD | G5: keyboard Done submitted offline (login password, register confirm) | Fixed: `_submit` returns when offline. Tests: login + register "offline, keyboard Done" |
| 3 | SHOULD | G3: `_generateUniqueFriendCode` lookup unbounded before `users.create` | Fixed: `_bounded` on the lookup. Test: "register gives up at 8s even in the friend-code lookup" |
| 4 | SHOULD | G4: Login's links stayed live while busy, so Register's error could toast on Login's await | Fixed: Create account + Forgot disabled while `_busy != none` (`AuthFooter.onPressed` nullable). Test: "while busy, Create account and Forgot are disabled" |
| 5 | SHOULD | J6: live region stayed empty with 0–1 chats | Fixed: refresh when empty; step on messages when `convTotal <= 1`. Test: "one chat still announces message counts" |
| 6 | SHOULD | B4: `NormalTheme` window background could flash | Fixed: both `styles.xml` NormalTheme → `@color/launch_bg`. Device check 1 |
| 7 | NIT | Parked bar announced a fake 30% | Fixed. First attempt (`semanticsValue: 'In progress'`) crashed the semantics update (a progress bar's value must be numeric); final: the parked bar's own semantics excluded, a wrapper says "In progress". Test: same J6 test |
| 8 | NIT | F5 photo step re-sent typed name/username | Fixed: re-sends the hook's saved values. Test: "the photo step re-sends what the hook saved" |
| 9 | NIT | `$e` gate only matches a variable named `e` | Not fixed (gate matches the spec's wording); widen when a page needs it |
| 10 | NIT | Non-socket `http.ClientException` on the Google POSTs gets the Google copy, not the network copy | Not fixed: rare; the copy is still honest ("didn't work. Try again.") |
| 11 | NIT | Record `app.dart` change, settings 800×1200 surface, R9 period | Done (both already listed above; R9 row punctuation fixed) |
| 12 | NIT | Timeout test can't detect a bound misplaced around `_saveSession` | Not fixed: placement verified by reading and by the reviewer; a slow-storage case is optional |
| 13 | NIT | One extra splash `go()` when the 1s timer rebuilds | Not fixed: harmless (logic moved verbatim per B1) |

## Cross-session input (Page 7 spec session, 2026-10-29)

- **Red screen on device** (`type 'Null' is not a subtype of type 'GoogleAuthResult'`, onboarding,
  taken username): root cause reproduced with the REAL router
  (`test/auth/onboarding_router_test.dart`). The AuthError makes the router refresh, and the
  refresh rebuilds the onboarding route without `extra`; HEAD's hard cast threw, and the H2
  fallback alone would have bounced the user to Login. Fix: the route keeps the last prefill
  (`_onboardingPrefill` in `app_router.dart`, outside `redirect`); no prefill at all (process
  death) still goes to Login. Test RED before the fix, GREEN after.
- **Hook fixed server-side** (decision 18): 400 username field error → `UsernameTakenException` →
  field copy (repo test); 503 → G1 network copy (`authErrorMessage` maps code 503; repo + G1
  tests); 401 → G1 Google fallback (G1 test). +4 tests (2 router, 2 hook).

## Known limits / follow-ups

- A late `authWithPassword` answer after the 8s timeout still lands in PocketBase's `authStore`
  (the SDK saves it); `_saveSession` does not run, so no keys or user id are set, and the next
  attempt overwrites it. Not visible to the user; noted for the K-series.
- `AppButton`'s own busy spinner is still `CircularProgressIndicator` (core widget, out of scope).

## Device check (you do every real sign-in)

From `auth.md`; item 3's copy is **Wrong email, username or password.** (G1).

1. Cold start signed out, in light, dark and AMOLED: no white flash; splash → login.
2. Cold start signed in: splash → home (or Backup PIN); the spinner only appears on a slow start.
3. Wrong password → **Wrong email, username or password.**; right password → Backup PIN or home.
4. Airplane mode on Login, Register, Forgot: action buttons dimmed + **Available online**; fields
   still type; back online → buttons return without reopening.
5. Register with a taken username → field error; with an email that has an account → field error;
   success → Backup PIN setup. Back from Register returns to Login.
6. Forgot password: the email arrives, the link opens a PocketBase page, the new password signs in.
7. Google, existing account → home. Google, NEW account → onboarding; pick a photo (crop step) →
   Create account → the photo shows on Profile. **Use a different Google account** → the account
   chooser appears on the next Google tap.
8. Password manager offers to save after sign-in / register.
9. 200% font size on a 360dp-wide phone: every auth screen scrolls, nothing clipped.
10. TalkBack: titles read as headings; show-password announces its state; the photo picker reads
    as a button.
11. Edit Profile's photo picker still works (P1).
12. New account → Backup PIN setup appears (email register, and Google onboarding).
13. Existing account, fresh install → Backup PIN restore (**needs K1 merged**): the card counts
    chats/messages; switch the theme mid-restore → re-themes, restore finishes on its own → Home.
14. Sign in with a **username** instead of the email.
15. Settings → Font → **Plus Jakarta Sans**: every screen switches at once, no restart; titles bold,
    button labels semibold (if 400/600/700 look the same, stop and report: L6). Survives a
    restart; back to **System default** works. Same switch from the restore wait.
16. Google onboarding with a **taken username**, after a full restart (not hot reload): the field
    shows **That username is taken.**, no red error screen, the screen stays put.
