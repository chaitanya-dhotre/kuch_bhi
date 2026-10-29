# K1: sign-in made a new key, so Backup PIN restore was skipped (work log)

Date: 2026-10-29.
Scope: finding K1 in the Page 7 spec (`auth.md` section K / `auth.html` S14). This is key code, done by Claude only.

## Status

| Step | Result |
|---|---|
| Static trace confirmed by test | RED 2026-10-29: the DM decrypt pass wrote a new private key into the empty slot. The test asserted the slot stays null; it got `mLMl…=` |
| Fix | `EncryptionService._readKeyPair()` reads only and never creates a key. `getOrDeriveConversationKey` uses it and throws `MissingKeyException` when there is no key. `getOrCreateKeyPair` is now reached only through `getPublicKeyBase64`, from `_initEncryptionKeys` |
| Gates | `flutter test` **423/423** (421 baseline + 2 K1 tests) · `flutter analyze` 0 errors · `git diff --check` clean · `trail check` no conflicts |
| Fresh-context review | Subagent, 2026-10-29: no blocking defects. Its findings are below |
| Device check | **PASS** 2026-10-29, user, M52 (in the K3 builds: an existing account on a fresh install lands on Restore, and the PIN brings history back) |
| Commit | With K3, one commit on `claude/peaceful-nightingale-f2f875` |

## Review findings and what was done

1. **K3 tried, then reverted.** I first switched `_initEncryptionKeys` to the three-way check
   (`tryHasPocketBaseBackup`, where "unknown" means skip generation). The reviewer found that a
   brand-new account hitting a network blip then gets no key at all. The router's no-local-key
   branch still uses the old check, which returns false on any error, so the user lands on Backup
   PIN setup. Setup calls `backupPrivateKey`, which throws "No local private key" until a resume
   or cold start re-runs key init. A proper K3 fix has to cover three places together: init, the
   router's no-local-key branch (P6.3 currently pins `needsSetup` there), and setup when no key
   exists. That is more than one line, so K3 stays a separate task.
2. **Group remove or leave on a device with no key** is a half action: the member is removed but
   the key is not rotated, because rotation now throws. You only reach this with no key on Home
   (Backup PIN setup → Skip). It is still better than before: the old code rotated under a new,
   unpublished key that no member could unwrap. No change.
3. **Private key stored but its public half missing** (a crash between restore's two writes).
   With the read-only getter this state would have decrypted nothing, forever, with no prompt.
   Fixed: `_readKeyPair` now rebuilds the public half from the private seed and writes nothing.
   Covered by the second K1 test.

## Device test (user)

1. Existing account, fresh install, sign in (email, then Google): Backup PIN **restore** appears.
   Enter the PIN; history becomes readable. Logcat shows no `[Enc] Deriving key` lines before the
   restore, and no new key.
2. Register a new account: it still lands on Backup PIN **setup**, and setup succeeds.
