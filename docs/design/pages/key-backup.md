# Key backup: recovery key, legacy-PIN migration (acceptance checklist, security §8.2)

Date: 2026-10-30 (rev 2: recovery key, user decision 2026-10-30). Visual ground truth:
**`docs/design/pages/key-backup.html`** (sections S1–S12, numbered; S1 = the finding and the attack
maths, S2 = every caller, S9 = format and migration, S10 = server, S12 = full diff vs current code).
Authority: `docs/design/00-foundation.md` (tokens/laws) → `docs/design/10-registry.md` (shared pieces)
→ `docs/design/pages/auth.md` (Page 7 auth pieces this page reuses) → this checklist. Letters A–H are
page-local. Source finding: `docs/audits/2026-10-30-security.md` §8.2 (high, confirmed).

Line refs, as of `6164166`: `bps` = `lib/features/auth/screens/backup_pin_screen.dart` (1080 lines),
`es` = `lib/services/encryption_service.dart`, `esp` =
`lib/features/auth/providers/encryption_sync_provider.dart`, `ar` = `lib/core/router/app_router.dart`,
`hs` = `lib/features/home/screens/home_screen.dart`, `ps` =
`lib/features/profile/screens/profile_screen.dart`, `aui` = `lib/features/auth/widgets/auth_ui.dart`.

**Routing.** Claude end to end (crypto). No Astra/Mimo brief. Phase 1 = this spec (no code). Phase 2 =
a fresh session after the user's spec PASS. The grading pass is a fresh-context reviewer (subagent or
`/code-review`), never the implementer.

**Pass criteria (page complete when):** all MUSTs ✓ · `flutter analyze` 0 errors · `flutter test`
green (baseline **669/669** at `6164166`; re-take it at phase 2 start, other sessions commit too; plus
the new tests; no existing assertion edited to pass, see the two allowed test edits under Test gates)
· test-gate files below green · `git diff --check` clean · `trail check` clean · the frozen-function
diff (⛔ below) unchanged vs HEAD · fresh-context review with no open BLOCK · device captures light +
dark + AMOLED of the key step, the check step, restore, the upgrade step and the Home upgrade banner ·
user device PASS (no commit without it) → one commit.

**Spec status: PASS 2026-10-30 (user), all defaults. Phase 2 = implement in a fresh session.** Decision 1 is settled (recovery key, the
user's call). 13 other decisions at the bottom, each with a recommended default.

**Server facts (live read-only check, user-approved 2026-10-30).** `users` listRule AND viewRule are
both `@request.auth.id != ""`, and neither `private_key_encrypted` nor `private_key_salt` is hidden.
No hook hid them (`google_auth.pb.js:53` returns them only to the user signing in). All 5 users have a
legacy backup (80-char blob each, none `v2:`). So **any signed-in account could list every user's
backup blob in one request**, and an offline guess loop then needs no further server contact. The app
fetches other users' records with a bare `getOne` (e.g. `message_repository_impl.dart:478, 5431`,
`presence_service.dart:159`), so hiding the fields must happen server-side.
Rate limiting is ON with PocketBase's four default rules (`*:auth` 2/3 s, `*:create` 20/5 s,
`/api/batch` 3/1 s, `/api/` 300/10 s); the real client IP reaches PocketBase via nginx `X-Real-IP`.
None of this limits backup guessing, because guessing is offline. **The owner-only hide hook
went live 2026-10-30 (H2); blobs copied before then stay crackable** until their owner moves to a
recovery key (and even then the old copy still opens the same X25519 key; only a new key pair
fixes that, out of scope).

**Why a recovery key (S1).** WhatsApp and Signal can let users pick short PINs only because the guess
counter lives in tamper-resistant hardware (HSMs, SGX enclaves) that never hands out the encrypted
key. PocketBase has no such box and anyone holding the database can guess offline, so the secret
itself must be unguessable. 25 random base-32 characters = 125 bits: 2^125 ≈ 4×10^37 guesses, beyond
any GPU farm for the life of the universe. The X25519 key it protects is itself ~128-bit strength, so
more bits would buy nothing. The real risks are where the user keeps it and losing it (D2 copy, C4).

---

## The finding, confirmed in code (S1)

- **6 digits only.** Six one-character controllers `bps:89-95`; the only valid input is
  `pin.length == 6 && isDigitsOnly` in all three modes `bps:157-176`. 10^6 possible secrets.
- **Weak KDF.** `_isoPbkdf2` `es:151-163` = PBKDF2-HMAC-SHA256, called with `iterations: 100000` at
  `es:818-822` (backup) and `es:878-882` (restore).
- **On the server.** `backupPrivateKey` `es:801-852` writes `private_key_encrypted` (nonce‖ct‖mac,
  base64) and `private_key_salt` (32 bytes, base64) onto the `users` record `es:841-849`.
