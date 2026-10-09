# Task 11 Report — Import gate + offline test matrix

Status: **DONE** (standard review tier). BASE 96d5359 (verified HEAD at start).
Commit: `[Offline P6] Import gate + offline test matrix` (see `git log` for SHA; trailer `Co-Authored-By: Claude Code <noreply@anthropic.com>`).

## Part A — Import gate

### Step 0: fcm_debug_helper move
`git mv lib/core/utils/fcm_debug_helper.dart lib/services/fcm_debug_helper.dart`; relative imports `../../data/...` → `../data/...` (2 lines); `lib/main.dart` import → `import 'services/fcm_debug_helper.dart';`. No other importers.

### Step 1: Gate 13
Appended verbatim from brief lines 17–46 to `test/grep_gates_test.dart`. Byte-identical proof: `sed -n '17,46p' brief` vs `sed -n '193,222p' file` → diff empty ("BYTE-IDENTICAL"). Sanctioned list + RegExp untouched (spec §12).

### Step 2: Teeth proof
Temporarily added `import 'package:http/http.dart';` to `lib/features/home/screens/home_screen.dart` → gate 13 FAIL:

```
00:00 +12 -1: no network SDK imports outside sanctioned integration paths [E]
  Expected: empty
    Actual: ['lib/features/home/screens/home_screen.dart']
  network SDK outside sanctioned paths: [lib/features/home/screens/home_screen.dart']
```
(Full: /tmp/g13-teeth-fail.txt). Removed import; `git diff` empty on that file; gate GREEN 13/13 (/tmp/g13-teeth-green.txt).

### Step 3: Gates
- `flutter test`: **131/131 passed** (130 baseline + gate 13; /tmp/t11-full-test.txt: `00:11 +131: All tests passed!`)
- `flutter analyze`: **0 errors, 86 issues** == baseline (Δ0; /tmp/t11-analyze.txt)

## Part B — Offline matrix (emulator-5554)

Full executed checklist: `docs/offline-test-matrix.md`. Captures under `docs/captures/t11-*.png`.

| Row | Scenario | Verdict |
|---|---|---|
| 1 | Airplane render-from-DB + send queues | **PASS** (4 captures) |
| 2 | Kill mid-queue | **PARTIAL** — survival+janitor PASS; reconnect-drain FAIL: 4 ops stuck queued attempts=0; root cause = ledgered T9.7 bodyCache kill-gap (`message_repository_impl.dart:891-894` → `OpSendOutcome.deferred`); server count 0 (no dups); warm-process control send SENT pk7h3ym2ef2l9eu + REST=1 |
| 3 | Long-gap reconnect | **BLOCKED-single-device** — global airplane kills any same-device peer; no 2nd client attached; prepared adb steps in matrix |
| 4 | Key-delay (T7) + terminal banner (T4) | **PARTIAL** — T7 PASS (🔒 list previews + key-wait empty-chat + _BodyPlaceholder); T4 banner BLOCKED-no-natural-solo-trigger (prepared repro in matrix; unit-covered) |
| 5 | Media lifecycle | **PASS** — download ✓, offline cached view ✓, delete→placeholder ✓, reconnect re-fetch ✓ (thumb 2972 B @11:57, full 36965 B @12:08; bubble+viewer render) |

No FCM rows (env FIS_AUTH_ERROR; untouched per N).

## Corrections

None to gate-13 code (verbatim maintained; no leak forced a carve-out). No ledgered deferred minors fixed.

## Concerns (observed, not fixed — for orchestrator/backlog)

1. **Kill-before-drain plaintext gap (LEDGERED T9.7/T2)** — confirmed on-device: 5 queued ops permanently deferred across kill+relaunch+online. Fix direction already ledgered (encryption-at-enqueue).
2. **chat_screen ref-after-dispose StateError** — `_ChatScreenState.dispose` uses `ref.read` (chat_screen.dart:177/230); pre-plan origin (bbb7d82); spams EXCEPTION CAUGHT BY WIDGETS on every chat exit.
3. **groupKeyReadyProvider defunct-element assertion spam** — ~every 4s in logs during session (173+ lines since 11:34:44).
4. **mediaFileProvider caches null** — non-autoDispose FutureProvider: after offline miss returns null, reconnect re-fetches files but warm-process bubble stays placeholder until restart (row 5 note). Candidate: invalidate on mediaChanges / autoDispose.
5. **Stale dao `ready` after external file delete** — dao said `_f` ready+localPath while file missing on disk; fast-path scan recovers on next pipeline run, but state can lie until then.

## Pass proof

- Commit SHA (this commit): `git rev-parse HEAD` after push of this change (see orchestrator handoff).
- Teeth FAIL excerpt + GREEN: above + /tmp/g13-teeth-{fail,green}.txt
- Suite: 131/131. Analyze: 0 errors / 86 issues.
- Matrix: docs/offline-test-matrix.md (rows 1,5 PASS; 2,4 PARTIAL; 3 BLOCKED).
- Captures: docs/captures/t11-row{1,2,4,5}-*.png (11 files).
