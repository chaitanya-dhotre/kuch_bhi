# App lock (12.11) — phase 2 work log

## Baseline (2026-11-02, before any phase 2 change)

- HEAD `719eb59`. Shared working tree: **979/979** passed (`flutter test`, ~57 s). The 3 over the spec's 976 are
  another session's uncommitted `test/chat/chat_presence_subtitle_test.dart` (+ its `media_blob_store` /
  `chat_tile_test` edits); not app lock. Gate counts below are against 979.

## J1 + J2 (Claude)

- `EncryptionService.checkBackupSecret` added after `restorePrivateKey` in `lib/services/encryption_service.dart`:
  51 insertions, 0 deletions (frozen methods byte-identical by construction). Same version rules, `parseRecoveryKey`,
  `_openBackup` / `_v2Key` / `_v2Aad` / `_isoPbkdf2` as restore; stops after opening; zeroes the plaintext.
- `test/offline/check_backup_secret_test.dart`: 6 tests (v2 restored, v1 restoredLegacy, wrong ×3, noBackup,
  unsupported, offline throws). Each check runs on a device holding a different key + cached conv/group keys and
  asserts: secure-storage `readAll()` identical before/after, the users record unchanged, every request a GET.
  Green with `key_backup_format_test.dart` (17/17).
- Expected total after Astra: 979 + 6 (J2) + Astra's new tests.

## Astra grading

### Round 1 (2026-11-03): FAIL — code mostly there, test gates mostly missing

Files and scope match the brief; frozen list respected (`es` untouched by Astra; `cs` only `_enter` + import; `fcm`
show methods only take title/body from `notificationText`; `ma` share-in/clipboard untouched). analyze: 0 errors.
Only 9 app-lock tests against the spec's ~40 test-gate cases.