- **The code admits it.** The comment at `es:793-799` says "use a strong PIN"; the UI can't take one.
- **Cost today (estimate, S1 table):** 10^6 PINs at PBKDF2-100k ≈ **10–20 seconds on one high-end GPU**
  (≈ 9 MH/s at 1k iterations, scaled to 100k), or a few hours on a laptop CPU. Result: the user's
  X25519 private key, so every past and future DM and every wrapped group key.

Two more defects found on the same path (fixed by this page):

- **Change PIN overwrites the device key to "verify".** Change mode checks the current PIN by calling
  `restorePrivateKey` `bps:195-197`, which saves the backup's key over the device key, re-publishes the
  public key and wipes every cached conversation and group key `es:897-934`. If the backup holds an
  older key than the device (a Start Fresh whose backup step failed), "verify" silently swaps the
  account back to the old key.
- **Restore can't tell "no backup" from "wrong PIN".** `restorePrivateKey` returns `false` for both
  (`es:869-872`, `es:942-945`), so a missing backup reads "Incorrect PIN. Try again." `bps:248-253`.
- **`$e` in user text:** `"An error occurred: ${e.toString()}"` `bps:312`.

## Every caller (S2)

| # | Path | Entry | Calls | Today |
|---|---|---|---|---|
| 1 | Setup (required) | router `needsSetup` `ar:119-122` → `/backup-pin/setup` | `backupOrCreateKey` `es:986-997` → `backupPrivateKey` | 6 digits ×2 |
| 2 | Setup (optional) | Home backup banner `hs:191-195` (shown by `showBackupBannerProvider` `esp:111-141` when local key + server says no backup) | same | + **Skip for now** `bps:317` |
| 3 | Start Fresh | **I forgot my PIN** `bps:671` → dialog `bps:336` → setup with `_isStartingFresh` | `generateAndBackupNewKey` `es:948-979` (public key first, then `backupPrivateKey`) | explicit overwrite |
| 4 | Change | Profile **Change Backup PIN** `ps:241-246` → `/backup-pin/change` `ar:233` | `restorePrivateKey` (as a check!) then `backupOrCreateKey` | defect above |
| 5 | Restore at sign-in | router `needsRestore` `ar:115-118` (K1/K3 route) → `/backup-pin/restore` | `restorePrivateKey` `es:854-946` then `syncAllHistory` | 6 digits |
| 6 | Restore-wait overlay (Page 7 J) | `_RestoreOverlay` `bps:708-1080`, shown while `_isLoading` | none (display only); phase copy `bps:22-55`; setup/change show the "Saving your PIN…" card `bps:972` | |
| 7 | Backup check | router, banner, `backupOrCreateKey` | `tryHasPocketBaseBackup` `es:1010-1019` (tri-state; reads `private_key_encrypted` non-empty) | |

Tests that touch it: `test/offline/encryption_sync_offline_test.dart` (K1/K3, incl. offline
`restorePrivateKey('123456')` throws `:416-425`), `test/auth/restore_overlay_test.dart` (fake
`restorePrivateKey` returns `true` `:20`), `test/grep_gates_test.dart:42, 144, 408` (colour gate
includes `bps`; Page 7 hygiene gate lists `bps` as frozen).

---

## ⛔ Key boundary (read first: a breach here is an automatic FAIL)

- [ ] **K1 MUST** No X25519 key is ever generated by this page's code. Key generation stays only where
  it is today: `generateAndBackupNewKey` (Start Fresh, explicit, behind its dialog) and sign-in key
  init (K3 rules, untouched). `backupOrCreateKey`'s three-way logic is byte-identical to HEAD. (The
  recovery key is a random secret, not an X25519 key; generating it is C1.)
- [ ] **K2 MUST** No public key is ever uploaded by the backup writer. The only `public_key` writes
  stay where they are today: `generateAndBackupNewKey` (first, K3) and `restorePrivateKey`'s
  re-publish of the key it just decrypted.
- [ ] **K3 MUST** Every write of `private_key_encrypted` / `private_key_salt` goes through ONE
  function (`backupPrivateKey`), and that function refuses to write (throws `KeyMismatchException`,
  zero PATCH) when the server record's `public_key` is non-empty and differs from the public key
  derived from the device's private key. It re-reads the record for this; it never trusts a cached
  value. Rationale: we only ever back up the key peers encrypt to. A re-wrap replaces a blob with the
  same key under a new secret, never a different key.
- [ ] **K4 MUST** Frozen vs HEAD (function-level diff in the gates): `_initEncryptionKeys`
  (`auth_repository_impl.dart`), `encryptionSyncProvider` and its no-local branch / `setupDue` /
  `_recheckOnReconnect` (`esp`), `generateAndBackupNewKey` except that its backup call now passes the
  recovery key, `tryHasPocketBaseBackup` (contract: `true`/`false` only on a server answer, `null` on
  ANY error), `_readKeyPair`, `getOrDeriveConversationKey`, `syncAllHistory`, the router redirect.
- [ ] **K5 MUST** A legacy (v1) backup is never deleted or rewritten except by a successful v2 write
  of the same key (K3). Wrong key, offline, Not now, app killed mid-save: the v1 blob is exactly as it
  was, and still opens with the old PIN.

