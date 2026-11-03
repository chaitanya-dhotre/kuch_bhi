# App lock: a PIN (and fingerprint or face) to open Kuch Bhi (acceptance checklist)

Date: 2026-11-02. Backlog **12.11**. Visual ground truth: **`docs/design/pages/app-lock.html`** (sections S1–S9,
numbered; S2 = the lock screen, S3 = setup, S4 = the settings page, S5 = wrong tries and fingerprint states,
S6 = forgot PIN, S7 = notifications and the app switcher, S8 = when it locks, S9 = diff summary).
Authority: `docs/design/00-foundation.md` (tokens/laws) → `docs/design/10-registry.md` (shared pieces) →
`docs/design/pages/key-backup.md` (the recovery key this page reuses for Forgot PIN) → this checklist. Page letters
A–J are page-local; decisions are numbered (bottom). Line refs as of `719eb59`: `app` = `lib/app.dart`, `main` =
`lib/main.dart`, `ar` = `lib/core/router/app_router.dart`, `ss` = `lib/features/settings/screens/settings_screen.dart`,
`cs` = `lib/features/chat/screens/chat_screen.dart`, `fcm` = `lib/services/fcm_service.dart`, `es` =
`lib/services/encryption_service.dart`, `sss` = `lib/data/local/secure_storage/secure_storage_service.dart`, `ma` =
`android/app/src/main/kotlin/com/chai/kuch_bhi/MainActivity.kt`.

**Starting point (audited 2026-11-02, `trail ask/skeleton/callers` + `sed -n` ranges + the local_auth 2.3.0 /
local_auth_android 1.0.56 sources in the pub cache; no code run on a device, no live PocketBase read).**

**Facts, confirmed in code (not assumed).**
1. **Nothing of app lock exists.** `local_auth: ^2.3.0` is in `pubspec.yaml:36` (locked 2.3.0, android 1.0.56) with
   **zero uses in `lib/`** (the Settings learning, 2026-10-29). `AppSettingsKeys.appLockEnabled`
   (`app_settings_table.dart:17`) is a string constant nothing reads or writes. No lock screen, no setting, no PIN
   storage, no lifecycle hook.
2. **local_auth can't run on today's activity.** `MainActivity : FlutterActivity()` (`ma:26`); local_auth on Android
   needs a `FragmentActivity` (`FlutterFragmentActivity`, its README). Its README also needs `LaunchTheme`'s parent to
   be a `Theme.AppCompat` theme "to prevent crashes on Android 8 and below"; today both `values/styles.xml` and
   `values-night/styles.xml` use `@android:style/Theme.*.NoTitleBar`. The plugin's own manifest adds
   `USE_BIOMETRIC` (merged in; nothing to add). It uses `BIOMETRIC_WEAK | BIOMETRIC_STRONG`, plus
   `DEVICE_CREDENTIAL` unless `biometricOnly: true`.
3. **`ma` already hosts two of our channels**: `kuch_bhi/clipboard` (sensitive copy, key backup) and the share-in
   channel (12.1, `onCreate` / `onNewIntent`). Both stay as they are; only the base class changes.
4. **The app's one lifecycle observer** is `_KuchBhiAppState.didChangeAppLifecycleState` (`app:73-110`): `resumed` →
   `presence.goOnline()` + `resyncOnResume` + session refresh; `inactive`/`paused` → `goOffline`; `paused` purges
   the decrypted-body cache (`bodyCachePurgeSignal`, `app:24`). Cold start runs `goOnline` + `resyncOnResume` +
   share-in `start()` in a post-frame callback (`app:47-58`). The notification shade fires `inactive` only (the
   2026-10-14 "locks flash" fix), so a shade pull must never lock.
5. **The chat marks itself read on open and on every resume**: `cs:290` (open) and `cs:329` (resumed) call `_enter`
   (`cs:337-340`) = `markConversationRead` + `presence.enterChat`. A notification tap pushes the chat
   (`fcm:284-312` `_openChat`) even while the app was in the background.
6. **`MaterialApp.router`** (`app:134`) has no `builder` today: the one place an overlay can sit above every route,
   sheet, dialog and toast without touching the router.
7. **Notifications never carry message text** (E2E). Message: title = sender name, body = the server's `preview`
   (media type) or **Sent you a message** (`fcm:604-633`). Friend request: **Friend request** / the sender's name
   (`fcm:635-660`). Group invite: **Group invite** / the inviter's name (`fcm:665-693`). The background isolate
   builds them with its own `SecureStorageService()` (`fcm:481`), so it can read a secure-storage flag.
8. **Secure storage**: `sss` wraps `FlutterSecureStorage` with `encryptedSharedPreferences: true` (Android
   Keystore). Sign-out's `clearSession` (`sss:140-152`) deletes **every key except the key pair slots**; so anything
   app lock stores there is wiped by sign-out and the E2E keys are never touched.
9. **The recovery key can be checked without touching keys, but no method does it yet.** `restorePrivateKey`
   (`es:880-969`) opens the backup (v2 recovery key, or the v1 6-digit PIN) and then **writes**: the device key, the
   public key on the server, and wipes every cached conversation key. Nothing reads the backup without writing.
   `tryGetBackupKind` (`es:1061`) returns `none` / `legacy` / `current` / `null` (unknown).
10. **Neither test phone is below Android 13**: M52 = Android 13 (API 33), Redmi S2 = AviumUI Android 16
    (two-device-testing memory). So `Activity.setRecentsScreenshotEnabled(false)` (API 33+) is the app-switcher path
    on both; the Android 8 AppCompat crash (fact 2) can't be reproduced on them.

**Plugin choice.** `local_auth` (already in `pubspec.yaml`) for fingerprint / face. Hashing with `cryptography`
(already a direct dependency, `Pbkdf2`). Secure storage with `flutter_secure_storage` (already). **No new package.**
The app-switcher snapshot and "send to background" are two lines each of Kotlin on our own channel, as the clipboard
and share-in channels already are (no `flutter_windowmanager` / `screen_protector` plugin for two calls).

