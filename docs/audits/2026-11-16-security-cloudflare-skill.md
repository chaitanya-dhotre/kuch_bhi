# Security audit, 2026-11-16 (Cloudflare security-audit method)

**Scope:** the Flutter Android client (`lib/`, `android/`), the server copies in `docs/server/`,
the live API rules recorded in `KUCH_BHI_PROJECT_BIBLE.md` §7 (read live on 2026-11-15), and the
hook behaviour described in `docs/design/pages/*.md`. Git history: all 173 commits on all refs.

**Method:** the workflow in `cloudflare/security-audit-skill` (`skills/security-audit/SKILL.md`),
adapted. It was read as reference only: nothing was installed, and none of its scripts were run.
- **Phase 1, recon:** the trust boundaries and seven principals in the table below.
- **Phase 2, hunting:** six area sweeps run as Sonnet subagents: client crypto, local data, network
  and auth, server rules, Android, secrets and supply chain.
- **Phase 3, validation:** done by me. I re-opened every cited line. A finding I could not tie to a
  file:line was dropped.
- **Skipped:** the skill's JSON ledger, the validators and the sandboxed local execution. No OS
  sandbox was available, so no target code ran. This is source-only.

The skill's evidence rules are kept:
- Only confirmed findings get a severity.
- Anything only the live server can settle is listed separately as **needs live check**, with no
  severity.
- No live server, SSH, Firebase or URL was contacted.
- Secret values are never quoted.

**Prior run:** `docs/audits/2026-10-30-security.md`, plus `server-rules.md` (N1–N9) and
`key-backup.md`. Their items are re-checked in §4.

Severity anchors (from the skill):
- **high:** fully defeats an explicit control with real consequences, such as reading another
  chat's data or breaking the E2E promise.
- **medium:** a real boundary violation with limited reach or uncommon preconditions.
- **low:** small gain or large effort.

## Status (updated 2026-11-18)

| Finding | Status | Commit |
|---|---|---|
| F1, F2, L1 | fixed live, device PASS | `be0e2f1` (spec `membership-rules.md`) |
| F3 | fixed, device PASS | `b0193d2` (`key-change-warning.md`) |
| F4, F7–F11 (+ polls, scheduled_messages, removed-creator re-entry) | fixed live, device PASS | `17801e4` (`server-rules-wave2.md`) |
| F5, F6, L6 | fixed on the phone and the server, device PASS | `168844b`, `832d415` (`delete-everyone-leftovers.md`) |
| F13–F19, F21, F22 | fixed, device PASS | `6017de5` (`client-security-wave2.md`) |
| New: leaving a group never re-keyed it | fixed, device PASS | `f9a0929`, merged in `d9ab6c2` (`leave-rotation.md`) |
| New: former members lose history after a reinstall | fixed live, device PASS | `247ef20` |
| **F12** (a failed removal rotation is never retried) | **open**, no spec | — |
| F20 | closed: the superuser row changed 2026-10-01 (after the 2026-07-21 rotation) and the user confirmed the old password fails (L9, 2026-11-18). Purge the history only if the repo is ever shared | — |
| L3 (partly), L4, L5, L7, L8, L9, L10 | checked live 2026-11-18, fine (§3 results) | — |
| F23, F24, F25 (from L2, L7, L3) | fixed live 2026-11-18 (dry run 15/15 on a copy; backups `.20261118-google-link-pre`), device PASS 2026-11-18 | (`google-link-and-push.md`) |

Nothing is pushed.

## Principals used

| # | Principal |
|---|---|
| P1 | Any signed-in user. Sign-up is open (`users` createRule `""`, bible:666) |
| P2 | A friend, DM partner or group member, including one who was removed or left |
| P3 | An unauthenticated internet client |
| P4 | Another app on the same phone |
| P5 | Someone holding the unlocked phone, a phone backup or a forensic copy |
| P6 | The server operator, or anyone with write access to the live DB |
| P7 | A network attacker |

---

## 1. Ranked findings (confirmed)