## A. Format and KDF (S9) — decisions 2, 3

- [ ] **A1 MUST** v2 blob: `private_key_encrypted` = `"v2:"` + base64(nonce 12 ‖ ciphertext 32 ‖
  GCM tag 16) (decision 3 default; with the alternative, the blob is unprefixed and
  `private_key_backup_version = 2`). `private_key_salt` = base64(16 random bytes from
  `Random.secure()`). Both fields go in **one** `users.update` call (atomic on the server).
- [ ] **A2 MUST** v2 KDF = HKDF-SHA256 (`Hkdf(hmac: Hmac.sha256(), outputLength: 32)` from
  `package:cryptography`, already a direct dependency; **no new package**): input key material =
  ASCII of the canonical 25-character recovery key (C2), salt = the 16 salt bytes, info = UTF-8
  `"kuch_bhi key backup v2"`. No slow KDF: the key has 125 random bits, so stretching adds nothing
  (decision 2). Runs inline, microseconds. Once committed, v2's construction never changes; a new one
  = v3.
- [ ] **A3 MUST** v2 cipher = AES-256-GCM (the existing `_aesGcm`), fresh 12-byte nonce, **AAD =
  UTF-8 `"kuch_bhi key backup v2 " + userId`**. A v2 blob copied onto another account, or with its
  prefix stripped (downgrade to v1), fails the tag check: wrong-secret result, nothing written.
- [ ] **A4 MUST** v1 (legacy) = any non-empty blob with no `v<digits>:` prefix (base64 has no `:`):
  PBKDF2-HMAC-SHA256, 100,000 iterations, 32-byte salt, no AAD, exactly as `es:874-904` today, still
  via `compute` (3.55 s on the Redmi S2, unchanged). Read only: **nothing ever writes v1 again.**
- [ ] **A5 MUST** Unknown prefix (`v3:` and up) → `RestoreResult.unsupported`; nothing written; copy
  E1. A malicious or newer record can't make this build guess.
- [ ] **A6 MUST** `restorePrivateKey(String secret)` picks the path from the blob, never from the
  input: v1 blob → PBKDF2 with the trimmed input as-is; v2 blob → `parseRecoveryKey(input)`, and a
  `null` parse is `wrongSecret` (no decrypt attempted).
- [ ] **A7 MUST** `restorePrivateKey` returns `RestoreResult` {`restored`, `restoredLegacy`,
  `wrongSecret`, `noBackup`, `unsupported`} instead of `bool`; it still THROWS when the record read
  fails (K3: offline is an error to show, not a wrong secret; the existing offline test keeps passing
  untouched). On `restored*` its writes are today's, in today's order.
- [ ] **A8 SHOULD** Update the stale comment `es:793-799` to describe v1/v2 and the guard.

## B. Migration and re-wrap (S9) — decisions 6, 7, 12

- [ ] **B1 MUST** Old-format restore works: a v1 blob + its 6-digit PIN → `restoredLegacy`, the
  device key equals the original key byte for byte (test T2).
- [ ] **B2 MUST** Upgrade step after a legacy unlock (decision 6): when restore returns
  `restoredLegacy`, the screen does NOT start the history sync yet; it shows the **key step** with the
  upgrade copy (D5), then the check step. **Turn on backup** → `backupPrivateKey(recoveryKey)` (v2,
  guarded by K3, trivially true since restore just re-published this key) → R5 toast **Recovery key
  saved.** → the frozen restore continuation (overlay, `syncAllHistory`, `go(home)`). **Not now** (on
  either step) → the same continuation, nothing written.
- [ ] **B3 MUST** A save failure in the upgrade step shows its error (E) and offers **Not now** /
  retry; the restored key is already saved, so no failure here ever sends the user back to restore.
- [ ] **B4 MUST** Set-up devices with a v1 backup (they never unlock): the Home banner slot shows the
  **upgrade** banner (D8) when local key present AND server answers `legacy`. Tap → `/backup-pin/change`.
  Dismiss → hidden 7 days under its own setting `backup_upgrade_dismissed_at` (decision 12). Unknown
  (offline / any error) → hidden, like today's tri-state.
- [ ] **B5 MUST** Change (decision 7): no current-secret step. It makes a new recovery key (key step
  → check step); the K3 guard is the protection. `restorePrivateKey` is never called from change mode
  (test).
- [ ] **B6 MUST** Interrupted re-wrap is safe at every point: killed before the PATCH → old blob
  untouched, banner still shows; PATCH failed → error shown, old blob untouched, retry works (same
  recovery key, still on screen); PATCH landed but the response was lost → server holds v2 under the
  key on screen; retry writes v2 again with a fresh salt under that same key. No local "upgrade in
  progress" flag exists; the server record is the only truth.
- [ ] **B7 MUST** After any successful backup write: `ref.invalidate(showBackupBannerProvider)` (the
  banner reads `current` and hides) and, for setup, today's `encryptionSyncProvider` invalidation.