Fixed by Claude (small, precise):
- **BLOCK E6** back on the lock screen popped the hidden route: `WillPopScope` in the `MaterialApp.router` builder sits
  above every route (no `ModalRoute`), so it never ran; and the default Android transition
  (`PredictiveBackPageTransitionsBuilder`) calls `navigator.pop()` straight from the gesture. Now: while locked the
  overlay swallows `NavigationNotification`s and sets `SystemNavigator.setFrameworkHandlesBack(false)` (Android sends
  the app to the background itself), restored from the last notification on unlock; `didPopRoute` (observer added
  before the Router's) as the button fallback → `moveTaskToBack`. Deviation: back on the Forgot step also
  backgrounds the app (the visible **Back** returns to the PIN step); a back that returned to the PIN step would
  need the framework to own back, which re-enables the route's pop gesture.
- **BLOCK G2** Forgot PIN ignored the wrong-try wait (`registerWrongAttempt` returns early while waiting), so the old
  6-digit backup PIN could be tried without limit. Both Forgot forms now refuse while waiting and show the wait line.
- **BLOCK C3** the fingerprint key went through the once-only auto-prompt guard, so it did nothing after the first
  prompt. It now calls `authenticateWithBiometrics` directly.
- **SHOULD C4** lock-out copy matched on `toString()`; `LockedOut` never matched. Now `biometricErrorCopy` switches on
  `PlatformException.code` (`local_auth/error_codes.dart`).
- **SHOULD G3** every thrown check showed the network copy. Now `forgotPinErrorCopy` uses `isUnreachableError`
  (network vs **Couldn't check your key. Try again.**); details to `debugPrint` as the runtime type only.
- **SHOULD D5** the PIN pad was keyed on `fails`, so a wrong PIN rebuilt it and the shake never showed. Key removed
  (overlay and settings gate).
- **SHOULD (lock off)** `onHidden` covered the app even with the lock off (a logo flash on every return). Now only when
  enabled.
- **SHOULD** `resetPin` with an unreadable entry returned without saving → Forgot PIN a dead end. Now writes a fresh
  entry.
- **NIT** message line `SizedBox(height: 36)` → min height (2 lines at 200% text no longer spill onto the keys);
  `default:` made unreachable by the new `hidden` case removed; two analyzer warnings in the settings screen.

Accepted as is: D4 clamp is implemented as "a wait longer than the step is treated as no wait" (a clock set back skips
the wait, the same reach as setting it forward, which D4 already accepts). The Forgot form is duplicated in the
overlay and the settings gate (follow-up, not this page).

Round 2 → Astra: the missing test-gate cases (brief in the shared notes, `app-lock-astra-round2.txt`).

### Round 2 (2026-11-03): tests only — PASS after Claude fixes

Astra added the test-gate cases (49 app-lock tests in total) and left 4 `skip: true`, reporting them as bugs:
- 2 toast "bugs" (**App lock is on.**, **New PIN set.**) were `fail()` placeholders, not tests. Claude wrote both as
  real tests; both pass. Not bugs.
- 2 `KuchBhiApp` lifecycle tests hung on `Future.delayed` inside fake async. With `tester.pump()` they ran, and one
  found a **real bug (SHOULD F5)**: every resume while locked queued its own `goOnline`, so presence went online N
  times after unlock. `app.dart` now queues one (`_goOnlineWhenUnlocked`). Both pass.

## Fresh-context review (2026-11-03, independent subagent, read-only + scratch tests)

Found **2 BLOCK, 5 SHOULD, 5 NIT**; all BLOCKs and SHOULDs fixed by Claude, each with a test that fails without it.

- **BLOCK** No `Material` / `Overlay` above the lock screen in production (`MaterialApp.builder` sits above the
  Navigator): every lock-screen `Text` got the yellow-underline error style, and the Forgot PIN field threw (no
  Material in debug; `Overlay.of(...)!` on every tap in release), so the only way back after a forgotten PIN broke.
  Tests missed it because the harness mounted the overlay under `home: Scaffold`. Fix: the locked content is
  `Material(color: t.bg, child: Overlay.wrap(...))` (the app child is not wrapped, so dialogs keep the root
  overlay). The lock-screen harness now mounts exactly like production (`MaterialApp.router` + `builder`); with
  `MaterialApp(home:)` the app's own `didPopRoute` pops first, which production (router) never does.
- **BLOCK F5** The chat's 1.5 s mark-read debounce (`cs` `_markReadSub`) sent read receipts while locked whenever a
  message arrived (SSE or resync backfill). The timer now waits for `whenUnlocked()` too. This widens the spec's
  "`cs`: `_enter` only" to `_enter` + that one timer. Test: a message emitted under the lock → 0 marks; after
  unlock → 2 (open + debounce); mutation-checked (removing the gate fails it).
- **SHOULD C5** A fingerprint prompt cancelled by leaving the app (`stickyAuth: false`) had its hidden/resumed
  ignored, so the time away never counted. Now hidden/resumed during the prompt are remembered and applied when the
  prompt did not succeed. Device note: a phone that reports hidden/resumed for the prompt itself, with
  **Immediately**, may lock after a cancelled settings-page prompt (acceptable: the PIN opens it).
- **SHOULD A1/sign-out** The cached entry survived sign-out in memory (old PIN still locks, settings say On, a write
  could re-save it). `app.dart` now calls `readConfig()` when auth becomes unauthenticated (a widening of the `app`
  unfreeze: one `ref.listen` in `build`).
- **SHOULD I2** The wait countdown was re-announced every second. The live region now keeps its label while only
  the digits change (`PinPad._shape`).
- **SHOULD D2 on B4** The settings-page PIN gate had live keys and a frozen countdown during a wait. It now dims the
  keys and ticks (no bypass existed: `unlockWithPin` refuses while waiting).
- **SHOULD D1** Delete + retype of the 6th digit during a running check started parallel checks (uncounted
  guesses). The pad is busy until the check returns.
- **NITs fixed**: Forgot PIN field cleared on success/Back on the settings page (G6); the blank key no longer a
  nameless disabled button (I1); the **Lock after** subtitle is a caption, not a row (B5).
- **NITs left**: the B1 trailing `Row` (**On**/**Off** can't overflow); deprecated `WillPopScope` in the create
  flow and `activeColor` (work as specified; deprecation sweep is repo-wide).
- One Astra test counted every `Switch` in the viewport; the shorter caption brought a third into view. Now it checks
  the fingerprint row only.

## Gates (after the review fixes)

- `flutter analyze`: 0 errors; no warnings in app-lock files.
- `flutter test`: **985 + 55 = 1040/1040** passed, 0 skipped (985 = 979 shared-tree baseline + 6 J2).
- `flutter build apk --release`: built (FlutterFragmentActivity + AppCompat LaunchTheme).
- `git diff --check`: clean.
- `trail check`: 1 match on `checkBackupSecret` vs the 2026-10-29 learning about first-time key setup making a key
  on an unknown backup check. Not applicable: `checkBackupSecret` never makes, installs or publishes a key and is
  not on the key-setup path. Recorded in the commit message.
- Frozen methods: `es` +51/−0 (only `checkBackupSecret`); `cs` `_enter` + the mark-read timer + import; `fcm` only
  the three show methods' title/body; `ma` share-in and clipboard untouched.
- No existing test edited by this page (`test/chat_tile_test.dart`, `test/offline/media_blob_store_test.dart`
  edits are another session's, present before phase 2).

## Known and accepted

- C6 / decision 13: a fingerprint newly added to the phone opens Kuch Bhi (local_auth can't detect it).
- D4: the wrong-try wait uses the wall clock; moving the clock forward skips it.

## Device check

**User device PASS 2026-11-03** (release build, the spec's 17 items; the user entered every PIN, fingerprint and
recovery key).

Observed once, not reproduced, set aside by the user:
- **M52, release:** while browsing chats (unlocked), the in-app back arrow and the system back both did nothing;
  typing and scrolling still worked. Killed from Recents. ~50 open/close cycles afterwards did not bring it back.
  Not in logcat (nothing logs back presses; 14 cold starts since 12:17 that day). App lock's back handling only acts
  while the lock screen is up, and the in-app arrow never goes through it; a stuck predictive-back gesture can't
  happen on Android 13. Next time: note the time and keep the phone on adb before killing the app.
- **Slow "loading" after unlock** = the cold-start splash, not app lock: the router holds `/` while
  `encryptionSyncProvider` re-checks the backup on the server after auth settles (unchanged since 2026-10-31). On
  Airtel LTE with TLS handshakes failing that read took 6–19 s (the laptop: 45 ms). The lock screen only made the
  same wait visible after unlocking. Follow-up candidate: keep Home up while that re-check runs when the value is
  already `keyOk`.
