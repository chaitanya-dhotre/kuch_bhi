# Task 12 review — Fake repositories + USE_FAKES dev seam (LIGHT-TIER)

**Range:** `6f293ac..4d94f58` (ledger commit 6f293ac docs-only; gate runs at HEAD `9f4edeb` = 4d94f58 + docs-only ledger commits `git diff --name-only 4d94f58..HEAD` → progress.md + task-12-report.md only, so results transfer to 4d94f58).
**Verifier:** reviewer agent, LIGHT-TIER (checks A–F only).
**Verdict: PASS**

## A. Gates honesty — VERIFIED (own runs)

| Gate | Claim (report) | My run |
|---|---|---|
| `flutter test` | 137/137 | `00:07 +137: All tests passed!` ✓ |
| `flutter analyze` | 86 issues, 0 errors | `86 issues found.`; severity breakdown error=0 / warning=21 / info=65 ✓ |
| `flutter test test/grep_gates_test.dart` (gate 13) | 13/13 | `00:00 +13: All tests passed!` ✓ |

Analyze issues in the 6 changed files: **zero** (`flutter analyze | grep` on main.dart / data_source.dart / fake_message_repository.dart / use_fakes_boot_test.dart → no hits). Count 86 == claimed baseline.

## B. Ruling R1 soundness — VERIFIED

- Fake class at `lib/core/config/fake_message_repository.dart` (182 lines, in lib/ per R1).
- `lib/main.dart` imports it relatively (`core/config/fake_message_repository.dart`) + `message_repository_impl.dart show messageRepositoryProvider`; analyzer 0 errors → import resolves. RED-3 rationale (package/relative URIs cannot address `test/` from `lib/`) is correct Dart semantics.
- `test/fakes/fake_message_repository.dart` is a 1-line barrel `export 'package:kuch_bhi/core/config/fake_message_repository.dart';` → brief's test-side import path `../fakes/…` works unchanged (boot test compiles).
- Gate 13 (`grep_gates_test.dart:198-222`) scans ALL of `lib/` except sanctioned (`infrastructure/`, `services/`, `core/network/`, `main.dart`, `firebase_options.dart`) → `lib/core/config/*` IS scanned, and passes: `data_source.dart` has no imports at all (only `bool.fromEnvironment`), fake imports only `dart:async` + domain/utils — no banned network SDK. Gate suite 13/13 green. R1 does not hide anything from the gate.

## C. Ruling R2 soundness (boot test discriminates) — VERIFIED from code

`test/offline/use_fakes_boot_test.dart:63`: `expect(find.text('Fake Boot Chat'), findsOneWidget)`.

Path analysis for the NO-override case:
1. String `'Fake Boot Chat'` exists only as the test's const seed (`:26-32`) → injected solely via `fake.seedConversation(...)` + `messageRepositoryProvider.overrideWithValue(fake)` (`:42`). Without the override the seeded instance is unreferenced.
2. Default `messageRepositoryProvider` (`message_repository_impl.dart:4378`) does `ref.watch(pocketbaseClientProvider)` → default provider `throw StateError('pocketbaseClientProvider must be overridden in main()…')` (`pocketbase_client.dart:63-65`) → `conversationsProvider` (`conversations_provider.dart:16` → `watchConversations()`) resolves to AsyncError → HomeScreen renders no conversation row.
3. Even if the default repo constructed, no fixture anywhere (lib/, empty `AppDatabase.test()`, no network in flutter_test) can produce the literal `Fake Boot Chat`.

**No path exists where the assertion passes with default providers.** `takeException()==isNull` alone would indeed be vacuous (R2 justification accepted: HomeScreen swallows provider errors into AsyncError) — the seeded-text assertion is the real discriminator, matching the report's RED-2 evidence shape. Not re-run per instructions.

## D. Fake honesty — VERIFIED

- `noSuchMethod` (`fake_message_repository.dart:179-181`) throws `UnimplementedError('FakeMessageRepository: <member> — extend as screens need it')` — loud, names the member. Declared `noSuchMethod` + `implements MessageRepository` routes every unstubbed call there.
- `.demo()` used exactly once in codebase: `lib/main.dart:75`. Tests use plain ctor + `seedConversation` (`use_fakes_boot_test.dart:37-38`). No `.demo()` in `test/`.
- `resyncOnResume()` → no-op (`:164-170`): semantically correct — fake owns no SSE sockets, nothing to resync; caller is `app.dart:32/:58` on every cold start, so a throw would be boot noise, not a detection. Correct fake answer, not a stub of real logic.
- `getIncomingGroupInvites()` → `const []` (`:172-174`): correct — fresh mock-build has zero invites; caller `friend_request_provider.dart:53/:58` badge renders none. Semantically true state, not a mask.
- Scope: `git diff 6f293ac..4d94f58 --name-only` = capture png + `data_source.dart` + `fake_message_repository.dart` + `main.dart` + test barrel + boot test. **No outbox/ingest/decrypt files touched.** ✓

