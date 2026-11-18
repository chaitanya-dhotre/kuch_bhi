# Security code changed: key pinning and a warning before encrypting to a new key (spec, rev 1)

Status: **spec PASS 2026-11-17 (user), all defaults (D-1..D-16). Built 2026-11-17 (1455/1455,
uncommitted, device check §8 pending); see `key-change-warning-work-log.md`.** Audit finding **F3 (medium)** in
`docs/audits/2026-11-16-security-cloudflare-skill.md`, plus the "own key deleted on mismatch"
hardening note in §5 of the same audit. No build, no server change, no live read. The board is
`key-change-warning.html` (visual ground truth for every screen below). Phase 2 = a fresh session.

All UI follows `docs/design/00-foundation.md` (tokens, C1–C5b, type scale, §6 states) and composes
`10-registry.md` pieces; the two new pieces are registry amendments (§7).

---

## 1. Why (code read 2026-11-17, `main` at `be0e2f1` plus the uncommitted working tree)

The server is not trusted to read messages. It **is** trusted, silently, to say which key each
person has. Anyone who can write the live DB (P6 in the audit: a stolen superuser login, a server
compromise, a bad migration) can swap a key and read what is sent next.

| # | Where | What it does today |
|---|---|---|
| 1 | `message_repository_impl.dart:6386-6413` `_getConvKey` (DM send, outbox drain) | Fetches the peer's `public_key` from the server on every DM key lookup. If it differs from the cached one: `debugPrint`, wipe **all** derived contact keys, cache the server value, derive from it. No notice. |
| 2 | `message_repository_impl.dart:6958` `_cacheUserRecord` (and `friend_repository_impl.dart:304,393`, `create_group_screen.dart:182-192`, `request_snapshot_cache.dart:164`) | Every user fetch overwrites `users.publicKey` with whatever the server says. All of them funnel through `UsersDao.upsertUser` / `upsertUsers` (`users_dao.dart:12-17`). |
| 3 | `decrypt_pass.dart:415-433` `_resolveKeys` (DM decrypt) | Derives from `users.publicKey`, i.e. whatever the last fetch wrote. |
| 4 | `message_repository_impl.dart:4141-4157` rotation, `create_group_screen.dart:176-210` create | Wraps the group key to each member's **server** `public_key`. A swapped key gets the group key at the next rotation. |
| 5 | `encryption_service.dart:496` `groupKeyFields` + `:776-800` group-key walk | Opens each wrapped group key with the wrapper's **current server** key (`expand.encrypted_by_user_id.public_key`). A swapped admin key lets the server hand members a group key it made itself; they would then send under it. (Not in the audit; same root cause. The audit's `encryption_service.dart:572-584` reference is stale, the code has moved.) |
| 6 | `auth_repository_impl.dart:582-597` `_initEncryptionKeys` | If the server's `public_key` for **me** differs from my local one, my private key is **deleted** and the phone goes to restore or generates a new key. A server writer can force a key reset. |

`users` update is owner-only (bible :667), so a normal user cannot swap someone else's key. This is
only about the server itself. It matters because "the server can't read your messages" is the
app's promise.

---

## 2. The model in one paragraph

Each phone keeps its own record of every contact's key (**pin**). The first key it sees for a
person is pinned silently (trust on first use). Encryption and decryption read **only** the pin,
never the server's `users.public_key`. When the server later shows a different key, the phone
stores it as **pending**, adds a local line "**Bob's security code changed**" to every chat with
Bob, and stops encrypting to Bob in the DM until the user **Accepts** it (optionally after
comparing a 60-digit **security code** in person or over a call). Accepting moves the old key to a
history list (old messages still open) and makes the new one the pin.

State per contact (board S2):

