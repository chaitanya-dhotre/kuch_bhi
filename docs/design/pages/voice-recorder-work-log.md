# Voice recorder (12.6): work log

## Round 1: Astra's implementation, graded 2026-11-03 — **FAIL**

**Gates.** `flutter analyze` 0 errors (new: 2 `unused_element_parameter` warnings for `_ComposerAction`'s
`onLongPressMoveUpdate` / `onLongPressEnd`, ~15 `curly_braces_in_flow_control_structures` infos in `message_input.dart`,
1 in `voice_recorder_panel.dart`). `flutter test` **1091/1091** (1060 at `34e0a95` + 31 new). `git diff --check`
clean. Scope = exactly the briefed files. Frozen files byte-identical to HEAD. No hex colours in the new widgets.
`_RecordingRow`, `_VoicePreviewRow`, `_durationTextToSeconds` gone.

**Why FAIL.**
- **T1 (BLOCK): the widget tests don't test the recorder.** `test/chat/voice_recorder_test.dart` pumps
  `VoiceRecorderPanel` / `VoiceHoldStrip` alone with dummy callbacks and checks labels. Spec cases 3–26 (hold, lock,
  pause/resume calls, send order, permission flow, interruptions, 290/300 s, leaving → draft, failed-send file
  check, TalkBack) drive `MessageInput` with a `FakeRecorder` / `FakeMicPermission` / fake send / temp draft dir;
  none do. Several cases are filler that pass on any panel ("permission flow copy belongs outside the panel",
  "a disabled panel does not expose a second action"). The 24 names match the count, not the content.
- Four code BLOCKs (fresh-context review, each confirmed by Claude in the code):

| # | Sev | Where | What | Fix |
|---|-----|-------|------|-----|
| 1 | BLOCK | `message_input.dart:448-456` `_sendLockedVoice` | Send from locked/paused goes out with `durationSeconds: 0`, `durationText: null` (only `_showVoicePreview` sets them) | set both from `_elapsed` (F3 rounding, min 1) before `_sendVoice()` |
| 2 | BLOCK | `:1482` `onDelete` → `_discardPreview` | ✕ while locked/paused hides the panel but never calls `recorder.cancel()` or cancels the timer: the mic keeps recording invisibly | locked/paused → cancel timer, `await recorder.cancel()`, then reset |
| 3 | BLOCK | `:561-564` `_onPointerDown` | every pointer overwrites `_voicePointerId`: a second finger or palm takes over the hold; the first finger's release is ignored | ignore pointer-down unless idle and not starting |
| 4 | BLOCK (spec gap) | `:638-640` `_loadVoiceDraft` | deletes the draft when `!canSendMessages` at first frame; groups always start false → every group draft deleted on reopen | spec L4 corrected: keep, show when it turns true, delete after a 15 s backstop |
| 5 | BLOCK (missing MUSTs) | panel `:346-351`, `:90-117`; `message_input.dart:1721` | D1: no drag-seek, and the tap fraction uses the panel's width, not the waveform's. J2: **Double tap to record** nowhere. B2: the lock pill is static (no rise, no closed lock, no nudge; `locked` always false) | as spec |
| 6 | SHOULD | `:282-301`, `:608-614` | lifting the finger while `start()` is pending leaves `holding` with no finger down | after a successful hold start, if the pointer is already up → stop |
| 7 | SHOULD | `:448-463`, `:490` | back during a locked send's `stop()`: `setState`/`ref` after dispose throws, the catch deletes the file, so no draft. Pause/✕/Send stay live during the stop | `mounted` guard; don't delete when unmounted; `_stopInProgress` disables the panel |
| 8 | SHOULD | panel `:312` | status line fixed at 18 dp: clipped at 200% text (J4) | `minHeight: 18` |
| 9 | NIT | panel `:358`, `:456` | labels read twice (Semantics + Tooltip + Text) | `excludeSemantics`, `excludeFromSemantics` |
| 10 | NIT | `voice_draft_store.dart` | save deletes the old draft before a move that can fail; stray `.json.tmp` never cleaned | move first, then replace; delete `.json.tmp` in load/delete |
| 11 | NIT | `:1541-1542` | `_ComposerAction` params now unused (analyzer warnings) | leave (frozen widget); or drop them |