## E. main.dart wiring — VERIFIED

- `lib/core/config/data_source.dart:9`: `const bool useFakes = bool.fromEnvironment('USE_FAKES');` — compile-time const ✓.
- `lib/main.dart`: exactly ONE conditional override added — `if (useFakes) messageRepositoryProvider.overrideWithValue(FakeMessageRepository.demo())` inside the existing overrides list. No other provider overridden in main.
- Production path (USE_FAKES unset): `useFakes` ≡ `false` → collection-if element never evaluated → overrides list identical to pre-diff. The added `show messageRepositoryProvider` import has no side effect (top-level provider decls are lazy). Behavior byte-equivalent ✓.
- Test-side extra override `appDatabaseProvider → AppDatabase.test()` (`use_fakes_boot_test.dart:50`) is sanctioned by ledger carry-3 and confined to the test.

## F. Carries claim (casts NOT hit) — VERIFIED from code

- Casts live in `decryptPassProvider` (`message_body_provider.dart:29`) and `drainStampWireProvider` (`:126`); both are reached only via `messageBodyProvider` → `bodyCoalescerProvider` → `ref.read(decryptPassProvider)`.
- Consumers of that chain: `MessageBodyText` (message_body_text.dart:71) and chat-surface widgets (`message_bubble.dart:78`, `chat_screen.dart:184`). `features/home/` has **zero** references to `MessageBodyText`/`messageBodyProvider`/`decryptPassProvider`.
- Boot path: `ConversationPreviewText` (`message_body_text.dart:137-143`) watches `conversationLastMessageProvider` → queries `appDatabaseProvider` (overridden → `AppDatabase.test()` = `NativeDatabase.memory()`, empty) → `watchSingleOrNull()` → `null` → falls back to `conversation.lastMessagePreview` string → `MessageBodyText` never constructed → cast-bearing providers never read.
- Claim matches code. Casts untouched/softened (grep confirms no cast edits in diff).

## Findings

| # | Severity | Location | Finding |
|---|---|---|---|
| 1 | Minor | `lib/core/config/fake_message_repository.dart:138-142` | `watchPinnedMessages` is one-shot (single yield, completes) while `watchConversations`/`watchMessages` tail their change pings — a pinned-message screen under mock-build renders once and never updates after sends/seeds. Consistent with the "extend as screens need it" policy; not consumed by any screen yet. |
| 2 | Minor (informational) | `lib/features/chat/providers/message_body_provider.dart:29,126` | Ledger carry-1 residual outside light-tier boot path: under `USE_FAKES=true`, a chat-screen body read (e.g. after a local send) reaches the `as MessageRepositoryImpl` cast on the fake. Soft-fail, not crash: the throw lands inside `BodyCoalescer._runAndWait`'s `catch` (`message_body_provider.dart:82-86`) → waiters resolve from cache → placeholder renders + debugPrint. Brief scopes chat restructure as future work against this seam; no action required for T12. |

No Critical. No Important.

## Rulings checked against report claims

- R1 (fake in lib/ + barrel): sound — see B.
- R2 (stronger assertion): sound — see C.
- R3 (`.demo()` in main): matches diff; justified by device-capture requirement (bare ctor = empty home).
- R4 (per-conversation ping instead of shared List controller): code at `:28-29,91-96` — shared controller would cross-talk; implementation is strictly better than brief sketch.
- R5 (resyncOnResume/getIncomingGroupInvites): see D — semantically correct fakes.
- R6 (warmPopLight theme in test): present (`:53`), needed for `ColorTokens` null-assert.
- RED excerpts: plausible per file paths/URI semantics; not re-run per instructions.
- Capture `docs/captures/off_use_fakes_boot.png` exists in diff (111 KB) ✓.

**P (proof):** my runs — test `+137 All tests passed`, analyze `86 issues / 0 errors / 0 in changed files`, gates `+13 All tests passed`.
**N (no-go):** none. Commit nothing — orchestrator commits this review.