| # | Sev | Finding | Where |
|---|---|---|---|
| F1 | **high** | Any signed-in user can move into any group as admin, and the real admin's phone then hands them the group key | bible:764, :763, :1050; `message_repository_impl.dart:4656-4701, 4120-4123` |
| F2 | **medium** | Every signed-in user can read which chat each user has open or is typing in (`current_chat`, `typing_in`); this feeds F1 | bible:664; `presence_service.dart:93, 123` |
| F3 | **medium** | A changed peer public key is accepted silently: no key-change warning, no safety number | `message_repository_impl.dart:6390-6400` |
| F4 | **medium** | Anyone can open a chat with anyone and add any user to it: no consent, and blocks are not enforced on the server | bible:738, :763 |
| F5 | **medium** | "Delete for everyone" still shows the text and thumbnail in reply quotes | `reply_quote.dart:23-27`; `ingest_boundary.dart:168, 186` |
| F6 | **medium** | "Delete for everyone" leaves the receiver's decrypted media on the phone and in the Media gallery | `ingest_boundary.dart:186`; `media_gallery_service.dart:20-27` |
| F7 | low | Friendships can be created one-sided, with no request | bible:710 |
| F8 | low | Friend requests: created as `accepted`, or `from_user`/`to_user` rewritten by the recipient | bible:689, :690 |
| F9 | low | Reactions can be written into any chat by a non-member | bible:875 |
| F10 | low | A `message_media` row can name a different chat than its message | bible:825 |
| F11 | low | A group member can forge "system" notice lines (e.g. "X removed Y") | bible:795; `message_bubble.dart:235-244` |
| F12 | low | A failed key rotation after a removal is never retried | `message_repository_impl.dart:4656-4692` |
| F13 | low | Link previews fetch any URL the sender writes, automatically (prior §6.1, still open) | `link_preview_service.dart:22` |
| F14 | low | Sign-out leaves this phone's FCM token on the old account, so the next user on the phone gets its notifications | `auth_repository_impl.dart:375-396` |
| F15 | low | The app-lock wait after wrong PINs uses the wall clock and can be skipped by changing the time | `app_lock_controller.dart:364-370` |
| F16 | low | Another app can drive in-app navigation through the `kuchbhi://` VIEW filter (prior §5.1, now wider) | `AndroidManifest.xml:38-43` |
| F17 | low | An unused `flutter_background_service` leaves exported, unguarded service and receiver | `pubspec.yaml:47` |
| F18 | low | Group join/leave text and display names logged in release builds (prior §3.3, still open) | `message_repository_impl.dart:5929, 5990`; `auth_repository_impl.dart:349` |
| F19 | low | Auth JWT still mirrored into plain Drift (prior §4.1, still open; its reach is now cut by `allowBackup=false`) | `auth_repository_impl.dart:454` |
| F20 | low | Old superuser password still in git history. It was rotated on 2026-07-21 and the repo is private | `b09a86e:README.md:40` (removed in `e77367c`) |
| F21 | low | Friend-code filter built by string interpolation; the QR code is checked for length only (prior §1.1/§5.2, still open) | `friend_repository_impl.dart:43`; `add_friend_screen.dart:368-374` |
| F22 | low | Cropped avatar PNG left in temp (prior §4.4, still open) | `crop_photo_screen.dart:153-157` |

---

## 2. Finding detail

### F1 — Any signed-in user can join any group as admin and receive its key (high)

**The rules (bible §7, read live 2026-11-15):**
- `conversation_members` updateRule, second branch, bible:764:
  `|| (user_id = @request.auth.id && @request.body.role:isset = false)`.
  - Only the admin branch locks `user_id` and `conversation_id`. The owner of a row may rewrite its
    `conversation_id` to any chat and keep its `role`.
- `conversation_members` createRule, bible:763:
  - The first branch lets the creator of a chat add themselves (or anyone) with any role.
  - The third branch lets an invitee self-join with any `role`. The client sends `member`
    (`message_repository_impl.dart:3880`), but the server does not require it.
- `group_invites` updateRule, bible:1050: the admin branch locks no field, so an admin of chat A
  can re-point an invite at chat B.
- `conversations` createRule, bible:738: any signed-in user, `created_by` unchecked.