**Verified correct by the review:** A1, A3, A4's single mounted `Listener`, A5, A6, A7, B1, B3, B4, C1–C5, D2, D3,
E1–E3, F1–F3 (preview path), G2, G4, H1–H3, I1, I2, I5, I6, I4/L3 (no `ref` in dispose, recorder disposed after
stop), L1, L2, L5, L6, J1, K copy, frozen regions.

**Not run:** nothing on a device.

---

## Fix brief, round 2 (paste as is)

```text
Round 2 fixes for "Voice recorder redesign" (repo /home/chaitanyadhotre/kuch_bhi). Your round-1 code stays; fix
exactly these. Spec: docs/design/pages/voice-recorder.md (section L4 was corrected today; re-read it). Grading
notes with line numbers: docs/design/pages/voice-recorder-work-log.md (table rows 1–10).

CODE (lib/features/chat/widgets/message_input.dart and lib/features/chat/widgets/voice_recorder_panel.dart only,
plus voice_draft_store.dart for row 10):
1. _sendLockedVoice: before _sendVoice(), set _durationSeconds = max(1, round(_elapsed seconds)) and
   _previewDuration = formatMmSs(_durationSeconds).
2. ✕ while locked or paused: cancel the timer, await _recorder.cancel() (catch errors), then reset to idle. ✕ in
   preview stays as is.
3. _onPointerDown: return unless _voiceState == idle and not _starting.
4. L4 as corrected: draft + !canSendMessages → keep it; show it when canSendMessages turns true (didUpdateWidget);
   delete only if still false 15 s after load (one Timer, cancelled in dispose). I5 (true -> false mid-recording)
   unchanged.
5. D1: the waveform seeks on tap AND horizontal drag, using the waveform's own width (LayoutBuilder).
   J2: in TalkBack mode the mic's semantics hint is exactly "Double tap to record" (wrap the mic in Semantics in
   _NormalInputRow; do not change _ComposerAction). B2: the pill rises with the finger 0–80 dp, shows
   Icons.lock_outline at the threshold, and the chevron nudges 4 dp every 1.2 s (parked under reduced motion).
6. A successful hold start whose pointer is already up -> stop at once (goes to preview or the under-1 s path).
7. Guard every setState/ref after an await with `if (!mounted)`; in _sendLockedVoice's catch, do not delete the file
   when !mounted. Disable ✕ / centre / send while a stop is in flight (_stopInProgress).
8. Status line: minHeight 18, not a fixed height.
9. Timer and disc Semantics: excludeSemantics: true; Tooltip excludeFromSemantics: true.
10. saveVoiceDraft: move the new audio in first, then replace the old files; load/delete also remove a stray
    <key>.json.tmp.

TESTS: rewrite test/chat/voice_recorder_test.dart so cases 3–26 of the spec's "Test gates" drive MessageInput itself
(ProviderScope overrides: voiceRecorderFactoryProvider -> a FakeRecorder implements AudioRecorder that records
calls, returns a real temp file path from stop(), and emits on a StreamController<RecordState> from
onStateChanged(); micPermissionProvider -> a fake; voiceDraftDirProvider -> a temp dir; sendMediaMessageProvider ->
a fake notifier that records its arguments and can throw). Use tester.startGesture on the mic key 'mic-action' for
holds and moves, tester.pump(Duration) for time, tester.runAsync for file IO. Each case asserts the behaviour the
spec names (calls on the fake, state on screen, files on disk), never only a label. Add: 32. ✕ while locked ->
cancel() called, nothing recording. 33. a second pointer down during a hold doesn't take it over. 34. draft +
canSendMessages false -> kept; flips true -> Draft shown; still false at 15 s -> deleted. 35. send from locked
passes durationSeconds = the elapsed seconds. Keep the 5 panel-only cases that check real behaviour; delete filler.

DO NOT TOUCH: everything frozen in the spec, test/chat/mic_hint_test.dart, any other existing test.

GATES (paste tails): flutter analyze (0 errors), flutter test (report total), git diff --check, git diff --stat.
Report what you changed per row. Do not commit.
Claude grades the result; do not claim PASS.
```

---

## Round 2: Astra's fixes, graded 2026-11-04 — **FAIL** (much closer)

