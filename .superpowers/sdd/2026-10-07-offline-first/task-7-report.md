# Task 7 report — Cache-policy flip: always commit ciphertext (the :2484 fix)

**Status:** DONE · **Commit:** `2ccf899` (amended once to sweep the
mandated handoff — same subject, no code change) · **Branch:**
`feature/offline-first` · BASE `595efe2`.
**Gates:** full suite **114 pass** (baseline 113 + 1 new) · `flutter analyze`
**0 errors** (88 legacy, unchanged) · offline dir **46 pass** · char 3/3
(test 3 flipped, tests 1-2 byte-untouched).
**Step 5 device capture:** DEFERRED-DEVICE by controller (skipped per
dispatch; see Concern C2 — the brief's group placeholder capture is not
reachable at Task 7 anyway, read path is Task 9's).

## What changed (files)

| # | File | Change |
|---|---|---|
| 1 | `lib/data/local/database/tables/messages_table.dart` | `decryptState` (text, default `'ready'`) + `keyId` (text nullable) |
| 2 | `lib/data/local/database/app_database.dart` (+`.g.dart`) | `schemaVersion 9`, `if (from < 9)` `addColumn` ×2 (AFTER `from < 8`), build_runner regen |
| 3 | `lib/infrastructure/repositories/message_repository_impl.dart` | delete the `:2484` skip block; `_cacheMessagesBatch(List<int>? key)`; `_cacheMsg/_cacheMsgInner(List<int>? key)`; `_ingestDecryptState` helper; `_companionFromRecord` gains `required String decryptState` + preserves `keyId`; SSE/history pass NULL key (was `?? const <int>[]`); rebuild companions (`ssePinDeleteCompanion`, `_syncDeletedForMe`, `_syncStarredMessages`) carry `decryptState`/`keyId`; poll fallback runs `_repairUndecrypted(active)` |
| 4 | `lib/data/local/database/daos/messages_dao.dart` | `cacheDecryptedBody` also writes `decryptState='ready'` (key-arrival heal) |
| 5 | `lib/infrastructure/ingest/ingest_boundary.dart` | DOC ONLY — always-commit bullet in the class doc (brief listed the file; behavior was already key-agnostic — correction R1) |
| 6 | `test/offline/send_fetch_char_test.dart` | test 3 flip only |
| 7 | `test/offline/always_commit_test.dart` | NEW (Step 1) |
| 8 | `.superpowers/…/handoff.md` | `## Task 7` AS-BUILT |

## TDD evidence

**Step 1 — RED stage A (compile):** test written first; run failed
`The getter 'decryptState' isn't defined for the type 'MessagesTableData'`
(×2) — column absent.

**Schema-only (no behavior change) → RED stage B (behavioral):**

```
[Msg] key not ready during fetch — skipping cache: MissingKeyException…
00:00 +0 -1: always-commit… [E]
  Expected: an object with length of <1>
    Actual: []      ← always_commit_test.dart:81 (cache landing)
```

The defect is pinned by the new test itself — the pre-flip production log
line (`skipping cache`) appears verbatim in the RED run.

**Step 3/4 — implement + flip + GREEN:**
- log line now `key not ready during fetch — committing ciphertext`;
- `flutter test test/offline/always_commit_test.dart test/offline/send_fetch_char_test.dart` → **4/4 pass**;
- full `flutter test` → **114 pass**; `flutter analyze` → **0 errors**
  (88 legacy; the intermediate 89th was one `Map<String,String?>` typing
  error in the new decrypt guard, fixed before GREEN).

## Contract delivered (brief Step 1, verbatim both phases)

`always_commit_test.dart` (1 test, 2 phases, non-vacuous both ways):

1. **Fetch with NO key** (seeded without `group_key_g1`, cold
   `repo.watchMessages` → production `_fetchAndCacheMessages`):
   - DB row lands: length 1, `decryptState == 'key_missing'`,
     `decryptedBody == null`, `encryptedBody` byte-identical to the
     server ciphertext;
   - **cursor advanced**: `settings.sync_cursor_g1 == 2026-10-07T10:00:00Z`
     (newest server `created` in the batch) — written inside the same
     boundary txn as the rows.
2. **Re-fetch after key arrives**: seed `group_key_g1` → warm
   `watchMessages` kick → predicate-wait on the drift stream until
   `decryptState=='ready' && decryptedBody != null` → exactly **1** row,
   `serverId == 'srv1'`, body `'always commit'` — id-based upsert, no
   duplicates. A dropped re-fetch fails by predicate timeout; a duplicate
   fails by `hasLength(1)`.

## decrypt_state semantics as built (spec §5.1)

| Situation | Written state |
|---|---|
| decrypt-at-write success (fetch batch, single cache, self-heal, repair) | `ready` |
| key lookup threw → no attempt (fetch, SSE, history-sync) | `key_missing` |
| key present, ciphertext missed / nothing to decrypt (e.g. media stub) | `pending` |
| migration default (legacy rows, create-side optimistic rows) | `ready` (column default) |
| terminal bad MAC | `failed` — **never written at T7** (Task 8's verdict) |

`keyId`: preserved across re-caches, **never populated** — nothing in the
codebase resolves a key *identifier* cheaply today (group keys are only
base64 bytes in storage; the `key_version` record id is read inside
`EncryptionService.getOrFetchGroupKey` and not returned). Left null per
brief; Task 8 owns wiring.

## Char test 3 flip (same commit)

- Title: `…key MISSING still caches (always-commit — Task 7 flipped)`.
- `repo.watchMessages('g1').first` ⇒ **`isEmpty` KEPT**, reason now cites
  Task 9 — `isGroupRowVisible` (design D1) still hides undecryptable
  non-media group rows, so the read stream is legitimately empty at T7.
- NEW cache-layer assertions: `h2.db.messagesDao.watchMessages('g1')` ⇒
  length 1, `decryptState 'key_missing'`, body null. The defect was
  "skips **cache**" — the cache is what must bite.
- Tests 1-2 untouched (git diff shows a single hunk at test 3 only).

## Corrections vs brief (reality rule)

- **R1 — `ingest_boundary.dart` modify = doc-only.** The brief's
  parenthetical describes repo-side behavior; the boundary receives
  fully-built companions and never consults keys (Task 6 contract). A
  forced code edit there would be fake work. Class doc gained the
  always-commit bullet.
- **R2 — char test 3 cannot flip to `rows isNotEmpty`** at the repo
  stream without a read-path edit (Task 9's domain); flip is at the cache
  layer. ⇒ **brief Step 5's device proof ("chat shows rows as
  placeholders instead of an empty list" for a GROUP) is unreachable at
  Task 7 alone** — a keyless group still renders an empty list; the DB
  rows land (proven by tests). Deferred run should either capture a DM
  (null-body → 🔒 bubble already today) or wait for Task 9.
- **R3 — null-key, not empty-key sentinel.** `key ?? const <int>[]`
  made "lookup threw" unrepresentable; `_cacheMsg`/`_cacheMessagesBatch`
  now take `List<int>?`. SSE + history-sync call sites updated (loadMore /
  single-message pass non-null keys — unchanged).
- **R4 — "key present, miss" ⇒ `pending`** (spec §7 literal), not
  `failed`.

## Downstream adaptations (in-scope: policy owns them)

1. **`cacheDecryptedBody` flips state with the body** — otherwise
   `_repairUndecrypted`'s success leaves `key_missing` beside a resident
   body forever.
2. **Poll fallback runs `_repairUndecrypted(active)`** — pre-flip, a
   keyless fetch never wrote the cursor, so the 5s SSE-down poll
   re-delivered the window and healed it on key arrival; post-flip the
   cursor is past those rows, so that heal disappeared. One indexed query,
   no-op without stuck rows. SSE-up-while-open behavior is unchanged
   (pre-flip it never healed there either — reopen only; reopen still
   heals via `_messagesStream`).
3. **Rebuild companions carry `decryptState`/`keyId`** — the boundary's
   delete-then-insert rebuilds from the companion; omission would reset a
   `key_missing` row to the column default `'ready'` (same loss class as
   Task 6 fix I1's `expiresAt`). Covered for `ssePinDeleteCompanion`,
   `_syncDeletedForMe`, `_syncStarredMessages`. Local toggle upserts
   (`insertOnConflictUpdate` with the column ABSENT) preserve by
   construction — verified, not edited.

## Concerns (ledger)

- **C1 — FCM bg insert now lies about state (new symptom of the v9
  default):** `fcm_service.dart:498` writes ciphertext-only rows with no
  `decryptState` ⇒ fresh insert defaults `'ready'` with null body
  (conflict path preserves — column absent from companion). NOT touched:
  outside this brief's files, already ledgered for the spec §4 two-gate /
  Tasks 11-12 audit. Recommended one-liner there: `decryptState:
  Value('pending')`.
- **C2 — device capture deferred + group read path:** see R2.
- **C3 — remaining key-skip sites (by design):** `loadMoreMessages` and
  `fetchAndCacheSingleMessage` still swallow `MissingKeyException` before
  caching (no rows, but also no cursor write — window not lost). Brief's
  scope was the `:2484` `_fetchAndCacheMessages` block only.
- **C4 — `getUndecryptableRows` filters `decryptedBody.isNull()`** —
  works at T7 (includes key_missing rows ⇒ repair heals them); must move
  to `decrypt_state IN ('pending','key_missing')` when T9 drops the body
  column.
- **C5 — T9 forward-carry (Task 2 ruling re-check):** outbound encryption
  point UNCHANGED (`sendMessage` still enqueues plaintext
  `decryptedBody`; drain encrypts — nothing in T7 touches send). What
  makes T9's drop need care: `cacheDecryptedBody` now writes body+state
  (keep the state half); `getUndecryptableRows` filter (C4);
  `_companionFromRecord` still computes `decryptedBody` (T9 removes the
  field, keeps `decryptState`); read-path surfaces keyed on
  `decryptedBody` (`isGroupRowVisible`, search, previews) — pre-existing
  T9 scope, unchanged here.
- **C6 — edge `body-present + key_missing`:** re-fetch with the key gone
  over an already-decrypted row preserves `decryptedBody` but writes
  `key_missing` (literal brief rule). Harmless at T7 (no state readers);
  Task 8 should treat state as authoritative and the body column as
  interim.

## Self-review checklist

- **Completeness:** always-commit (rows+state+cursor) ✓ · migration v9
  + regen ✓ · char-test-3 flip in SAME commit ✓ · new test RED→GREEN ✓ ·
  key-arrival repair checks ✓ · handoff `## Task 7` ✓.
- **Quality:** one derive helper, one new test file, no speculative code;
  boundary edit is honest doc, not fake code.
- **Discipline:** behavior change isolated to `2ccf899` (guard 5); no
  drive-bys — every non-brief edit is a named downstream adaptation with
  an in-situ comment; char tests 1-2 byte-untouched.
- **Testing:** re-fetch idempotency proven (1 row, no dup, predicate
  non-vacuous) ✓ · full suite 114 ✓ · analyze 0 errors ✓ · offline dir 46
  ✓.

# Fix round 1/5 — I1

**Finding (reviewer, I1):** phase-2 idempotency proof partially vacuous —
the pre-fix predicate `decryptState == ready && decryptedBody != null`
is satisfied by the PARALLEL `_repairUndecrypted` pass alone (the warm
kick at the phase-2 boundary runs fetch and repair concurrently). The
original report claim — self-review line "re-fetch idempotency proven …
predicate non-vacuous ✓" and the TDD note "dropped re-fetch fails by
predicate timeout" — was OVERSTATED: with no re-fetch at all, repair
still flips ready+body (verified: under the mutation RED run below the
fetch returns 0 rows and `[Enc] repair pass decrypted 1 stuck row(s) in
g1` still fires, yet the pre-fix predicate would have been satisfied).

**Fix (test-side only, `test/offline/always_commit_test.dart`):**
1. `final phase1Done = DateTime.now();` captured immediately after the
   phase-1 cursor assert, before the Phase-2 comment.
2. Predicate strengthened — third clause:
   `r.updatedAt.millisecondsSinceEpoch > phase1Done.millisecondsSinceEpoch`.
   Only the fetch companion bumps `updatedAt`
   (`_companionFromRecord`, `message_repository_impl.dart:3369`,
   `updatedAt: DateTime.now()`); `_repairUndecrypted` →
   `cacheDecryptedBody` writes `decryptedBody`+`decryptState` ONLY
   (`messages_dao.dart:197-203`) — never `updatedAt`.
   `millisecondsSinceEpoch` (not utc-flag equality): drift returns local
   DateTime (T5 pitfall).
3. Mutation mode added to `alwaysCommitClient` — optional
   `bool Function()? refuseRecords`; when true, `messages/records`
   returns 200 with an empty valid PB list envelope
   `{page:1,perPage:40,totalItems:0,totalPages:1,items:[]}`.
   Armed via a local `neuterReFetch` flag flipped AFTER the phase-1
   asserts (before the phase-2 warm kick) for the RED run only.

**Extra caveat found while gating (reality rule):** the mandated `>`
clause alone made GREEN fail on the first attempt. Drift persists
`DateTime` as unix **SECONDS** (`drift-2.28.2`
`lib/src/runtime/types/mapping.dart:72` — `millisecondsSinceEpoch ~/ 1000`),
so a fetch bump landing in the SAME wall-clock second as `phase1Done`
reads back equal and `>` never holds (first GREEN run: re-fetch logged
`fetched 1 messages (cursor=true)` yet still
`TimeoutException after 0:00:30.000000`). Fix: a
`Future.delayed(Duration(milliseconds: 1100))` between the capture and
the warm kick crosses the second boundary. RED is unaffected either way
— without a fetch write `updatedAt` stays at its phase-1 value, which is
`<= phase1Done` by construction (the phase-1 write precedes the capture).

**RED / mutation proof (final predicate + delay, mutation armed after
phase-1; verbatim tail):**

```
[Msg] _fetchAndCacheMessages — fetched 1 messages (cursor=false)
[Msg] watchMessages EMIT — convId: g1, rowCount: 1
[Msg] _fetchAndCacheMessages — fetched 0 messages (cursor=true)
[Enc] repair pass decrypted 1 stuck row(s) in g1
  TimeoutException after 0:00:30.000000: Test timed out after 30 seconds. See https://pub.dev/packages/test#timeouts
00:30 +0 -1: Some tests failed.
```

Re-fetch dropped (`fetched 0`) → no `updatedAt` bump; repair ran
(`decrypted 1 stuck row(s)` → ready+body) but cannot satisfy the third
clause → 30s predicate timeout. The pre-fix two-clause predicate WOULD
HAVE PASSED in exactly this configuration (ready+body both present via
repair) — that is the vacuous path I1 named.

**Reverted GREEN (mutation flag back to false; client always returns
the record; verbatim tail):**

```
[Msg] _fetchAndCacheMessages — fetched 1 messages (cursor=true)
[Enc] repair pass decrypted 1 stuck row(s) in g1
00:01 +1: All tests passed!
```

**Gates:**

| gate | output |
|---|---|
| `flutter test test/offline/always_commit_test.dart` | `00:01 +1: All tests passed!` |
| `flutter test` (full suite) | `00:05 +114: All tests passed!` |
| `flutter analyze` | `88 issues found.` — 0 errors, count == pre-fix baseline (88) |

**Discipline:** `lib/` untouched; `git diff --stat -- test/offline/char_*`
empty (char tests byte-identical); commit = test file + this report only.