**Attack (P1, the only need is a sign-up):**
1. Sign up. Create a conversation with yourself as `created_by`.
2. Create your own member row with `role: "admin"` (bible:763, first branch).
3. PATCH that row with `conversation_id = <victim group id>`. Branch 2 at bible:764 passes because
   the stored row is yours. You are now an admin member of the victim group. Two other routes reach
   the same place:
   - Invite yourself in your own group, re-point the invite (bible:1050), then self-join as admin
     (bible:763, third branch).
   - If you hold a real invite, accept it with `role=admin`.
4. The victim group's real admin's phone runs `_reconcileGroupKeyGaps` on every resync
   (`message_repository_impl.dart:4656-4701`). It sees a member without the current key and
   rotates. `_rotateGroupKeyNow` then wraps the new key for every row the server lists
   (`:4120-4123`), including yours.
5. From then on you decrypt every new group message. As admin you can also remove members, invite
   others and write `group_keys` rows.

The victim chat id comes from F2.

**Why high:** this fully defeats the membership control, and with it the E2E promise for group
content, for a stranger. It needs only a chat id (F2) and one resync on the admin's phone. A
watchful admin may spot the extra name in Group info, but nothing alerts them. DMs are not
readable this way (their keys come from ECDH between the two people), but the intruder does see
the DM's ciphertext rows, receipts and timing.

**Fix (one line):** add `&& @request.body.conversation_id:isset = false && @request.body.user_id:isset = false`
to the second updateRule branch, require `@request.body.role = "member"` in the invite branch of
createRule, and lock `conversation_id`/`invited_user_id`/`invited_by` in the admin branch of the
invites updateRule.

**Follow-ups for the same spec:**
- Re-check the client too: rotation should wrap only for members the local device has seen join
  through an invite or an admin add.
- Ask the server, with a read-only query, whether any member row's `conversation_id` differs from
  how it was created. There is no audit column, so look for member rows with no matching invite or
  admin add.

### F2 — Everyone can see which chat each user is in right now (medium)

**Evidence:**
- `users` list/view is `@request.auth.id != ""` (bible:664-665).
- The 2026-10-30 hide hook strips only the two key-backup fields (`key-backup.md:310-314`: "`public_key` still present").
- The app writes the open chat id into `current_chat` (`presence_service.dart:93`) and the typed-in
  chat id into `typing_in` (`:123`).

**Attack (P1):** list `users` every few seconds.
- Two users showing the same `current_chat` are talking to each other right now. That is the
  who-talks-to-whom leak N1–N9 were meant to close.
- Each id is also the input F1 needs.
- The same list hands every user's `fcm_token`, `last_seen`, `is_online` and `friend_code` to any
  stranger.

**Fix:** blank `current_chat`, `typing_in` and `fcm_token` for non-owners in the same enrich hook,
or move presence into a member-scoped collection.

### F3 — Public-key swap is silent (medium)

**Evidence:** `message_repository_impl.dart:6390-6400`. The peer's `public_key` is fetched from the
server on each DM key lookup. When it differs from the cache, the code clears the cached keys and
derives a new key from the server's value, with only a `debugPrint`.
- Group-key wrapping (`encryption_service.dart:572-584`) trusts the same server-served key.
- No safety-number or key-change UI exists in `lib/`.

**Attack (P6):** whoever can write the live DB sets Bob's `public_key` to their own. Alice's next
message derives a key the attacker holds. On the next rotation, the admin's phone also wraps the
group key to the attacker's key.
- Users cannot do this to each other: `users` update is owner-only (bible:667).
- This is the classic server-MITM gap. It matters here because the app's promise is that the
  server cannot read content.

**Fix:** pin the first-seen key per contact and show a blocking "security code changed" notice
before encrypting to a new key. Later, add a safety-number screen.

### F4 — Unsolicited chats and member adds; blocks not enforced (medium)

**Evidence:**
- `conversations` create is any signed-in user (bible:738).
- `conversation_members` create lets the chat's creator add any user id with any role (bible:763,
  first branch).
- `blocked_users` rules only scope the blocker's own rows (bible:921-925). No rule elsewhere reads
  them.

**Attack (P1, or a blocked P2):** create a group and add the victim, or open a fresh DM with someone
who blocked you. The chat appears on the victim's phone. The invite consent flow
(`group_invites`) is skipped.

**Fix:** members create should require an accepted invite (groups) or a friendship with no block
(DMs). Conversations create should require `@request.body.created_by = @request.auth.id`.