- [ ] **B8 MUST** Start Fresh: the key step and check step come FIRST, then `generateAndBackupNewKey(
  recoveryKey)` runs in its existing order (public key, local save, backup), so no new X25519 key is
  made until the user has saved the recovery key. Its dialog copy D7.

## C. The recovery key (S4) — decisions 1, 11, 13, 14

- [ ] **C1 MUST** Generation: 25 symbols, each `Random.secure().nextInt(32)` into the Crockford
  base-32 alphabet `0123456789ABCDEFGHJKMNPQRSTVWXYZ` (no I, L, O, U). 125 bits. Shown as 5 groups of
  5 joined by `-`, e.g. `7KQ2M-9XHMA-4TRBC-8D1WZ-P6YVN`.
- [ ] **C2 MUST** Parsing (restore and check step): uppercase; drop spaces, `-` and all whitespace;
  map `O→0`, `I→1`, `L→1`; the result must be exactly 25 alphabet characters, else `null`. That
  25-character string is the canonical key (A2's input).
- [ ] **C3 MUST** One pure file `lib/core/utils/recovery_key.dart`: `generateRecoveryKey([Random?
  rng])`, `parseRecoveryKey(String) → String?`, `formatRecoveryKey(String) → String`. Unit-tested.
- [ ] **C4 MUST** The key lives only in the screen's state until saved: never logged (no
  `debugPrint` of it or of any input field), never in a route parameter, never persisted, never sent
  anywhere but into HKDF. Leaving the screen drops it; coming back makes a new one (decision 11).
- [ ] **C5 MUST** Check step (decision 13): the field must parse to the same canonical key as the one
  shown (paste allowed). Mismatch → field error (E1). **Turn on backup** is enabled only on a match.
- [ ] **C6 MUST** Restore input is valid when it is exactly 6 digits (legacy PIN) or parses (C2);
  anything else → field error **A recovery key has 25 letters and numbers. Check that you have all of
  it.** with no server call. **Restore** is enabled at 1+ characters.
- [ ] **C7 MUST** Copy (decision 14): **Copy** puts the grouped key on the clipboard + R5 toast
  **Recovery key copied.** After a successful save, if the clipboard still holds that key, it is
  cleared. `shortcut: Gboard's clipboard history can still hold it; no platform flag for sensitive
  clips in Flutter, add a MethodChannel if this matters.`

## D. Screens and copy (S4–S8) — decisions 8, 9, 10

Copy below is verbatim. "Recovery key" replaces "Backup PIN" in every user-facing string
(decision 10); route paths, class and enum names stay.

- [ ] **D1 MUST** One screen, the existing `BackupPinScreen`, rebuilt on Page 7's auth pieces
  (decision 9): `AuthTitle`, `authBodyStyle`, `AuthTextField` (R13), R3 buttons, `OfflineDim` +
  `OfflineActionHint`, R5 toast, R20 confirm dialog. The six digit boxes, their controllers, focus
  nodes and backspace handlers `bps:89-135` are deleted. Gutter 24, scrolls. Two steps where a key is
  made (setup, Start Fresh, change, upgrade): **key step** → **check step**; system back on the check
  step returns to the key step (same key).
- [ ] **D2 MUST Key step (setup)** — title **Save your recovery key** · body **Your messages are locked
  with a key that lives on this phone. This recovery key unlocks a copy of it on our server, so you
  can get your messages back after a reinstall. Nobody else has it, and nobody can reset it.** · the
  key block (C1 groups, monospace, `t.surface` card, not selectable text) · tonal button **Copy** ·
  helper **Save it in your password manager or write it down. Don't keep it only on this phone.** ·
  primary **I've saved it** · optional setup keeps text button **Skip for now** (today's
  `_skipBackup`, unchanged). The optional-setup prefix line becomes **Set up a recovery key to protect
  your messages.**
- [ ] **D3 MUST Check step** — title **Check your recovery key** · body **Type or paste the key you
  just saved. This makes sure you can get back in later.** · field label **Recovery key**,
  `textCapitalization: characters`, monospace, visible (not obscured), autofill `newPassword` with
  the account email as the `username` hint (so a password manager offers to save it) · primary
  **Turn on backup** → saving card → R5 **Backup is on.** · text button **Show the key again**.
- [ ] **D4 MUST Start Fresh** — key step title **Start fresh: save your new recovery key**, body **This
  makes a new key for your messages. Save this recovery key to protect it.**, rest as D2/D3.
- [ ] **D5 MUST Upgrade step** (after `restoredLegacy`) — key step title **Make your backup stronger**
  · body **You're in. Your backup still uses a 6-digit PIN, which is easy to crack. Save this recovery
  key to replace it.** · D2's key block, Copy, helper · primary **I've saved it** · text button **Not
  now**. Check step as D3, plus **Not now**.
- [ ] **D6 MUST Restore** (decision 8) — title **Restore your messages** · body **Enter the recovery
  key you saved. If you set a 6-digit PIN before, enter that instead.** · one field, label **Recovery
  key or PIN**, text keyboard, `textCapitalization: characters`, monospace, autofill `password`,
  visible by default with the R13 show/hide toggle · primary **Restore** · text button **I lost it**
  (→ D8 dialog).
