---
title: "App lock's forgot-PIN path uses the recovery key, not sign-out, because sign-out keeps this phone's keys"
author: Chaitanya
date: 2026-11-02
branch: main
cost: { minutes: 17, tokens: 273121 }
id: l-72cbff34
scope: repo
status: active
src: agent
touches:
  - docs/design/pages/app-lock.md
  - docs/design/pages/app-lock.html
  - docs/design/pages/multi-select.md
  - docs/design/pages/key-backup.md
---

## Decided
(Proposed in the 12.11 app lock spec, 2026-11-02, awaiting the user's spec PASS.) Forgot PIN = enter the recovery key (or the old 6-digit backup PIN) and check it read-only against the server backup; nothing is written to keys, storage or server. No Sign out button on the lock screen.

## Tried and ruled out
- Sign out as the way past a forgotten PIN: sign-out's session wipe keeps every key pair slot, so signing back in to the same account opens every chat. For a Google account, anyone holding the phone with its Google account signed in could do that and skip the lock.
- Re-entering the account password: the same Google-account hole.
- Calling the existing restore to check the key: it writes the device key, re-publishes the public key and wipes cached conversation keys.

## Watch out
- local_auth on Android needs the activity to be a FragmentActivity and the launch theme to have an AppCompat parent (the README says Android 8 and below crash without it). The app's activity was a plain FlutterActivity with an android:Theme parent, and neither test phone is old enough to show the crash.
- Wrong recovery-key attempts must share the PIN's wait ladder, or the old 6-digit backup PIN can be brute-forced through the reset screen.
- The chat marks itself read on every resume, so anything that hides the app (a lock) must hold that call back until unlock.

In the code:
- docs/design/pages/app-lock.md (decision 8, G, J1)
- secure_storage_service.dart clearSession keeps private_key*/local_public_key* slots
- encryption_service.dart restorePrivateKey writes; new read-only checkBackupSecret proposed
- MainActivity.kt FlutterActivity; res/values*/styles.xml LaunchTheme parent @android:style/Theme.*.NoTitleBar
- chat_screen.dart _enter called on open and on resumed
