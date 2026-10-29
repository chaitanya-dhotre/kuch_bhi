# K3: a network blip at sign-in uploaded a new public key over the backed-up one (work log)

Date: 2026-10-29.
Scope: finding K3 in the Page 7 spec (`auth.md` section K). This is key code, done by Claude only.
Built on the K1 fix (`_readKeyPair`, read-only derivation), which is still uncommitted in worktree
`peaceful-roentgen-8e43f5`. Its diff is applied here unchanged, so this tree holds K1 + K3.

## Status

| Step | Result |
|---|---|
| RED, existing account | On HEAD+K1, a blip on key init's backup read made a key and sent `PATCH users/u_test {public_key: …}` |
| RED, new account | With only key init switched (the one-line version tried and reverted under K1), setup threw `No local private key to backup` |
| Fix | Three places together, below |
| Run 2 fix | Register / Google sign-up pass `newAccount`: for them an UNKNOWN backup check means "none", so key init makes the key on a blip. A backup the server reports still wins (Google hook unread). RED: no key; GREEN. Fresh review: nothing blocking |
| Run 3 fix | A device with a key routed while the server was unreachable re-checks on each offline→online change, and re-routes only if setup is now due (a new account registered offline). RED: no re-route; GREEN. Fresh review: nothing blocking |
| Gates | `flutter test` **430/430** (423 with K1 + 7 K3 tests; P6.3 rewritten) · `flutter analyze` 0 errors · `git diff --check` clean · `trail check` no conflicts |
| Fresh-context review | Subagent, 2026-10-29: nothing blocking. Findings below |
| Device check | **PASS** 2026-10-29, user, M52, 22:20 build (run 3 fix) |
| Commit | With K1, one commit on `claude/peaceful-nightingale-f2f875` |

## The fix

1. **Key init** (`auth_repository_impl.dart` `_initEncryptionKeys`): uses `tryHasPocketBaseBackup`
   and generates only on a confirmed `false`. `true` and unknown both skip.
2. **Router, no local key** (`encryption_sync_provider.dart`): re-checks up to 5 times, 2s apart
   (`backupCheckRetryDelay`), while the splash shows. Confirmed backup → Restore, confirmed none →
   setup. Never answered → **Restore**: it writes nothing unless the user picks Start Fresh, which
   is also how a keyless new account gets out if the server stays unreachable.
3. **Backup PIN setup without Start Fresh** (`backup_pin_screen.dart` → new
   `EncryptionService.backupOrCreateKey`): backs up the device key. With no key it creates one only
   on a confirmed "no backup". Otherwise it writes nothing, and the screen's existing invalidate +
   `go(home)` sends the router back through the check.
4. The catch-all `hasPocketBaseBackup` is deleted; nothing calls it any more.

## Review findings and what was done

K3 makes Restore the screen an offline no-key route lands on, which exposed three things:

1. **Fixed: offline Restore said "Incorrect PIN"**, pushing users to Start Fresh. `restorePrivateKey`
   now lets a failed record read throw, so the screen shows its error text (still the raw `$e`,
   which is K5).
2. **Fixed: Start Fresh offline left an unpublished key.** `generateAndBackupNewKey` saved the key
   locally before uploading it. On the next cold start that key routed to keyOk while the server
   held the old public key. It now uploads first, so offline it fails with nothing written.
3. **Fixed: setup bounced silently when its own check failed.** `backupOrCreateKey` now throws
   "Can't reach the server" on unknown, so the user stays on setup with an error.
   The third K3 test covers 1-3 (written after the fix, not shown RED).

Not changed (notes):

- **Skip on setup loops for a keyless new account.** The route passes `isOptionalSetup: !hasLocal`,
  so Skip only shows when there is NO key, and the skip flag is read only when there IS one. Not a
  dead end (setting a PIN works). Pre-existing, more reachable now. Product call: hide Skip when
  keyless.
- **Two generators can race.** Google onboarding invalidates `authProvider`, which re-runs key init
  through `getCurrentUser`. A slow confirmed "no backup" there while setup generates could leave
  local key, public key and backup mismatched. Tiny window, new with K3.