- [ ] **D7 MUST Change** — Profile row **Recovery key** (`ps:243`) → app bar title **Recovery key** (R14
  `pageAppBar`) · body **Make a new recovery key for your backup. Your old key or PIN stops working
  once the new one is saved.** · primary **Make a new key** → key step (title **Your new recovery
  key**) → check step → on success R5 **New recovery key saved.** + pop.
- [ ] **D8 MUST Start Fresh dialog** (R20, destructive) — title **Start fresh?** · body **Without your
  recovery key, your old messages can't be opened.\n\nStarting fresh makes a new key. New messages
  work, but every older message stays locked for good.** · **Cancel** / **Start fresh**. Logic
  unchanged.
- [ ] **D9 MUST Home upgrade banner** (same `_BackupBanner` widget, second copy) — **Your backup uses a
  short PIN that's easy to crack. Tap to get a recovery key.** · dismiss tooltip **Dismiss reminder**.
  The no-backup copy is corrected to **Back up your encryption key so you can restore your messages
  after a reinstall. Tap to set up.** Only one banner at a time (no backup wins).
- [ ] **D10 MUST Saving card** (setup/change/upgrade, `_RestoreOverlay` non-restore branch) text
  **Locking your backup…** (was "Saving your PIN…"); restore's `RestorePhase.deriving` message
  **Checking your key…** (was "Deriving your encryption key…"). Nothing else in the overlay changes
  (Page 7 J stays frozen).

## E. Errors (S7) — no `$e`, detail to `debugPrint` only

- [ ] **E1 MUST** Copy by result/exception (one mapper, pure, tested):

  | Case | Where shown | Copy |
  |---|---|---|
  | malformed input (C6) | field error, no server call | **A recovery key has 25 letters and numbers. Check that you have all of it.** |
  | check-step mismatch (C5) | field error | **That's not the key on the last screen. Tap "Show the key again" and copy it.** |
  | `wrongSecret` | field error, field kept (so typos can be fixed) and refocused | **That doesn't match your backup. Check for typos and try again.** |
  | `noBackup` | error card above the button | **This account has no backup to restore. Tap "I lost it" to start fresh.** |
  | `unsupported` | error card | **This backup was made by a newer version of Kuch Bhi. Update the app, then try again.** |
  | network (`ClientException`, PB status 0, timeout) | error card | **Can't reach the server. Check your connection and try again.** |
  | `KeyMismatchException` | error card | **This phone's key isn't your account's current key, so your backup wasn't changed.** |
  | any other, saving | error card | **Couldn't save your backup. Try again.** |
  | any other, restoring | error card | **Couldn't restore your messages. Try again.** |
  | Start Fresh failed | error card | **Couldn't start fresh. Check your connection and try again.** |

- [ ] **E2 MUST** `bps` carries no `$e`, `e.toString()`, `Exception` or `$` interpolation of an
  error in any `Text` (the existing `$e` gate is extended to `bps`).
- [ ] **E3 MUST** No lockout or attempt counter (it would only slow the online path; the offline
  path is what the recovery key fixes).
- [ ] **E4 MUST** The error card is R12-style text on `t.surface` with an error icon; text in ink
  (foundation C4), `liveRegion: true`.

## F. Offline (S8)

- [ ] **F1 MUST** Offline (`isOnlineProvider` false): the key step works fully (the key is made on the
  phone); fields stay editable; **Turn on backup** / **Restore** / **Make a new key**'s final save are
  disabled under `OfflineDim` + `OfflineActionHint` (**Available online**). **Skip for now**, **Not
  now**, **I lost it** stay enabled (the dialog's Start fresh then fails with E1's copy if still
  offline).
- [ ] **F2 MUST** Going offline mid-save: the call throws, E1 network copy, old blob untouched (B6),
  the same key stays on screen for the retry.
- [ ] **F3 MUST** The upgrade banner never shows on an unknown backup state (offline).

## G. A11y, motion, 360dp at 200% (S8)

- [ ] **G1 MUST** Every field has a visible label (not hint-only); the restore field's show/hide
  toggle is 48dp with tooltip **Show key** / **Hide key**; `enableSuggestions: false`,
  `autocorrect: false` on every key field.
- [ ] **G2 MUST** The key block is one semantics node whose label spells the key out character by
  character, groups separated by commas (e.g. **7, K, Q, 2, M, then 9, X, H…**), so TalkBack reads
  it unambiguously; **Copy** is a 48dp target with its own label.
- [ ] **G3 MUST** Field errors and the error card are announced once (live region); focus returns to
  the field after `wrongSecret` or a mismatch.
- [ ] **G4 MUST** Title in `Semantics(header: true)` (via `AuthTitle`).
- [ ] **G5 MUST** Reduced motion: no shake; the saving card's pulse parks (already does under
  `disableAnimations`).
- [ ] **G6 MUST** 360×640dp at 200% text: key step, check step, restore, upgrade step and change
  scroll with no overflow; the key block wraps by group (never mid-group); buttons full width (test).