**What app lock is, and is not.** A privacy gate for someone holding your unlocked phone. It does not encrypt the
database or the keys (Android's own storage encryption and the Keystore already do), it never changes what is sent,
and it never touches E2E keys. Copy never claims more (G-copy below).

**Routing.** Spec: Claude (this session). Phase 2: **Claude first** writes the one key-adjacent method
(`checkBackupSecret`, J1) and its test, then the user pastes the **Astra brief** (bottom) for everything else; Claude
grades. The grading pass is a fresh-context reviewer, never the implementer.

**Pass criteria (page complete when):** all MUSTs ✓ · `flutter analyze` 0 errors · `flutter test` green (baseline
re-run at phase 2 start, plus the new tests; **no existing test edited**) · test-gate files below green ·
`git diff --check` clean · `trail check` clean · frozen-method diff vs HEAD empty · fresh-context review with no open
BLOCK, findings in `app-lock-work-log.md` · device captures of the device-check list · user device PASS (no commit
without it).

**Spec status: user PASS 2026-11-02; every deferred decision = its default (1–14).** Phase 2 goes in a fresh
session: Claude J1 + J2 first, then the Astra brief.

**Live PocketBase.** None needed. No schema, rule or hook change. Forgot PIN reads your own `users` record, which
the owner-only hide hook (key backup H2, live 2026-10-30) already lets you read.

**Status key:** `[x]` implemented AND verified by code/tests or recorded device evidence; `[ ]` pending.

---

## ⛔ Frozen (read first: a breach here is an automatic FAIL)

E2E and key code anywhere (`es` except J1's new method; `restorePrivateKey`, `backupPrivateKey`,
`generateAndBackupNewKey`, `backupOrCreateKey`, `tryGetBackupKind` byte-identical), `sss` (no new method there: app
lock uses its generic `read`/`write`/`delete`), the router's `redirect` and every existing route, presence service,
receipts and `markConversationRead`, the outbox and its senders, the SSE handler, `resyncOnResume`, the FCM
background fetch / cache / `_markDelivered` / routing, the share-in channel code in `ma`, the clipboard channel,
`bodyCachePurgeSignal` and its purge.

**Unfrozen by this page, and only these:**
- `app`: a `builder` on `MaterialApp.router` for the lock overlay; the lifecycle handler tells the lock controller
  about `hidden` / `resumed`; `presence.goOnline()` (cold start and resume) waits for unlock (decision 11).
- `main`: read the lock settings before `runApp` and pass them in as a provider override (no flash, F1).
- `ar`: ONE new route `/settings/app-lock`. Nothing else.
- `ss`: a **Privacy** section with one row.
- `cs`: `_enter` waits for unlock first (decision 11). Nothing else.
- `fcm`: the three `_show…Notification` methods take their title/body from one new pure function (H1).
- `ma`: base class → `FlutterFragmentActivity`; a new `kuch_bhi/privacy` channel. `values/styles.xml` +
  `values-night/styles.xml`: `LaunchTheme` parent only.
- `es`: J1's new read-only method (Claude writes it, not Astra).
- `app_settings_table.dart`: delete the dead `appLockEnabled` constant (decision 14).
- NEW `lib/features/app_lock/` (controller, platform wrapper, PIN pad, overlay, create-PIN screen, settings screen).

---

## A. What is stored, and how (S1; decisions 2, 3)

- [ ] **A1 MUST** One secure-storage entry, key **`app_lock`**, JSON: `{"v":1,"salt":b64,"hash":b64,"iter":10000,
  "bio":bool,"after":seconds,"hideNames":bool,"fails":int,"waitUntil":ms|null}`. Absent = app lock off. Written
  through `SecureStorageService.write/read/delete` (no new `sss` method). Sign-out's `clearSession` removes it, so
  app lock is off after signing out (fact 8); nothing else ever deletes it except **Turn off**.
- [ ] **A2 MUST** PIN = exactly **6 digits** (decision 2). Stored as PBKDF2-HMAC-SHA256 (`cryptography`'s `Pbkdf2`,
  `bits: 256`), **10,000 iterations**, 16 random bytes of salt from `Random.secure()`, run in `compute` (≈0.35 s on
  the Redmi S2 by scaling the measured 3.55 s for 100k; the M52 is faster). The PIN itself is never stored, logged,
  put in a route or kept after the check. Compare with a constant-time loop. Why so few rounds: the entry already sits
  in Keystore-encrypted storage, and 10^6 PINs fall to any offline attack whatever the round count; the guard that
  matters is the attempt wait (D) and the Keystore. The rounds only keep the PIN out of storage in the clear.
- [ ] **A3 MUST (decision 3)** Weak PINs are refused at create: all six the same (`000000`…`999999`) or a straight
  run up or down (`012345`, `123456`, `234567`, `345678`, `456789`, `987654`, `876543`, `765432`, `654321`,
  `543210`). Field error **Pick a PIN that's harder to guess.**
- [ ] **A4 MUST** Defaults on first turn-on: `after` = 60 (1 minute, decision 5), `hideNames` = true (decision 9),
  `bio` = whatever the setup step chose.

## B. Turning it on, changing it, turning it off (S3, S4; decisions 4, 6)

- [ ] **B1 MUST** Settings (`ss`) gets a new R9 header **Privacy** after **Notifications** and before the About group,
  with one R10 row in an R10b group: icon `Icons.lock_outline`, title **App lock**, trailing value **On** / **Off**
  (flexible, end-aligned: the settings-row learning), chevron. Tap → `/settings/app-lock`.
- [ ] **B2 MUST App lock page, lock off.** R14 bar **App lock**. Body **Ask for a PIN every time Kuch Bhi opens, so
  someone holding your unlocked phone can't read your chats.** Primary R3 **Turn on app lock** → B3. When
  `tryGetBackupKind` says `none`, an R12-style note above the button: **You don't have a recovery key yet. Without
  one, a forgotten PIN can only be fixed by clearing Kuch Bhi's storage, and your old messages would be lost.** with
  an R3 text button **Set up a recovery key** → the route the Home backup banner opens. `legacy`, `current` or
  unknown (offline) → no note.
- [ ] **B3 MUST Create PIN** (one pushed screen, three steps, the shared PIN pad E1):
  1. **Create a PIN** · body **6 digits. You'll enter it each time you open Kuch Bhi.** The 6th digit submits. Weak
     → A3 error, pad cleared.
  2. **Enter it again** · body **Type the same 6 digits.** Mismatch → back to step 1 with the error **Those PINs
     don't match. Try again.**
  3. Only when the phone has a fingerprint or face enrolled (C1): **Unlock with fingerprint or face?** · body **You
     can still use your PIN any time.** · primary **Use fingerprint or face** → the system prompt (C2); success →
     `bio` = true; cancel or error → `bio` = false, no error shown · text button **Not now** (`bio` = false).
  Then save (A1), pop, R5 toast **App lock is on.** System back on step 2 or 3 → step 1 (nothing saved); back on
  step 1 → leave, nothing saved.
- [ ] **B4 MUST (decision 6) Opening the page when the lock is on asks for the PIN first**: the page body is the
  PIN pad, title **Enter your PIN**, fingerprint key when `bio` (C3), wrong-try rules D1–D4, **Forgot PIN?** (F).
  Right PIN or fingerprint → the settings list for as long as the page is open. Back → leave.
- [ ] **B5 MUST App lock page, lock on (after B4)**, R10 rows in R10b groups:
  - **App lock** with a `Switch` (on). Off → R20 **Turn off app lock?** / **Kuch Bhi will open without a PIN.** /
    **Turn off** (not destructive) → delete `app_lock`, toast **App lock is off.**, the page shows B2.
  - **Change PIN** → B3 steps 1–2 only (no fingerprint step), keeps every other setting, resets `fails`, toast
    **PIN changed.**
  - **Unlock with fingerprint or face** `Switch` (C1 decides how it shows). On → the system prompt first (C2);
    success → `bio` = true; cancel → stays off.
  - R9 **Lock after**, then four rows with R16's `CheckDisc` + `inMutuallyExclusiveGroup` semantics:
    **Immediately** (0) · **After 1 minute** (60) · **After 5 minutes** (300) · **After 30 minutes** (1800). Subtitle
    under the header row group: **Time away from Kuch Bhi before it asks again.**
  - **Hide names in notifications** `Switch`, subtitle **Notifications say "New message" instead of who it's from.**
  Every write is awaited; a storage failure → R5 error toast **Couldn't save. Try again.** and the control snaps back.

## C. Fingerprint or face (S5; decisions 4, 13)

- [ ] **C1 MUST** "Available" = `isDeviceSupported()` && `getAvailableBiometrics()` is not empty, read each time the
  page or the lock screen opens (a fingerprint can be removed in between). In the settings list: available → the
  switch works; supported but nothing enrolled → the row dimmed (38%, one `Opacity`, not enabled) with subtitle
  **Add a fingerprint or face in your phone's settings first.**; not supported → no row. Create step 3 only shows
  when available.
- [ ] **C2 MUST** Every prompt = `authenticate(localizedReason: 'Unlock Kuch Bhi', authMessages: [AndroidAuthMessages(
  signInTitle: 'Unlock Kuch Bhi', cancelButton: 'Use PIN', biometricHint: '')], options: AuthenticationOptions(
  biometricOnly: true, stickyAuth: false, useErrorDialogs: false))`. `biometricOnly: true` (decision 4): the phone's
  own PIN or pattern never opens the app. Exceptions are caught; nothing reaches the UI as text except C4's copy.
- [ ] **C3 MUST** On the lock screen with `bio` on and available: the prompt opens **once by itself** each time the
  lock screen appears (not again after the user cancels it); the pad's bottom-left key is a fingerprint key
  (**Unlock with fingerprint or face**) that opens it again. `bio` on but not available now → no key, no prompt, no
  message (the PIN works).
- [ ] **C4 MUST** Prompt errors → a line under the dots (same slot as D-errors, live region):
  `LockedOut` → **Too many tries with fingerprint or face. Use your PIN.**; `PermanentlyLockedOut` → **Fingerprint
  or face is off until you unlock your phone. Use your PIN.**; `NotAvailable` / `NotEnrolled` / cancel → nothing.
  Fingerprint failures never count toward D's wrong tries (Android counts its own).
- [ ] **C5 MUST** While the system prompt is up, lifecycle changes it causes (`inactive`, and `hidden`/`paused` on
  phones that report them) are ignored by the lock controller (an `authInProgress` flag set around `authenticate`),
  so a successful fingerprint with **Immediately** never re-locks.
- [ ] **C6 MUST (decision 13, watch out)** local_auth can't tell when a new fingerprint is added to the phone. Whoever
  can add one (they need the phone's own PIN) can open Kuch Bhi with it. Accepted; stated in the device check and the
  work log, no copy in the app.

## D. Wrong tries (S5; decision 7)

- [ ] **D1 MUST** `fails` and `waitUntil` live in A1 (killing the app doesn't reset them). A wrong PIN →
  `fails += 1`. Tries 1–4 free. After the 5th wrong: wait **30 s**; after the 6th: **1 min**; 7th: **5 min**; 8th
  and every later one: **15 min**. A right PIN or fingerprint resets both. Forgot PIN's reset attempts (F2) count in
  the same counter.
- [ ] **D2 MUST** Copy: a wrong PIN with free tries left → **Wrong PIN.**; with 1–2 free tries left → **Wrong PIN. 2
  more tries before a short wait.** / **Wrong PIN. 1 more try before a short wait.**; while waiting → **Too many
  tries. Try again in 0:30.** (m:ss, counting down; the digits and Delete keys at 38%, not enabled; the fingerprint
  key and **Forgot PIN?** stay enabled). The wait line is announced once when it starts, not every second.
- [ ] **D3 MUST** Nothing is ever wiped, signed out or deleted by wrong tries (decision 7). No attempt limit beyond
  the waits.
- [ ] **D4 MUST** `shortcut:` the wait uses the wall clock (`DateTime.now()`), so moving the phone's clock forward
  skips it. Upgrade = a Kotlin `SystemClock.elapsedRealtime()` stamp on the privacy channel, if it matters. A clock
  set backwards never makes a wait longer than 15 min (clamp `waitUntil - now` to the step's length).
- [ ] **D5 MUST** A wrong PIN: the dots shake once (200 ms, ±8 dp) and clear; `HapticFeedback.vibrate()`. Reduced
  motion: no shake (the dots just clear).

## E. The lock screen (S2)

- [ ] **E1 MUST** NEW shared `PinPad` (registry **R22**): title (h1, `Semantics(header: true)`), optional body, six
  dots (14 dp, `t.line` ring empty / `t.ink` filled), a message line (13/18 ink, live region, min 2 lines reserved so
  the pad doesn't jump), a 3×4 keypad: `1 2 3 / 4 5 6 / 7 8 9 / [fingerprint or blank] 0 [delete]`, keys 72 dp
  circles on `t.surface2` (≥48 dp at any text size), digit 28/w600 ink in a `FittedBox`, delete
  `Icons.backspace_outlined` (**Delete digit**). Long-press delete clears all. Used by the lock overlay, B3 and B4.
- [ ] **E2 MUST Lock overlay.** `MaterialApp.router(builder:)` returns a `Stack`: the app wrapped in `Offstage(
  offstage: locked || covered)` (not painted, no hit tests, no semantics, state kept: routes, drafts, a picked photo
  stay), and on top, when locked, the lock screen; when only covered (F-lifecycle), a plain `t.bg` cover with the
  R15 logo. The overlay has no Navigator of its own: its steps (unlock → Forgot PIN → create → confirm) are internal
  state.
- [ ] **E3 MUST Lock screen layout** (`t.bg`, safe area, scrolls when short, 24 gutter): R15 `AppLogoTile(size: 64)`,
  then E1 with title **Enter your PIN**, no body, the fingerprint key per C3, then R3 text button **Forgot PIN?**.
  Centred, max width 360. Light, dark, AMOLED from tokens only.
- [ ] **E4 MUST** Right PIN → `fails` reset, overlay gone (no animation needed; under 150 ms fade at most, none with
  reduced motion), the app exactly where it was. The keyboard does not come back (E5).
- [ ] **E5 MUST** On lock: `FocusManager.instance.primaryFocus?.unfocus()` (the keyboard goes down; the composer's
  draft stays).
- [ ] **E6 MUST** Android back on the lock screen sends the app to the background (`moveTaskToBack(true)` on the
  privacy channel) and never pops a route underneath. On the Forgot PIN step, back returns to the PIN step.
- [ ] **E7 MUST** A share from another app (12.1) or a notification tap while locked: the share picker or the chat
  opens underneath; the lock stays on top; after unlocking you are on it.

## F. When it locks (S8; decision 5)

- [ ] **F1 MUST Cold start.** Lock on → locked from the very first frame: `main` reads `app_lock` before `runApp`
  and overrides the controller's initial state (fact: `main` already awaits storage and Firebase there). No frame of
  Home or a chat ever paints before the lock.
- [ ] **F2 MUST Going away.** On `AppLifecycleState.hidden` (Flutter fires it before `paused` on Android): stamp
  `awayAt ??= now` and set `covered = true` (so the first frame on return is the cover, never a chat). `inactive`
  alone (notification shade, split-screen peek, the fingerprint prompt) does nothing.
- [ ] **F3 MUST Coming back.** On `resumed`: `covered = false`; if lock on and `now - awayAt >= after` → `locked =
  true`; `awayAt = null`. **Immediately** (0) locks on every return, including from the app's own photo / file /
  camera pickers (the picked item waits in the composer under the lock).
- [ ] **F4 MUST** The decision is one pure function `shouldLock({enabled, awayAt, after, now})` (unit-tested). The
  controller exposes `Future<void> whenUnlocked()` that completes when neither `locked` nor `covered` (so a listener
  that runs before the app's resumed handler still waits correctly).
- [ ] **F5 MUST (decision 11) While locked**, sync keeps running (`resyncOnResume`, SSE, FCM), but
  `presence.goOnline()` (`app` cold start and resume) and the chat's `_enter` (`cs:290`, `cs:329`) wait for
  `whenUnlocked()`. So nobody sees you online, and no read receipts go out, until you have unlocked.
- [ ] **F6 MUST** Turning the lock on doesn't lock you out right away; the first lock is the next time F1 or F3 says
  so.

## G. Forgot PIN (S6; decision 8). Never wipes, never touches keys

- [ ] **G1 MUST** **Forgot PIN?** (lock screen and B4) → a step with title **Reset your PIN** · body **Enter your
  recovery key, or the 6-digit backup PIN if you set one before. Your chats and keys stay as they are.** · one field,
  label **Recovery key or PIN** (same field as the key-backup restore field: text keyboard, `textCapitalization:
  characters`, monospace, `autocorrect: false`, `enableSuggestions: false`, show/hide toggle **Show key** / **Hide
  key**, autofill `password`) · primary **Reset PIN** · text button **Back**.
- [ ] **G2 MUST** **Reset PIN** → J1's `checkBackupSecret(input)` (read-only). Opened (v2 or legacy) → B3 steps 1–2
  inside the overlay → save the new PIN (other settings kept, `fails` reset) → unlocked, R5 toast **New PIN set.**
  Every reset attempt that doesn't open counts as a wrong try (D1), so the old 6-digit backup PIN can't be guessed
  through this screen faster than the PIN itself.
- [ ] **G3 MUST** Results → copy (one pure mapper, tested):

  | Result | Where | Copy |
  |---|---|---|
  | wrong secret | field error, field kept | **That doesn't match your backup. Check for typos and try again.** |
  | input neither 6 digits nor a parseable recovery key | field error, no server call, not a wrong try | **A recovery key has 25 letters and numbers. Check that you have all of it.** |
  | no backup | error card | **This account has no recovery key, so the PIN can't be reset. The only way back in is to clear Kuch Bhi's storage in your phone's settings and sign in again. Your old messages would be lost.** |
  | unsupported | error card | **This backup was made by a newer version of Kuch Bhi. Update the app, then try again.** |
  | network | error card | **Can't reach the server. Check your connection and try again.** |
  | any other | error card | **Couldn't check your key. Try again.** |

- [ ] **G4 MUST** Offline (`isOnlineProvider` false): **Reset PIN** under `OfflineDim` + `OfflineActionHint`
  (**Available online**); the field stays editable. The legacy-PIN check can take ~3.5 s on the Redmi: the button
  shows R3 `busy` meanwhile.
- [ ] **G5 MUST** No **Sign out** on the lock screen (decision 8). No code path in this page deletes, overwrites or
  re-derives a key, calls `restorePrivateKey`, `backupPrivateKey`, `generateAndBackupNewKey`, `deleteKeyPair` or
  `clearSession`, or writes to the server.
- [ ] **G6 MUST** The recovery key never leaves the field: not logged, not stored, cleared from the controller when the
  step closes.

## H. Notifications and the app switcher (S7; decisions 9, 10)

- [ ] **H1 MUST** NEW pure `notificationText({required String type, required Map data, required bool hideNames}) →
  (String title, String body)` in `fcm`, used by all three `_show…Notification` methods (their channel, id, payload
  and details unchanged). `hideNames` = `app_lock` exists **and** its `hideNames` is true (read with the isolate's
  `SecureStorageService()`; a read failure counts as true when the entry can't be parsed, false when absent).
  Hidden: message → **Kuch Bhi** / **New message**; friend request → **Kuch Bhi** / **New friend request**; group
  invite → **Kuch Bhi** / **New group invite**. Not hidden: today's strings exactly.
- [ ] **H2 MUST** It applies whenever app lock is on with the switch on, locked or not (a notification can't know
  whether the app will be locked when it's read).
- [ ] **H3 MUST (decision 10) App switcher.** While app lock is on: API 33+ → `setRecentsScreenshotEnabled(false)`
  (the Recents card is blank; your own screenshots still work); API < 33 → `FLAG_SECURE` on the window (blank card,
  and screenshots of Kuch Bhi are blocked on those phones). Set at start (F1) and whenever the lock is turned on or
  off, through `kuch_bhi/privacy` method `setHideInRecents(bool)`.
- [ ] **H4 MUST** The lock overlay's cover (F2) is the second layer: even if a phone snapshots before the flag takes,
  the snapshot is the cover, not a chat.

## I. Accessibility and layout

- [ ] **I1 MUST** The dots are one semantics node: **PIN, 2 of 6 digits entered** (updates as you type, not a live
  region). Each key a button named by its digit; **Delete digit**; **Unlock with fingerprint or face**. Disabled keys
  are not enabled.
- [ ] **I2 MUST** The message line is a live region, announced once per change. The title is a header.
- [ ] **I3 MUST** 360×640 dp at 200% text (Plus Jakarta Sans too): lock screen, create, Forgot PIN and the settings
  page scroll with no overflow; keys stay 72 dp (digits scale inside them, `FittedBox`). Landscape 640×360: the
  lock screen scrolls, no overflow.
- [ ] **I4 MUST** TalkBack can unlock: focus lands on the title when the lock appears; double-tap keys works.
- [ ] **I5 MUST** Reduced motion (`MediaQuery.disableAnimations`): no shake, no fades.
- [ ] **I6 MUST** No `Text` coloured `t.accent` or `t.error` (foundation C4); error copy in ink with an error icon.
- [ ] **I7 MUST** No `$e`, `e.toString()` or an exception in any visible text; details to `debugPrint` only, never
  the PIN or the key.

## J. The one key-adjacent method (Claude, before Astra)

- [ ] **J1 MUST** NEW `Future<RestoreResult> checkBackupSecret(String secret)` in `es`: reads the current user's
  record and opens the backup exactly as `restorePrivateKey` does (same version rules, same v1/v2 paths, same
  `parseRecoveryKey`, the existing private `_openBackup` / `_v2Key` / `_v2Aad` helpers), then **stops**: returns
  `restored` (v2 opened) or `restoredLegacy` (v1 opened), `wrongSecret`, `noBackup`, `unsupported`; throws when the
  record read fails. It writes nothing anywhere (no storage, no server, no cache), and the decrypted bytes are dropped
  (overwritten with zeros) before it returns. `restorePrivateKey` is not refactored (frozen; the ~20 shared lines are
  duplicated on purpose so the restore path stays byte-identical).
- [ ] **J2 MUST** Test (Claude, in `test/offline/key_backup_format_test.dart`'s harness, a NEW file
  `test/offline/check_backup_secret_test.dart`): v2 right key → `restored`; v1 `'123456'` → `restoredLegacy`; wrong →
  `wrongSecret`; no blob → `noBackup`; `v9:` → `unsupported`; offline → throws; in every case **zero PATCH/POST
  captured and the secure-storage map is byte-identical before and after**.

---

## Test gates (phase 2)

- [ ] NEW `test/app_lock/app_lock_controller_test.dart` (fake storage map, fake clock, fake platform): `shouldLock`
  table (off; away < after; = after; > after; Immediately; null awayAt) · `hidden` → covered; `inactive` alone →
  nothing; `resumed` → covered false and locked per `shouldLock` · events during `authInProgress` ignored · cold start
  with the entry → locked; without → not · `whenUnlocked` completes only after unlock, and waits when `covered` is
  still true · right PIN unlocks and resets `fails` · wrong-try ladder: 4 free, then 30 s / 1 min / 5 min / 15 min,
  persisted across a new controller · a backwards clock never waits > 15 min · weak PINs refused (all 20 listed) ·
  hash round-trip (right PIN true, wrong false) with 16-byte salt and 10,000 iterations recorded · turn off deletes the
  entry and calls `setHideInRecents(false)`; turn on calls `true` · the stored JSON never contains the PIN.
- [ ] NEW `test/app_lock/lock_screen_test.dart` (widget): locked → the app under it is offstage (a `find.text` of a
  chat line finds nothing hit-testable; semantics has no chat text) · 6 digits wrong → **Wrong PIN.**, dots clear ·
  5th wrong → the wait line, digit keys disabled, Forgot PIN enabled · right → overlay gone, the route underneath
  unchanged · fingerprint key only with `bio` + available; prompt opens once by itself, not again after cancel;
  `LockedOut` / `PermanentlyLockedOut` copy · back → `moveTaskToBack` called, no route popped · Forgot PIN: malformed
  → no service call; `restored` → create steps → new PIN works, old doesn't, other settings kept; `wrongSecret` copy
  + `fails` + 1; `noBackup` / `unsupported` / network copy; offline → disabled + **Available online** · no visible
  `Exception` or `$` · semantics: dots label, key names, live message line, header title · 360×640 at 200% + Jakarta,
  and 640×360: no overflow · reduced motion: no animation controller running.
- [ ] NEW `test/app_lock/app_lock_settings_test.dart` (widget): Settings shows **Privacy** / **App lock** / **Off** →
  page B2; `none` backup → the note; `current` → no note · turn on → create (weak refused, mismatch copy) → fingerprint
  step only when available → toast **App lock is on.** → entry written with defaults (60 s, hideNames true) · page with
  lock on asks for the PIN first · Change PIN keeps settings · Lock after rows are a mutually exclusive group and save
  · fingerprint row: available / enrolled-none (dimmed + copy) / unsupported (absent) · turn off → R20 → entry gone,
  toast · a storage write failure → error toast, control snaps back.
- [ ] NEW `test/app_lock/notification_text_test.dart`: every type × hideNames true/false gives the exact strings in
  H1; not hidden = today's strings (sender name, `preview`, fallbacks **New message** / **Sent you a message**,
  **Friend request**, **Group invite**).
- [ ] NEW `test/app_lock/presence_gate_test.dart`: while locked, a resume doesn't call `goOnline` and an opened chat
  doesn't call `markConversationRead` / `enterChat`; both happen once after unlock; lock off → called as today.
- [ ] J2 (Claude).
- [ ] Existing tests green **unedited**, every `test/` file, `grep_gates_test` included (new files must pass its
  token / no-`$e` / no-network-import gates).
- [ ] Count: the work log records **baseline + N = total**.
- [ ] Function-level diff vs HEAD of every frozen method in an edited file: empty.
- [ ] Full suite green · analyze 0 errors · `git diff --check` clean · `trail check` clean · a release build
  (`flutter build apk --release`) succeeds (the activity and theme change).

## Device check list (phase 2, M52 + Redmi; you enter every PIN and fingerprint yourself)

Use a PIN you don't use anywhere else. Claude never types a PIN on the device.

1. Settings → **Privacy** → **App lock** **Off** → the page (with the recovery-key note only if you have none) →
   **Turn on app lock** → try `123456` (refused) → your PIN twice → fingerprint step (M52; the Redmi if it has one) →
   **App lock is on.** The row now says **On**.
2. Swipe Kuch Bhi away, reopen → the lock screen is the first thing you see (no flash of Home), the fingerprint prompt
   opens by itself → unlock. Repeat with the PIN (**Use PIN**).
3. **Lock after 1 minute**: Home button, back within 30 s → no lock; wait 70 s → locked. **Immediately**: pull the
   notification shade → no lock; Home and back → locked; the fingerprint prompt never re-locks itself after success.
4. Recents with the lock on: the Kuch Bhi card is blank on both phones. Take a screenshot inside the app on the M52
   → it works (API 33+). Turn the lock off → the Recents card shows the app again.
5. Have a chat open with a half-typed message → Home → wait → back → lock → unlock → the same chat, the draft still
   there, the keyboard down.
6. On the other phone, send yourself a message while this phone is locked in the foreground: the other phone sees you
   **offline** and the message stays **delivered** (not read) until you unlock and open it.
7. Notification while app lock is on: **Kuch Bhi** / **New message** (no name). Turn **Hide names in notifications**
   off → the sender's name again. A friend request and a group invite read **New friend request** / **New group
   invite** when hidden.
8. Tap a notification while locked → the lock first, then that chat. Share a photo into Kuch Bhi from Gallery while
   locked → the lock first, then **Send to**.
9. Five wrong PINs → **Too many tries. Try again in 0:30.**, keys dim, the countdown runs; kill and reopen → still
   waiting. The 6th wrong → 1 minute.
10. **Forgot PIN?** → airplane mode → **Reset PIN** dimmed with **Available online** → online → a wrong key → the
    error → your real recovery key → make a new PIN → **New PIN set.** → chats all open (keys untouched). Settings →
    Recovery key still works as before.
11. Back button on the lock screen → the phone's home screen, Kuch Bhi still locked when you come back.
12. Settings → App lock with the lock on → asks for the PIN first → **Change PIN** → the old PIN no longer opens it.
    **Turn off** → the dialog → reopen the app: no lock.
13. Sign out and back in → app lock is off (and your chats open, keys untouched).
14. Add a new fingerprint in the phone's settings → it opens Kuch Bhi (C6: known, accepted). Remove all
    fingerprints → no fingerprint key, PIN only, no error.
15. Largest text + Plus Jakarta Sans, 360dp if available: lock screen, create, Forgot PIN, settings page. TalkBack:
    the title is read first, keys by digit, **PIN, 3 of 6 digits entered**, the wrong-PIN line once. Landscape lock
    screen scrolls.
16. Reduce animations: no shake. Light, dark, AMOLED captures of the lock screen, create step, settings page.
17. Redmi only: the app starts normally after the theme change (no white flash change you dislike, no crash).

## Out of scope (do NOT build on this page)

A separate PIN per chat or hidden chats · a password (letters) instead of a PIN (decision 2's alternative) · the
phone's own screen lock as the app lock (decision 1's alternative) · wiping data after N tries · lock on a timer while
the app is open in front · a "panic" / decoy PIN · detecting new fingerprints with a Keystore key (decision 13's
alternative) · encrypting the database with the PIN · Sign out on the lock screen · iOS (no iOS build here) · anything
in ⛔.

**Follow-ups noticed (not this page):**
- **F-a** `restorePrivateKey` and J1's `checkBackupSecret` share ~20 lines by copy; once key backup has been stable
  for a while, one private `_openBackupFor(userId, secret)` can serve both (a key-boundary change of its own).
- **F-b** Notification channels: a phone's own "hide sensitive content on the lock screen" setting already hides the
  body there; Kuch Bhi never sets a `publicVersion`. Not needed while bodies carry no text.

---

## Diff vs current implementation

| # | Area | Today (file:line) | Spec | Checklist |
|---|------|-------------------|------|-----------|
| 1 | App lock | nothing; `local_auth` unused; dead `appLockEnabled` (`app_settings_table.dart:17`) | PIN + fingerprint/face, one secure-storage entry | A, B, C |
| 2 | Activity | `FlutterActivity` (`ma:26`), plain `LaunchTheme` | `FlutterFragmentActivity`, AppCompat `LaunchTheme` parent | B, C |
| 3 | Settings | Appearance, Font, Notifications, About (`ss:24-40`) | + **Privacy → App lock** | B1 |
| 4 | Overlay | no `builder` (`app:134`) | lock overlay over every route; app offstage | E2 |
| 5 | Lifecycle | `paused`/`inactive` → offline; `resumed` → online (`app:73-110`) | + `hidden` → cover + stamp; `resumed` → lock decision; online waits for unlock | F |
| 6 | Chat read | `_enter` on open/resume (`cs:290, 329`) | waits for unlock | F5 |
| 7 | Notifications | sender name / inviter name (`fcm:604-693`) | **Kuch Bhi** / **New message** while lock + hide names | H1 |
| 8 | Recents snapshot | shows the last screen | blank while lock on | H3 |
| 9 | Backup check | only `restorePrivateKey` (writes keys) | `checkBackupSecret`, read-only | J1 |

---

## Deferred decisions (default in bold; reply with a number to change one)

1. **Kuch Bhi's own PIN** (Telegram style). Someone who knows your phone's PIN (family, a partner) still can't open
   your chats. Alternative: use the phone's own screen lock (fingerprint, face, or the phone's PIN/pattern; WhatsApp /
   Signal style): far less to build (no PIN storage, no wrong-try rules, no Forgot PIN: Android handles all three),
   but anyone who knows the phone's PIN gets in.
2. **Exactly 6 digits**, the 6th digit submits. Alternative: 4 to 8 digits with an OK key, or also a password
   (letters) option (a text field instead of the pad on every lock screen).
3. **Refuse all-same and straight-run PINs** (20 PINs). Alternative: allow any 6 digits.
4. **Fingerprint or face is an optional shortcut; only your Kuch Bhi PIN backs it up** (`biometricOnly: true`).
   Alternative: let the phone's own PIN/pattern also open the app from the system prompt.
5. **Lock after: Immediately / 1 minute (default) / 5 minutes / 30 minutes.** Alternative sets: WhatsApp's
   Immediately / 1 min / 30 min, or Telegram's 1 min / 5 min / 1 h / 5 h.
6. **Opening App lock settings asks for the PIN once**, then Change PIN and Turn off need nothing more. Alternative:
   no gate on the page; ask for the PIN only on Change PIN and Turn off.
7. **Wrong tries: 4 free, then waits of 30 s, 1 min, 5 min, then 15 min per try; nothing is ever wiped.**
   Alternative: no waits (a 6-digit PIN can then be tried in a few hours by hand), or erase after 10 tries (rejected:
   it would destroy keys).
8. **Forgot PIN = your recovery key (or old backup PIN), checked without touching anything; no Sign out on the lock
   screen.** Without a recovery key, the only way in is clearing the app's storage (old messages lost, the same as
   Telegram's passcode). Alternatives: **(a)** also a **Sign out** button: sign-out keeps this phone's keys, so
   signing back in opens every chat, which means anyone who can sign in to your account (for a Google account, anyone
   holding your phone with its Google account) gets past the lock; **(b)** re-enter your account password instead of
   the recovery key (same Google-account problem).
9. **Hide names in notifications: on by default when app lock is on.** Alternative: off by default.
10. **App switcher: blank card on Android 13+ with screenshots still allowed; on older Android, `FLAG_SECURE` (blank
    card, screenshots blocked).** Alternatives: `FLAG_SECURE` everywhere while the lock is on (also blocks your own
    screenshots on Android 13+), or nothing below Android 13 (the cover, H4, is then the only guard).
11. **While locked you stay offline and nothing is marked read until you unlock**; messages still sync. Alternative:
    online and read as today the moment the app comes to the front.
12. **Our own on-screen keypad.** Alternative: the phone's number keyboard under one hidden field (less code; the
    keyboard sometimes doesn't come up by itself on return, and it pushes the layout around).
13. **Accept that a newly added phone fingerprint opens Kuch Bhi** (local_auth can't detect it; WhatsApp behaves the
    same). Alternative: a Keystore key bound to the current fingerprints through our own Kotlin channel (~60 lines),
    so adding one turns fingerprint unlock off until the PIN is used.
14. **Delete the unused `appLockEnabled` constant** so the next search doesn't find a fake feature. Alternative: keep
    it.

## Baseline

Recorded 2026-11-02 at `719eb59` on a clean detached checkout, before any phase 2 change: **976/976** (`flutter
test`, all passed, ~1 min). The shared working tree at the same time read 976 passed / 3 failed, all 3 in files
another session had uncommitted edits in (`media_blob_store`, the new `chat_presence_subtitle_test.dart`), not app
lock. Phase 2 re-runs it first and records it again.

---

## Astra implementation brief (paste as is, after Claude has landed J1)

```text
You are implementing "App lock" in a Flutter app (Android only). You do not know this repo; everything you need is
below. Do exactly this, nothing more. Do not change files not listed. Do not add packages.

REPO: /home/chaitanyadhotre/kuch_bhi (Flutter 3.47, Riverpod 2.6 with plain Provider/Notifier, go_router 14).
SPEC: docs/design/pages/app-lock.md (sections A–I are yours; J is already done). The HTML board
docs/design/pages/app-lock.html shows every screen. Copy in bold in the spec is VERBATIM: use it exactly.

ALREADY THERE (use, don't rebuild):
- local_auth 2.3.0, cryptography (Pbkdf2, Hmac.sha256), flutter_secure_storage: all in pubspec.yaml.
- SecureStorageService (lib/data/local/secure_storage/secure_storage_service.dart): use only its
  read({key}), write({key, value}), delete({key}). Provider: secureStorageProvider.
- EncryptionService.checkBackupSecret(String) -> Future<RestoreResult> (lib/services/encryption_service.dart):
  read-only check of the recovery key; enum RestoreResult {restored, restoredLegacy, wrongSecret, noBackup,
  unsupported}; throws on network errors. tryGetBackupKind(userId) -> BackupKind? {none, legacy, current}.
  parseRecoveryKey(String) -> String? in lib/core/utils/recovery_key.dart.
- Theme tokens: `final t = context.t;` (t.bg, t.surface, t.surface2, t.ink, t.inkSoft, t.inkFaint, t.line,
  t.accent, t.onAccent, t.accentSoft, t.error). Never a hex colour. Never colour a Text with t.accent or t.error.
- Shared widgets (lib/core/widgets/): pageAppBar (R14), SettingsTile (R10), SettingsGroup, SectionHeader (R9),
  AppButton (R3, variants primary/secondary/text, busy), showToast (R5), showConfirmDialog (R20), AppLogoTile (R15),
  appFieldDecoration (R13), StatusBanner (R12). CheckDisc is in
  lib/features/settings/widgets/theme_mode_group.dart. OfflineDim + OfflineActionHint and isOnlineProvider: find
  them with `grep -rn "class OfflineDim\|OfflineActionHint\|isOnlineProvider =" lib`.
- The key-backup restore field (copy its decoration and options for the Forgot PIN field):
  lib/features/auth/screens/backup_pin_screen.dart (read only; do not edit it).

FILES TO CREATE:
1. lib/features/app_lock/app_lock_platform.dart — class AppLockPlatform (overridable Provider): wraps
   LocalAuthentication (isDeviceSupported, getAvailableBiometrics, authenticate with spec C2's exact options and
   AndroidAuthMessages) and MethodChannel('kuch_bhi/privacy') methods setHideInRecents(bool) and moveTaskToBack().
2. lib/features/app_lock/app_lock_controller.dart — the A1 JSON entry 'app_lock', hashing (A2), weak-PIN check
   (A3), wrong-try ladder (D1–D4), lifecycle (F2–F5): onHidden(now), onResumed(now), authInProgress,
   locked/covered state, whenUnlocked(), and the pure top-level functions
   shouldLock({required bool enabled, DateTime? awayAt, required int afterSeconds, required DateTime now}) and
   isWeakPin(String). Inject a clock (DateTime Function()) for tests. Initial state comes from main (F1).
3. lib/features/app_lock/widgets/pin_pad.dart — PinPad (spec E1), with semantics I1/I2, shake D5.
4. lib/features/app_lock/lock_overlay.dart — the builder overlay (E2, E3, E4, E6) with internal steps
   unlock -> forgot (G1–G4) -> create -> confirm.
5. lib/features/app_lock/create_pin_screen.dart — B3 (and Change PIN = steps 1–2).
6. lib/features/app_lock/app_lock_settings_screen.dart — B2, B4, B5, C1.
7. Tests: test/app_lock/app_lock_controller_test.dart, lock_screen_test.dart, app_lock_settings_test.dart,
   notification_text_test.dart, presence_gate_test.dart — exactly the cases in the spec's "Test gates".

FILES TO EDIT (only the parts named):
- lib/app.dart: MaterialApp.router gets builder: (context, child) => LockOverlay(child: child!). In
  didChangeAppLifecycleState add: hidden -> controller.onHidden(now); resumed -> controller.onResumed(now) FIRST,
  before the existing code. Every presence.goOnline() (cold-start post-frame callback and resumed) becomes
  `controller.whenUnlocked().then((_) => presence.goOnline())`. Do not touch resyncOnResume, refreshSessionThrottled,
  share-in start, goOffline or the body-cache purge.
- lib/main.dart: before runApp, read 'app_lock' with the existing secureStorage instance; add one override to the
  ProviderScope so the controller starts locked when the entry exists; call setHideInRecents(entry != null).
- lib/core/router/app_router.dart: add AppRoutes.appLock = '/settings/app-lock' and one GoRoute for it. Nothing else.
- lib/features/settings/screens/settings_screen.dart: SectionHeader('Privacy') + one SettingsGroup with the App lock
  row (B1), between the Notifications row and the About group.
- lib/features/chat/screens/chat_screen.dart: the first line of _enter() becomes
  `await ref.read(appLockProvider.notifier).whenUnlocked(); if (!mounted) return;`. Nothing else in the file.
- lib/services/fcm_service.dart: add the pure static notificationText(...) (spec H1) and make
  _showMessageNotification, _showFriendRequestNotification and _showGroupInviteNotification take title/body from
  it (reading hideNames from SecureStorageService().read(key: 'app_lock')). Channel, id, payload, details unchanged.
- android/app/src/main/kotlin/com/chai/kuch_bhi/MainActivity.kt: `FlutterActivity` -> `FlutterFragmentActivity`
  (import io.flutter.embedding.android.FlutterFragmentActivity); add the 'kuch_bhi/privacy' channel in
  configureFlutterEngine next to the clipboard channel: setHideInRecents(bool) -> on API 33+
  setRecentsScreenshotEnabled(!hide), else add/clear WindowManager.LayoutParams.FLAG_SECURE; moveTaskToBack ->
  moveTaskToBack(true). Run both on the UI thread. Do not touch the share-in or clipboard code.
- android/app/src/main/res/values/styles.xml: LaunchTheme parent -> Theme.AppCompat.Light.NoActionBar;
  values-night/styles.xml: LaunchTheme parent -> Theme.AppCompat.NoActionBar. Keep every item inside the styles.
  If the build can't find Theme.AppCompat, add implementation("androidx.appcompat:appcompat:1.7.0") to
  android/app/build.gradle(.kts) dependencies and say so in your report.
- lib/data/local/database/tables/app_settings_table.dart: delete the line `static const String appLockEnabled`.

DO NOT TOUCH (automatic FAIL): lib/services/encryption_service.dart, secure_storage_service.dart, presence_service,
message_repository_impl.dart, the router redirect, backup_pin_screen.dart, share_in_service.dart, any existing test.
No `$e` / e.toString() in visible text. Never log a PIN or a recovery key.

GATES (run all, paste the tail of each in your report):
  flutter analyze            -> 0 errors
  flutter test               -> all green; report "baseline + N new = total" (baseline in the spec's Baseline line)
  flutter build apk --release -> succeeds
  git diff --check           -> clean
  git diff --stat            -> only the files listed above

Report: files changed, test count, anything you could not do and why. Do not commit.
Claude grades the result; do not claim PASS.
```