- **Seen in run 1's log, pre-existing:** a resume refresh re-runs key init through `_saveSession`.
  When that drops a stale key that doesn't match the server's public key, the route already said
  keyOk and is not re-run, so the user stays on Home with no key until the next cold start (which
  then routes to Restore). Only an install that kept old data can hit this, not a fresh install.
- A new account that hit the 5-miss fallback cannot succeed at Restore. Its exits are Start Fresh
  (whose wording about losing history doesn't apply to it) or a restart.

## Device test (user)

**Run 1, 2026-10-29 21:40-21:45: INVALID, wrong build.** The APK came from the main checkout
(built 21:20:05; main has neither K1 nor K3) and went on with `install -r`, so app data survived.
Logcat shows the old catch-all (`hasPocketBaseBackup check failed:` then `[Keys] New
device/reinstall detected — uploading fresh public key.`), a message this tree no longer has. The
upload itself failed offline, so the server key was not overwritten. The failures seen (no
Restore/setup page, Home with a stale key) are the K1/K3 bugs on the old code.

**Run 2, 2026-10-29 21:50-21:55, right build.** Existing account: Restore, PIN restored history
(PASS). New account (register, airplane mode right after Create account): key init skipped on the
unknown check, the route missed 5 times (21:55:21-29), then **Restore**. As designed, but wrong: a
just-registered account cannot have a backup. Fixed by passing `newAccount` from register and
Google sign-up, so key init makes the key without asking. Offline, the account now lands on Home
with a key. Its public key and the PIN setup prompt follow on the next online start or resume.

Before every run: build from THIS worktree and do a real fresh install.

```bash
cd /home/chaitanyadhotre/kuch_bhi/.claude/worktrees/peaceful-nightingale-f2f875 && flutter build apk --debug
adb -s RFCRA047WSJ uninstall com.chai.kuch_bhi
adb -s RFCRA047WSJ install build/app/outputs/flutter-apk/app-debug.apk
```

Check it's the right build: `adb -s RFCRA047WSJ logcat -d | grep -c "hasPocketBaseBackup check
failed:"` must stay 0 (only the `(unknown)` variant exists now).

1. **Existing account, fresh install, flaky network**: sign-in itself needs the network, so sign
   in with it on and switch airplane mode on right after tapping Sign in. Expected: the splash stays up (spinner after 1s) for up to ~8s, then Backup
   PIN **Restore** (or Restore straight away once the network is back). Logcat: no
   `[Keys] New device/reinstall detected — uploading fresh public key.` line. Turn the network on,
   enter the PIN, history becomes readable.
2. **New account (register), normal network**: lands on Backup PIN **setup**, setup succeeds, Home.
3. **New account, blip**: same airplane trick right after Create account. Splash waits, then setup
   (network back) or Restore (still offline). From setup, entering a PIN creates the key. From
   Restore: Forgot PIN → Start Fresh with the network on → Home, sending works.
4. K1's device checks still hold (Restore appears on a fresh-install sign-in).

## Run 2 review notes (not changed)

- After an offline sign-up, the public key reaches the server only on the next cold start, or on a
  resume at least 30 min later (`refreshSessionThrottled` → `_saveSession` → key init). Until then
  peers cannot encrypt to the account. It's a delay, not a loss: nothing drops the key meanwhile.
  PIN setup with a local key backs up only the private key, never `public_key`.
- The test drives key init directly. That `register()` and `registerWithGoogle()` pass the flag is
  checked by reading the code (two call sites).

## Run 3, 2026-10-29 ~22:10 (22:05 build)

New account registered offline: Home with a key (no Restore any more), but PIN setup appeared
only after reopening the app. Fixed (22:20 build): while the server is unreachable, the route
listens for the network coming back and checks again, up to 5 tries 2s apart. It re-routes
(splash → setup) only when the server confirms no backup and setup is due. A set-up user is never
bounced out of a chat, and the listener stops after the first definite answer.

Review notes (not changed):
- It triggers on the OS offline→online change only. If the phone has network but the server is
  down, or if the network returns before the listener starts, setup waits for the next app open.
- If the re-run's own check fails, the user briefly goes splash → Home.