## H. Server (S10) — decisions 3, 4, 5. Every item needs the user's OK before it runs

- [x] **H1 DONE 2026-10-30 (read-only, user OK)** R1–R3: rules, `hidden` flags, backup count, hook
  listing; results in Server facts above.
- [x] **H2 DONE LIVE 2026-10-30 (user OK)** `pb_hooks/key_backup_hide.pb.js` deployed (S10 code plus
  a `requestInfo` guard and a superuser exception), backup `/home/ubuntu/pb_backups/pb_hooks.20261030-key-backup-hide-pre`.
  Verified first on a throwaway DB copy on port 8099 (same binary): A lists all users → only A's own
  blob + salt present, others absent, `public_key` still present; A GET B → absent; A GET A →
  present; `?fields=private_key_encrypted` on B → absent. Live after restart: health 200, anon list
  empty, 389×200 + 18×204 and no 4xx/5xx, no journal errors; both phones cold-start to Home with no
  backup banner (owner still sees own backup). Not separately tested: `expand` of a member's user
  (same enrich path); restore on a fresh install (phase 2 DC check). Rollback: delete the file, restart.
- [ ] **H3 (only if decision 3 = separate field)** the migration in S10, same deploy pattern as the
  2026-10-29 avatar migration (backup `data.db` first).
- [ ] **H4** No new rate limiting (decision 5 default).

---

## Test gates (mandatory)

Harness: `test/offline/char_harness.dart` (`charHarness(clientFactory:)` with `MockClient`), as the
K1/K3 tests do. Real HKDF and PBKDF2 in tests (PBKDF2-100k ≈ 0.4 s on the dev box); no platform
channels. Every PATCH body is captured.

- [ ] NEW `test/offline/key_backup_format_test.dart`
  - **T1 round-trip v2:** backup with a generated key → captured PATCH has `v2:` prefix, 16-byte
    salt, exactly the two keys (no `public_key`) → feed it back as the record → restore with the same
    key, typed lowercase with spaces instead of dashes → `restored`, device key byte-equal.
  - **T2 legacy v1:** a v1 fixture built in-test with PBKDF2-100k + `'123456'` (32-byte salt, no AAD)
    → restore `'123456'` → `restoredLegacy`, key byte-equal.
  - **T3 old → new:** after T2, `backupPrivateKey(key)` → v2 PATCH; restore with the key →
    `restored`; restore with `'123456'` → `wrongSecret`.
  - **T4 wrong secret (v1 and v2):** `wrongSecret` (incl. an unparseable input against a v2 blob);
    device key unchanged (null stays null, an existing key stays); zero PATCH.
  - **T5 no backup:** `noBackup`, not `wrongSecret`; zero PATCH.
  - **T6 unsupported:** `v9:…` → `unsupported`; zero PATCH.
  - **T7 tamper:** v2 blob with the prefix stripped → `wrongSecret`; v2 blob moved to another user id
    (AAD) → `wrongSecret`; zero PATCH.
  - **T8 interrupted re-wrap:** the PATCH throws `ClientException` → the call throws; the record the
    mock serves is still the v1 fixture and still opens with `'123456'`; device key unchanged; a
    second attempt with a working client writes v2.
  - **T9 guard / no key over an existing backup:** server `public_key` ≠ device public key, backup
    present → `KeyMismatchException`, zero PATCH; server `public_key` empty or equal → one PATCH.
    No call path in `es` other than `generateAndBackupNewKey` and `restorePrivateKey` sends
    `public_key` (asserted over every PATCH captured in this file).
  - **T10 construction pinned:** a fixed (key, salt, nonce, userId) vector decrypts a blob committed
    as a test constant (regression: any change to A2/A3 breaks every existing backup).
- [ ] NEW `test/core/recovery_key_test.dart`: 1,000 generated keys are 25 alphabet characters, parse
  to themselves, and are distinct; a seeded `Random` gives a fixed key; parse accepts lowercase,
  dashes, spaces, `O`/`I`/`L`; rejects `U`, 24 and 26 characters, empty; format gives 5 groups of 5.
- [ ] NEW `test/auth/backup_secret_screen_test.dart` (fake `EncryptionService`, overridden
  `isOnlineProvider`): key step shows 5 groups and the G2 semantics label · **Copy** puts the key on
  the clipboard + toast · **I've saved it** → check step · **Turn on backup** disabled until the field
  parses to the shown key · mismatch copy · **Show the key again** returns the same key · after save
  the clipboard is cleared if it still holds the key · restore malformed input → C6 copy, zero calls ·
  `wrongSecret` → E1 field copy, field kept · `noBackup` / `unsupported` / network / mismatch → their
  E1 copy · **no visible text contains `Exception` or `$`** · `restoredLegacy` → upgrade key step;
  **Not now** → history sync starts, zero backup calls; save → one backup call then sync · change
  mode never calls `restorePrivateKey` · Start Fresh calls `generateAndBackupNewKey` only after the
  check step · offline → key step works, save/restore disabled + **Available online**, fields
  editable · 360×640 at 200% text: key step, check step, restore, upgrade, change with no overflow ·
  reduced motion: no animation controllers running except the parked card.