**Gates, run by Claude.** `flutter analyze` 0 errors (115 issues). `flutter test` **1100/1100** (1060 + 40 new).
`git diff --check` clean. Scope = the briefed files. Frozen files byte-identical to HEAD. No hex colours.

**Tests now bite.** Mutation check in a scratch copy, each round-1 bug put back: no duration on a locked send → cases
9 and 35 fail; ✕ keeps recording → 32 fails; any pointer steals the hold → 33 fails; a held draft dropped at once →
34 fails. T1 is closed.

**Rows 1, 2, 4, 5, 6, 8, 10 fixed. Row 3 and 7 partial. Row 9 fixed but caused R1.**

| # | Sev | Where | What | Fix |
|---|-----|-------|------|-----|
| R1 | BLOCK | panel `_disc`, `:529-533` | **TalkBack can't press any panel control.** `excludeSemantics: true` also drops the `GestureDetector`'s tap. **Proven:** `tester.semantics.tap` on **Pause recording** throws `does not support SemanticsAction.tap`; with the fix, it presses. A TalkBack user reaches `locked` (J2) and can't pause, send or delete, with the mic on. **Caused by Claude's own row 9.** | `onTap: onTap, enabled: onTap != null` on that `Semantics` |
| R2 | BLOCK | `message_input.dart:217`, `:683`, `voice_draft_store.dart:52-54` | Reopening a chat during the dispose save: load in the gap between moving the audio and writing the sidecar sees audio with no marker and deletes it; a load during `await stop()` finds nothing, and a new recording then replaces the draft | per-chat save future, awaited by the load (L3); replace the sidecar by rename, no delete first |
| R3 | SHOULD | `:605-611` | Row 3 only closed once holding: during the 500 ms before the long press fires, any idle pointer takes the id. Palm on the text field → the thumb's release is ignored and the hold runs on with no finger | set id and origin from a `Listener` around the mic only |
| R4 | SHOULD | `:369`, `:449`, `:420-445` | `_stopRecording` / `_stopAndListen` set `_stopInProgress` without `setState`, and pause, resume and discard ignore it. **Stop and listen**, then Resume during the stop → phantom **Recording** with the mic off | `setState`; early return on the flag; re-check the state after `await` |
| R5 | SHOULD (spec) | `:691-697`, spec L4, I5 | The 15 s backstop deletes a member's draft on slow key loading; I5 deletes on any flip | spec changed: only ✕, a send or sign-out remove a draft; I5 saves as a draft |
| R6 | SHOULD | `:159-162` | `_takeShare()` runs before the draft has loaded: a share lands under a draft preview and its upload row is hidden | `await _loadVoiceDraft(); _takeShare();` |
| R7 | NIT | `:640`, panel `:136`, `:731` | closed-lock state unreachable (P1 tests it); pill 8 dp off the mic's centre; locked under 0.5 s then back leaves a temp file | drop the param; `right: 4`; delete the file |
| R8 | test gaps | test 19, 33, 35 | 19 taps with a pointer (missed R1); 33's second finger comes after the hold (missed R3); 35 compares floor with round and passes by luck at 4.2 s; nothing covers rows 6 and 7 through `MessageInput` | see the brief |

**Not run:** nothing on a device.

---

## Round 3: Claude's fixes (user's choice), reviewed 2026-11-04 — **code-level PASS, device check pending**

The user chose Claude over Astra for this round, so the brief at the bottom of this file was never pasted. It stays
as the record of what was asked. Grading = a fresh-context reviewer, not Claude.

**Gates, final:** `flutter analyze` 0 errors (113 issues; new ones are row 11's 2 `_ComposerAction` warnings and the
`curly_braces` infos from round 1). `flutter test` **1117/1117** (1060 + 57). `git diff --check` clean. Frozen files
and every existing test byte-identical to HEAD.

**`trail check`:** 6 flagged, none real. `message_input.dart:694` (a doc comment) and `:718` (the draft retry timer) are
keyword matches; no share is cleared and no failed bubble exists. `message_repository_impl.dart:2149-2152` are in
`34e0a95` (F-b, another session), not this work. Say so in the commit message.

