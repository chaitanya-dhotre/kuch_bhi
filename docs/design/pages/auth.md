# Auth: splash, login, register, forgot password, Google onboarding (acceptance checklist, Page 7)

Date: 2026-10-29. Visual ground truth: **`docs/design/pages/auth.html`** (sections S1–S12, numbered;
S10 = which candidate features the app and PocketBase support today, S12 = full diff vs current code).
Authority: `docs/design/00-foundation.md` (tokens/laws) → `docs/design/10-registry.md` (shared pieces)
→ this checklist. Page letters A–I are page-local. Line refs, as of `482ca9d`: `lg` = `login_screen.dart`,
`rg` = `register_screen.dart`, `fp` = `forgot_password_screen.dart`, `go` =
`google_onboarding_screen.dart`, `atf` = `auth_text_field.dart`, `gsb` = `google_sign_in_button.dart`,
`ap` = `providers/auth_provider.dart`, `ar` = `lib/core/router/app_router.dart`, `arr` =
`lib/infrastructure/repositories/auth_repository_impl.dart`, `aos` =
`lib/infrastructure/services/auth_onboarding_service.dart`.

**Starting point.** All five surfaces exist and were audited 2026-10-29: login (279 lines), register (313),
forgot password (223), Google onboarding (449), the splash (`_SplashScreen`, `ar:258-288`), plus
`AuthTextField` (77) and `GoogleSignInButton` (43). Entry points (trail): the router's initial location
and redirect (`ar:80-127`) are the only way into splash/login; Register is reached only from Login
(`lg:258`); Forgot only from Login (`lg:209`); onboarding only from Login's Google button (`lg:67`). No
widget test covers any of them; the only coverage is the colour gate `test/grep_gates_test.dart:36`
and `test/auth/update_profile_test.dart` (profile save, not these screens).

**Routing.** Claude end to end (spec, implementation, grading); Omnirush down until 2026-11-02 17:30
IST. No Astra/Mimo brief. The grading pass is a fresh-context reviewer (subagent or `/code-review`),
never the implementer.

**Pass criteria (page complete when):** all MUSTs ✓ · `flutter analyze` 0 errors · `flutter test`
green (baseline **421/421**, plus the new tests, with no existing test edited to pass) · test-gate
files below green · `git diff --check` clean (and no trailing whitespace in new files) ·
forbidden-pattern grep over `lib/features/auth/` (minus the frozen files) empty · `trail check` clean ·
key-method diff vs HEAD unchanged · fresh-context review with no open BLOCK · device captures light +
dark (+ AMOLED for splash) of: splash, login, login offline, register with a field error, forgot
password sent, Google onboarding · user device PASS (no commit without it).

**Spec status: user PASS 2026-10-29; every deferred decision = its default** (decision 20's font note corrected the same day: Jakarta is the approved optional font, selector = parked T1). Deferred decisions at the
bottom; each has a recommended default.

**Server facts (read-only reads, user-approved, 2026-10-29; nothing changed on the server).**
1. `pb_hooks/google_auth.pb.js`: lowercases and sanitises the username. On a taken username it
   computes a free candidate but then saves the ORIGINAL (`username: un`, not `cand`), so the save
   hits the unique index and the hook answers **500 `"GAuth: <raw error>"`**: not identifiable as
   "username taken" (decision 18). `register` on an existing email → **409**. `signin` on an unknown
   email → 404 (as the client expects). See K2 for a security finding in the same file.
2. SMTP: **enabled**, host and sender set, `appURL = https://kuch-bhi.duckdns.org`. Reset emails
   should send; the link opens PocketBase's own page on that domain (device check 6 proves it).
3. `users`: `username` required, **min 3, no max, no pattern** (the client regex is the only
   pattern guard), unique index (case-sensitive; every client path lowercases). `display_name`
   required, max 255. `password` min 8. `email` unique. **Password auth accepts email OR username**
   (`identityFields: ["email","username"]`, decision 19).

**Status key:** `[x]` implemented AND verified by code/tests or recorded device evidence;
`[ ]` pending, partial, or blocked.

---

## ⛔ Key boundary (read first: a breach here is an automatic FAIL)

Out of scope and frozen: the Backup PIN screens' logic (`backup_pin_screen.dart`: everything except
the `_RestoreOverlay` visuals, J1), the K1–K5 findings (separate tasks), `getOrCreateKeyPair`,
`encryption_sync_provider.dart`, `_initEncryptionKeys`, `updatePublicKey`,
`_saveSession`, `signOut`, `deleteAccount`, `getCurrentUser` (incl. its reinstall branch), secure
storage, `lib/core/decrypt/`, encryption/key services, and the router's `redirect` function body
(`ar:82-127`). If `arr` is edited (G3, E1, F7), those methods are diffed against HEAD **at function
level** and must be byte-identical. Read for context only, do not re-solve:

- `.trail/learnings/2026-10-29-never-refresh-the-signed-in-user-chaitanya.md`
- `.trail/learnings/2026-10-29-user-photos-only-load-from-a-chaitanya.md`
- `.trail/learnings/2026-10-28-group-key-rotation-keeps-history-only-chaitanya.md`
- `.trail/learnings/2026-10-29-one-device-rotates-a-group-s-chaitanya.md`
- `.trail/learnings/2026-10-29-blocking-account-deletion-app-lock-mute-chaitanya.md`

Why the 8s bound (G3) is NOT wrapped around the whole sign-in: `signInWithEmailPassword` →
`_saveSession` → `_initEncryptionKeys` (`arr:66-83, 415-458`). A UI-level `.timeout()` stops waiting
but not the work; a retry would run `_initEncryptionKeys` twice at once on the same device. The bound
goes on the network call only, before `_saveSession` starts.

## A. Shell, laws, grep-gated hygiene (S1, S7)

- [ ] **A1 MUST** C3: colours only via `context.t.*`, radii only via `WarmPopTokens`. No `colorScheme`,
  no `withValues(alpha`, no `Theme.of(context).textTheme` in auth code (today: `lg:117-128, 224-254`,
  `rg:117-129, 286-289`, `fp:104-118, 186-200`, `go:149-436`).