### F5 — Deleted-for-everyone text survives in reply quotes (medium)

**Evidence:** `reply_quote.dart:23-27` loads the quoted parent by id with no check of
`isDeletedForEveryone`. The tombstone only sets the flag and keeps `encryptedBody`/`iv`
(`ingest_boundary.dart:168, 186`), so the parent still decrypts.

**Attack (P2 is the victim):** Alice deletes a message for everyone. Every reply to it still shows
her text or photo thumbnail on every phone.

**Fix:** treat a tombstoned parent as "Message not available", and blank `encryptedBody`/`iv` when
the tombstone lands.

### F6 — Deleted-for-everyone media stays on the receiver's phone and in the gallery (medium)

**Evidence:**
- The tombstone path (`ingest_boundary.dart:186`) never calls `mediaBlobStore.forgetLocal`. Only
  expiry (`message_repository_impl.dart:1005`) and a cancelled send do.
- The Media gallery lists `message_media` straight from the server by chat and type
  (`media_gallery_service.dart:20-27`), with no join to the message's deleted state.

**Result:** the receiver can still open and re-save a photo the sender deleted for everyone.
Whether the server still serves the file is a live check (L6).

**Fix:** on tombstone, call `forgetLocal` and clear the body cache. Filter the gallery by
non-deleted message ids.

### F7–F10 — Rows written outside the writer's own chat or relation (low)

| # | Where | Gap | Effect | Fix |
|---|---|---|---|---|
| F7 | bible:710 | `friendships` create checks only `user_a` | Any user can put themselves in anyone's friend list | Create friendships from a hook when a request is accepted, or require an accepted `friend_requests` row |
| F8 | bible:689-690 | Create allows `status="accepted"`; the recipient's update locks no fields | Forged accepted requests; the recipient can rewrite `from_user`/`to_user` | Create: `&& @request.body.status = "pending"`. Update: lock `from_user`/`to_user` |
| F9 | bible:875-876 | `reactions` create/update check only `user_id` | A non-member who knows a chat and message id adds reactions members will see | Add the `M` clause on `conversation_id` to create; lock the ids on update |
| F10 | bible:825 | `message_media` create checks the message's sender, not the row's `conversation_id` | A sender can pin a media row into another chat's gallery; rows can't be deleted by users | `&& conversation_id = message_id.conversation_id` |

`polls` (bible:902-903) and `scheduled_messages` (bible:948) have the same kind of create gap. The
app uses neither. Delete the collections, or add the membership clause. Whether a scheduled-send
hook exists is L5.

### F11 — Forged system notices inside a group (low)

**Evidence:**
- `messages` create checks the sender and membership but not `type` (bible:795).
- `type == 'system'` rows render as a centred notice with no sender and no long-press
  (`message_bubble.dart:235-244`).

**Attack:** a member posts "Admin removed Bob", encrypted with the group key. Every phone shows it
as an app notice.

**Fix:** reject client creates with `type = "system"` (`&& @request.body.type != "system"`), or
show the author on system rows.

### F12 — A removal whose rotation fails is never repaired (low)

**Evidence:**
- Removal deletes the member row, then rotates.
- If the rotation throws (offline, or a member with an empty `public_key`), the old key stays
  current.
- `_reconcileGroupKeyGaps` (`message_repository_impl.dart:4686-4692`) only rotates when a current
  member lacks the newest key, so it never notices.

**Result:** the removed member's old key opens later messages for anyone who also gets the
ciphertext (P6, or the F1 path).

**Fix:** store a per-group "rotation owed" flag and let the reconciler honour it.

### F13 — Automatic link-preview fetch (low, prior §6.1 unchanged)

**Evidence:** `link_preview_service.dart:22`: `Dio().get(url)` with no scheme, host, redirect or
size limit. It runs when the bubble renders.

**Attack (P2):** a sender learns every recipient's IP address, and can make their phones issue GETs
into their own LAN.

**Fix:** https only, block private and loopback ranges, `maxRedirects: 0`, cap the body. Better:
fetch only on tap.

### F14 — Sign-out keeps the push channel pointed at this phone (low)

**Evidence:**
- `signOut` (`auth_repository_impl.dart:375-396`) wipes local data, but never clears
  `users.fcm_token` or calls `deleteToken()`.