**R1–R7 all fixed** (the review confirmed each). Two departures from the brief:
- **R6 done the other way round.** `await _loadVoiceDraft(); _takeShare();` broke 6 existing share tests: file IO never
  finishes under fake time, and a first-frame share must not wait on disk anyway. `flutter analyze` couldn't show
  this; the full suite did. Instead the share keeps its timing and the draft yields: `_composerBusy` → retry every
  500 ms. The first test for this (40) didn't exercise the order, and its mutant survived. Case 41 does.
- **R5 got simpler than briefed:** with no deletion there's nothing to hold, so the held draft and its timer are gone.
  A draft stays on disk, and sending opening just runs the load again.

**The review of round 3 found, all dealt with:**

| # | Sev | What | Fix | Test |
|---|-----|------|-----|------|
| 1 | BLOCK | **Mic on, invisibly, under the restriction banner.** `canSendMessages` turning false during a pending `start()`: I5 only acts on a non-idle state, so the recording went `locked` with no panel until the 300 s auto-stop. Proven by the reviewer's probe | re-check after `start()`, cancel | 42 |
| 2 | SHOULD | A hold during a pending draft save replaced an unseen draft; a load landing during `start()` overwrote `_tempPath` | no start while a save is pending; `_starting` in `_composerBusy` | 43 |
| 3 | SHOULD | Plugin: after Pause → Resume, a call sends no pause event | no cheap fix; recorded in I1, device check 8 | device |
| 4 | NIT | A native recorder failure was an uncaught error, the UI stuck with the clock running | `onError` → stop, to preview | 44 |
| 5 | NIT | TalkBack long click started then stopped at once with a **Hold to record** toast | no long press in TalkBack mode | 48 |
| 6 | NIT | Dispose during a pending I5 save dropped the first future | saves chain | — |
| 7 | NIT | ✕ during a queued resume left a no-op timer | cancel again after the await | — |

**Coverage added:** a stop that fails on a locked send (45), a pause that fails (46), I5 from a preview (47), dispose
with a retry pending (49).

**Mutation check:** each fix with a test was reverted in a scratch copy, one at a time, and failed its test: R1 → 19,
19b; R2 → 38; R3 → 33b, 33c; R4 → 37; R5 → 39; R6 → 41; row 6 → 36; #1 → 42; #2 → 43; #4 → 44; #5 → 48; the retry
timer → 49.

**Left as is (accepted):** a stop or send in flight when sending closes lands as a preview under the banner, recovered
on leave or when sending opens; a process kill in that window loses it. Row 11's 2 analyzer warnings
(`_ComposerAction` is frozen). A second press on the mic during `_starting`.

**Not done:** the last fixes (the table above) had no second fresh-context review; each is covered by a
mutation-checked test or is a NIT. **Nothing has run on a device.** Open there: `stop()` latency, whether a Resume can
beat a stale PAUSE event (check 22), what a resumed recording captures during a call (check 8), the pill's position
over the mic, the look against the board.

**Device check, 2026-11-04: user PASS on the M52 and the Redmi**, except no vibration on the M52 (B4).

- **First diagnosis, wrong as the whole cause:** `system.haptic_feedback_enabled=0` on the M52 (SM-M526B, Android 13)
  against `1` on the Redmi. It was off, but turning it on changed nothing.
- **Real cause, by test and the phone's vibration log (`dumpsys vibrator_manager`):** with the setting on, the user
  held the mic, swiped to reply, long-pressed and entered a wrong PIN. Only the wrong PIN was felt, and only those
  presses are logged as TOUCH from Kuch Bhi. `HapticFeedback.vibrate()` (`LONG_PRESS`) arrives; `lightImpact`
  (`VIRTUAL_KEY`) and `mediumImpact` (`KEYBOARD_TAP`) never reach the vibrator. Why the phone drops them is not
  established (the M52's vibrator reports no effects and no amplitude control).
- **First fix, replaced:** `HapticFeedback.vibrate()`. It would have worked on both phones but buzzes hard.
- **Final fix, user's choice:** the user found flutter/flutter#73987 (open, device-specific, Samsung reports since
  2021) and `haptic_feedback`. Source read before adding: it calls `Vibrator` directly, past the dropped path. Its
  strategies: primitives if `areAllPrimitivesSupported` → waveform if `hasAmplitudeControl` → legacy timing. The M52
  has only `PRIMITIVE_NOOP` and no amplitude control, so it gets the legacy path: 55 ms on/off, `usage` ignored, so it
  buzzes even with touch vibration off. Pinned **0.6.5**: 0.7+ needs AGP 9, this project is on 8.11.1. Decision 9's
  light haptic stands. Recorder only; other screens = F-d.
