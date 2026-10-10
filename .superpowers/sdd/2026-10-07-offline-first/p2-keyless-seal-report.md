# P2 — Keyless sealed outbox (finisher report)

**Status: COMPLETE (code+spec+report+commit) with ONE STEP NOT EXECUTABLE — device
scenario blocked, see §3.**

Branch `feature/offline-first`. Finisher ran over the previous implementer's
complete-but-uncommitted work (that agent died of an infra error mid-task). Nothing
was redesigned and no logic was changed: gates were green at handoff, this report
re-ran them and they were still green. The only edit made to code-adjacent files was
the spec amendment (§2) — prod/test content is byte-identical to what the orchestrator
already proved (147/147, RED-discipline verified).

Original dispatch expected HEAD `0db71be`; HEAD is now `eaec9d4` (orchestrator added
the P2 attempt-1 fail + salvage ledger commit while this run was in flight). The finisher
commit lands on top of it.

## 1. Gates (re-run by finisher)

| Gate | Command | Result |
|---|---|---|
| Unit/widget suite | `flutter test 2>&1 \| tail -1` | **`All tests passed!` — 147/147** (142 baseline + 5 new `keyless_sealed_outbox_test.dart`) |
| Static analysis | `flutter analyze 2>&1 \| tail -1` | **`86 issues found.` — 0 errors** (`grep -c "error •"` → `0`; all 86 are info/lint) |
| Grep guards | `flutter test test/grep_gates_test.dart` | **`All tests passed!` — 13/13** |

No gate was red, so no gate fix was attempted.

## 2. Spec amendment (micro-amend)

`docs/superpowers/specs/2026-10-07-offline-first-design.md` **§5.2**, one paragraph
appended after "Enqueue atomicity" (same shape as the §5.1 P7 amend): documents the
`device_sealed` `decrypt_state` — keyless enqueue seals under the device-local outbox
key (`device_outbox_key`, `key_id` = `device:<fp>`); §3 forbids durable *plaintext*,
not durable sealed text; a sealed row is visible and unwraps through
`messageBodyProvider`; the drain re-encrypts to the group key (sealed-ciphertext-in →
group-ciphertext + `ready` out, same transaction as the server create) so no
device-sealed row is left at rest after a successful send; logout wipes the slot with
the session.

## 3. Device scenario — NOT COMPLETED (login wall)

**BLOCKED. The app was not in a logged-in chat session; it was on the login screen.**

Per standing instruction — "do NOT hunt for credentials or server login; if the app
shows a login screen, report that and stop the device step, don't fake it" — the
scenario was stopped at step (b) and no part of the R2-kill flow was simulated,
claimed, or faked. What was verified on-device:

- `adb devices` → `emulator-5554  device` (one emulator attached).
- Foreground window at start → `com.chai.kuch_bhi/com.chai.kuch_bhi.MainActivity`
  (app installed and in the foreground, `pm path` confirms `base.apk` present).
- UI dump of the foreground activity shows **only** auth surfaces:
  `Welcome back`, `Sign in to continue`, `Sign In`, `Forgot password?`,
  `Continue with Google`, `Don't have an account?` / `Sign Up`. No conversation
  list, no composer, no 🔒 keyless tiles — so there was nothing to open or send into.
- Screenshot of that state: `docs/captures/p2-device-login-screen.png` (valid PNG,
  160 KB).
- Radio/network: airplane mode is **off** (`settings get global airplane_mode_on` →
  `0`), so nothing was left disabled by this run — no restore is pending (step 6 is a
  no-op).

Consequently captures `p2-keyless-kill-{1-offline,2-relaunch,3-sent}.png` do **not**
exist. The claimed device evidence for this blocker is **the P8 unit suite** (147/147,
which includes the kill/relaunch/drain behavior asserted at the repository and DAO
level, including `FakeSecureStorage` surviving across a rebuilt repo = a process kill),
not an on-device run. Re-running the R2 scenario needs a logged-in device session and
is outstanding for the orchestrator.

## 4. Design read (inherited, unchanged)

Read from the code to describe the finished design (no edits):

- `lib/core/decrypt/device_key_store.dart` — `resolve()` lazily creates/reuses one
  256-bit key in secure storage; `keyId()` = `device:` + `DecryptPass.fingerprintOf`
  (same fingerprint namespace as decrypted rows); `forget()` drops only the in-memory
  copy, leaving the slot to `clearSession()`.
- `decrypt_pass.dart` — `_splitSealed` keeps device-sealed rows out of the
  conversation-key group (they would read as MAC failures); sealed rows resolve their
  own group under the device key; the keyless→`key_missing` writer skips them, and a
  decrypted sealed row is put into the **body cache only** while its at-rest state
  stays `device_sealed`.
- `group_visibility.dart` — `device_sealed` is visible (never in the
  cannot-resolve set) so a just-sent message can't vanish from the user's own chat.
- `message_repository_impl.dart` — enqueue seals under the device key when
  `_tryResolveSendKey` returns null (falling back to the legacy `__pending__` marker if
  the device-key path throws, so this change can only help); `_sendTextOp` unwraps with
  the device key (cache as fallback), and promotes the row to group ciphertext + `ready`
  in the same transaction as the server create.

**Design smells noticed (none fixed, all judged pre-existing/acceptable):**
1. A malformed or replaced secure-storage slot silently regenerates the device key —
   rows sealed with the old key become permanently undecryptable. Documented honestly
   in the file's comment ("that ciphertext is unrecoverable either way"); no re-wrap
   path is possible, so there's nothing better to do.
2. Plaintext remains in `bodyCache` briefly after a device-sealed unwrap (in-memory
   only) — same as the existing C1/own-message behavior, allowed by §3.
3. `keyId: Value(enqueueKey == null ? sealedKeyId : ...)` reads the decision off
   `enqueueKey` rather than `sealedBody`; harmless (they move together) but a slightly
   confusing two-variable expression.

## 5. Files in the commit

Changed: `lib/core/decrypt/decrypt_pass.dart`, `lib/core/utils/group_visibility.dart`,
`lib/infrastructure/repositories/message_repository_impl.dart`,
`test/offline/char_harness.dart`, `test/offline/encrypt_at_enqueue_test.dart`.
New: `lib/core/decrypt/device_key_store.dart`,
`test/offline/keyless_sealed_outbox_test.dart`.
Plus: `docs/captures/p2-device-login-screen.png`, this report, the spec amendment.

Committed as `[Offline P8] Keyless sealed outbox — device-key wrap, kill-survivable,
no plaintext at rest`. No push, no merge.