- Push handlers show `sender_name` with no session check when app lock is off
  (`fcm_service.dart:608-640`).

**Result (P5):** the next person who signs in on the phone sees the old account's sender names.

**Fix:** best-effort `users.update({'fcm_token': ''})` plus `FirebaseMessaging.deleteToken()`
before `clearAuth()`.

### F15 — App-lock wait trusts the wall clock (low)

**Evidence:** `app_lock_controller.dart:364-370`. `waitUntil` is compared with `DateTime.now()`.
Moving the clock forward ends the wait. Moving it back past the window also ends it, because
`remaining <= wait` then fails.

**Attack (P5):** free PIN guesses between the 30 s–15 min waits.

**Fix:** measure the wait with a monotonic clock (elapsed realtime), and treat a clock that jumped
as still waiting.

### F16 — VIEW intents reach the router (low)

**Evidence:**
- `AndroidManifest.xml:38-43` declares a BROWSABLE `kuchbhi` filter.
- No Dart handler exists, but Flutter's default deep linking is not disabled (no
  `flutter_deeplinking_enabled` meta-data).

**Attack (P4):** a page or app can open `kuchbhi://x/<route>` and push the user onto any route
after auth and the lock.

**Fix:** add `flutter_deeplinking_enabled=false` and drop the dead filter.

### F17 — Unused exported background service (low)

**Evidence:** `pubspec.yaml:47` pulls `flutter_background_service`, which nothing in `lib/` uses.
Its `BackgroundService` and `WatchdogReceiver` are `exported=true` with no permission in the merged
manifest. That manifest is a build artifact and may be stale.

**Attack (P4):** any app can start it (wake lock, a FlutterEngine).

**Fix:** remove the dependency. This also drops `RECEIVE_BOOT_COMPLETED`, `WAKE_LOCK` and
`FOREGROUND_SERVICE`.

### F18–F22 — Open leftovers from earlier runs (low)

| # | Where | What | Fix |
|---|---|---|---|
| F18 | `message_repository_impl.dart:5929, 5990`, `auth_repository_impl.dart:349` | Release logcat gets group join/leave text and display names | Log the chat id and a status word only |
| F19 | `auth_repository_impl.dart:454` (read back `:291-294`, `fcm_service.dart:119, 161, 484, 543`) | Session JWT in plain SQLite | Read it from `SecureStorageService` in the isolates and drop the Drift copy |
| F20 | `b09a86e:README.md:39-40` (removed in `e77367c`) | Superuser email and password in history. The password was rotated 2026-07-21; the repo is private | Confirm the old password fails (L9). Optionally purge the history before the repo is ever shared |
| F21 | `friend_repository_impl.dart:43`, `add_friend_screen.dart:368-374` | Unescaped friend code reaches a filter; a 6-char payload only causes a 400 today | Validate `^[A-Z0-9]{6}$` in `findUserByCode` |
| F22 | `crop_photo_screen.dart:153-157` | Cleartext avatar crop never deleted | Delete it after `updateProfile` |

---

## 3. Needs live check (no severity; each names the exact thing to look at)

Every item here needs the user's go-ahead before anyone reads the live server.

### L1. Key-backup blobs readable through a filter

**Why it may be open:** the hide hook is an `onRecordEnrich` that strips the two fields from
responses (`key-backup.md:310-316`). A filter is not a response. With `users` list open to every
signed-in user (bible:664), a request like
`filter=id="<victim>" && private_key_encrypted~"<prefix>"` returns 1 or 0 rows. That is a yes/no
oracle that can rebuild a blob one character at a time in a few thousand requests.

**Why it matters:** the H2 test list did not try filters (`key-backup.md:312-316`). A v2 blob gives
nothing: its 125-bit key is unguessable. A **v1** (6-digit PIN, PBKDF2-100k) blob still on the
server cracks offline in minutes and yields that user's X25519 private key.

**Look at:**
- A non-owner list call filtered on `private_key_encrypted` against a throwaway user on a DB copy.
- The count of users whose blob does not start with `v2:`.

**Fix if open:** move the two fields into an owner-only `key_backups` collection (list/view
`user_id = @request.auth.id`), or mark them `hidden`, and serve the owner through a hook route.

