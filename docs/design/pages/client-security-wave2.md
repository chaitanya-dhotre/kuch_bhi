# Client security wave 2 (spec, rev 1)

Status: **spec PASS 2026-11-17, all defaults. Built 2026-11-17, device
check pending, uncommitted** (see `client-security-wave2-work-log.md`). No live server or SSH was used. Nothing here changes a server rule or
hook.

Source: `docs/audits/2026-11-16-security-cloudflare-skill.md` §1 and §2, the low
client and Android findings F13–F19, F21 and F22. Format follows security wave 1
(`docs/audits/2026-10-30-security.md`, commit `3d4231d`).

**Out of scope:** F20 (an old superuser password in git history) needs a live
check (audit L9), not client code. L3 (does `fcm_notify` clear a token that moves
to another user) is a server read; F14 below does not need it.

Every finding below was re-read against the code on 2026-11-17. Line numbers are
from that read. `message_repository_impl.dart` has uncommitted edits from another
session, so its lines may move; each item also names the function.

## Summary

| # | Finding (verified) | Fix in one line | Size |
|---|---|---|---|
| F13 | Every bubble with a link makes the recipient's phone GET that URL, with no limits | Stop fetching; the card shows the domain only | delete ~70 lines |
| F14 | Sign-out leaves this phone's push token on the old account | Clear `users.fcm_token` and delete the FCM token before `clearAuth()` | ~15 lines |
| F15 | The PIN wait, and the lock-after-away timer, trust the wall clock | Measure both with Android's elapsed-since-boot clock | ~60 lines + 1 Kotlin method |
| F16 | Any app or web page can push the router to any route through `kuchbhi://` | Turn off Flutter deep linking and drop the dead filter | 2 manifest edits |
| F17 | An unused background-service plugin ships 3 exported components and 2 permissions | Remove the dependency | 1 pubspec line |
| F18 | Release logcat shows group join/leave text and the user's display name | Log the chat id and a status word only | 3 lines |
| F19 | The session JWT is copied into plain SQLite | Keep it in secure storage only, move it out once, delete the copy | ~20 lines |
| F21 | The friend code reaches a server filter unescaped; the QR is checked for length only | Accept only `^[A-Z0-9]{6}$` in the repo and the QR parser | ~8 lines |
| F22 | Cropped avatar PNGs (and the picker's copy) are never deleted | Delete them when the screen that owns them closes | ~10 lines |

---

## F13: link previews fetch any URL, automatically

### What is wrong (verified)

- `lib/infrastructure/services/link_preview_service.dart:22`: `Dio().get(url)`
  with no scheme check, no host check, Dio's default redirects (5), and no body
  size cap. Only a 5 s timeout.
- It runs when the bubble builds: `message_bubble.dart:222` takes the first
  `https?://…` match (`emoji_utils.dart:16`), and `:1046` builds
  `LinkPreviewCard(url:)`, which watches `linkPreviewServiceProvider(url)` at once
  (`link_preview_card.dart:16`).
- So a sender learns each recipient's IP address and when they opened the chat,
  and can make their phones send GETs to `http://192.168.x.x/...` on their own
  network.
- What the fetch buys today is small. The card shows only the page `<title>` and
  the domain. The parsed `description` is never drawn (`link_preview_card.dart`
  reads `meta.title` only). There is no image.

### Smallest fix (default, decision 1 = A)

Delete the fetch. The card keeps its current look in its fallback state: link
icon, the domain as the title, the domain again below, tap opens the link in the
browser. That is exactly what users see today whenever the fetch fails or the
page has no title.

- `link_preview_card.dart`: becomes a `StatelessWidget`; drop the `ref.watch` and
  the `when`; `_buildCard(context)` uses the domain as the title.
- `link_preview_service.dart`: delete the file.
- `chat_provider.dart:101` keeps its own `invalidateOnReconnect` use, so the
  helper in `connectivity_signal.dart:72` stays.

### Every caller touched

| File | Change |
|---|---|
| `lib/features/chat/widgets/link_preview_card.dart` | stateless, no provider |
| `lib/infrastructure/services/link_preview_service.dart` | deleted |
| `lib/features/chat/widgets/message_bubble.dart:1046` | none (same constructor) |
| `test/chat/media_link_widgets_test.dart:29-75` | drop the two provider overrides; keep both "domain fallback" checks as one test |
| `test/chat/chat_calm_test.dart:34` | drop the `linkPreviewServiceProvider` override |
| `test/media/media_retry_test.dart:443-468` | delete the "failed fetch is read again after reconnect" test |

### Test

- Widget: `LinkPreviewCard(url: 'https://example.com/a')` shows `example.com`
  twice, the link icon, the `Open link example.com` label, with **no provider
  overrides** (proves nothing is fetched; a fetch would need Dio and fail the
  test's no-network setup).
- Grep gate in `test/grep_gates_test.dart`: no file under `lib/` contains
  `Dio().get(` with a variable URL outside `lib/services/` and
  `lib/infrastructure/media/` (the media paths fetch only our server). Simplest
  form: `link_preview_service.dart` does not exist and `link_preview_card.dart`
  has no `Dio`.

### Decision 1: what happens to link previews

- **A. No fetch, domain-only card (default).** Closes the IP leak and the LAN
  GETs completely. Loses the page title on the card.
- B. Filtered auto-fetch: https only; resolve the host and refuse loopback,
  private (10/8, 172.16/12, 192.168/16, 100.64/10, fc00::/7), and link-local
  ranges; `followRedirects: false`; stop reading after 256 KB. Keeps titles.
  Still tells the link's owner each recipient's IP and read time, which is the
  main point of F13.
- C. Tap-to-load: the card shows the domain and a "Show title" button that
  fetches with B's filters. Weak trade: the tap that would load the title is the
  same tap that opens the page anyway, and it adds a button to every link bubble.
- D. Sender-side preview (what Signal does): the sender's phone fetches the
  title while typing and sends it inside the encrypted message. Recipients never
  fetch. Needs a message format change and old-app handling: too big for a low
  wave. Park as backlog if A feels too plain.

---

## F14: sign-out keeps the push channel on this phone

### What is wrong (verified)

- `AuthRepositoryImpl.signOut` (`auth_repository_impl.dart:375-396`) cancels the
  token listener, calls `pbClient.clearAuth()`, wipes secure storage and every
  Drift table. It never clears `users.fcm_token` on the server and never calls
  `FirebaseMessaging.instance.deleteToken()`.
- So the server keeps sending the old account's pushes to this phone. When
  another person signs in here, `fcm_service.dart:608-640` shows the old
  account's `sender_name`, `from_user_name`, `inviter_name` and group names
  (names are hidden only while an app lock is set, `_hideNames`).
- The Drift wipe also removes `last_fcm_token`, so the next account registers the
  same token on its own row: two rows then point at one phone.

### Smallest fix

In `signOut`, before `pbClient.clearAuth()` (the update needs the session):

1. Read `currentUserId` from Drift. If present, `users.update(id, {'fcm_token': ''})`
   with `.timeout(kAuthNetworkTimeout)` (8 s), in a `try/catch` that only logs.
2. `FirebaseMessaging.instance.deleteToken()` with the same timeout, in its own
   `try/catch`. This kills the token at Google, so even a stale server row stops
   reaching this phone. The next sign-in's `_saveSession` calls `getToken()` and
   gets a fresh token (`last_fcm_token` is wiped, so it always registers).

Both are best effort: sign-out must never fail or hang because the network is
down.

### Every caller touched

| Caller | Effect |
|---|---|
| `AuthNotifier.signOut` (`auth_provider.dart:212`) ← profile screen sign-out (`profile_screen.dart:110`) | gains up to 2 × 8 s worst case offline (decision 2) |
| `AuthRepositoryImpl.deleteAccount` (`:401-411`) → `signOut` | the `users.update` 404s (the row is gone) and is swallowed; `deleteToken` still runs |
| `test/offline/keyless_sealed_outbox_test.dart:494, 527`, `encryption_sync_offline_test.dart` | real `signOut` on a mock PB client: the extra request must not break them; `FirebaseMessaging.instance` throws with no Firebase app and is caught |
| `fcm_service.dart:111` `onTokenRefresh` listener | reads `currentUserId` from Drift, which is wiped, so a refresh during sign-out writes nothing. No change |

### Test

`test/auth/sign_out_push_test.dart` with `PocketBaseClient.forTest` and a
`MockClient`: sign in a fake session, call `signOut()`, assert one
`PATCH /api/collections/users/records/<id>` with body `{"fcm_token":""}` and an
`Authorization` header (so it ran before `clearAuth`). Second case: the mock
returns a socket error, `signOut()` still completes and the tables are empty.

### Decision 2: how long sign-out may wait offline

- **A. Each call capped at 8 s, run in parallel, so 8 s worst case (default).**
  Only on a dead network; online it is one round trip.
- B. Fire and forget (no wait). Sign-out is instant, but `clearAuth()` may run
  before the request is sent, so the update often fails.

---

## F15: the app-lock clock can be moved

### What is wrong (verified)

**PIN wait.** `AppLockController.isWaiting` (`app_lock_controller.dart:364-371`)
compares the stored wall-clock `waitUntil` with `DateTime.now()`:

- clock forward past `waitUntil` → `remaining <= 0` → not waiting;
- clock back far enough → `remaining > wait` → also not waiting (the guard meant
  for a bad stored value lets the guess through).

Either way, someone with the phone in hand gets free PIN guesses between the
30 s–15 min waits (`_waitSeconds`, `:520-526`).

**Found while reading, same root cause: the lock-after-away timer.** `app.dart:90`
passes `DateTime.now()` to `onHidden` and `onResumed`, and `shouldLock`
(`:18-27`) locks only when `now - awayAt >= after`. Setting the phone's clock
back by the time away, then opening the app, skips the lock entirely. This is
worse than the PIN wait (no PIN needed at all) and is the same fix, so it is in
this item (decision 3).

**Why not Dart's `Stopwatch`:** on Android it uses `CLOCK_MONOTONIC`, which stops
while the phone sleeps. A phone left with the screen off for 10 minutes would
count only the seconds it was awake, and "lock after 5 min" would not lock.
Android's `SystemClock.elapsedRealtime()` counts sleep and cannot be set by the
user. It restarts at boot.

### Smallest fix

1. Kotlin, `MainActivity.kt`, the existing `kuch_bhi/privacy` channel (`:73`):
   `"elapsedRealtime" -> result.success(SystemClock.elapsedRealtime())`.
2. `AppLockPlatform` (`app_lock_platform.dart`): `Future<int?> elapsedRealtime()`
   returning null on `MissingPluginException`/`PlatformException`.
3. PIN wait, stored in boot time:
   - `AppLockConfig` gets `waitStart` (elapsed ms when the current wait began);
     `encode`/`decode` carry it (`:92-93`, `:132-152`).
   - `registerWrongAttempt` sets `waitStart` when a wait begins (fails ≥ 5).
   - `unlockWithPin` (already async) reads `elapsedRealtime()` first. Waiting =
     `now - waitStart < _waitSeconds(fails) * 1000`. If `now < waitStart` (the
     phone rebooted), the wait starts again from `now` and is saved (decision 4).
     It then rewrites `waitUntil = DateTime.now() + remaining` so the existing
     countdown text (`messageFor`, `waitRemaining`) stays right without becoming
     async.
   - `isWaiting`: replace `remaining <= wait` with clamping (as
     `waitRemaining` already does), so a clock moved back shows a full wait
     instead of none. It stays the sync display check; the gate is step 3's.
   - A config from before this change (no `waitStart`, wait still running) is
     treated as a wait that starts now.
4. Away timer: `onHidden` also starts `_awayElapsed = _platform.elapsedRealtime()`
   (a `Future<int?>`, so `onHidden` stays sync); `onResumed` awaits it and a
   fresh read, and locks when the elapsed difference ≥ `after`. If either read is
   null or the difference is negative (reboot), it locks. The wall-clock check
   stays as a second trigger: lock if **either** says so. The biometric path
   (`authenticateWithBiometrics` finally block, `:345-352`) replays `onHidden`
   with the stored time; it captures `_awayElapsed` at the same moment as
   `_hiddenDuringAuth`.

`shouldLock` keeps its signature and test table; it gains an optional
`int? elapsedAway` argument.

### Every caller touched

| File | Change |
|---|---|
| `android/app/src/main/kotlin/com/chai/kuch_bhi/MainActivity.kt:73-95` | one `when` branch |
| `lib/features/app_lock/app_lock_platform.dart` | one method |
| `lib/features/app_lock/app_lock_controller.dart` | `AppLockConfig.waitStart`, `isWaiting`, `unlockWithPin`, `registerWrongAttempt`, `onHidden`, `onResumed`, `shouldLock`, biometric finally |
| `lib/app.dart:88-109` | none (still passes wall `now`; the controller reads boot time itself) |
| `test/app_lock/app_lock_controller_test.dart`, `lock_screen_test.dart`, `presence_gate_test.dart` | their fake `AppLockPlatform` gains `elapsedRealtime` (a settable int) |

### Test

In `app_lock_controller_test.dart`, with a fake platform whose elapsed clock the
test sets:

- 5 wrong PINs → wait 30 s. Wall clock +1 h, elapsed +5 s → the correct PIN is
  refused, message says about 0:25.
- Wall clock −1 h, elapsed +5 s → still refused (today this passes the guess).
- Elapsed +31 s → the correct PIN unlocks.
- Elapsed goes below `waitStart` (reboot) → refused, wait restarts at 30 s.
- Away: lock after 60 s; `onHidden`, wall clock −10 min, elapsed +61 s,
  `onResumed` → locked. Elapsed +30 s and wall +30 s → not locked.
- Old config JSON with `waitUntil` and no `waitStart` decodes and waits.

### Decision 3: include the lock-after-away timer

- **A. Yes, same change (default).** Same clock, same channel, and it is the
  bigger hole.
- B. PIN wait only, as the audit wrote it; the away timer becomes its own item.

### Decision 4: after a reboot during a PIN wait

- **A. The wait starts again, full length (default).** Worst case one extra
  15 min wait for someone who rebooted during the longest wait. A reboot plus a
  clock change can never shorten it.
- B. Trust the wall clock after a reboot. Kinder, but reboot + clock forward
  skips the wait again.

---

## F16: `kuchbhi://` VIEW intents reach the router

### What is wrong (verified)

- `AndroidManifest.xml:38-44`: a `VIEW` + `BROWSABLE` filter for scheme
  `kuchbhi` on `MainActivity`.
- No Dart code handles it: the only `kuchbhi://` uses are the profile QR payload
  (`profile_screen.dart:208`) and the in-app scanner's prefix strip
  (`add_friend_screen.dart:371`).
- No `flutter_deeplinking_enabled` meta-data. On Flutter 3.47.7 deep linking is
  on by default, so the intent's path becomes the router's location. Any app or
  web page can open `kuchbhi://x/<route>` and move the user to that route (after
  auth and the lock, which still gate it).
- The scheme does not work for its stated purpose: a phone camera scanning the
  profile QR would send `kuchbhi://add/ABC123`, which Flutter turns into
  location `/ABC123`, which is not a route.

### Smallest fix

In `android/app/src/main/AndroidManifest.xml`:

1. Delete the `kuchbhi` intent-filter (`:38-44`).
2. Add inside `<activity .MainActivity>`:
   `<meta-data android:name="flutter_deeplinking_enabled" android:value="false" />`.

Keep the QR payload `kuchbhi://add/<code>` unchanged: the in-app scanner
(`_parseCode`) still reads it, and existing printed or saved QR codes keep
working there.

Share-in (`SEND`/`SEND_MULTIPLE`) is untouched: it uses its own channel
(`MainActivity.kt:97`), not Flutter deep linking.

### Every caller touched

Manifest only. Nothing in `lib/` reads the scheme from an intent.

### Test

Manifest grep gate in `test/grep_gates_test.dart`: the main manifest contains
`flutter_deeplinking_enabled` with value `false` and no
`android:scheme="kuchbhi"`. Behaviour is a device check (D5).

### Decision 5: the dead scheme

- **A. Remove it (default).** It never worked from outside the app.
- B. Keep the filter and write a real handler that accepts only
  `kuchbhi://add/<6 chars>` and opens Add a friend. That is a new feature
  (camera-app scan to add), not a fix; backlog it if wanted.

---

## F17: unused `flutter_background_service`

### What is wrong (verified)

- `pubspec.yaml:47` `flutter_background_service: ^5.0.10`. Nothing in `lib/`,
  `test/` or `android/` imports it.
- The release merged manifest (`build/.../release/.../AndroidManifest.xml`, built
  2026-11-16) has three of its components, all `exported="true"` with no
  permission: `BackgroundService` (`stopWithTask="false"`), `WatchdogReceiver`,
  and **`BootReceiver`** (listens to `BOOT_COMPLETED`, `QUICKBOOT_POWERON`,
  `MY_PACKAGE_REPLACED`; the audit named only the first two).
- The merge report shows `FOREGROUND_SERVICE` and `RECEIVE_BOOT_COMPLETED` come
  only from this plugin. `WAKE_LOCK` also comes from `firebase_messaging`, so it
  stays.

### Smallest fix

Remove the line from `pubspec.yaml`, run `flutter pub get` (updates
`pubspec.lock`, drops the 4 `flutter_background_service*` entries).

### Every caller touched

`pubspec.yaml`, `pubspec.lock`. No code.

### Test

None in Dart (nothing used it). Build check: after `flutter build apk --release`
the merged manifest has no `id.flutter.flutter_background_service` and no
`RECEIVE_BOOT_COMPLETED` or `FOREGROUND_SERVICE`. Device check D6.

No decision.

---

## F18: names and group text in release logs

### What is wrong (verified)

`debugPrint` prints in release builds (there is no release override in
`lib/`). Three lines print user content:

| Where | Prints |
|---|---|
| `message_repository_impl.dart:5929`, `_emitSystemMessage` (local emit) | `[SysMsg] local emit → "<body>" in <convId>`; body = "Asha joined", "Ravi was removed by Asha", group renames |
| `message_repository_impl.dart:5994`, `_emitLocalSystemMessage` | same, for local-only rows ("You were removed from this group" etc.) |
| `auth_repository_impl.dart:349`, `_backgroundRefresh` | `[Auth] Background refresh done: <displayName>` |

A sweep of every `debugPrint` in `lib/` for names, bodies, previews, captions,
file names and titles found no others (`action.name` and `view.name` are enum
names).

### Smallest fix

- `:5929` → `debugPrint('[SysMsg] local emit in $convId')`.
- `:5994` → `debugPrint('[SysMsg] local-only emit in $convId')`.
- `:349` → `debugPrint('[Auth] Background refresh done: ${user.id}')`.

Exception text (`$e`) is left as is: it is needed for device debugging, and a
`ClientException` carries the server's error, not message plaintext.

### Every caller touched

Those three lines. `message_repository_impl.dart` has another session's
uncommitted edits: the builder edits only these two lines and checks
`git diff` shows nothing else of theirs changed.

### Test

Grep gate in `test/grep_gates_test.dart`: no `debugPrint(` line under `lib/`
interpolates `$body`, `displayName`, `preview`, `plaintext` or `caption`. This
also guards future lines.

### Decision 6: per-line fix or silence release logs

- **A. Fix the three lines plus the grep gate (default).** Release logcat stays
  useful for device runs (the history-sync timing lines, FCM, app lock).
- B. `debugPrint = (_, {wrapWidth}) {}` in release in `main.dart`. One line,
  catches everything, but every device check on a release build loses its logs.

---

## F19: the session JWT is copied into plain SQLite

### What is wrong (verified)

- `_saveSession` (`auth_repository_impl.dart:439-456`) writes the token to
  secure storage, then again to Drift `app_settings` key `auth_token` (`:454`).
- Readers of the Drift copy, each as a fallback after secure storage:
  - `getCurrentUser` (`:289-299`), when PocketBase has no token;
  - `fcm_service.dart:119` (token refresh), `:161` (register retry), `:484`
    (background cache message), `:543` (mark delivered).
- Drift is plain SQLite, readable from any copy of the app's data. `allowBackup`
  is off (wave 1), so the reach is a rooted phone or a forensic copy.
- The copy was added on 2026-05-09 (`a4b8134`) as a "reliable fallback for
  Samsung devices where EncryptedSharedPreferences fails across restarts". Since
  then the private key and every group key live only in the same secure storage,
  so a phone where secure storage really failed would also lose its keys. The
  fallback no longer saves a working session on its own.

### Smallest fix

1. `_saveSession`: drop the Drift write of `authToken` (`:454`). Keep the
   `currentUserId` write.
2. `getCurrentUser` (`:289-299`): one-time move. If PocketBase has no token, read
   the Drift copy; if present, save it to secure storage, load it into the auth
   store, and delete the Drift row (`settingsDao.deleteSetting`). In every other
   case also delete the Drift row if it exists. After one start on the new
   build, no phone has the copy.
3. `fcm_service.dart:119, 161, 484, 543`: delete the `token ??= …settingsDao…`
   lines; secure storage only.

No Drift schema change (a row delete, not a column).

### Every caller touched

`auth_repository_impl.dart` (`_saveSession`, `getCurrentUser`),
`fcm_service.dart` (4 lines). `AppSettingsKeys.authToken` stays (the move reads
it). Tests: `test/auth/auth_timeout_test.dart` and the two offline tests build a
real `AuthRepositoryImpl`; any that seed the Drift `auth_token` must seed secure
storage instead.

### Test

- `getCurrentUser` with the token only in Drift → token now in secure storage,
  Drift row gone, user returned.
- `_saveSession` → Drift has no `auth_token` row.
- Grep gate: `AppSettingsKeys.authToken` appears only in `getCurrentUser`.

### Pre-check before building (M52)

The fallback was written for a Samsung. Before the build, on the M52 with the
current release build: cold start 3 times and grep logcat for
`Restoring token from Drift`. If it **ever** shows on a normal cold start,
secure storage is losing the token there: stop and keep the copy (decision 7 B).

### Decision 7

- **A. Drop the copy, with the one-time move and the M52 pre-check (default).**
- B. Keep the copy. F19 stays open as accepted risk.

---

## F21: friend-code filter and QR charset

### What is wrong (verified)

- `FriendRepositoryImpl.findUserByCode` (`friend_repository_impl.dart:39-49`)
  builds `'friend_code="${code.toUpperCase()}"'` by interpolation.
- Its only caller, `searchByCode` (`friend_request_provider.dart:557-584`),
  checks `length == 6` only. Its callers: the code field
  (`add_friend_screen.dart:133, 189`) and the QR tab (`:100`).
- The QR parser `_parseCode` (`add_friend_screen.dart:369-375`) accepts any 6
  characters after the prefix.
- Codes are made from `A-Z0-9` only (`auth_repository_impl.dart:694-698`).
- So a 6-character payload like `"||1=1` reaches the filter. Today it can only
  make a 400, but the shape is an injection.

### Smallest fix

1. `lib/domain/repositories/friend_repository.dart`: one top-level
   `bool isFriendCode(String s) => RegExp(r'^[A-Z0-9]{6}$').hasMatch(s);`
2. `findUserByCode`: upper-case, then `if (!isFriendCode(c)) return null;`
   (shows "No user found."). Also build the filter with the SDK's escaping:
   `_pb.filter('friend_code = {:c}', {'c': c})` (pocketbase 0.21.0 has it).
3. `_parseCode`: `final c = code.toUpperCase(); if (isFriendCode(c)) widget.onCodeFound(c);`

`_generateUniqueFriendCode` (`auth_repository_impl.dart:705`) interpolates a code
it made itself from the safe alphabet; no change.

### Every caller touched

`friend_repository.dart`, `friend_repository_impl.dart`,
`add_friend_screen.dart` (`_parseCode`). The two fakes
(`test/home/add_friend_openers_test.dart:28`, `add_friend_sheet_test.dart:48`)
implement the interface method, which keeps its signature.

### Test

- `isFriendCode`: `ABC123` yes; `abc123` no (the caller upper-cases); `"||1=1`,
  `ABC12`, `ABC1234`, `ÄBC123` no.
- `findUserByCode('"||1=1')` on a mock client returns null and sends no request.
- QR tab: a scan of `kuchbhi://add/"||1=1` does not call `onCodeFound`.

No decision.

---

## F22: avatar crop files left in temp

### What is wrong (verified)

- `_CropPhotoScreenState._use` (`crop_photo_screen.dart:153-158`) writes a
  512 px PNG of the cropped face to the temp dir
  (`avatar_crop_<ms>.png`) and pops it. Nothing deletes it.
- Also left: the picker's own copy. `pickCroppedPhoto` (`:20-42`) passes
  `picked.path` (an `image_picker` copy, resized to 1024) to the crop screen, and
  never deletes it.
- The cropped file is owned by `_pickedImage` in two screens:
  `edit_profile_screen.dart:39` and `google_onboarding_screen.dart:50`. It is
  left on save, on cancel, and when the user picks a second photo (the first is
  dropped).
- The upload re-encodes to JPEG without EXIF (`auth_repository_impl.dart:511`),
  so the leftovers are the only copies with no re-encode.

### Smallest fix

1. `pickCroppedPhoto`: after the crop route returns (crop or cancel),
   `File(picked.path).delete()` in a `try/catch` (the crop screen has already
   decoded it).
2. Each owner screen (`edit_profile_screen.dart`, `google_onboarding_screen.dart`):
   - when a new crop replaces `_pickedImage`, delete the old file;
   - in `dispose()`, delete `_pickedImage` if set (fire and forget, `try/catch`).
     The save has finished or been abandoned by then, and `dispose` uses no
     `ref`.

### Every caller touched

`crop_photo_screen.dart` (`pickCroppedPhoto`), `edit_profile_screen.dart`
(`_pickImage`, `dispose`), `google_onboarding_screen.dart` (`_pickAvatar`,
`dispose`). `updateProfile` reads the file while the screen is still open, so the
delete in `dispose` comes after it.

### Test

Widget test with a temp dir: open Edit profile with a fake crop that returns a
real temp file, pick twice → first file gone; leave the screen → second file
gone. Same for onboarding in `google_onboarding_screen_test.dart`.

### Decision 8: sweep old leftovers

- **A. No sweep (default).** Android's cache dir is app-private and the OS clears
  it under storage pressure; new crops are cleaned from now on.
- B. On sign-out, also delete `avatar_crop_*.png` in the temp dir (3 lines next
  to `wipeMediaCache`).

---

## Build notes

- One build session, one commit. Order: F17 and F16 (manifest and pubspec, no
  Dart), F18, F21, F22, F13, F14, F19, F15 last (the largest).
- Baseline: run the full suite first and record the count; the end count = the
  baseline − the deleted reconnect test + the new tests.
- `message_repository_impl.dart` has another session's uncommitted edits. Touch
  only the two `[SysMsg]` lines; do not commit that file's other changes. If
  those edits are still uncommitted at build time, ask before committing.
- No server change. No live read.

## Device check list

M52 = Samsung, Redmi = second phone. Release build unless noted.

| # | Item | How | Pass |
|---|---|---|---|
| D0 | F19 pre-check (before the build) | M52, current build, cold start ×3, `adb logcat \| grep "Restoring token from Drift"` | no line |
| D1 | F13 link card | Send `https://example.com` and an `http://192.168.1.1` link from the Redmi; open the chat on the M52 | Both cards show the domain, no title; tapping opens the browser; router log (if available) shows no hit from the M52 |
| D2 | F14 sign-out | M52: sign out of account A. Sign in as account B on the M52. From the Redmi, message account A | No notification on the M52 |
| D3 | F14 offline sign-out | M52 in airplane mode → sign out | Back at sign-in within about 8 s, no error |
| D4 | F15 PIN wait | App lock on. 5 wrong PINs (30 s wait). Settings → date and time → move the clock 1 hour forward, back to the app, correct PIN | Still refused with a countdown; works after the real 30 s. Repeat with the clock 1 hour back: same |
| D5 | F15 reboot | Start a wait, reboot the phone, open the app, correct PIN at once | Refused, wait shows the full length again |
| D6 | F15 away timer | Lock after 1 min. Open the app, go home, set the clock back 5 min, wait 70 s, open the app | Locked |
| D7 | F15 away timer, no false lock | Lock after 5 min. Leave for 1 min with the screen off, open | Not locked |
| D8 | F16 | `adb shell am start -a android.intent.action.VIEW -d "kuchbhi://x/settings"` | "unable to resolve Intent" or the app opens on its normal screen, never Settings |
| D9 | F16 QR | Redmi: Add a friend → scan the M52's profile QR | Finds the user (in-app scan still works) |
| D10 | F17 | `adb shell dumpsys package com.chai.kuch_bhi \| grep -iE "background_service\|BOOT_COMPLETED\|FOREGROUND_SERVICE"` | no output |
| D11 | F18 | Create a group, add and remove a member, rename it; `adb logcat \| grep -E "SysMsg\|Background refresh"` | chat ids and user ids only, no names |
| D12 | F19 | Debug build: sign in, then `adb shell run-as com.chai.kuch_bhi ls databases` and query `app_settings` for `auth_token` | no row. Cold start ×3 stays signed in |
| D13 | F19 upgrade | Install the new build over the old one without signing out | still signed in, no K1 restore screen |
| D14 | F21 | Add a friend → type `"||1=1` (6 chars) → Search | "No user found." |
| D15 | F22 | Edit profile → pick a photo → crop → pick another → crop → Save. Debug build: `adb shell run-as com.chai.kuch_bhi ls cache` | no `avatar_crop_*.png`, no picker `image_picker*` file |
| D16 | Regression | Sign-in, share-in from Gallery, push notifications on both phones, app lock unlock with fingerprint | all work as before |

## Decisions (defaults in bold)

1. F13 link previews: **A no fetch, domain-only card** / B filtered auto-fetch /
   C tap-to-load / D sender-side (backlog).
2. F14 offline wait: **A capped at 8 s, parallel** / B fire and forget.
3. F15 away timer in scope: **A yes** / B PIN wait only.
4. F15 reboot during a wait: **A full wait again** / B trust the wall clock.
5. F16 scheme: **A remove** / B real `add/<code>` handler (new feature).
6. F18: **A three lines + grep gate** / B silence release logs.
7. F19: **A drop the copy, one-time move, M52 pre-check** / B keep it.
8. F22 old leftovers: **A no sweep** / B sweep on sign-out.