- [ ] NEW `test/home/backup_upgrade_banner_test.dart`: `legacy` → upgrade copy; `current` → none;
  `none` → no-backup copy; unknown → none; dismissed < 7 days → none.
- [ ] Existing, **must stay green unedited**: `test/offline/encryption_sync_offline_test.dart` (all
  K1/K3 tests, incl. offline restore throws).
- [ ] **Allowed edits to existing tests (2, and only these):**
  `test/auth/restore_overlay_test.dart:20` fake returns `RestoreResult.restored` instead of `true`
  (type change, no assertion touched); `test/grep_gates_test.dart:408` removes `bps` from the Page 7
  `frozen` list (tightens the gate: `bps` now gets the tokens / no-`$e` / no-network-import checks;
  `bps` keeps its `encryptionServiceProvider` import, so that one check, if it trips, gets a named
  exemption for `bps` only).
- [ ] Function-level diff vs HEAD for every K4 symbol: empty.

## Device check list (phase 2; M52 for flows, Redmi S2 for the slow phone; you do every real sign-in)

1. Existing v1 account, uninstall → install → sign in → Restore → old 6-digit PIN (≈ 3.5 s on the
   Redmi, unchanged) → **Make your backup stronger** → Copy → **I've saved it** → paste → **Turn on
   backup** → chats restore with the progress card.
2. Uninstall again → sign in → the recovery key restores at once (typed by hand, lowercase, once with
   spaces); the old PIN shows **That doesn't match…**.
3. Legacy restore → **Not now** → chats restore → Home shows the upgrade banner → tap → **Make a new
   key** → save → banner gone (after the banner refresh).
4. The other phone (set up, never reinstalled, v1): upgrade banner shows → Change → save → banner
   gone; that phone's chats still open (key unchanged).
5. A password manager (Google Password Manager or yours) offers to save the key on the check step.
6. After **Turn on backup**, the clipboard no longer holds the key (paste somewhere).
7. Airplane mode on the key step (works), check step and restore (save/restore disabled with
   **Available online**, fields editable, no crash); mid-save airplane → network copy, retry after
   reconnect works with the same key.
8. Kill the app during **Locking your backup…** → reopen → either the banner is still there (v1) or
   it's gone (v2); a reinstall restores with the PIN (v1) or the key that was on screen (v2).
9. Three wrong keys in a row: same copy each time, no lockout; a 24-character key shows the C6 copy.
10. 200% font on 360dp: key step, check step, restore, upgrade, change, both banners: nothing clipped,
    the key wraps by group. TalkBack reads the key character by character, the field error once.
11. Light, dark, AMOLED captures of the key step, check step, restore, upgrade step, Home upgrade
    banner.
12. As another account, `GET /api/collections/users/records/<your id>` has no `private_key_encrypted`
    / `private_key_salt`; your own read has them (H2 is live; re-check once with the new build).

## Out of scope (do NOT build on this page)

- Key rotation / re-keying the X25519 pair (a backup re-wrap never changes the key), including for
  blobs copied before the hide hook went live.
- Showing an existing recovery key again (decision 11), QR export, printing, passkey-wrapped backups.
- Admin re-wrap / force-setup for the 7-day backup-skip window (existing backlog).
- A server-side recovery service (Signal-style SVR, HSM) or social recovery.
- Moving the backup out of `users` (decision 4 alternative).
- Renaming routes, classes or enums from "pin" (decision 10).
- The restore overlay's layout (Page 7 J, frozen except D10's two strings).

## Diff vs current implementation