| State | Meaning | Send in DM | Decrypt in DM | Group wraps to them |
|---|---|---|---|---|
| none | never seen | — | — | first sight pins (TOFU) |
| pinned | one accepted key | to the pin | pin + history | to the pin |
| pinned + verified | the user compared codes and they matched | to the pin | pin + history | to the pin |
| pending | server shows a key that is not the pin | **held** (composer card) | pin + history only (new-key rows stay locked) | **skipped**, wrapped on Accept |

---

## 3. Decisions (defaults in bold)

| # | Decision | Options |
|---|---|---|
| D-1 | Where pins live | **New Drift table `contact_keys`** (dies with the rest of the local DB, same lifetime as `users`) · secure storage (no streams for the UI, one more storage scan) |
| D-2 | First sight of a contact | **Pin silently** (no line; every new friend would otherwise show a notice) · add "You can compare security codes with Bob" line |
| D-3 | DM after a change | **Blocking: the composer is replaced by the change card until Accept; queued rows hold** · non-blocking line only (WhatsApp's default; the swap would read the next message) |
| D-4 | Messages that arrive under the new key before Accept | **Stay locked (C1 `key_missing`) and open on Accept** · open at once under the line (the server could then speak as Bob) |
| D-5 | Group rotation or group create meets a pending member | **Skip that member; the Accept on an admin's phone writes their wrap for the current version (catch-up wrap)** · fail the whole rotation (a removal would then leave the removed member holding the key) |
| D-6 | Opening a wrapped group key | **Only with a key this phone has accepted for that wrapper (pin or history). A wrap that opens only with a pending key is not used, and the group shows the change banner** · trust the server key (today) |
| D-7 | Who sees what in a group | **Every member: the local line. Admins: also an R12 banner "Bob can't read new messages here until you check their code". Members, when an admin's own key is pending: the banner with "Check Carol's new code to keep chatting here"** · line only for everyone |
| D-8 | Code format | **60 digits in 12 groups of 5, plus a QR to scan in person** (Signal's numeric fingerprint, version 0, SHA-512 × 5200) · digits only · emoji or words |
| D-9 | Name in the UI | **"security code"** (WhatsApp's word; "safety number" reads as a phone number) · "safety number" |
| D-10 | Accept for a contact marked verified | **R20 confirm first** ("You had verified Bob…") · one tap like the rest |
| D-11 | My own key on the server differs from this phone's | **Blocking screen: "Restore with recovery key" (today's path) or "Keep this phone's code" (re-publish mine)** · today's silent delete |
| D-12 | Existing installs (migration) | **Seed pins from the cached `users.public_key` of every row except me; unverified; no lines** · start empty and pin from the next server fetch (a swap already live would be pinned without a cache to compare) |
| D-13 | Pins in the recovery-key backup | **Not now** (a reinstall pins again on first sight; verified ticks are lost) · add pins to a v3 blob |
| D-14 | Server key goes back to the pin while pending | **Pending clears silently; the earlier line stays** · add a "code is back" line |
| D-15 | Tell the person who starts fresh | **One sentence added to the Start fresh dialog (key-backup D8)** · nothing |
| D-16 | Where the code screen is reached | **Change card and line, DM ⋮ menu "Security code", View profile row** · also the group member sheet |

---

## 4. Checklist (phase 2 builds exactly this)

### A. Pin store

- [ ] **A1 MUST** Drift schema 14 → 15: table `contact_keys` — `user_id` TEXT PK, `key` TEXT (accepted,
  base64 X25519), `previous_keys` TEXT (JSON list, newest first, default `[]`), `pending_key` TEXT
  NULL, `pending_since` DATETIME NULL, `verified` BOOL default false, `updated_at` DATETIME.
- [ ] **A2 MUST** One entry point `ContactKeysDao.observe(userId, serverKey)`, called from
  `UsersDao.upsertUser` / `upsertUsers` whenever the companion carries a non-empty `publicKey` and
  `userId != me`. That is the single funnel every user fetch already uses (§1 #2), so no caller
  changes. Rules:
  - no row → insert pinned (D-2), no line;
  - `serverKey == key` → clear any pending (D-14);
  - `serverKey == pending_key` → nothing;
  - otherwise → `pending_key = serverKey`, `pending_since = now`, emit the change event (A4).
  - A key that equals one in `previous_keys` is still a change (a real person can't go back to an
    old key without the old backup, which Start fresh replaced).
- [ ] **A3 MUST** `users.publicKey` stays as the server's value for display only. **No code path
  encrypts or decrypts from it after this change** (grep gate: `publicKey` reads in
  `message_repository_impl.dart`, `decrypt_pass.dart`, `create_group_screen.dart` go through
  `contact_keys`).
- [ ] **A4 MUST** Change event → `_emitLocalSystemMessage` (the local-only line used by removal-lock,
  `:6820`) in the DM with that person and in every group where both are current members:
  **{Name}'s security code changed.** One line per new pending key per chat. Local only; never sent
  to the server (the server must not be able to write or suppress it).
- [ ] **A5 MUST** `accept(userId)`: `previous_keys = [key, ...previous_keys]`, `key = pending_key`,
  clear pending, `verified = false` unless the accept came from a matching scan (C4). Then fire
  A6 and B5.
- [ ] **A6 MUST** After accept: re-run the DM decrypt pass for that chat (rows sealed with the new
  key now open) and, on an admin's phone, **rotate** every group where I am admin and that person
  is a member (the existing rotation, which wraps to pins). *Rev 2026-11-18 (device run): a
  "fill the missing row" catch-up never fired, because a friend who started fresh still has a
  row at the current version wrapped to the old key, and rows are never updated.*
- [ ] **A7 MUST** Stop wiping derived keys on a change. Delete the `saveContactEncryptionKey(convId,'')`
  + `clearAllContactKeys()` pair in `_getConvKey` (`:6396-6403`); the derived-key cache is keyed by
  `conv_peerKey` (`encryption_service.dart:271`), so old and new keys never collide.

### B. DMs

- [ ] **B1 MUST** `_getConvKey` (DM branch): fetch + cache the user as today (that runs `observe`),
  then read `contact_keys`. Pending → throw `KeyChangedException` (a `MissingKeyException`
  subtype, so the outbox's existing hold applies: row stays `pending`, `OpSendOutcome.deferred`,
  `:1561-1567`). Otherwise derive from `key`.
- [ ] **B2 MUST** `_tryResolveSendKey` keeps its keyless fallback; a `KeyChangedException` is a
  keyless enqueue, not a crash.
- [ ] **B3 MUST** `decrypt_pass._resolveKeys` (DM): candidates = `[key, ...previous_keys]`, never the
  pending key (D-4). Rows that don't open keep today's `key_missing` look (foundation §6, lock +
  "Can't decrypt").
- [ ] **B4 MUST** `canSendIn` gains `keyChanged` (DM only). While pending, the composer is replaced by
  the **change card** (C21, board S3). The share-in picker (C18) already calls `canSendIn`, so a
  share into that chat opens it with the card.
- [ ] **B5 MUST** On accept, queued rows for that chat that were sealed under the old key and are not
  yet confirmed by the server are re-sealed with the new key before the drain sends them (the user
  wrote them for Bob, and accepted that this is Bob). Rows already sent stay as they are.

### C. Groups

- [ ] **C1 MUST** Rotation (`:4141-4157`) and create (`create_group_screen.dart:176-210`) wrap to the
  member's **pin**. No row (never seen) → `observe` pins first (TOFU), then wrap. Pending → **skip**
  that member (D-5), log `[Keys] skipped wrap for pending key`, and finish the rotation for the
  rest. A member with no server key at all keeps today's behaviour (rotation fails, create shows
  `MemberKeyMissingError`).
- [ ] **C2 MUST** Group-key walk (`encryption_service.dart:776-800`): add the wrapper id to
  `groupKeyFields` (`encrypted_by_user_id` alongside `expand.encrypted_by_user_id.public_key`).
  For each wrapper: run `observe(wrapperId, expandKey)`, then try opening with `[key,
  ...previous_keys]` of that wrapper only. A wrap that opens with none of them is skipped like an
  undecryptable wrap today. Side effect: versions wrapped by an admin before that admin's own
  reset now open again (history key), where today they fail.
- [ ] **C3 MUST** Group banner (R12 with the C21 action amendment, board S5), one at a time, newest
  first:
  - I am admin and a member is pending → **{Name}'s security code changed. They can't read new
    messages here until you check it.** · action **Check**.
  - The newest group-key version is wrapped by someone whose key is pending → **{Name}'s security
    code changed. Check it to keep chatting here.** · action **Check**. The composer's restriction
    line (`chat_screen.dart:966-970`) reads **Check {Name}'s new security code to send here.**
    instead of the "Waiting for a group admin" text.
- [ ] **C4 MUST** Non-admin members with no blocking condition see the line only (D-7); their sends
  use the group key, which a pending member never received.

### D. Security code screen and entry points (board S3, S4)

- [ ] **D1 MUST** Code: per side `fp(userId, key)` = SHA-512 over `0x0000 ‖ key ‖ utf8(userId)`, then
  5199 more rounds of SHA-512 over `hash ‖ key`; first 30 bytes → six 5-byte big-endian chunks →
  each `mod 100000`, zero-padded → 30 digits. Code = the two 30-digit halves ordered by string
  compare, joined → 60 digits, shown as 12 groups of 5 in 3 rows of 4. Runs in `compute` (same
  isolate rule as key derivation). A fixed test vector is part of the build.
- [ ] **D2 MUST** Screen `SecurityCodeScreen(userId)`: R14 `pageAppBar` **Security code** · R1 avatar
  56 + **You and {Name}** (title 16/22 w600) · code card (surface, radiusMd, 1px line): digits in
  body 15/22 w400 with tabular figures, ink, 12 dp column gap · QR (`qr_flutter`, payload
  `kuchbhi-sc0:` + the 60 digits) 176 dp on a white tile with 12 dp padding in both themes, so it
  scans · body 13/18 inkSoft **To check that your chat is private, compare these numbers with
  {Name} in person or on a call, or scan their code.** · R3 primary **Scan {Name}'s code** · R3
  secondary **Mark as verified** (verified state: a success check row **Verified** + R3 text
  **Clear verified**).
- [ ] **D3 MUST** Pending mode (same screen): above the code a note card (accentSoft, `accentText`
  info icon, C5b) **{Name}'s code changed on {d MMM}. These are the new numbers.** Buttons: R3
  primary **Scan {Name}'s code** · R3 secondary **Accept new code** (D-10: R20 first when the
  contact was verified: title **Accept the new code?** · body **You had verified {Name}'s old
  code. Only accept if {Name} told you they reinstalled or started fresh.** · **Cancel** /
  **Accept**).
- [ ] **D4 MUST** Scan: full-screen `MobileScanner` page reusing the add-friend QR tab's scanner
  setup. Match → pop, `verified = true` (and `accept` if pending), R5 **Codes match. {Name} is
  verified.** · different code → R5 error **These codes don't match. Don't accept until you've
  talked to {Name}.** · not ours → R5 error **That's not a kuch bhi security code.** · camera
  refused → R5 error **Couldn't open the camera.**
- [ ] **D5 MUST** Change card (C21, DM composer slot): surface card, radiusMd, 1px line, 16 padding,
  `accentText` shield icon 20, title **{Name}'s security code changed** (16/22 w600 ink), body
  13/18 inkSoft **This happens when {Name} reinstalls kuch bhi or starts fresh. It can also mean
  someone else is trying to read this chat. Compare codes before you send.**, buttons in one row:
  R3 tonal **Compare codes** (→ D3) · R3 secondary **Accept**. No solid primary (the send button
  is gone, and accepting must not look like the default).
- [ ] **D6 MUST** Local line: the system bubble variant with a 14 dp shield glyph; tap → D3 (or D2 once
  accepted). Copy: **{Name}'s security code changed. Tap to compare.**
- [ ] **D7 MUST** Entry points (D-16): DM ⋮ menu (C4a) row **Security code** (`Icons.shield_outlined`)
  after **Disappearing messages**; View profile R10 row **Security code** with subtitle
  **Verified** / **Not verified** / **Changed, check it**.
- [ ] **D8 MUST** Motion: card and banner arrive with `motionEnter`/`curveEnter` (L1: not when present
  at first paint); reduced motion = instant. Accept removes the card with `motionExit` and the
  composer returns.
- [ ] **D9 MUST** Large text (200 %): card buttons wrap to two rows; code rows wrap by group, never
  split a group of 5. Semantics: the code is read group by group ("12345, 67890, …").

### E. My own key (board S6)

- [ ] **E1 MUST** `_initEncryptionKeys` (`auth_repository_impl.dart:582-597`): on a mismatch **don't
  delete**. Set a `ownKeyMismatch` state the router sends to a blocking screen (same slot as the
  restore wait):
  - title **Your security code changed** · body **Your account has a new code that this phone
    didn't make. If you started fresh on another phone, restore here with your new recovery key.
    If you didn't, keep this phone's code; your friends will see it change back.**
  - R3 primary **Keep this phone's code** → `updatePublicKey(local)` → Home.
  - R3 secondary **Restore with recovery key** → R20 (title **Use the new code?** · body **This
    phone's key will be removed. Messages only open again after you restore with your recovery
    key.** · **Cancel** / **Continue**) → `deleteKeyPair()` → today's restore path (K3 unchanged).
  - Offline: both buttons as R3 with today's offline handling; the screen stays until one works.
- [ ] **E2 MUST** The legacy-adoption branch (`:556-575`) is unchanged; it already refuses a
  mismatched key.

### F. Migration (D-12)

- [ ] **F1 MUST** Drift `onUpgrade` 14 → 15: create `contact_keys`; insert one row per `users` row
  with a non-empty `public_key` and `id != current user`: `key = public_key`, `previous_keys =
  []`, `verified = false`. No lines, no notices.
- [ ] **F2 MUST** Users without a cached key pin on first sight after the update.
- [ ] **F3 MUST** Old-app peers are unaffected: nothing changes on the wire or the server.

### G. Copy elsewhere (D-15)

- [ ] **G1 MUST** Start fresh dialog (key-backup D8) body gains a last sentence: **Your friends will
  see that your security code changed, and they accept it before your new messages open.**

### H. Tests (build session writes them; suite stays green)

`contact_keys` state machine (A2 all branches, D-14) · migration seeds (F1) · `_getConvKey` throws
`KeyChangedException` and the row stays `pending` · B3 candidates exclude pending · B5 re-seal ·
rotation skips pending and still writes the rest (C1) · walk ignores a wrap that only opens with a
pending or unknown-to-history key, and opens an old wrap with a history key (C2) · catch-up wrap
on accept (A6) · D1 test vector + symmetry (both sides get the same 60 digits) · E1 no delete on
mismatch · widget tests for C21 card (both themes, 200 %), the screen's three modes, the banner.

---

## 5. How a legitimate change looks (board S7)

| What Bob did | Bob's key | What friends see |
|---|---|---|
| Reinstalled and restored with his recovery key | **same** (restore brings back the same key pair, `key-backup.md`) | **nothing** |
| Signed in on a second phone and restored | same | nothing |
| Lost his recovery key and chose **Start fresh** | new | the line in every shared chat; the DM card until they Accept; Bob's new messages to them stay locked until then; admins see the group banner, and Bob reads new group messages only after one admin accepts (catch-up wrap) |
| Reinstalled with **no backup ever made** (generate path) | new | same as Start fresh |
| Changed his recovery key (key-backup D7) | same (only the backup's secret changes) | nothing |
| Alice (the friend) reinstalls | Alice re-pins everyone on first sight; her own key only changes if she started fresh | Bob sees Alice's change only if her key changed |

Without the attack, the only cost is one tap per friend after a Start fresh, which already loses
all old messages.

---

## 6. What this does not fix (say so in the PASS)

1. **First sight is trusted.** A key swapped before a phone first sees a person (a new friend, or
   every contact on a fresh install) is pinned silently. Comparing codes (D) is the only check.
   D-13 would narrow the reinstall case.
2. **Group membership is still server-written.** A server writer can add a visible member (or a
   fake wrapper who is a member) to a group; that is F1 / membership territory, not key pinning.
   C2 only stops a swapped key of a person this phone already knows.
3. **Who wrote a message** is not bound (no AAD; audit §5 crypto). Unchanged here.
4. A pending key blocks the DM for that person until someone taps Accept or Compare. That is the
   point of D-3.

---

## 7. Registry amendments (same PR as the build)

| ID | Piece | Path | Contract |
|---|---|---|---|
| C21 | `KeyChangeCard(name, onCompare, onAccept)` | `lib/features/chat/widgets/key_change_card.dart` | D5: the DM composer slot while a key is pending; surface card, `accentText` shield, R3 tonal + secondary, no solid primary |
| C22 | `SecurityCodeScreen(userId)` + `securityCode(myId, myKey, theirId, theirKey)` | `lib/features/security/security_code_screen.dart`, `lib/services/security_code.dart` | D1–D4: three modes (pinned, verified, pending), QR + scan, accept |
| R12a | `StatusBanner(action: (label, onTap))` | `status_banner.dart` | optional labelled action besides `onRetry` (min-h 48); used by C3 |

---

## 8. Device check list (after the build; M52 + Redmi, test accounts)

1. Fresh build over an existing install: no lines appear; all chats send and read (F1).
2. On the Redmi account, **Start fresh**. On M52: the line in the DM and in each shared group; the
   DM shows the card; typing is not possible; a message the Redmi sends shows as locked.
3. M52 → **Compare codes**: both phones show the same 60 digits; scan the Redmi's QR → "Codes
   match", the card goes, the locked message opens, the composer returns.
4. Repeat 2 with **Accept** (no scan) on a contact marked verified → the R20 shows first.
5. M52 is admin of a group with the Redmi: before accepting, M52 removes a third member (rotation)
   → the rotation succeeds, the Redmi can't read the next message; after Accept, the Redmi reads
   messages sent after the accept.
6. Restore with the recovery key on the Redmi (no Start fresh) → M52 shows nothing.
7. Own-key screen: superuser edits the test account's `public_key` on a **copy or test account
   only** (needs the user's go-ahead for any server write) → the phone shows E1; **Keep this
   phone's code** puts it back; the other phone's pending clears without a second line.
8. 200 % text and dark mode on the card, banner and screen.

---

## 9. Must not undo

- K1/K3 (`850fe34`): decrypt paths only read the device key pair; a missing key never generates
  one. E1 keeps that: "Keep" re-publishes the existing key, "Restore" goes through K3 unchanged.
- The outbox never fails a message for a key that isn't ready (`:1561-1567`): pending keys are a
  hold, not a failure.
- Rotation that fails on a member with **no** key stays as is (group-info / `MemberKeyMissingError`).
- Leave-rotation and former-member-history specs (in flight in other sessions) touch the same
  rotation function: C1 changes only which key each member's wrap uses and adds the skip; it must
  sit inside their per-chat serial slot.

## 10. Out of scope

Pins in the backup (D-13), multi-device per account, signing group membership, AAD on ciphertext,
a "show all my verified contacts" list.