### L2–L10

| # | What to look at | Why it matters |
|---|---|---|
| L2 | `google_auth.pb.js`: does `signin` for an email that a password account already holds require that account to be verified, or reset its password on link? Is `register()` (`auth_repository_impl.dart:226-241`) gated on email verification? | Pre-hijack: a stranger signs up with the victim's Gmail and a password first. When the victim later uses Google, they land in the attacker's account, with the attacker's `public_key` |
| L3 | `fcm_notify.pb.js`: the payload fields, the relay secret handling, and whether a token that moves to another user is cleared on the old row | Decides the reach of F14, and confirms no `preview` text is ever sent |
| L4 | `disappearing_stamp.pb.js`: does "all others have read" count only current members' receipts? | The receipt create rule `auth = recipient_id` (bible:852) lets a non-member write a `read_at` receipt on a message id they know |
| L5 | Is a scheduled-message sender hook deployed (§7.16)? | It would post `scheduled_messages` rows with `$app`, and their create rule has no membership check (bible:948) |
| L6 | On delete-for-everyone, are `message_media` rows and files kept until expiry? | Decides whether F6 is also re-downloadable from the server |
| L7 | The live rules still equal §7 (they were last read 2026-11-15). The `users` field flags (`hidden`, `emailVisibility`) | Every server finding above assumes §7 is current |
| L8 | Is the Firebase client API key (`android/app/google-services.json:31`, `lib/firebase_options.dart:56`) restricted to the package and SHA in Google Cloud? | Unrestricted keys allow quota abuse |
| L9 | The superuser password from F20 no longer works | Memory says it was rotated 2026-07-21; this confirms it |
| L10 | `docs/server/tests/tok.pb.js` (mints a token for any user id) is not in live `pb_hooks` | If it were deployed, anyone could become any user |

### Results of the live read (2026-11-18, read-only, user go-ahead)

The read covered `ls`/`cat` of `pb_hooks` and `/opt/kuchbhi/fcm_webhook.py`, `sqlite3 -readonly` of `_collections`
(rules, NULL check, `users` field flags and auth options), row counts only for `users` and
`scheduled_messages`, and id/created/updated only for `_superusers`. No row content was read.
Hook line numbers below are for the live files.

| # | Result |
|---|---|
| L2 | **New finding F23 (medium).** See below. `register()` (`auth_repository_impl.dart:221-243`) signs in straight after sign-up with no email check, and `users` authRule is empty, so an unverified account can sign in. 2 of 5 live users are unverified |
| L3 | Payload: `fcm_notify.pb.js:63-69` sends only id, chat id, sender id and sender display name. `fcm_webhook.py:49-55` puts the same fields in FCM `data`. **No preview text is sent.** The relay listens on 127.0.0.1:8091 only and checks `X-Hook-Secret` from the env (`fcm_notify.pb.js:61`). Token move: nothing clears a token on the old row, giving **new finding F25 (low)**, below. Hardening, not findings: `fcm_webhook.py:31` falls back to a fixed secret when the env var is unset (reachable only from the VM itself), and group invites send the group name through FCM (`fcm_webhook.py:102`). `group_invite_notify.pb.js` was listed but not read |
| L4 | **Fine.** `disappearing_stamp.pb.js:27` / `:54` loads the chat's current members (minus the sender) and starts the clock only when each of them has a read receipt. Receipts from non-members are collected but never looked at. Edge: a chat with no other member left starts the clock on any read receipt. That removes only the sender's own message there, so it is not a finding |
| L5 | **Fine.** No scheduled-send hook is deployed (the only cron hooks are `disappearing_messages`, `media_expiry`, `online_status`). `scheduled_messages` has 0 rows, and its create/update/delete rules are NULL (superusers only) |
| L7 | **Fine.** All 17 non-system collections' five rules equal bible §7 text exactly (scripted diff). Every rule that is empty in the dump is NULL (locked), except `users` createRule `""` (open sign-up, as §7.1 says). `users` hidden fields are exactly `fcm_token`, `typing_in`, `current_chat`, `private_key_encrypted`, `private_key_salt` (plus `password`, `tokenKey`). `emailVisibility`: 1 of 5 users has it on, giving **new finding F24 (low)**, below |
| L8 | **Fine** (user checked the console 2026-11-18). The Android key is restricted to the app, with an API restriction of 26 APIs |
| L9 | **Fine.** One `_superusers` row, `updated` 2026-10-01 06:30 (after the 2026-07-21 rotation). The user confirmed the old password fails at `/_/`. F20 closed |
| L10 | **Fine.** `tok.pb.js` is not live. The only live route that mints a token is `google_auth.pb.js:1`. Leftover `test_b64.js` defines a `/api/hooks/test-b64` route, but its name lacks `.pb.js`, so PocketBase never loads it (dead file). Nothing listens besides :8090 (PocketBase) and :8091 (FCM relay) |

