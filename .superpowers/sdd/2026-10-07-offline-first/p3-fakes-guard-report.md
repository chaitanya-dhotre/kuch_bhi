# P3 — USE_FAKES release guard + gate-comment honesty

Status: **DONE** (all deliverables, all gates green)
SHA: self-referential — this report file is amended INTO the commit, so the
commit cannot embed its own SHA. Authoritative value: `git rev-parse HEAD`
on `feature/offline-first` (unique subject `[Offline P9] USE_FAKES release
guard + gate-comment honesty`; parent records it in the ledger).
Branch: `feature/offline-first` — committed, NOT pushed, NOT merged.
Commit: `[Offline P9] USE_FAKES release guard + gate-comment honesty`

Dict: T=task, G=gate, B=bundle check, fn=assertFakesAllowed.

## 1. Fail-loud guard — location decision (documented as tasked)

- Guard fn lives in **`lib/core/config/data_source.dart`** (co-located with
  `const bool useFakes`) — pure, no framework import:
  `void assertFakesAllowed({required bool release, required bool useFakes})`
  → throws `StateError('USE_FAKES must never be enabled in a release build. ...')`
  when `release && useFakes`.
- Call site: **`lib/main.dart` — first statement of `main()`**, before Marionette
  binding, before Firebase init, before `runApp(ProviderScope(...))`:
  `assertFakesAllowed(release: kReleaseMode, useFakes: useFakes);`
- Fail mode: uncaught StateError on the first line of `main()` → release binary
  dies at boot, ProviderScope never mounts. Matches ruling (assert/StateError
  before ProviderScope).

## 2. Test — RED/GREEN evidence

File: `test/offline/use_fakes_release_guard_test.dart` (7 tests).

**Seam honesty (task-sanctioned option a):** `kReleaseMode`/`kDebugMode` are
compile-time consts pinned by the framework — `flutter_test` always runs
`kDebugMode=true`, so a widget test CANNOT simulate a release context. The pure
`release`/`useFakes` parameter function is the honest seam; `main()` wires it to
the real consts. Stated here as required.

- **RED (raw):** `Method not found: 'assertFakesAllowed'` ×4 sites →
  `Compilation failed ... Some tests failed.`
- **GREEN (raw):** `00:00 +7: All tests passed!`
- Coverage: (1) release+true → throws StateError, message contains
  `USE_FAKES must never be enabled in a release build`; (2) release+false pass;
  (3) debug+true pass (dev seam stays open); (4) debug+false pass;
  wiring pins: main.dart calls fn, call index < `runApp(` index, args are
  `kReleaseMode` + `useFakes` (not hard-coded).

## 3. Bundle check — RAW results (no faking)

Build env: release APK build **succeeded** (no signing blocker) —
`✓ Built build/app/outputs/flutter-apk/app-release.apk (93.2MB)`.

**Default release** (`flutter build apk --release`, USE_FAKES unset = false),
`strings` on `lib/<abi>/libapp.so`, counts per ABI:

```
arm64-v8a  FakeMessageRepository=0  OfflineDemoGroup=0  demo-conv-group=0  guardMsg=0
armeabi-v7a FakeMessageRepository=0 OfflineDemoGroup=0  demo-conv-group=0  guardMsg=0
x86_64     FakeMessageRepository=0  OfflineDemoGroup=0  demo-conv-group=0  guardMsg=0
```

Pipeline control (arm64, proves grep works): `kuch_bhi`=132,
`messageRepositoryProvider`=2, `Creating message record on server`=1 (real repo
present), `fake_message_repository`=0 (source URI stripped).
→ **Fake + demo fixtures fully tree-shaken from default release.**

**Mis-build probe** (`--release --dart-define=USE_FAKES=true`, arm64):

```
FakeMessageRepository=4  Offline Demo Group=1  demo-conv-group=1
fake_message_repository=1  guardMsg=1
guardMsg verbatim: "USE_FAKES must never be enabled in a release build. Rebuild without --dart-define=USE_FAKES=true."
```

→ In the dangerous config the fake IS in the bundle (it must be, seam needs it)
but the **guard string is present verbatim** — guard not stripped, fires first,
ProviderScope never runs. Guard = actual protection for mis-builds; tree-shaking
= protection for default release.

**Honest oddity:** `guardMsg=0` in default release too — const-folding inlines
`fn(release:true, useFakes:false)` → condition folds false → throw+string
dead-code-eliminated. Harmless (a false `useFakes` can never throw); noted, not
hidden. Workspace restored: default release rebuilt after the probe, reverified
`FakeMessageRepository=0 guardMsg=0`.

## 4. Gate-comment honesty (spec §4 amend companion)

`test/grep_gates_test.dart` gate-13 comment adjusted:
- now leads with **network SDK IMPORT LOCALITY only**;
- adds SCOPE paragraph citing **spec §4 amendment 2026-10-10 (user-ratified)**:
  gate does NOT and cannot enforce the single-writer/two-gate domain rule;
  "Do NOT read gate-13 green as 'two-gate rule proven'".
- Gate 13 run: **PASS (test 12/13 in file, suite 13/13)** → `hits` empty →
  `lib/core/config/*` NOT flagged (no network SDKs there; guard fn adds none).

## 5. Gates (all after final edits)

| Gate | Result |
|---|---|
| `flutter test` | **160/160 PASS** (baseline 153 + 7 new) |
| `flutter analyze` | **88 issues / 0 errors** (baseline exact; 0 hits on touched files) |
| `flutter test test/grep_gates_test.dart` | **13/13 PASS** |

## Deviations

1. `distill` CLI broken in this env (`Error: No such device or address (os
   error 6)`, standalone repro) → skill fallback: raw output captured (exact
   values required), distill language kept in prose.
2. Pure-fn seam instead of widget-level release simulation — task-sanctioned
   option (a), reason in §2.
3. `guardMsg=0` in default release — const-fold, disclosed in §3 (not a fail;
   mis-build probe proves the string survives exactly when it matters).
4. No ledger edit — not in P3 deliverables (parent owns ledger).

## Files

- `lib/core/config/data_source.dart` — +guard fn (22 lines)
- `lib/main.dart` — +guard call first-statement (6 lines)
- `test/offline/use_fakes_release_guard_test.dart` — new, 7 tests
- `test/grep_gates_test.dart` — gate-13 comment honesty (16+/5-)