- **Gates:** `flutter test` **1119/1119** (+ test 51, a failed haptic leaves the recording alone). Tests 50 and 51 each
  fail when their code is reverted. Release APK builds on AGP 8.11.1.
- **Final device check, 2026-11-04: user PASS**, the mic vibrates on both phones. Committed on the user's word.

---

## Fix brief, round 3 (not used: the user chose Claude; kept for the record)

```text
Round 3 fixes for "Voice recorder redesign" (repo /home/chaitanyadhotre/kuch_bhi). Your code stays; fix exactly these.
Spec: docs/design/pages/voice-recorder.md — re-read B2, I5, L3 and L4, all changed today. Grading table with line
numbers: docs/design/pages/voice-recorder-work-log.md, rows R1–R8. Row R1 came from a mistake in the last brief.

CODE:
R1. voice_recorder_panel.dart _disc: on the Semantics that has excludeSemantics: true, add onTap: onTap and
    enabled: onTap != null. excludeSemantics removes the GestureDetector's action, so without this TalkBack can't
    press the control.
R2. message_input.dart: `static final Map<String, Future<void>> _draftSaves = {};`. dispose stores its save future
    under the conversation id and removes it when complete. _loadVoiceDraft awaits that future first.
    voice_draft_store.dart saveVoiceDraft: move the audio in, write <key>.json.tmp, rename it over <key>.json. Never
    delete the old sidecar first.
R3. Set _voicePointerId and _holdOrigin from a Listener around the mic only (in _NormalInputRow, onPointerDown passed
    down), not from the panel's Listener, which keeps move/up/cancel. _ComposerAction stays untouched.
R4. _stopRecording and _stopAndListen set _stopInProgress inside setState. _pauseRecording, _resumeRecording and
    _discardVoice return early while it is true. After their await, pause and resume do nothing further unless the
    state is still the one they started from.
R5. Spec L4 and I5: remove _draftExpiryTimer and the deletion. Draft + !canSendMessages -> keep _heldDraft, show it
    when canSendMessages turns true. canSendMessages turning false during a recording or a preview -> save as the
    chat's draft exactly as dispose does (share one method), back to idle. Only ✕, a successful send or sign-out
    remove a draft.
R6. The post-frame callback in initState becomes async: await _loadVoiceDraft(); then _takeShare().
R7. Drop VoiceHoldStrip's `locked` param and P1's expectation of it. Lock pill right: 4. Dispose in locked with a
    recording under 0.5 s deletes the stopped temp file.

TESTS (test/chat/voice_recorder_test.dart; give FakeRecorder an optional Completer gate on start() and on stop()):
- 19 rewritten: TalkBack path end to end. tester.semantics.tap on the mic, then on Pause recording, Resume recording
  and Send voice note, using find.semantics.byLabel. Assert the fake's calls. Also ✕ by semantics on a second run.
- 25 rewritten: a draft with canSendMessages false is kept at 60 s (both files exist).
- 33 add: a second finger down and up on the text field during the first 300 ms of the press; the hold still starts,
  and lifting the first finger stops it.
- 35: drive the clock to 4.6 s and expect durationSeconds 5.
- 36 new: release during a gated start() -> stop called once the start completes.
- 37 new: Stop and listen with a gated stop(), Resume tapped meanwhile -> ends in preview, resume not called, no
  amplitude calls afterwards.
- 38 new: widget removed while locked with a gated stop(), a new MessageInput for the chat pumped, gate released ->
  Draft shown, both files exist.
- 39 new: canSendMessages flips false while locked -> draft saved, idle; flips true -> Draft shown.
- 40 new: a draft plus a share handed to the chat -> preview shown, the share not run; ✕ -> the share runs.
Every case asserts calls, state or files, never only a label.

DO NOT TOUCH: everything frozen in the spec, _ComposerAction, test/chat/mic_hint_test.dart, any other existing test.

GATES (paste tails): flutter analyze (0 errors), flutter test (report total), git diff --check, git diff --stat.
Report what you changed per row. Do not commit.
Claude grades the result; do not claim PASS.
```