#### F23 — Google sign-in joins an existing password account, verified or not (medium)

- **Where:** `google_auth.pb.js:25` finds the user by the Google email, then `:47-50` signs in any record found, with no check on `verified`. Nothing resets the password or old sessions.
- **Attack:** a stranger (P1) signs up with the victim's Gmail and a password of their own; no email check is needed. Later the victim taps Continue with Google and lands in that account. The stranger still holds the password and their session, so they see the friends list, chats and members, and can swap `public_key` (F3 warns friends) or post as the victim.
- **Fix:** when Google signs in to an unverified account, set `verified`, set a new random password, and refresh `tokenKey` (signs out every other session).

#### F24 — Google sign-ups are created with a public email (low)

- **Where:** `google_auth.pb.js:40` creates the record with `emailVisibility: true`. `users` list/view is open to any signed-in user (§7.1), and sign-up is open.
- **Attack:** a stranger signs up and lists `users` to read every Google-registered member's email (1 live account today).
- **Fix:** drop `emailVisibility: true` from the hook, and set it to false on the existing row.

#### F25 — A push token can sit on two accounts (low)

- **Where:** `fcm_notify.pb.js:39-42` sends to each member's `fcm_token`, and nothing keeps a token unique. Sign-out clears it best-effort only (F14). The phone shows the notification from the push data alone (`fcm_service.dart` `_showMessageNotification`).
- **Attack:** account A signs out while offline, and B signs in on the same phone. A's new-message pushes keep arriving there, showing A's sender names to B.
- **Fix:** when a user saves an `fcm_token`, clear that same token on every other `users` row (one after-update hook, direct SQL).

---

## 4. Earlier findings, re-checked

| Prior item | Status now | Evidence |
|---|---|---|
| 10-30 §1.1 friend-code filter | still open | F21 |
| §1.2 other interpolations | still fine (ids only) | `auth_repository_impl.dart:705, 727` |
| §2.1 `google-services (N).json` | still fixed | `.gitignore:48` |
| §2.2 tracked config | unchanged (client key only) | L8 |
| §3.1 FCM token at start | still fixed | `FcmDebugHelper` gone |
| §3.2 FCM token on refresh | still fixed | `fcm_service.dart:112` |
| §3.3 plaintext in logs | still open | F18 |
| §4.0 keys in secure storage | still fixed | `secure_storage_service.dart:7-9` |
| §4.1 JWT in Drift | still open | F19 |
| §4.2 allowBackup | still fixed | `AndroidManifest.xml:12-13` + `data_extraction_rules.xml` |
| §4.3 decrypted media, no TTL | accepted by design (user, 2026-11-01); logout wipes it | `media_blob_store.dart:73-83` |
| §4.4 avatar crop temp | still open | F22 |
| §4.5 video temp copy | moot (temp path removed) | `media_viewer_providers.dart:50-53` |
| §5.1 `kuchbhi://` filter | still open, wider | F16 |
| §5.2 QR charset | still open | F21 |
| §6 TLS | still fine (https, no trust override, no cleartext) | `app_constants.dart:7` |
| §6.1 link-preview SSRF | still open | F13 |
| §7.1 group icon EXIF | fixed in `348b4b0` (not re-read this run) | — |
| §8.1 starred plaintext | still fixed (ids only) | `message_repository_impl.dart:2866-2873` |
| §8.2 6-digit PIN backup | fixed for new writes (v2 recovery key, `Random.secure`, HKDF, AAD = user id); v1 blobs still readable on restore | L1 |
| §8.3 push text verbatim | unchanged, hardening only | `fcm_service.dart:612-650` |
| server-rules N1–N9 | still fixed: migration, spec and §7 match line for line | `docs/server/migrations/1794700100_updated_rules_scope.js:13-38` |
| key-backup hide hook | live per spec; filter path untested | L1 |
| media-expiry `@now` | fixed | `docs/server/hooks/media_expiry.pb.js:8` |
| google_auth K2/K4 | fixed live 2026-10-29 (per notes); not in repo | L2 |