| # | Area | Today (file:line) | Spec | Checklist |
|---|---|---|---|---|
| 1 | Secret | user-chosen 6 digits, 6 boxes `bps:89-95, 157-176` | generated 125-bit recovery key (25 chars, 5 groups); legacy PIN still accepted at restore | C1–C7, D1 |
| 2 | KDF | PBKDF2-SHA256 100k `es:151-163, 818, 878` | HKDF-SHA256 (v2, instant); PBKDF2 kept read-only for v1 | A2, A4 |
| 3 | Format | unversioned base64 blob, 32-byte salt `es:841-849` | `v2:` prefix (or version field), 16-byte salt, AAD = user id | A1, A3 |
| 4 | Unknown version | n/a | `unsupported`, no write | A5 |
| 5 | Restore result | `bool`; no-backup = wrong PIN `es:869-872, 942-945` | `RestoreResult` enum; throws offline (unchanged); path chosen by blob | A6, A7, E1 |
| 6 | Change verify | `restorePrivateKey` overwrites the device key, re-publishes, wipes caches `bps:195-197` | makes a new key; no current-secret step; K3 guard | B5, K3 |
| 7 | Write guard | none: any caller can overwrite any backup | one writer, public-key match required | K3, T9 |
| 8 | Legacy users | n/a | upgrade step after legacy restore; Home upgrade banner for set-up phones | B2–B4, D5, D9 |
| 9 | `$e` | `"An error occurred: ${e.toString()}"` `bps:312` | E1 mapper; detail to debugPrint | E1, E2 |
| 10 | Copy | "Backup PIN", "6-digit", "I forgot my PIN", "Start Fresh?" `bps:336, 444-453, 671`, `ps:243` | recovery-key copy D2–D10 | D |
| 11 | Visuals | hand-styled boxes, `AppBar` transparent `bps:463`, Material dialog | Page 7 auth pieces, key block, R14, R20 | D1, D7, D8 |
| 12 | Gates | `bps` frozen out of the Page 7 grep gate `grep_gates_test.dart:408` | `bps` in the gate | E2, Test gates |
| 13 | Saving / deriving copy | "Saving your PIN…" `bps:972`, "Deriving your encryption key…" `bps:42` | "Locking your backup…", "Checking your key…" | D10 |
| 14 | Banner | one copy, "Backup your…" `hs:733` | two copies (no backup / upgrade), grammar fixed | B4, D9 |
| 15 | Server visibility | any signed-in user could list every blob (confirmed live 2026-10-30) | owner-only via enrich hook — **live 2026-10-30** | H1, H2 |
| 16 | Comment | "use a strong PIN" `es:793-799` | v1/v2 + guard | A8 |
| 17 | Start Fresh order | PIN entered, then new key pair | recovery key saved and checked, then new key pair | B8 |

### Decisions (default = recommended; 1 is settled)

1. **SETTLED (user, 2026-10-30): a generated recovery key**, 25 Crockford base-32 characters = 125
   bits, shown as 5 groups of 5. Was: a user-chosen passphrase with four rules (dropped: people pick
   guessable passphrases that pass rules, and with the server copy offline-guessable that's the whole
   risk). Sub-choice default 25 characters; alternative 26 characters = 128 bits with an uneven last
   group (2^125 vs 2^128 makes no practical difference; the X25519 key is ~128-bit itself).
2. **KDF: HKDF-SHA256, no slow KDF**, because a random 125-bit key can't be guessed however fast each
   guess is, and restore becomes instant instead of seconds. Alternative: Argon2id 64 MiB/t3/p4 as
   well (measured 1.83 s on the Redmi S2, 0.45 s on the M52, S11): costs every restore and buys
   nothing against 2^125.
3. **Version marker: a `v2:` prefix inside the existing `private_key_encrypted` field.** No schema
   change, no live write, and blob + version can never disagree (one field). Alternative: a new number
   field `private_key_backup_version` (0/1 = legacy, 2 = recovery key), exact migration in S10 (H3).
4. **DONE LIVE 2026-10-30: owner-only hide hook** (H2). Alternatives were a separate `key_backups`
   collection (data migration; an old build on a fresh install would see "no backup" and could
   generate a key over the account) or leaving it.
5. **No new rate limiting.** The built-in limiter is already on (live, defaults), but one fetch is all
   an offline attack needs, and the app reads `users` records constantly (presence, senders), so a
   tighter limit on that path would hurt the app before it hurt an attacker. Alternative: PocketBase's
   built-in limiter on the `users:view` tag.
6. **After a legacy-PIN restore, the recovery-key steps come next on the same screen, with Not now.**
   Not now restores anyway and leaves the Home banner. Alternatives: **(a)** forced (no Not now);
   **(b)** nothing until the user taps the banner.
7. **Change makes a new key without asking for the old one; the public-key guard (K3) protects the
   backup.** Asking for the old secret only stops someone already holding your unlocked phone, who
   could read your chats anyway, and people who lost the old key would be stuck on it. Alternative:
   ask for the current key or PIN, checked read-only (decrypt and compare, no writes).
8. **Restore: one field that takes either the recovery key or the old PIN**; the blob's version
   decides how the input is read. Alternative: read the record when the screen opens and switch the
   copy and keyboard (adds a loading and an offline state to the screen).
9. **Rebuild the screen on Page 7's auth pieces**, since the six boxes go anyway. Alternative: keep
   today's styling and swap only the boxes.
10. **"Recovery key" in every user-facing string; code names stay.** Alternative: also rename
    routes/classes (pure churn).
11. **The key is never stored on the phone; "Make a new key" replaces it.** Any phone that still
    works can make a fresh key at any time, so losing the written copy is fixable while you still have
    a phone, and no second secret sits in storage. Alternative: keep it in secure storage and add
    **Show recovery key** (Signal's approach; one more secret on the device, which already holds the
    private key it protects).
12. **Upgrade banner dismissable for 7 days** (same as today's backup banner, own setting key).
    Alternative: not dismissable.
13. **Check step: type or paste the whole key.** Proves the place it was saved holds it, and the
    field is the same one restore uses; password managers offer to save it here. Alternatives:
    **(a)** type only the last group (weaker proof, the screen was just showing it); **(b)** no check.
14. **A Copy button, and the clipboard is cleared after a successful save.** Alternative: no Copy
    button (forces writing it down; more typos, more lost keys).