- [ ] **A2 MUST** C4: no accent- or error-coloured `Text` and no accent icon on `bg`/`surface`. Today:
  **Sign Up** / **Sign In** links in accent (`lg:262`, `rg:297`), **Forgot password?** in
  `colorScheme.primary` = accent (`lg:207`), onboarding initial in accent (`go:233`), its error line in
  error red (`go:390`), the reset-sent icon in accent (`fp:181`). Accent appears only as a fill.
- [ ] **A3 MUST** Type scale only: titles h1 24/30 w700 (not `headlineSmall` w600/bold), body 15/22,
  captions 13/18, button labels 15 w600 (R3's own). No w500 (`gsb:113`), no 14 (`go:391`), no 36
  (`go:231`).
- [ ] **A4 MUST** Space scale: side gutter **24** (today 28, `lg:99`, `rg:106`, `fp:63`, `go:158`;
  28 is not on the 4-base list).
- [ ] **A5 MUST** Fields use **R13** `appFieldDecoration` + `appFieldError`. `AuthTextField` stays as
  the auth wrapper (it carries focus/action/validator wiring) but its decoration becomes R13;
  onboarding's two hand-built decorations (`go:314-338, 356-381`) and its fake read-only email box
  (`go:270-298`) become `AuthTextField`.
- [ ] **A6 MUST** Buttons are **R3 `AppButton`**: primary (expanded, `busy`) for the main action,
  secondary for Google, text for links. The four hand-styled `FilledButton`s with `circular(14/16)` and
  inline `CircularProgressIndicator` go (`lg:178-204`, `rg:250-276`, `fp:137-163, 204-218`,
  `go:400-426`). `GoogleSignInButton` becomes an R3 secondary with the 4-colour G (the existing gate
  `grep_gates_test.dart:71` stays green).
- [ ] **A7 MUST** No `$e` / `e.toString()` in user-visible text, in screens **and** in `AuthError`
  messages (`ap:47, 64, 97, 131, 154`, `fp:46`, `go:141`). Detail goes to `debugPrint` only.
- [ ] **A8 MUST** No direct `SnackBar(`; errors use R5 `showToast(…, error: true)` (today raw
  SnackBars on `t.error` with white text, 3.9:1: `lg:84-90`, `rg:91-97`, `fp:43-49`).
- [ ] **A9 MUST** No `flutter_animate` in auth screens: the logo `scale(400ms)` exceeds the 250ms
  ceiling and `shake()` is not a motion token (`go:180, 394`).
- [ ] **A10 MUST** Screens never call PocketBase directly (L4): Forgot's
  `pocketbaseClientProvider…requestPasswordReset` (`fp:35-39`) moves behind `AuthRepository`.
- [ ] **A11 MUST** Never `ref.invalidate(authProvider)` (today `go:99`, after the photo upload).

## B. Splash (S2)

- [ ] **B1 MUST** `_SplashScreen` moves out of `ar` to NEW `lib/features/auth/screens/splash_screen.dart`
  as `SplashScreen`; its navigation logic (`ar:262-284`: the listen + the post-frame `whenData`) moves
  **verbatim**. The route at `ar:131-134` points at it. `redirect` is untouched.
- [ ] **B2 MUST** Visual: `Scaffold(backgroundColor: t.bg)`, centred **R15 `AppLogoTile`** (88) +
  **Kuch Bhi** h1 24/30 w700 ink, 16 between. No lone spinner at first paint (today
  `CircularProgressIndicator`, `ar:287`).
- [ ] **B3 MUST** (decision 10) If the splash is still showing after **1s**, an **R3a `BusySpinner`**
  fades in 24 below the name (opacity, 150ms). The timer is cancelled on dispose. Under reduced motion
  R3a parks (registry contract).
- [ ] **B4 MUST** (decision 11) Native launch window matches the token background, so there is no white
  flash: `launch_background.xml` (both `drawable/` and `drawable-v21/`) paints `@color/launch_bg`,
  NEW `values/colors.xml` = `#FAF7F1`, NEW `values-night/colors.xml` = `#171512`. No logo in the native
  layer (that is the Flutter splash's job).

## C. Login (S3)

- [ ] **C1 MUST** Order, top to bottom, inside one scroll view, gutter 24: 48 · Capybara 112×95 (kept,
  mascot slot) · 16 · **Welcome back** h1, centred, `Semantics(header: true)` · 4 · **Sign in to
  continue** body inkSoft · 32 · Email · 16 · Password · 4 · **Forgot password?** R3 text, end-aligned ·
  16 · **Sign in** R3 primary expanded · 24 · "or" divider (1px `t.line` + 13/18 inkSoft) · 24 ·
  **Continue with Google** R3 secondary expanded · 32 · footer · 32.
- [ ] **C2 MUST** Footer is a `Wrap` (centred): **Don't have an account?** body inkSoft + **Create
  account** R3 text (ink). Not a `Row` (overflows at 200% text on 360dp).
- [ ] **C3 MUST** Busy state follows the button that was tapped: Sign in busy → Google disabled; Google
  busy → Sign in disabled. Today both read `authState is AuthLoading` and Sign in spins during the
  Google flow (`lg:78, 188, 239`). A screen-local `_busy` value (`none | password | google`) drives it.
- [ ] **C4 MUST** (decision 19) The first field is **Email or username** (PocketBase accepts either):
  validator = non-empty only; the `@` check goes. Trimmed; password sent as typed. Keyboard type
  `emailAddress`, autofill hint `username`.
- [ ] **C5 MUST** Show-password toggle kept (`lg:159-167`) with tooltip **Show password** / **Hide
  password**.
- [ ] **C6 MUST** (decision 6) `AutofillGroup` around the fields; hints `email` / `password`;
  `TextInput.finishAutofillContext()` after a successful sign-in.

## D. Register (S4)

- [ ] **D1 MUST** (decision 9) Pushed from Login (`context.push`), so Back returns to Login. App bar
  **R14 `pageAppBar(context, 'Create account')`**; body starts with **Join Kuch Bhi** body inkSoft.
- [ ] **D2 MUST** Fields in order: Display name · Username (`prefixText: '@'`, helper **Letters,
  numbers and underscores. At least 3.**) · Email · Password (helper **At least 8 characters.**) ·
  Confirm password. Labels in sentence case (today **Display Name**, **Confirm Password**). 16 between.
- [ ] **D3 MUST** Validation kept (`rg:142-245`): name ≥2, username ≥3 + pattern, email `@`, password
  ≥8, confirm matches. Username lowercased at submit (kept, `rg:77`).
- [ ] **D4 MUST** Server field errors land on the field via `appFieldError`, not a toast: username taken
  → **That username is taken.** (repo maps `isUsernameTaken` → `UsernameTakenException`, the Page 5
  helper `arr:40`); email taken → **An account with this email already exists.** (`validation_not_unique`
  on `email`). Editing the field clears its server error.
- [ ] **D5 MUST** Footer `Wrap`: **Already have an account?** + **Sign in** R3 text → `pop()` (or
  `go(login)` if nothing to pop).
- [ ] **D6 MUST** The dead Google-prefill parameters go: `prefilledEmail` / `prefilledDisplayName`
  (`rg:11-45`) and the route's `extra` read (`ar:141-146`). Nothing passes them (trail: only caller is
  `lg:258`, with no `extra`).
- [ ] **D7 MUST** (decision 6) Autofill hints `name`, `newUsername`, `email`, `newPassword` ×2.

## E. Forgot password (S5)

- [ ] **E1 MUST** NEW `AuthRepository.requestPasswordReset(String email)` (+ impl, + fake). Impl =
  `users.requestPasswordReset(email)` bounded at 8s (G3). The screen calls it through the repository
  provider and never imports `pocketbase`.
- [ ] **E2 MUST** App bar **R14 `pageAppBar(context, 'Reset password')`** (today a default `AppBar` with
  the title repeated in the body, `fp:59, 101-108`). Body: **Enter your account email and we'll send a
  link to set a new password.** body inkSoft · 24 · Email · 24 · **Send link** R3 primary, busy while
  sending.
- [ ] **E3 MUST** (decision 14) Sent state: 72 `accentSoft` disc with `Icons.mark_email_read_outlined`
  32 in **ink** · 24 · **Check your email** h1 · 8 · **If an account exists for {email}, a reset link
  is on its way. It opens a web page where you choose a new password.** body inkSoft · 32 · **Back to
  sign in** R3 primary → `pop()` · 8 · **Send again** R3 text → back to the form with the email kept.
  PocketBase answers 204 whether or not the email exists, so the copy never claims it does.
- [ ] **E4 MUST** Failure → R5 error toast with G1 copy; the form stays filled.

## F. Google onboarding (S6)

- [ ] **F1 MUST** No app bar; hero layout, gutter 24: 32 · avatar picker · 16 · **Complete your
  profile** h1 `Semantics(header: true)` · 8 · **We found your Google account. Pick a name, a username
  and a photo.** body inkSoft · 24 · Email (read-only `AuthTextField`, lock suffix icon inkSoft) · 16 ·
  Display name · 16 · Username · 24 · **Create account** R3 primary · 8 · **Use a different Google
  account** R3 text. (decision 16: the 64 logo tile `go:165-180` goes; the avatar is the hero.)
- [ ] **F2 MUST** Avatar picker: **R1 `AppAvatar`** radius 48 (`AppAvatar.image` for the picked file,
  `initialsOf(displayName)` otherwise, never accent text) + a 32 camera badge (accent fill, onAccent
  glyph, 2px `t.bg` ring). `Semantics(button: true, label: 'Add a profile photo' | 'Change profile
  photo')`. Disabled while busy.
- [ ] **F3 MUST** (decision 12) Picking = the Page 5 flow: gallery → `CropPhotoScreen` → `File`, via
  NEW shared `pickCroppedPhoto(BuildContext)` (registry P1) extracted from Edit Profile's `_pickImage`
  (`edit_profile_screen.dart:105-130`), which then calls it. A `PlatformException` → toast **Couldn't
  open your photos.** (Edit Profile's copy).
- [ ] **F4 MUST** Display name: required, ≥2 (same rule as register; today unvalidated). Username:
  prefilled from the email exactly as today (`go:44-50`), `prefixText: '@'`, same rule and helper as
  D2, **lowercased at submit** (today sent as typed, `go:120`). Validate on submit, then live.
- [ ] **F5 MUST** Submit → `registerWithGoogle(idToken, displayName, username, avatarFile)`. The photo
  upload moves **inside `AuthNotifier.registerWithGoogle`**: after the hook returns the user and
  **before** state becomes `AuthAuthenticated`, it calls `_repo.updateProfile(displayName, username,
  about: '', avatarFile)` bounded at 30s (Page 5's photo bound). Success → publish the returned user.
  Failure → `debugPrint`, publish the hook's user, and return `photoFailed: true`. Why: today the
  redirect replaces the screen as soon as state turns authenticated, and the `if (!mounted) return`
  at `go:123` then skips the upload, so a picked photo is probably never uploaded (device check).
- [ ] **F6 MUST** The photo goes through `updateProfile` → `_avatarJpegWithoutExif` (`arr:506-517`), so
  GPS/EXIF is stripped. `AuthOnboardingService` (`aos`, raw bytes with EXIF, `aos:25-29`) and its
  provider are **deleted** (only caller `go:94`). No `invalidate(authProvider)` (A11).
- [ ] **F7 MUST** (decision 13) **Use a different Google account** and system Back (`PopScope`) both call
  NEW `AuthRepository.forgetGoogleAccount()` (best effort: `GoogleSignIn().signOut()`, errors only
  logged) and then `go(login)`. Today Back is `context.pop()` on a route reached by `go` (`go:432`),
  which has nothing to pop.
- [ ] **F8 MUST** Errors: username taken → field error **That username is taken.** only once the hook
  answers it as a field error (decision 18); until then the hook's 500 shows the G1 generic toast.
  409 (account already exists) → toast **This Google account already has a Kuch Bhi account. Sign in
  instead.** and `go(login)`. `photoFailed` → R5
  toast **Your account is ready, but the photo didn't upload. Add it from Edit profile.** (not an
  error variant: nothing is lost).

## G. Errors, timeouts, offline (S9)

- [ ] **G1 MUST** NEW pure function `authErrorMessage(Object error, AuthAction action)` in
  `ap` (unit-tested). Copy:

  | Case | Copy |
  |---|---|
  | `TimeoutException`, PB status 0, `SocketException` | **Can't reach the server. Check your connection and try again.** |
  | sign in, status 400 | **Wrong email, username or password.** |
  | Google sign-in / register, other | **Google sign-in didn't work. Try again.** |
  | sign in, other | **Couldn't sign you in. Try again.** |
  | register, other | **Couldn't create your account. Try again.** |
  | reset, other | **Couldn't send the link. Try again.** |

  Server message strings (`_parseErrorMessage`, `arr:655-669`) are never shown on these screens.
- [ ] **G2 MUST** `AuthNotifier` builds `AuthError` from G1 (with an optional `field: 'email' |
  'username'` for D4/F8) and `debugPrint`s the detail. Google picker cancel stays silent (`null`, as
  today).
- [ ] **G3 MUST** (decision 8) 8s bound on each **network call** in `arr`, never around
  `_saveSession`: `authWithPassword` (`arr:73, 241`), `users.create` (`arr:231`), both `google-auth`
  POSTs (`arr:131, 183`), `requestPasswordReset` (E1). Timeout → `AuthException(code: 'timeout')`. The
  Google account picker and `googleUser.authentication` are not bounded (user-paced).
- [ ] **G4 MUST** A screen shows an `AuthError` only for an action it started (screen-local flag). With
  Register pushed above Login, both listeners are alive; today each shows every error.
- [ ] **G5 MUST** Offline (`isOnlineProvider == false`): **Sign in**, **Continue with Google**, **Create
  account** (both screens) and **Send link** are disabled at a single 38% dim, with one
  `kOfflineActionHint` (**Available online**) 13/18 inkSoft centred under the primary button. Fields,
  links, show-password, the photo picker and navigation stay live. Splash is never dimmed.

## H. Navigation & routing (S8)

- [ ] **H1 MUST** Login → Register `push`; Login → Forgot `push` (kept); Google new → `go(onboarding,
  extra)` (kept); Google existing / sign-in success → `go(splash)` / redirect (kept).
- [ ] **H2 MUST** The onboarding route tolerates a missing `extra` (process death): `extra` not a
  `GoogleAuthResult` → `LoginScreen` (today a hard cast, `ar:246`).
- [ ] **H3 MUST** `redirect` (`ar:82-127`) and `RouterRefreshNotifier` (`ar:59-70`) are byte-identical
  to HEAD.

## I. A11y & motion (S11)

- [ ] **I1 MUST** Every screen title is `Semantics(header: true)` (R14 does it for app-bar titles).
- [ ] **I2 MUST** At **360dp wide × 200% text** every screen scrolls with no overflow (login, register,
  forgot form + sent, onboarding, splash). Tested at that size, not only at 800px / 1x.
- [ ] **I3 MUST** Field errors are live regions (R13 `appFieldError`); the offline hint is plain text.
- [ ] **I4 MUST** No custom animation beyond B3's 150ms fade; the Capybara keeps its own rig (parks
  under reduced motion).

## J. Restore wait: progress you can use (S13) — decisions 1, 20, 21

Context: after the Backup PIN is accepted, the restore screen awaits `syncAllHistory` (re-download
and decrypt of every conversation, "~1-3 min" per its own comment, `backup_pin_screen.dart:236-240`)
and shows `_RestoreOverlay` (`:703-910`, shown from `build` at `:685-692` while `_isLoading`) with real counts (`HistorySyncProgress`: conversation
index/count, message current/total). Today the user stares at a bar for minutes. **Depends on K1:**
until the key race is fixed, an existing account on a new device usually never reaches this screen.

- [ ] **J1 MUST** Only the restore-progress overlay (`_RestoreOverlay`) is restyled (decision 1 = this view only; PIN entry,
  setup and change keep today's visuals for their own page). Restore **logic is frozen**: `_submit`'s
  restore branch, `RestorePhase` transitions, the `syncAllHistory` call and its `onProgress` mapping,
  `_skipBackup` and every `encryptionSyncProvider` / `go` call are byte-identical to HEAD
  (function-level diff in the gates).
- [ ] **J2 MUST** Layout (scrolls, gutter 24): progress card on `t.surface`, `radiusMd`, 1px line —
  **Unlocking your chats** title 16/22 w600 · phase line 13/18 inkSoft (today's `RestorePhase`
  messages) · determinate bar (track `surface2`, value `accent` = fill) once a total is known,
  indeterminate before · count line **7 of 12 chats** / **1,240 of 3,100 messages** 13/18 inkSoft,
  tabular figures · **Keep the app open. This takes a minute or two.** 13/18 inkSoft.
- [ ] **J3 MUST** (decision 20) Below the card: R9 `SectionHeader('While you wait')` + the **theme
  rows** from Settings (R16, the exact Page 6 group: same provider, same check disc, same error
  toast) + the **Notifications** status row from Settings (R17). Both work offline and never touch
  the network or keys; a theme change re-themes the app without restarting the restore.
- [ ] **J4 MUST** The picks never block or reorder the restore: no dialog, no navigation, no focus
  steal; the screen still leaves only through the frozen `go(home)`.
- [ ] **J5 MUST** When `RestorePhase.ready`, the card's title becomes **Your chats are ready** with a
  success-tinted check (icon in `t.success`, text ink) for the existing transition; nothing waits on
  the user.
- [ ] **J6 MUST** A11y: the count line is a live region announced at most every 10%; the bar has a
  semantics value (`42%`). Reduced motion: the indeterminate bar parks as a static 30% segment.

## L. Font choice (S15) — decision 23, added 2026-10-29 after spec PASS ("Add it to Page 7")

Pulls parked task T1 (`docs/superpowers/plans/2026-10-06-w3-widget-gaps.md` Task 1) into Page 7.
Its provider and theme wiring are kept; its UI (RadioListTile + amber "FONT" header) is replaced
by the Page 6 language. Approved by the W3 spec (P11): system font default, Plus Jakarta Sans
optional (`pubspec.yaml:109-112`, family `PlusJakartaSans`, one variable font file).

- [ ] **L1 MUST** NEW `lib/features/settings/providers/font_provider.dart`, the T1 shape as written:
  `enum AppFont { system, jakarta }`, storage key `app_font`, `AppFontX.fromStorage` (unknown/null →
  `system`), labels **System default** / **Plus Jakarta Sans**, `fontFamilyProvider`
  (`StreamProvider<AppFont>` over `settingsDao.watchSetting`), `fontControllerProvider` →
  `FontController.setFont(AppFont)`.
- [ ] **L2 MUST** `warmPopLight({String? fontFamily})` / `warmPopDark({bool amoled = false, String?
  fontFamily})` thread `fontFamily` into `ThemeData(fontFamily:)`; `null` = system (P11 comment
  updated). `app.dart` watches `fontFamilyProvider` (`valueOrNull ?? system`) and passes it to all
  three theme builds (`app.dart:108-120`). One Drift write repaints every screen with no restart.
- [ ] **L3 MUST** NEW R18 `FontChoiceGroup()` (`lib/features/settings/widgets/font_choice_group.dart`):
  an R10b group of two R10 rows, each title **rendered in its own font** (the row is its preview),
  trailing check disc exactly as R16, `Semantics(selected:, inMutuallyExclusiveGroup: true)`, awaited
  `setFont` in try/catch → R5 **Couldn't change the font. Try again.**, detail to `debugPrint`. Row
  icon: `Icons.text_fields` in the well for both.
- [ ] **L4 MUST** Settings: Appearance becomes R9 **Appearance** + theme group (R16) · 16 · R9 **Font**
  + R18 · then Notifications and About as today. (Amends Page 6 B1's "no other rows".)
- [ ] **L5 MUST** Restore wait (J3): **While you wait** lists theme (R16), then R9 **Font** + R18, then
  Notifications (R17). A font change re-lays-out the overlay live; the restore keeps running (J4).
- [ ] **L6 MUST** Weights must really render in Jakarta. The bundled file is a single **variable**
  font (`fvar` table); Flutter may not map `FontWeight.w600/w700` onto its `wght` axis, which would
  render every weight alike or as synthetic bold. Device check 15 compares 400/600/700. If they do not
  differ: fall back to static Jakarta weight files (400/600/700, OFL, from the official repo; the
  download needs your OK) declared per `weight:` in `pubspec.yaml`. Never `fontVariations` on
  individual styles across the app.
- [ ] **L7 MUST** Sign-out wipes every Drift table (`auth_repository_impl.dart` `signOut`), so the font
  (like the theme) resets to default on sign-out. Kept as is (key boundary); recorded in the work log.

## K. Found while specifying — OUTSIDE Page 7 (proposed as separate tasks; not built here)

- **K1 (blocks J, explains your report) — sign-in creates a new local key before the restore check.**
  Sign-in saves the PB token (`authWithPassword` / `authStore.save`) BEFORE `_saveSession`. The
  message repository's `authStore.onChange` listener (`message_repository_impl.dart:141-185`) sees
  the new identity as soon as `saveCurrentUserId` lands and calls `_reconnect()` → poll fallback →
  `_syncConversations` / `_fetchAndCacheMessages` / `_repairUndecrypted` → `DecryptPass._resolveKeys`
  → `getOrDeriveConversationKey` → **`getOrCreateKeyPair()`, which silently generates and saves a
  NEW key pair when the slot is empty** (`encryption_service.dart:177-205`). Then
  `encryptionSyncProvider` sees `hasLocalPrivateKey() == true` → `tryHasPocketBaseBackup == true` →
  **`keyOk` → Home**, never Restore. The new key is never uploaded, so nothing decrypts until the PIN
  is entered from Profile. Same for email/password and Google (both save the token first). Fix
  belongs in the key boundary: decrypt paths must never create a key (a read-only key getter →
  `key_missing`), generation only in `_initEncryptionKeys` / PIN setup. Static trace, high
  confidence; a logcat of one fresh-install sign-in (`[Keys]` / `[Msg] Auth identity changed`) proves
  it.
- **K2 (security, server) — the `google-auth` hook never verifies the Google token's signature.** It
  base64-decodes the JWT and checks only `exp` and `aud`. Anyone can hand-craft a token with any
  email and get a valid session for that account (sign in, send as them, change their public key).
  Fix: verify with Google (tokeninfo or JWKS) before trusting `email`, and require
  `email_verified`.
- **K3 (keys) — `_initEncryptionKeys` uses the catch-all `hasPocketBaseBackup`** (`false` on any
  network error), so a blip during sign-in on a new device generates AND uploads a new public key
  over the backed-up one. The tri-state `tryHasPocketBaseBackup` exists for exactly this.
- **K4 (server) — hook saves the original username, not its free candidate** (fact 1); decision 18.
- **K5 — Backup PIN restore shows `$e`** (`"An error occurred: ${e.toString()}"`,
  `backup_pin_screen.dart:307`), inside the frozen logic.

## Registry amendments (same commit, L2)

| ID | Amendment |
|---|---|
| R15 | `AppLogoTile({double size = 88})` in NEW `lib/core/widgets/app_logo_tile.dart`: About's inline logo moved as is (`about_screen.dart:44-53`: accent fill, `radiusXl`, `Icons.lock_outline` at size/2 in onAccent). Used by About and Splash. |
| R16 | `ThemeModeGroup()` in NEW `lib/features/settings/widgets/theme_mode_group.dart`: Settings' Appearance group (`settings_screen.dart:79-91`; the R9 header stays with the caller) moved as is — four R10 rows, check disc, `selected` semantics, awaited `setTheme` + error toast. Used by Settings and the restore wait (J3). |
| R17 | `NotificationsStatusRow()` in NEW `lib/features/settings/widgets/notifications_status_row.dart`: Settings' Notifications row (`settings_screen.dart:93-110`) moved as is, with its resume listener (`:29`). Used by Settings and J3. |
| R18 | `FontChoiceGroup()` in NEW `lib/features/settings/widgets/font_choice_group.dart`: two R10 rows (System default / Plus Jakarta Sans), each title in its own font, R16's check disc and semantics, awaited `setFont` + error toast. Used by Settings and the restore wait (L3–L5). |
| P1 | `pickCroppedPhoto(BuildContext) → Future<File?>` in `lib/features/profile/screens/crop_photo_screen.dart`: Edit Profile's gallery → crop flow (1024 max, quality 80), `null` = cancelled, `PlatformException` → toast. Used by Edit Profile and Google onboarding. |

## Test gates (mandatory; there are NO auth screen tests today)

All screen tests use a fake `AuthNotifier` / `FakeAuthRepository` and an overridden `isOnlineProvider`;
no platform channels, no real network. Semantics via `tester.getSemantics`, not by finding `Semantics`
widgets.

- [ ] NEW `test/auth/auth_error_message_test.dart`: every G1 row (timeout, status 0, sign-in 400,
  Google, each fallback), and no output contains `Exception` or `$`.
- [ ] NEW `test/auth/login_screen_test.dart`: empty submit → both field errors, no notifier call ·
  valid submit → `signInWithEmailPassword` once with the trimmed email · `AuthError` → toast with its
  copy · only the tapped button is busy · offline → Sign in and Google disabled + **Available online**,
  fields still editable · **Create account** pushes `/register` · **Forgot password?** pushes
  `/forgot-password` · show-password tooltip flips · no `Text` in `t.accent` / `t.error` · 360×200% no
  overflow.
- [ ] NEW `test/auth/register_screen_test.dart`: each validator · username submitted lowercased ·
  `field: 'username'` error → **That username is taken.** under the field, cleared on edit ·
  `field: 'email'` → its copy · **Sign in** pops · an error raised while another screen started the
  action is not shown (G4) · 360×200%.
- [ ] NEW `test/auth/forgot_password_screen_test.dart`: calls `requestPasswordReset` once with the
  trimmed email · sent view shows the email in the copy · **Send again** returns to the form with the
  email kept · failure → G1 toast · offline → **Send link** disabled + hint · 360×200% (form and sent).
- [ ] NEW `test/auth/google_onboarding_screen_test.dart`: username prefill from the email · display
  name required · username lowercased at submit · submit passes the picked file (or null) ·
  `photoFailed` → its toast · **Use a different Google account** → `forgetGoogleAccount` once + `/login`
  · 360×200%.
- [ ] NEW `test/auth/register_with_google_test.dart` (notifier + `FakeAuthRepository`): photo success →
  published user is the updated one · photo throws or exceeds 30s → still `AuthAuthenticated` with the
  hook's user and `photoFailed` · state is never `AuthAuthenticated` before the photo step ends.
- [ ] NEW `test/auth/auth_timeout_test.dart`: `signInWithEmailPassword` and `signInWithGoogle` with a
  never-answering client (`http.runWithClient` / PB `httpClientFactory`) throw `AuthException(code:
  'timeout')` after 8s (fake async), and `_saveSession` never ran (no token written).
- [ ] NEW `test/auth/splash_screen_test.dart`: logo + **Kuch Bhi**, no spinner at t=0, R3a present
  after 1s · unauthenticated → `/login`.
- [ ] NEW `test/auth/restore_overlay_test.dart` (pump `BackupPinScreen(mode: restore)` with a fake
  `EncryptionService.restorePrivateKey` → true and a fake `syncAllHistory` that emits progress then
  completes): the card shows **3 of 12 chats** for that progress; **While you wait** shows the four
  theme rows and the Notifications row; tapping **Dark** calls `setTheme(dark)` once and the sync
  keeps going (its completer still completes, `go(home)` still happens); the bar's semantics value
  matches; 360×200% no overflow.
- [ ] Settings tests (`test/settings/settings_screen_test.dart`) stay green after the R16 / R17
  extraction (imports only). The one sanctioned behaviour edit: section-order / row-count assertions
  (`:63-65`, `:82`) gain the **Font** section (L4). Each such line is listed in the work log with the
  reason; nothing else in that file changes.
- [ ] NEW `test/settings/font_choice_test.dart`: T1's `AppFont` round-trip (null / garbage →
  system) · `warmPopLight(fontFamily:)` and `warmPopDark(amoled: true, fontFamily:)` carry
  `PlusJakartaSans` into `textTheme.bodyMedium`, and `null` without it · tapping **Plus Jakarta Sans**
  calls `setFont(jakarta)` once and that row is `selected` (via `tester.getSemantics`) · a throwing
  `setFont` → toast, no escape · `app.dart` rebuild: pumping `KuchBhiApp` with the provider emitting
  `jakarta` gives `Theme.of(context).textTheme.bodyMedium.fontFamily == 'PlusJakartaSans'` · Settings
  shows **Font** between Appearance and Notifications · 360×200% no overflow.
- [ ] Function-level diff vs HEAD of `_BackupPinScreenState` (every method), `RestorePhase`, the
  `_RestorePhaseCopy` extension, and `HistorySyncProgress` handling: unchanged. Only `_RestoreOverlay`
  / `_RestoreOverlayState` differ.
- [ ] `test/grep_gates_test.dart`: NEW test **inside `main()`** over `lib/features/auth/` minus
  `backup_pin_screen.dart` and `encryption_sync_provider.dart` (frozen): no `colorScheme`,
  `withValues(alpha`, `textTheme`, `CircularProgressIndicator`, `SnackBar(`, `flutter_animate`,
  `(Border|Radius).circular(<digit>`, `e.toString()` / `$e` except on `debugPrint(` lines,
  `invalidate(authProvider)`, `.collection(`, and no import of `pocketbase`, `dio`, `package:http`,
  `secure_storage`, `crypto` or `encryption`. Plus: `auth_onboarding_service.dart` does not exist.
  Prove it RED once (break it locally), then GREEN.
- [ ] Count: the work log records **421 + N = total**, N = tests added, and the suite total matches.
  No existing test edited to pass (Edit Profile tests may change only for the P1 extraction, imports
  or names only, each listed in the work log).
- [ ] Full suite green · analyze 0 errors · `git diff --check` clean · `trail check` clean ·
  function-level diff of the key-boundary methods vs HEAD empty.

## Device check list (phase 2, M52 if connected, else Redmi S2; you do every real sign-in)

1. Cold start signed out, in light, dark and AMOLED: no white flash; splash → login.
2. Cold start signed in: splash → home (or Backup PIN); the spinner only appears on a slow start.
3. Wrong password → **Wrong email or password.**; right password → Backup PIN or home.
4. Airplane mode on Login, Register, Forgot: action buttons dimmed + **Available online**; fields still
   type; back online → buttons return without reopening.
5. Register with a username you know is taken → field error; with an email that already has an
   account → field error; success → Backup PIN setup. Back from Register returns to Login.
6. Forgot password: the email arrives (needs SMTP, gate 2), the link opens a PocketBase page, the new
   password signs in.
7. Google, existing account → home. Google, a NEW Google account → onboarding; pick a photo (crop step
   shows) → Create account → the photo shows on Profile. **Use a different Google account** → the
   account chooser appears on the next Google tap.
8. Password manager offers to save after sign-in / register.
9. 200% font size on a 360dp-wide phone: every auth screen scrolls, nothing clipped.
10. TalkBack: titles read as headings; show-password announces its state; the photo picker reads as a
    button.
11. Edit Profile's photo picker still works (P1 extraction).
12. **New account → Backup PIN setup appears** (email register, and Google onboarding). By code it
    should: a new key is generated and uploaded, no server backup exists → `needsSetup` → setup
    (`encryption_sync_provider.dart:44-64`, `app_router.dart:113-116`). Unverified on a device.
13. **Existing account, fresh install → Backup PIN restore appears** (only after K1 is fixed). Enter
    the PIN → the restore card counts chats/messages; switch the theme mid-restore → the app
    re-themes and the restore finishes on its own → Home with history readable.
14. Sign in with a **username** instead of the email (decision 19).
15. Settings → Font → **Plus Jakarta Sans**: every screen (Home, Chat bubbles, Profile, Settings, auth)
    switches at once, no restart; titles still look bold and button labels semibold (L6: if 400 / 600
    / 700 look the same, stop and report). Survives an app restart; back to **System default** works.
    Same switch from the restore wait.

## Out of scope (do NOT build on this page)

Backup PIN screens (logic always; visuals per decision 1) · everything in the key boundary · email
verification · remember-me · terms/privacy link · a password-strength meter · signing out of Google on
app sign-out (`signOut` is key-boundary; backlog) · the unused `fetchGoogleProfile` /
`getGooglePrefill` (no UI callers; backlog) · Sheets/overlays (page 8) · new mascot placements
(page 10) · `AppButton`'s own internal spinner (core widget, not this page).

---

## Diff vs current implementation

| # | Area | Today (file:line) | Spec | Checklist |
|---|---|---|---|---|
| 1 | Splash location | Private `_SplashScreen` inside the router `ar:258-288` | `screens/splash_screen.dart`, logic verbatim | B1 |
| 2 | Splash visual | Lone `CircularProgressIndicator` on the default canvas `ar:287` | R15 logo + name on `t.bg`; R3a only after 1s | B2, B3 |
| 3 | Native launch | White in light **and** dark (`drawable/launch_background.xml`, `values-night` reuses it) | `#FAF7F1` / `#171512` | B4 |
| 4 | C3 colour | `colorScheme.onSurface.withValues(...)` ×14, `surfaceContainerHighest`, `scaffoldBackgroundColor` (`lg`, `rg`, `fp`, `go`) | `context.t.*` only | A1 |
| 5 | Accent / error text | Sign Up, Sign In, Forgot password?, onboarding initial, onboarding error line, reset icon `lg:207, 262` `rg:297` `go:233, 390` `fp:181` | ink text; accent fill only | A2 |
| 6 | Type | `headlineSmall` w600/bold, w500 Google label, 14 / 36 sizes | h1 24/30 w700, scale only | A3 |
| 7 | Gutter | 28 everywhere | 24 | A4 |
| 8 | Fields | `AuthTextField` radius 12 + error-red text; onboarding hand-built decorations + fake email box `go:270-381` | R13 everywhere via `AuthTextField` | A5 |
| 9 | Buttons | 4 hand-styled `FilledButton`s, radius 14/16, inline spinners; Google `OutlinedButton` | R3 primary / secondary / text | A6 |
| 10 | `$e` | `AuthError('… $e')` ×5 `ap`; `e.toString()` `fp:46`; `'Registration failed: $e'` `go:141` | G1 copy; detail to debugPrint | A7, G1, G2 |
| 11 | Error display | Raw `SnackBar` on `t.error` (3.9:1) `lg:84`, `rg:91`, `fp:43`; red shaking text `go:386-394` | R5 toast or R13 field error | A8, D4, F8 |
| 12 | Motion | `scale(400ms)`, `shake()` `go:180, 394` | none (B3 fade only) | A9, I4 |
| 13 | L4 | Forgot calls PocketBase from the screen `fp:35-39` | `AuthRepository.requestPasswordReset` | A10, E1 |
| 14 | Busy state | Shared `AuthLoading`; Sign in spins during Google `lg:78` | per-button `_busy` | C3 |
| 15 | Footer links | `Row` + `GestureDetector`, overflows at 200% `lg:245`, `rg:280` | `Wrap` + R3 text | C2, D5 |
| 16 | Autofill | None | `AutofillGroup` + hints | C6, D7 |
| 17 | Register nav | `go` both ways, Back exits the app `lg:258`, `rg:293` | `push` / `pop` | D1, D5, H1 |
| 18 | Register app bar | None; title in body | R14 `Create account` | D1 |
| 19 | Register labels | **Display Name**, **Confirm Password**; username helper only | sentence case; `@` prefix; password helper | D2 |
| 20 | Taken username/email | Server string in a toast | field errors | D4 |
| 21 | Dead prefill | `prefilledEmail` / `prefilledDisplayName` + route extra `rg:11-45`, `ar:141-146` | deleted | D6 |
| 22 | Forgot app bar | Default `AppBar` + body title `fp:59, 101` | R14 `Reset password` | E2 |
| 23 | Reset sent copy | "A password reset link has been sent to your email address." (claims an account exists) | neutral, names the email, explains the web page; **Send again** | E3 |
| 24 | Onboarding logo | 64 tile, `margin: horizontal 130`, scale anim `go:165-180` | removed; avatar is the hero | F1 |
| 25 | Onboarding avatar | Hand-built circle, accent initial, raw `Image.file` `go:203-258` | R1 `AppAvatar` + badge + semantics | F2 |
| 26 | Onboarding photo | No crop; raw bytes **with EXIF/GPS** via `AuthOnboardingService` `aos:25-29` | P1 crop → `updateProfile` (EXIF stripped); service deleted | F3, F6 |
| 27 | Photo after sign-up | Upload after `AuthAuthenticated` + `if (!mounted) return` `go:123-128`; redirect likely disposes the screen first | upload inside `registerWithGoogle`, before publish | F5 |
| 28 | Invalidate | `ref.invalidate(authProvider)` `go:99` | never | A11, F6 |
| 29 | Onboarding validation | Display name unchecked; username not lowercased `go:106-121` | ≥2; lowercased | F4 |
| 30 | Onboarding Back | `context.pop()` on a `go` route `go:432` | forget Google account + `go(login)`; `PopScope` | F7 |
| 31 | Onboarding extra | Hard cast `state.extra as GoogleAuthResult` `ar:246` | fallback to Login | H2 |
| 32 | Timeouts | None on any auth call | 8s on network legs only (`arr`) | G3 |
| 33 | Cross-screen errors | Every mounted auth screen shows every `AuthError` | only the screen that started it | G4 |
| 34 | Offline | Nothing; buttons spin then fail | single 38% dim + **Available online** on network actions | G5 |
| 35 | Tests | Colour gate only `grep_gates_test.dart:36` | 9 test files + a page gate inside `main()` | Test gates |
| 36 | Login identity | Email only, `@` required `lg:138-149` | **Email or username** (PB `identityFields`) | C4 |
| 37 | Onboarding 409 | Raw hook message | toast + `go(login)` | F8 |
| 38 | Restore wait | Overlay with a bar for 1-3 min, nothing to do `backup_pin_screen.dart:685-910` | progress card + **While you wait** (theme, notifications) | J1–J6 |
| 39 | Theme / notifications rows | Private to `settings_screen.dart:79-110` | R16 / R17, shared | Registry |
| 40 | Font choice | Jakarta bundled, no selector; `fontFamily` never set (`app_theme.dart:50`) | `font_provider` + theme threading + R18 in Settings and restore wait | L1–L7 |
| 41 | Settings sections | Appearance · Notifications · About | Appearance · **Font** · Notifications · About | L4 |

---

### Deferred decisions (you decide at spec review; default = recommended)

Every candidate was checked against what the app and PocketBase support today (evidence in
`auth.html` S10).

1. **Backup PIN visuals: restyle only the restore-progress overlay here (J), logic frozen; PIN
   entry / setup / change keep their visuals for their own page.** The overlay is where the 1-3 minute
   wait happens. Alternative: leave the whole screen for its own page (then J moves with it).
2. **Show password: keep the toggles that already exist** (`lg:159`, `rg:204, 230`), add tooltips. Keep
   the confirm-password field. Alternative: drop the confirm field, since the toggle lets you check.
3. **Password rules: PocketBase's minimum of 8 only**, shown as a helper up front. No complexity rules
   and no strength meter (the server enforces neither). Alternative: add a strength hint.
4. **Remember me: not offered.** The PocketBase auth store is always persisted; a "don't remember"
   mode would be a new sign-out-on-close feature inside the key boundary.
5. **Terms / privacy link: not offered.** No such document exists in the repo; a private app for
   friends. Alternative: add one when a document exists.
6. **Autofill: add** `AutofillGroup` + hints. A platform feature, no dependency, lets password managers
   fill and save. Alternative: leave it out.
7. **Errors: field-level for "email/username taken", R5 error toast for the rest.** Alternative: an
   inline error block above the primary button on every screen.
8. **8s bound on the network calls inside the repository**, not around the whole sign-in (key boundary
   note above). Alternative: no bound on auth (a dead server spins forever, as today).
9. **Register is pushed from Login**, so Back returns. Alternative: keep `go` (Back exits the app).
10. **Splash: logo + name, a spinner only after 1s.** Alternative: logo only, never a spinner (a hung
    key check would look frozen).
11. **Native launch background = token background** (light `#FAF7F1`, dark `#171512`). AMOLED users
    still see `#171512` for the native frame; the Flutter splash paints true black right after.
    Alternative: leave Android's white.
12. **Onboarding photo: reuse Page 5's crop step** (P1) and upload through `updateProfile` (strips
    EXIF). Alternative: no crop step (the EXIF fix is a MUST either way).
13. **"Use a different Google account" signs the Google picker out**, so the chooser appears next time.
    Alternative: plain Back to Login (the same Google account is picked again silently).
14. **Reset-sent copy is neutral** ("If an account exists…") with **Send again**. Alternative: today's
    copy, which claims an account exists.
15. **Email verification: not required** (PocketBase supports it; the app has never asked for it, and it
    needs SMTP). Its own task.
16. **Onboarding drops its logo tile**; the avatar picker is the hero. Alternative: keep the logo above
    the avatar.
17. **Login keeps its Capybara; no new mascots** until Page 10.
18. **Google onboarding "username taken": fix the hook to answer `400 {data: {username: {code:
    "validation_not_unique"}}}`** (and stop computing an unused candidate), so the client shows the
    field error. A small server change, done with your OK in the K2 server task. Alternative: keep the
    hook; the user sees the generic toast and guesses.
19. **Login accepts email or username** (PocketBase already does). Alternative: email only, as today.
20. **While you wait = theme + font (decision 23) + notifications** (all work offline, touch no keys).
    **Font: not in Page 7.** Correction (2026-10-29): a font choice IS approved: the W3 spec (P11)
    makes the system font the default and bundles Plus Jakarta Sans (`assets/fonts/PlusJakartaSans/`,
    `pubspec.yaml:109-112`) as the optional user-selectable font; foundation §3's "Jakarta only labels
    boards" is the stale line (conflicts resolve upward to W3). But no selector exists yet: it is the
    parked task T1 in `docs/superpowers/plans/2026-10-06-w3-widget-gaps.md` (Drift setting cloned from
    the theme pattern + a Settings row). Superseded by decision 23: T1 is pulled into Page 7 (section L) and its row joins
    **While you wait**. Also considered and left out: profile photo (an existing account usually has
    one; needs the network mid-restore), chat wallpaper (doesn't exist), tips carousel (copy to
    maintain, nothing to do). Alternative: theme only.
21. **The restore stays blocking** (today's logic; the picks make the wait useful). Alternative: let
    the user go to chats while history finishes in the background: a change to the restore and sync
    logic, so its own task inside the key boundary.
22. **K1–K5 are separate tasks, not Page 7.** K1 and K2 first (K1 decides whether restore ever shows;
    K2 is an account-takeover hole). Proposed as their own sessions.
23. **Font choice joins Page 7** (your ruling 2026-10-29, "Add it to Page 7"): section L, parked T1's
    provider/theme wiring with Page 6 visuals, in Settings and in the restore wait.