**Out of scope for N1–N9, and the source of F1, F4, F7–F10:** `server-rules.md:31-34` lists
`conversation_members` create/update, `group_invites`, `reactions`, `friend_requests`,
`friendships` and `scheduled_messages` as "looked at and left alone".

---

## 5. Hardening (not findings: no reachable boundary violation shown)

**Crypto**
- Ciphertext carries no AAD (sender, chat or message id). A group member can re-post another
  member's ciphertext as their own, and P6 can re-attribute `sender_id`. Bind
  `sender_id|conversation_id` as GCM AAD at the next format bump.
- When the server `public_key` differs from the local one, the client deletes its own private key
  (`auth_repository_impl.dart:584-593`). A server writer can force a key reset. Pairs with F3.

**Local data**
- Drift is plain SQLite (`app_database.dart:244-257`). Drafts (`draftText`), file names, chat names
  and timestamps are readable from a forensic copy. Voice drafts are plaintext audio.
- The app-lock PIN hash is PBKDF2 at 10,000 iterations (`app_lock_controller.dart:14`). The lock is
  a UI overlay, so the data underneath is not gated by it.
- A Keystore reset that loses the app-lock entry disables the lock (`main.dart:64-65`). This is fail
  open.
- `FLAG_SECURE` and the recents block apply only while an app lock is set
  (`MainActivity.kt:73-95`).

**Android**
- No `filterTouchesWhenObscured` on delete and send confirms.
- Share-in photos are sent without a preview of the picked media (`share_payload.dart:120`).

**Server abuse**
- Open sign-up, with only PocketBase's default rate limits. No per-user caps on requests, chats,
  invites or media rows.

**Release**
- The release build is signed with the debug key (`android/app/build.gradle.kts:31`).
- Minify is off.
- The Gradle wrapper has no `distributionSha256Sum`.

**Repo hygiene**
- `.claude/settings.json` is untracked and not ignored.
- `.claude/settings.local.json` is ignored only by the user-global ignore file.
- Add `.env*`, `pb_data/` and `*.pem` to `.gitignore`.

**Server copies**
- `media_expiry.pb.js:13-14` handles at most 500 rows a night.
- Group icons and avatars are public plaintext files. Media files are public but hold ciphertext.

---

## 6. What was not checked

- **The live server.** No rule, hook, field flag, nginx config or log was read (user constraint).
  The hook sources for `google_auth`, `fcm_notify`, `disappearing_stamp`, `disappearing_messages`
  and `key_backup_hide` are not in the repo; only their written descriptions were audited (§3).
- **Runtime behaviour.** No build, test, app run or device check. F16's deep-link behaviour and
  F17's exported components are reasoned from the Flutter default and a possibly stale merged
  manifest.
- **Third-party code.** `cryptography`'s X25519 low-order-point handling and its RNG source. CVEs in
  the 247 locked pub packages (no network). Dio redirect defaults were taken from docs, not source.
- **Unread client paths.** Whether in-chat search, Starred and Pinned exclude tombstoned or expired
  rows. A live purge timer while a chat stays open. The `friend_requests`/`friendships` realtime
  handlers. `presence_service.dart:175` subscriptions.
- **Images and video.** Screenshots and recordings in `docs/` and the untracked folders were not
  viewed for secrets (text grep only). History of `docs/audits/` and `*.txt` was not pattern-scanned.
- **Excluded trees.** `.claude/worktrees/`, `.opencode/`, `build/`, `test/` (except names), and the
  iOS target (none exists).
- **The skill's own tooling.** Its JSON findings/ledger files and validators, and the independent
  second verification pass (Phase 5). The ranking is one reviewer's triage over six sweeps.
- **Coverage.** This run is one pass. A run of the full skill workflow, or a second pass on the
  server rules after F1 is fixed, may find more.
