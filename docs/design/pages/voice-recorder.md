# Voice recorder: hold, lock, pause, listen, send (acceptance checklist)

Date: 2026-11-03. Backlog **12.6**. Visual ground truth: **`docs/design/pages/voice-recorder.html`** (sections S1–S8,
numbered; S2 = the flow, S3 = the hold strip, S4 = the recording panel, S5 = the preview panel, S6 = the waveform,
S7 = mic permission, S8 = interruptions and diff summary).
Authority: `docs/design/00-foundation.md` (tokens/laws, colour laws C1–C4) → `docs/design/10-registry.md` (shared
pieces) → this checklist. Page letters A–L are page-local; decisions are numbered (bottom). Line refs as of
`244f568`: `mi` = `lib/features/chat/widgets/message_input.dart`, `vb` =
`lib/features/chat/widgets/voice_message_bubble.dart`, `cp` = `lib/features/chat/providers/chat_provider.dart`,
`mr` = `lib/infrastructure/repositories/message_repository_impl.dart`, `cs` =
`lib/features/chat/screens/chat_screen.dart`, `rec` = the `record` 6.2.0 package in the pub cache
(`lib/src/record.dart`), `reca` = `record_android` 1.5.1, `recp` = `record_platform_interface` 1.5.0.

**The user's reference.** A centred **Voice note** title, a waveform, a big timer (01:14) and three round controls:
cancel ✕ / record / send. Accent only as a fill, no purple (foundation C1/C2).

**Starting point (audited 2026-11-03, `trail ask/callers` + `sed -n` ranges + the record sources in the pub cache;
no code run on a device, no live PocketBase read).**

**Facts, confirmed in code (not assumed).**
1. **Hold only, no lock, no pause, no waveform.** `enum _VoiceState { idle, recording, preview }` (`mi:35`). A long
   press on the mic starts (`mi:1373`), release stops (`mi:1375`), a drag left past 80 px cancels (`mi:1132`,
   `mi:1172`). A quick tap shows the tooltip **Hold to record** above the mic (`mi:1372`, `_ComposerAction.tapHint`
   `mi:1197-1219`); `test/chat/mic_hint_test.dart` pins both the tooltip and the semantics hint.
2. **The recording strip** (`_RecordingRow`, `mi:1389-1454`) = a pulsing mic and the timer, both in `t.error`, and
   **Slide to cancel** / **Release to cancel**. The timer in `t.error` at 16 px fails 4.5:1 on light (the group
   screens learning: error red is 3.91:1).
3. **The preview row** (`_VoicePreviewRow`, `mi:1458-1631`) = ✕ (Discard, `t.error` icon), a pill with play/pause and
   a 3 px `LinearProgressIndicator`, and an accent send disc. Its play disc is accent-on-accent-tint (accent as
   ink, against C2's "accent only as fill" ask).
4. **The clock is a 1 s counter** (`Timer.periodic(1 s)`, `mi:232-239`), auto-stop at
   `AppConstants.maxVoiceMessageSeconds = 300` (`app_constants.dart:16`). The sent duration comes from that counter
   (`_durationTextToSeconds`, `mi:364`).
5. **Config** = `RecordConfig(encoder: AudioEncoder.aacLc)` (`mi:215`): the defaults are 128 kbps, 44.1 kHz,
   **2 channels** (`recp` `record_config.dart:80-82`), ~4.8 MB for 5 minutes, from one phone mic.
6. **The plugin already has everything this page needs.** `pause()` / `resume()` / `isPaused()` (`rec:106-130`),
   `getAmplitude()` (`rec:158`) and `onAmplitudeChanged(interval)` (`rec:219`, itself a `Timer.periodic` calling
   `getAmplitude`, `rec:233-250`), `onStateChanged()` (`rec:191`), `cancel()` = stop and delete the file (`rec:95`).
   On Android the amplitude is dBFS: `20·log10(max/32767)`, floor **-160** (`reca` `PCMReader.kt:197`, `:23`).
7. **Calls and other apps already pause it.** The default `audioInterruption: AudioInterruptionMode.pause`
   (`recp` `record_config.dart:89`) requests audio focus and pauses on any focus loss (a call, an alarm, another
   recorder; `reca` `AudioRecorder.kt:237-245`), and `onStateChanged` reports it. Nothing listens today.
8. **The app going to the background is not handled.** `MessageInput` has no lifecycle hook; Android stops feeding a
   background app's mic (no foreground service), so a hold that outlives a Home press records silence.
9. **Permission.** `Permission.microphone.request()` on every press (`mi:202`); not granted → toast **Microphone
   permission denied** (`mi:205`). The first press opens the system dialog while the finger is down; the release
   lands while the dialog is up, and if the user grants, recording then starts with no finger on the mic.
10. **Leaving the chat leaks the file.** `dispose` (`mi:160-170`) disposes the recorder but deletes neither a
    recording in progress nor an unsent preview (both sit in the temp folder).
11. **A voice note never carries the reply.** `SendMediaMessage.send` has no reply parameter (`cp:179-189`); the
    reply bar hides while recording (`mi:1113`) and stays set after a voice send.
12. **Offline send already works.** `sendMediaMessage` writes the row and the blob (`uploadPending: true`,
    `mr:1741`) before an unawaited upload; offline, `_resumeMedia` (`mr:2152-2174`) uploads it on reconnect, and the
    bubble shows `MediaUploadControl` (`vb:245`). A rejection before the row lands keeps the preview with **Couldn't
    send voice note. Try again.** (`mi:357`, the "send that fails gives the text back" learning).
13. **App lock covers on `hidden`** (`app.dart` lifecycle, app lock F). Recording state lives in `MessageInput`, under
    the lock overlay, so nothing about the lock needs changing here.
14. **Back** is the chat's own `PopScope(canPop: false)` (`cs:851-860`): it exits selection mode or pops at once (the
    "back must never wait" learning). A `PopScope` inside `MessageInput` can't stop that pop.
15. **A send moves the file.** `sendMediaMessage` hands the file to `mediaBlobStore.registerLocal`, which **renames**
    it into the blob store (`media_blob_store.dart:465-468`); if the send then throws, the moved copy is deleted
    (`mr:1756-1762`). So after such a throw the preview's file can be gone, and today's "keep the preview so it can be
    resent" (`mi:355`) would resend a missing file (G2 fixes it).
16. **Logout wipes cached media** through `wipeMediaCache()` (`media_blob_store.dart:71-81`, called at
    `auth_repository_impl.dart:392`): the temp-folder `media_clear` and `share_in` folders. Nothing in the app's
    documents folder is wiped there except the database.

**Plugin choice.** `record` 6.2.0 (already, `pubspec.yaml:53`) for recording, pause/resume and the amplitude;
`just_audio` (already) for the preview; `permission_handler` (already) for the mic and `openAppSettings()`. The
waveform is a `CustomPainter` fed by `getAmplitude()` (`audio_waveforms` and friends bring a second recorder; we only
need bars). **One new package, added 2026-11-04 at the user's request:** `haptic_feedback`, pinned to exactly **0.6.5**
because 0.7+ needs AGP 9 and this project is on AGP 8.11.1 (B4). Don't widen the pin before upgrading AGP.

**Routing.** Spec: Claude (this session). Phase 2: the user pastes the **Astra brief** (bottom); Claude grades with a
fresh-context reviewer, never the implementer.

**Pass criteria (page complete when):** all MUSTs ✓ · `flutter analyze` 0 errors · `flutter test` green (baseline
re-run at phase 2 start, plus the new tests; **no existing test edited**, `mic_hint_test.dart` included) · test-gate
files below green · `git diff --check` clean · `trail check` clean · frozen diff vs HEAD empty · fresh-context review
with no open BLOCK, findings in `voice-recorder-work-log.md` · device captures of the device-check list · user device
PASS (no commit without it).

**Spec status: user PASS 2026-11-03; device PASS 2026-11-04 on the M52 and the Redmi; shipped.** Every deferred decision
= its default, except decision 8, which the user set: leaving a chat keeps the recording as a **voice draft** (section
L, added 2026-11-03). Grading history: `voice-recorder-work-log.md`.

**Live PocketBase.** None needed. No schema, rule or hook change (decision 7's alternative would need one).

**Status key:** `[x]` implemented AND verified by code/tests or recorded device evidence; `[ ]` pending.

---

## ⛔ Frozen (read first: a breach here is an automatic FAIL)

`mr` (send, upload, resume, retry), `media_upload_service.dart`, `cp`, the outbox and its senders, `vb` (the bubble
is not redesigned here), `message_bubble.dart`, `cs`, `app.dart`, everything under `lib/features/app_lock/`, the
text send path in `mi` (`_send`, drafts, reply bar), the share-in hold in `mi` (`_takeShare` / `_maybeRunShare`;
only `_composerBusy`'s voice clause may change), every upload row in `mi` (album, image, video, document),
`_ComposerAction` except the one new optional `onTap`-while-accessible wiring (J2), every existing test.

**Unfrozen by this page, and only these:**
- `mi`: the voice part only: the state enum, the recording fields and helpers (`mi:69-80`, `mi:199-368`), `dispose`'s
  voice lines, the mic wiring in `_NormalInputRow` (`mi:1367-1378`), the voice branches of `build`
  (`mi:1113`, `mi:1124-1144`), and `_RecordingRow` + `_VoicePreviewRow` (**deleted**, replaced by the files below).
- NEW `lib/features/chat/widgets/voice_waveform.dart`: `VoiceWaveform` painter widget + two pure functions (E).
- NEW `lib/features/chat/widgets/voice_recorder_panel.dart`: `VoiceHoldStrip`, `VoiceRecorderPanel` (C, D) and the
  preview player state.
- NEW `lib/features/chat/providers/voice_recorder_providers.dart`: two test seams (A6).
- NEW `lib/features/chat/voice_draft_store.dart`: the voice draft files (L1–L3).
- `lib/infrastructure/repositories/auth_repository_impl.dart`: ONE line, `await wipeVoiceDrafts();` right after
  `await wipeMediaCache();` (`:392`), plus its import (L6). Nothing else in the file.
- `docs/design/10-registry.md`: one new row **C20** (A7).

---

## A. States and the flow (S2; decisions 1–3)

- [ ] **A1 MUST** `enum _VoiceState { idle, holding, locked, paused, preview }` replaces `mi:35`. `_composerBusy`
  (`mi:410`) stays true in every state but `idle`, so a held share still waits (12.1).
- [ ] **A2 MUST The flow** (decisions 1–3):
  - idle → **long press on the mic** → `holding` (recording, finger down; B).
  - `holding` → release → stop → `preview` (D). Under 1 s → nothing kept, the existing **Hold to record** toast
    (`mi:273`, unchanged).
  - `holding` → finger moves **left** ≥ 80 dp → **Release to cancel**; release there → `recorder.cancel()`, back to
    idle, nothing kept.
  - `holding` → finger moves **up** ≥ 80 dp → `locked` at once (no release needed; a light haptic), the finger may
    lift and recording goes on.
  - `locked` → centre **pause** → `paused`; `paused` → centre **resume** → `locked`.
  - `locked` / `paused` → **send** → stop, then send at once (no preview).
  - `paused` → **Stop and listen** → stop → `preview`. (An AAC file can't be played until it is stopped, so
    listening ends the recording; the button says so by its name.)
  - `locked` / `paused` / `preview` → **✕** → cancel or delete the file, back to idle.
  - `preview` → **send** → send; → **✕** → delete.
  - leaving the chat in `holding` (1 s or more), `locked`, `paused` or `preview` → stop and save as this chat's
    **voice draft** (L); opening the chat again → `preview` of the draft.
- [ ] **A3 MUST** Starting a recording unfocuses the text field (keyboard down). The typed draft stays as it is and
  comes back with the composer.
- [ ] **A4 MUST The hold gesture survives the row swap.** The pointer that started the hold is tracked by ONE
  `Listener` wrapping the whole floating panel's child in `MessageInput.build` (it stays mounted while the mic row is
  swapped for the strip): `onPointerMove` gives the offset from the press point, `onPointerUp` /
  `onPointerCancel` = release. The mic's `onLongPressStart` only starts; its `onLongPressMoveUpdate` /
  `onLongPressEnd` wiring goes. Pointers other than the one that started the hold are ignored.
- [ ] **A5 MUST Config** (decision 5): `RecordConfig(encoder: AudioEncoder.aacLc, numChannels: 1, bitRate: 64000)`;
  every other field at its default (`audioInterruption: pause` stays, fact 7). File name and folder as today
  (`mi:210-212`).
- [ ] **A6 MUST Test seams** in `voice_recorder_providers.dart`:
  `final voiceRecorderFactoryProvider = Provider<AudioRecorder Function()>((_) => AudioRecorder.new);` and
  `final micPermissionProvider = Provider<MicPermission>((_) => const MicPermission());` where `MicPermission` has
  `Future<PermissionStatus> status()`, `Future<PermissionStatus> request()` and `Future<bool> openSettings()`
  (thin calls to `Permission.microphone.status/request` and `openAppSettings()`), and
  `final voiceDraftDirProvider = Provider<Future<Directory> Function()>((_) => getApplicationDocumentsDirectory);`
  (L2). `MessageInput` creates its recorder from the factory and reads the other two in `initState` (`ref.read`).
  Tests override all three; nothing else uses them.
- [ ] **A7 MUST** Registry row **C20** `VoiceWaveform(levels, {progress?, live})` + `waveLevel(dbfs)` +
  `bucketLevels(levels, bars)` | `lib/features/chat/widgets/voice_waveform.dart` | the one waveform; bars 3 dp wide,
  2 dp gaps, radius 1.5, min height 3 dp; colours from tokens only (E3); `ExcludeSemantics`. Plus the panel:
  `VoiceRecorderPanel` / `VoiceHoldStrip` | `voice_recorder_panel.dart` | the composer's voice states (12.6).

## B. The hold strip (S3)

- [ ] **B1 MUST** While `holding`, the composer row (`_NormalInputRow`) is replaced by `VoiceHoldStrip`, same 64 dp
  height, inside the existing floating panel: an 8 dp `t.error` dot (pulses with the existing `_pulseAnim`;
  static under reduced motion), the timer (16/22 w600 **`t.ink`**, `FontFeature.tabularFigures()`), a live
  `VoiceWaveform` (`Expanded`, 28 dp high), then **‹ Slide to cancel** (13/18 `t.inkSoft`) which reads **Release to
  cancel** past the cancel threshold, and at the end the 48 dp mic disc (`t.accent` fill, `t.onAccent` icon) drawn
  under the finger at 1.15× scale (1× under reduced motion).
- [ ] **B2 MUST The lock pill.** A 40 × 88 dp pill directly above the mic disc, overlapping the chat (a `Stack` with
  `Clip.none`; the panel's height doesn't change): `t.surface` fill, 1 dp `t.line` border, radius pill, the
  `T1` card shadow; inside, `Icons.lock_open_outlined` (20, `t.inkSoft`) over `Icons.keyboard_arrow_up` (20,
  `t.inkSoft`). It rises with the finger (clamped 0–80 dp); at the threshold the state is `locked` and the panel
  opens, which is the cue (a closed-lock icon would never get a frame). The chevron nudges up 4 dp every 1.2 s while idle in the pill (parked under reduced
  motion). `ExcludeSemantics` (the hold path is not a TalkBack path; J2 is).
- [ ] **B3 MUST** Dragging moves the mic disc with the finger: x clamped to [-120, 0], y to [-80, 0]. Only one axis
  wins: once |dx| > 16 the vertical offset is ignored for the rest of the hold, and the other way round (no diagonal
  half-lock / half-cancel).
- [ ] **B4 SHOULD Haptics** (decision 9): `Haptics.vibrate(HapticsType.light, usage: HapticsUsage.touch)` from
  `haptic_feedback` (pinned, see Plugin choice) on start, on lock, and on crossing the cancel threshold (once each
  way), errors swallowed. Not Flutter's `lightImpact` as first specced: the M52 drops it and `mediumImpact` before the
  vibrator, with touch vibration on (device test and its vibration log, 2026-11-04; flutter/flutter#73987). The
  package calls the vibrator directly. On the M52 (no primitives, no amplitude control) that's its legacy path: a
  plain 55 ms buzz that ignores `usage`, so it fires even with touch vibration off, and light, medium and heavy feel
  the same.

## C. The recording panel: `locked` and `paused` (S4; the user's reference)

- [ ] **C1 MUST** In `locked`, `paused` and `preview` the floating panel's child is `VoiceRecorderPanel` (not a
  sheet, not a route: the chat stays visible and scrolls above it). Padding 16, 12 on top. Top to bottom:
  1. **Voice note**, 16/22 w600 `t.ink`, centred, `Semantics(header: true)`.
  2. A status line, 13/18 `t.inkSoft`, centred, 18 dp tall even when empty: `locked` = 8 dp `t.error` dot +
     **Recording**; `paused` = **Paused**; last 10 s = **10 seconds left** (replaces Recording); `preview` = empty,
     or **Draft** when the preview is a saved voice draft (L4).
     `Semantics(liveRegion: true)`.
  3. `VoiceWaveform`, full width, 48 dp high, 12 dp above and below.
  4. The timer, 28/34 w700 `t.ink`, tabular figures, centred, `m:ss` (decision 10).
  5. The controls row, centred, 32 dp gaps: **✕** 56 dp disc (`t.surface2` fill, `Icons.close` 24 `t.ink`) · the
     centre 72 dp disc (`t.accent` fill, 32 dp icon `t.onAccent`) · **send** 56 dp disc (`t.accent` fill,
     `Icons.send_rounded` 24 `t.onAccent`). Every disc has a 48 dp+ hit area, a tooltip and a semantics label (J3).
  6. `paused` only: an R3 text button **Stop and listen** under the controls (min-h 40), `t.ink` label.
- [ ] **C2 MUST The centre disc**: `locked` = `Icons.pause` (**Pause recording**); `paused` = `Icons.mic`
  (**Resume recording**); `preview` = `Icons.play_arrow` / `Icons.pause` (**Play voice note** / **Pause voice
  note**), a `BusySpinner` (`color: t.onAccent`) while the file loads.
- [ ] **C3 MUST** Pause = `recorder.pause()`, the clock and waveform stop; resume = `recorder.resume()`, both go on.
  A pause or resume that throws leaves the state as it was and shows **Couldn't pause the recording.** /
  **Couldn't resume the recording.**
- [ ] **C4 MUST Accent only as fill.** The two accent discs (and B1's mic) are the only accent on the page. No accent
  text, icon, stroke or bar; `t.error` only for the 8 dp recording dot (status, C2). The old `t.error` timer and
  ✕ icon go.
- [ ] **C5 MUST** The panel enters with a `motionBase` fade (no slide, no size animation); reduced motion = no fade.

## D. The preview panel (S5)

- [ ] **D1 MUST** Same panel as C1 with status line empty, the centre disc = play/pause, and the waveform = the whole
  recording (E2) drawn as the player: bars left of the play position `t.ink`, the rest `t.inkFaint`. Tap or
  horizontal drag on the waveform seeks (`player.seek`); a seek before the first play loads the file first.
- [ ] **D2 MUST** The timer shows the total (`1:14`) until the first play, then the position (`0:12`); at the end it
  goes back to 0 and shows the total again (today's completed → seek 0 + pause, `mi:1498-1501`).
- [ ] **D3 MUST** The preview player is a `just_audio` `AudioPlayer` owned by the panel's state, set from the file on
  the first play (as `mi:1516-1524`); a load error → **Couldn't play the recording.** toast, state stays `preview`
  (send still works). While sending, ✕ / play / seek are disabled and the send disc shows a `BusySpinner`
  (`t.onAccent`).

## E. The waveform (S6; decision 6)

- [ ] **E1 MUST Source.** One `Timer.periodic(100 ms)` while `holding` / `locked` (cancelled on pause and stop):
  each tick does `elapsed = base + timer.tick × 100 ms` and appends `waveLevel((await recorder.getAmplitude()).current)`
  to `_levels` (the same call `onAmplitudeChanged` makes inside the plugin, `rec:233-250`; one timer instead of a
  timer plus a stream, and it runs under the test clock). A tick whose `getAmplitude` throws appends nothing. On
  resume `base` = the elapsed so far and a new timer starts.
- [ ] **E2 MUST Pure functions** (unit-tested):
  - `double waveLevel(double dbfs)` = `((dbfs + 50) / 50).clamp(0.06, 1.0)`; NaN or infinite → 0.06. So -160 (the
    floor) and anything quieter than -50 dBFS draw the minimum bar, 0 dBFS a full one.
  - `List<double> bucketLevels(List<double> levels, int bars)`: `bars ≤ 0` → empty; fewer levels than bars → the
    levels as they are; else split into `bars` equal buckets and take each bucket's **max** (peaks stay visible).
- [ ] **E3 MUST Drawing.** `VoiceWaveform(levels, {double? progress, bool live = false})` with a `CustomPainter`:
  bar count = `(width + 2) ~/ 5`; bar height = level × height (min 3 dp), centred vertically. `live` = the last
  `count` levels, newest at the right edge, bars `t.ink`; not live = `bucketLevels(levels, count)` spread over the
  width, `progress` (0–1) splits `t.ink` / `t.inkFaint`; `progress == null` = all `t.ink`. `shouldRepaint` compares
  length, progress and colours. Wrapped in `RepaintBoundary` + `ExcludeSemantics`.
- [ ] **E4 MUST** At 10 samples a second, 5 minutes = 3,000 doubles; nothing is stored or sent. The waveform stays on
  this phone (decision 7): the bubble the other side sees is unchanged.

## F. Timer and maximum length (decision 4)

- [ ] **F1 MUST** The clock is E1's elapsed (100 ms resolution); paused time doesn't count. Shown as
  `formatMmSs(elapsed.inSeconds)` (`format_utils.dart:7`).
- [ ] **F2 MUST** At 290 s the status line reads **10 seconds left** (C1.2; the hold strip has no status line, so a
  hold shows nothing extra). At `AppConstants.maxVoiceMessageSeconds` (300 s, unchanged) recording stops by itself →
  `preview`, toast **Voice notes can be up to 5 minutes.**
- [ ] **F3 MUST** The duration sent = `elapsed.inSeconds` rounded to the nearest second (min 1);
  `durationText` = `formatMmSs` of it. `_durationTextToSeconds` (`mi:364-368`) is deleted.

## G. Sending, online and offline

- [ ] **G1 MUST** Send calls `sendMediaMessageProvider.notifier.send(conversationId, mediaType: 'voice', mediaFile,
  durationSeconds, durationText)` exactly as `_sendVoice` does today (`mi:338-346`). From `locked` / `paused` it
  first stops (`recorder.stop()`); a stop that throws → **Couldn't save the voice note.** toast, the file deleted,
  back to idle.
- [ ] **G2 MUST** Success → idle, panel gone, and the voice draft's sidecar deleted if this was a draft (L5). A throw
  (rejected before the row landed) → toast **Couldn't send voice note. Try again.** (today's copy, `mi:357`), then:
  the file still exists → stay in `preview` with it; the file is gone (the send moved and then deleted it, fact 15)
  → idle, and a draft's sidecar deleted too.
- [ ] **G3 MUST Offline needs nothing new**: the row and blob are written first and uploaded on reconnect (fact 12).
  Recording, pause, preview and send all work in airplane mode; the bubble shows its usual upload state.
- [ ] **G4 MUST** The temp file is never deleted by the panel after a successful send (the repository owns it from
  then, `mi:336-337`).

## H. Mic permission (S7)

- [ ] **H1 MUST** On the long press, check `micPermission.status()` **without** requesting first:
  - granted → start (`holding`).
  - not yet asked / denied (not permanently) → `request()`, **never start recording from this press**. Granted →
    toast **Microphone on. Hold to record.** Denied → toast **Kuch Bhi needs the microphone to record voice notes.**
    (`error: true`).
  - permanently denied or restricted → R20 `showConfirmDialog`: title **Microphone is off**, body **Turn on the
    microphone for Kuch Bhi in your phone's settings to record voice notes.**, confirm **Open settings**, cancel
    **Not now**; confirm → `openSettings()`.
- [ ] **H2 MUST** `recorder.start` throws (mic held by a call or another app) → toast **Couldn't start recording.
  The microphone may be in use.**, back to idle, the file deleted. Replaces **Could not start recording**.
- [ ] **H3 MUST** The old **Microphone permission denied** string is gone.

## I. Interruptions (S8)

- [ ] **I1 MUST Calls, alarms, other recorders.** `MessageInput` listens to `recorder.onStateChanged()` (cancelled in
  `dispose`). `RecordState.pause` arriving while `holding` → stop → `preview` (as a release); while `locked` →
  `paused` (the clock and waveform stop; no toast, the panel says **Paused**). A focus regain never resumes by itself
  (the plugin's `pause` mode, fact 7). **Known plugin limit (found in round 3):** `record_android` gives up audio focus
  on `pause()` and does not ask for it again on `resume()`, so after a Pause → Resume a call sends no pause event and
  the recording runs on through it. No cheap fix in our code; check what it captures on a device (device check 8).
- [ ] **I2 MUST App backgrounded or screen off.** An `AppLifecycleListener(onHide: …)` in `MessageInput` (disposed in
  `dispose`): `holding` → stop → `preview`; `locked` → pause → `paused`; `preview` → pause playback. `inactive` alone
  (the notification shade) changes nothing.
- [ ] **I3 MUST App lock** needs no change: it covers on `hidden` (fact 13), which I2 has already paused, so nothing
  records behind the lock; after unlock the panel is where it was.
- [ ] **I4 MUST Leaving the chat** (back, a notification opening another chat; decision 8): `dispose` saves the
  recording as this chat's voice draft (L3) and never deletes it. Back still pops at once (nothing is awaited before
  the pop). No `ref` in `dispose` (the dispose learning): everything L3 needs is read in `initState`.
- [ ] **I5 MUST** `canSendMessages` turning false mid-recording or during a preview (removed from a group, or a key
  hiccup) → in `didUpdateWidget`, save it as the chat's voice draft exactly as on leaving (L3), back to idle. Nothing
  is deleted (L4's rule); it comes back as **Draft** when sending opens again.
- [ ] **I6 MUST** The recorder's first-use `start` may take a moment: a second long press while the first `start` is
  still pending does nothing (today's `_voiceState != idle` guard, kept with a `_starting` flag).

## J. Accessibility and motion

- [ ] **J1 MUST** `mic_hint_test.dart` passes untouched: a quick tap shows the **Hold to record** tooltip above the
  mic; the mic's semantics = label **Record voice message**, hint **Hold to record**, button.
- [ ] **J2 MUST TalkBack** (`MediaQuery.accessibleNavigationOf(context)` true; decision 11): a tap on the mic goes
  straight to `locked` (permission rules H1 first) and the mic's hint becomes **Double tap to record**; no tooltip.
  This is the only `_ComposerAction` change: `_NormalInputRow` passes `onTap` and `tapHint: null` in that mode.
- [ ] **J3 MUST Labels**: ✕ = **Delete voice note**; centre = C2's labels; send = **Send voice note**; the timer =
  `Semantics(label: '$m minutes $s seconds')`; the waveform excluded. Focus order: title, status, timer, ✕, centre,
  send, Stop and listen.
- [ ] **J4 MUST** 200% text on a 360 dp phone: the panel grows taller, nothing overflows (title and status wrap, the
  timer `FittedBox(scaleDown)`, the control row has fixed sizes: 56 + 72 + 56 + 64 = 248 dp). The hold strip's
  **Slide to cancel** is `Flexible` with ellipsis.
- [ ] **J5 MUST Reduced motion** (`MediaQuery.disableAnimationsOf`): the dot doesn't pulse, the mic doesn't scale,
  the chevron doesn't nudge, the panel doesn't fade. The waveform still updates (it's data, not decoration).
- [ ] **J6 MUST** Light, dark and AMOLED from tokens only; no hex in the new files (grep gate).

## K. Copy (verbatim)

| Where | Text |
|---|---|
| Panel title | **Voice note** |
| Status | **Recording** · **Paused** · **10 seconds left** · **Draft** |
| Hold strip | **Slide to cancel** · **Release to cancel** (both unchanged) |
| Paused button | **Stop and listen** |
| Tooltips / labels | **Delete voice note** · **Pause recording** · **Resume recording** · **Play voice note** · **Pause voice note** · **Send voice note** · mic: **Record voice message** + hint **Hold to record** (unchanged) / **Double tap to record** (TalkBack) |
| Toasts | **Hold to record** (under 1 s, unchanged) · **Microphone on. Hold to record.** · **Kuch Bhi needs the microphone to record voice notes.** · **Couldn't start recording. The microphone may be in use.** · **Couldn't pause the recording.** · **Couldn't resume the recording.** · **Couldn't save the voice note.** · **Couldn't play the recording.** · **Voice notes can be up to 5 minutes.** · **Couldn't send voice note. Try again.** (unchanged) |
| Dialog | **Microphone is off** / **Turn on the microphone for Kuch Bhi in your phone's settings to record voice notes.** / **Open settings** / **Not now** |

Removed strings: **Microphone permission denied**, **Could not start recording**, **Could not save voice message**,
**Discard**, **Send voice message**.

Added with section L: status **Draft**.

## L. Voice drafts (S8; decision 8, user choice 2026-11-03)

A recording you leave unsent is kept for that chat until you send or delete it, and survives closing the app.
- [ ] **L1 MUST Storage.** `<documents>/voice_drafts/<key>.m4a` + `<key>.json`, where `<documents>` comes from
  `voiceDraftDirProvider` (default `getApplicationDocumentsDirectory`, not the temp folder, which Android may clear)
  and `<key>` = the conversation id with every character outside `[A-Za-z0-9_-]` replaced by `_`. JSON:
  `{"v":1,"seconds":int,"levels":[…]}`, levels = `bucketLevels(levels, 100)` rounded to 2 decimals. The `.json` is
  the marker: a draft exists only when both files exist. One draft per chat; the files stay in app-private
  storage, like every sent voice note's own copy.
- [ ] **L2 MUST** `voice_draft_store.dart` (top-level functions, each taking `Future<Directory> Function() baseDir`):
  `class VoiceDraft { final File file; final int seconds; final List<double> levels; }`;
  `loadVoiceDraft(conversationId, baseDir)` → `VoiceDraft?` (sidecar unreadable, wrong `v`, or audio missing → both
  files deleted, `null`); `saveVoiceDraft(conversationId, File audio, int seconds, List<double> levels, baseDir)` →
  moves the audio in (`rename`, falling back to `copy` + `delete` across filesystems, as `registerLocal` does), then
  writes the sidecar to `<key>.json.tmp` and renames it, so a kill mid-write never leaves a half marker; an existing
  draft for the chat is replaced; `deleteVoiceDraft(conversationId, baseDir)`; `wipeVoiceDrafts(baseDir)` = delete
  the folder. Every function catches its own IO errors (`debugPrint` without the path) and never throws.
- [ ] **L3 MUST Saving on leave** (`dispose`, I4): `holding` with 1 s or more, `locked`, `paused` →
  `unawaited((() async { final path = await recorder.stop(); if (path != null) await saveVoiceDraft(…); await
  recorder.dispose(); })())` (the recorder is disposed only after the stop, never before); `holding` under 1 s →
  `recorder.cancel()` then dispose; `preview` of a temp recording → `saveVoiceDraft` of it; `preview` that is already
  the draft → nothing (it's in place). The player, the timer and the state subscription are disposed at once. The
  save's future is kept per chat in a `static Map<String, Future<void>>` until it completes, and L4's load awaits it
  first, so reopening the chat during the save finds the draft instead of half of it.
- [ ] **L4 MUST Opening a chat.** After the first frame, `loadVoiceDraft`: a draft and `canSendMessages` → `preview`
  of the draft (file, seconds, levels), status **Draft**. A draft and not `canSendMessages` → **keep it** and wait:
  group chats start unable to send until the group key settles (the share-in learning), so show it when
  `canSendMessages` turns true (`didUpdateWidget`). Never delete it for this: **only ✕, a successful send or sign-out
  remove a voice draft**, because a recording you kept is worth more than a stray file. A chat you can no longer
  send in simply keeps it unseen until sign-out. (Corrected twice on 2026-11-03/04 after grading: the first wording
  deleted every group draft on reopen; the second deleted it after 15 s of slow key loading.) The text draft (`_drafts`, `mi:64`) is untouched and shows again once the voice draft is sent or
  deleted. A share that arrives while the draft is up (12.1) waits, as it waits for any non-idle composer, and runs after. A
  share handed over at the first frame keeps its timing and goes first: if the composer is busy when the draft
  finishes loading (`_composerBusy`: a share's editor, dialog or upload, or a sheet on top), the draft retries every
  500 ms and shows once it's free, so its panel never covers a share's row.
- [ ] **L5 MUST Send or delete a draft.** Send = G1 with the draft's file and seconds; the send moves the audio into
  the media store (fact 15); success → `deleteVoiceDraft` (removes the marker). ✕ → `deleteVoiceDraft`. A send that
  throws follows G2.
- [ ] **L6 MUST Sign-out** deletes every draft: `await wipeVoiceDrafts(getApplicationDocumentsDirectory);` right
  after `await wipeMediaCache();` (`auth_repository_impl.dart:392`).
- [ ] **L7 MUST What is not a draft** (decision 13): going to the background only pauses (I2), so you can resume after
  a call. A recording that was never stopped is lost if Android kills the app in the background (the file has no
  ending until it stops). Saved drafts survive kills and restarts.

---

## Test gates (phase 2)

New files only; every existing test untouched and green.

**`test/chat/voice_waveform_test.dart`** (pure):
1. `waveLevel`: -160 → 0.06; -50 → 0.06; -25 → 0.5; 0 → 1.0; +3 → 1.0; NaN → 0.06.
2. `bucketLevels`: empty → empty; 3 levels into 10 bars → the 3; 10 levels into 5 → 5 maxes; `bars` 0 → empty.

**`test/chat/voice_recorder_test.dart`** (widget; `FakeRecorder implements AudioRecorder` recording every call and
emitting on a `StreamController<RecordState>`, a `FakeMicPermission`, a fake `SendMediaMessage` notifier; the
`mic_hint_test.dart` pump shape; a fresh conversation id per test, the drafts learning):
3. Hold the mic 600 ms (`tester.startGesture` + `pump`) → `start` called with `numChannels: 1, bitRate: 64000`;
   **Slide to cancel** shown; the timer reads `0:01` after another 1 s.
4. Release after 2 s → **Voice note** panel, play disc, **Send voice note** present; `stop` called once.
5. Release after 0.5 s → back to idle, **Hold to record** toast, file not kept (`cancel` or delete).
6. Move left 100 → **Release to cancel**; release → `cancel` called, idle, no panel.
7. Move up 100 (finger still down) → **Recording** panel; release → `stop` NOT called, still **Recording**.
8. Locked → **Pause recording** → `pause` called, **Paused**, **Stop and listen** shown, timer frozen over 2 s;
   **Resume recording** → `resume` called, timer moves again.
9. Locked → **Send voice note** → `stop` then the fake send called with `mediaType: 'voice'` and
   `durationSeconds` = the elapsed seconds; panel gone.
10. Preview → **Delete voice note** → idle; the temp file no longer exists.
11. Fake send throws → still in preview, **Couldn't send voice note. Try again.**
12. Permission `denied` at press → `request` called, `start` NOT called; granted → **Microphone on. Hold to record.**
13. Permission `permanentlyDenied` → **Microphone is off** dialog; **Open settings** → `openSettings` called.
14. `start` throws → **Couldn't start recording. The microphone may be in use.**, idle.
15. `RecordState.pause` from the fake while holding → preview; while locked → **Paused**.
16. App hidden (`tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden)` via inactive → hidden)
    while locked → `pause` called, **Paused**; `inactive` alone → still **Recording**.
17. Elapsed 290 s → **10 seconds left**; 300 s → preview + **Voice notes can be up to 5 minutes.**
18. Widget removed while holding under 1 s → `cancel` called, no draft written.
19. `accessibleNavigation: true` → a tap on the mic opens the **Recording** panel; hint **Double tap to record**.
20. 360 × 640 at text scale 2.0, locked and preview → no overflow exception.
21. Widget removed while locked (`voiceDraftDirProvider` → a temp dir; file IO inside `tester.runAsync`) → `stop`
    called, then the draft's `.m4a` and `.json` exist with the elapsed seconds; `dispose` on the fake recorder comes
    after `stop`.
22. Widget removed in preview → the draft exists; pumping a new `MessageInput` for the same chat → **Draft** and the
    play disc.
23. A draft → **Send voice note** succeeds → the `.json` is gone.
24. A draft → **Delete voice note** → both files gone, idle.
25. A draft and `canSendMessages: false` → no panel, both files still there at 60 s.
26. Fake send throws after deleting the file it was given → toast, idle (not a preview of a missing file).

**`test/chat/voice_draft_store_test.dart`** (pure IO, a temp dir):
27. save → load: the audio moved (source gone), seconds and ≤ 100 levels back.
28. Sidecar without audio, or unreadable JSON, or `"v":2` → `null`, both files deleted.
29. Save twice for one chat → one draft, the second.
30. `delete` and `wipe` remove the files; on a missing folder neither throws.
31. Key: conversation id `a/b:c` → files `a_b_c.m4a` / `a_b_c.json`.

**Added during grading** (all in `voice_recorder_test.dart`; see the work log): 19b, 32–49, each one mutation-checked.

**Grep gates:** no `Color(0x` / `Colors.` in the two new widget files; no `t.accent` outside a fill (`color:` of a
`BoxDecoration` / `Material`) in them; `_RecordingRow`, `_VoicePreviewRow`, `_durationTextToSeconds` gone from `mi`.

---

## Device check list (phase 2, M52 + Redmi; never in the user's real chats, a test chat only)

1. Hold, speak 5 s, release → preview with your waveform; play it; seek by tapping the middle; send. The other phone
   plays it, duration right.
2. Hold, slide left → **Release to cancel**, release → gone, nothing sent.
3. Hold, slide up → locks with a tick; lift the finger, speak 20 s, pause, wait 10 s, resume, speak 5 s, send →
   25 s note, no gap noise.
4. Locked → pause → **Stop and listen** → listen → delete.
5. Diagonal drag: starts left then up → stays in cancel mode (no lock).
6. Airplane mode: record and send → bubble waits; airplane off → uploads, the other phone plays it.
7. First-ever press after clearing the app's permissions → system dialog, no recording; then hold → records.
   Deny twice → **Microphone is off** → **Open settings** lands on Kuch Bhi's app info.
8. Call the phone from the other one while locked → **Paused**; hang up → still paused; resume → records. Then the
   plugin limit (I1): Pause → Resume first, then a call. It won't pause by itself; listen to what it recorded.
9. While holding, an incoming call → preview of what was recorded.
10. Locked → Home button → back → **Paused**. With app lock on (1 min, set to Immediately for the test): Home → back →
    the lock screen, unlock → **Paused**, nothing recorded behind it.
11. Locked, 15 s → back out of the chat → nothing sent; open the chat again → **Draft** preview of those 15 s; play
    it, send it → the other phone plays it. Again with a hold-released preview → **Draft** → ✕ → gone.
12. Record 5 minutes (locked) → **10 seconds left** at 4:50, stops at 5:00 into preview with the toast.
13. TalkBack: double tap the mic → panel; every control read by name; the status read when it changes.
14. Largest text + Plus Jakarta Sans at 360 dp (or the Redmi's narrowest): strip and panel, no overflow.
15. Reduce animations on: no pulse, no nudge, no fade. Light, dark, AMOLED captures of the strip, the recording
    panel, the paused panel and the preview.
16. File size: a 60 s note is about 0.5 MB (mono 64 kbps), not ~1 MB.
17. A draft in a chat → swipe Kuch Bhi away from Recents → open the chat → the draft is still there.
18. A draft → sign out → sign back in → no draft (`adb shell run-as com.chai.kuch_bhi ls app_flutter/voice_drafts`
    shows nothing or no folder).
19. TalkBack on: double tap the mic, then pause, resume, send; again and delete. Every control presses.
20. Group chat: leave a locked recording, swipe the app away, reopen the chat → **Draft** appears once the group is
    ready to send, on mobile data too. Nothing lost however long the key takes.
21. Share a document into a chat that has a draft: the share goes first, the draft appears after it.
22. Tap Pause and Resume quickly several times: the panel always matches the phone's mic indicator.

## Out of scope (do NOT build on this page)

The voice bubble's look (a waveform in the bubble needs the levels sent: decision 7's alternative) · a reply quote on
a voice note (F-a) · recording in the background (foreground service) · speed or trim in the preview · voice notes in
the share-in or album paths · transcription · iOS · anything in ⛔.

**Follow-ups noticed (not this page):**
- **F-a** A voice note sent while a reply is set ignores the reply and the reply bar stays (fact 11). Carrying it
  needs `replyToLocalId` through `SendMediaMessage.send` → `sendMediaMessage` (frozen here).
- **F-d** Every other haptic in the app is silent on the M52 for the same reason as B4: swipe-to-reply
  (`swipe_to_reply.dart:55`) and the long-press menus (`message_context_menu.dart:99,133`) use `mediumImpact`; the
  profile (`profile_screen.dart:26`) and the chat (`chat_screen.dart:635`) use `selectionClick`, not tested there.
  Move them to `haptic_feedback`.
- **F-c** Home's chat tile doesn't show that a chat has a voice (or text) draft.
- **F-b** The bubble's play disc and speed chip (`vb:270-356`) use accent as icon/text colour on the received side,
  against "accent only as fill". A bubble pass can fix it alongside decision 7's alternative.

---

## Diff vs current implementation

| # | Area | Today (file:line) | Spec | Checklist |
|---|------|-------------------|------|-----------|
| 1 | Flow | hold → release → preview; slide left cancels (`mi:1124-1176`) | + slide up to lock, pause/resume, Stop and listen, send from locked | A |
| 2 | Gesture | mic long-press callbacks + a `Listener` on the swapped-in row (`mi:1407-1412`) | one `Listener` on the panel that stays mounted | A4 |
| 3 | Strip | pulsing mic + timer in `t.error` (`mi:1417-1429`) | ink timer, live waveform, 8 dp error dot, lock pill | B |
| 4 | Panel | small preview row, 3 px progress bar (`mi:1458-1631`) | **Voice note** panel, waveform player, 3 round controls | C, D |
| 5 | Waveform | none | `getAmplitude` every 100 ms → `VoiceWaveform` (C20) | E |
| 6 | Clock | 1 s counter (`mi:232`) | 100 ms tick, pause-aware | F |
| 7 | Audio | AAC stereo 128 kbps (`mi:215`) | AAC mono 64 kbps | A5 |
| 8 | Permission | request on each press, may start with no finger (`mi:202`) | check first, never start from the asking press; settings dialog | H |
| 9 | Interruptions | none (fact 8) | focus loss and background pause or stop | I1, I2 |
| 10 | Leaving | temp file leaked, recording lost (`mi:160-170`) | saved as the chat's voice draft, back in the chat as **Draft** | I4, L |
| 12 | Failed send | preview kept even when the send had already deleted its file (fact 15) | preview only while the file exists | G2 |
| 11 | TalkBack | hold only | double tap opens the panel | J2 |

---

## Deferred decisions (default in bold; reply with a number to change one)

1. **Hold to record, slide up to lock** (the quick tap keeps its **Hold to record** hint). Alternative: tap the mic
   to open the panel and record hands-free every time (simpler, no gesture; one extra tap for short notes, and
   `mic_hint_test.dart` would have to change).
2. **Releasing a hold opens the preview** (today's behaviour). Alternative: release sends at once (WhatsApp); the
   preview then only comes from **Stop and listen**.
3. **Pause / resume in the locked panel; listening ends the recording (Stop and listen).** Alternative: no pause, the
   centre is a stop button that goes straight to the preview (Telegram). Listening and then recording more would
   need joining audio files, which needs a new package.
4. **5 minutes max** (unchanged). Alternative: 15 minutes (≈ 7 MB at decision 5's rate).
5. **Mono AAC 64 kbps** (half today's size; a phone mic is mono anyway). Alternative: keep stereo 128 kbps.
6. **Waveform bars in ink** (played ink, rest faint); accent only on the record and send discs. Alternative: accent
   bars (closer to most reference images; low contrast on light, decorative only).
7. **The waveform stays on your phone**; the bubble the other side sees is unchanged. Alternative: send ~40 levels
   with the message and draw them in the bubble (a new message field: a live PocketBase field AND an update-rule
   change, per the unknown-fields learning, plus a bubble redesign).
8. **Leaving the chat keeps the recording as a voice draft** (user choice, 2026-11-03; section L). Was: back
   discards with no prompt.
9. **A light haptic on start, lock and the cancel threshold.** Alternative: none.
10. **Timer as `1:14`**, matching the bubble. Alternative: `01:14` as in the reference.
11. **TalkBack: a double tap on the mic opens the recording panel.** Alternative: hold only (TalkBack's double-tap-
    and-hold works, but lock/cancel by sliding doesn't).
12. **The text draft and the reply bar are left as they are** while recording; a voice note goes without the reply
    (today's behaviour, F-a). Alternative: carry the reply (unfreezes the media send path).
13. **Going to the background only pauses** (resume after a call works; a recording never stopped is lost if Android
    kills the app meanwhile). Alternative: save as a draft on every background, never lost, but no resume after a
    call or a Home press.

## Baseline

Recorded 2026-11-03 at `244f568` (working tree: no changes under `lib/` or `test/`): **1052/1052** (`flutter test`,
all passed, ~1 min). Since then `34e0a95` (F-b, 1060 tests) landed on main, so phase 2 re-runs it first and records
it again. Another session (bug wave 5) was working in the
same folder at the time; phase 2 checks `git status lib test` before starting.

---

## Astra implementation brief (paste as is)

```text
You are implementing "Voice recorder redesign" in a Flutter app (Android only). You do not know this repo;
everything you need is below. Do exactly this, nothing more. Do not change files not listed. Do not add packages.

REPO: /home/chaitanyadhotre/kuch_bhi (Flutter 3.47, Riverpod 2.6 with plain Provider/Notifier).
SPEC: docs/design/pages/voice-recorder.md (sections A–L are yours). The HTML board
docs/design/pages/voice-recorder.html shows every state. Copy in bold in the spec is VERBATIM: use it exactly.

ALREADY THERE (use, don't rebuild):
- record 6.2.0 (AudioRecorder: start, stop, cancel, pause, resume, getAmplitude -> Amplitude(current dBFS, max),
  onStateChanged -> Stream<RecordState>), just_audio (AudioPlayer), permission_handler (Permission.microphone,
  openAppSettings). All in pubspec.yaml.
- The current recorder: lib/features/chat/widgets/message_input.dart. Voice code = enum _VoiceState (line 35), fields
  69-80, _startRecording/_stopRecording/_discardPreview/_sendVoice/_durationTextToSeconds (199-368), dispose (160-170),
  build's voice branches (1113, 1124-1144), the mic in _NormalInputRow (1367-1378), _RecordingRow (1389-1454),
  _VoicePreviewRow (1458-1631). Keep _sendVoice's send call exactly (sendMediaMessageProvider.notifier.send with
  mediaType 'voice', mediaFile, durationSeconds, durationText).
- AppConstants.maxVoiceMessageSeconds (300) in lib/core/constants/app_constants.dart; formatMmSs in
  lib/core/utils/format_utils.dart.
- Theme tokens: `context.t` (t.bg, t.surface, t.surface2, t.ink, t.inkSoft, t.inkFaint, t.line, t.accent,
  t.onAccent, t.error, t.shadow); WarmPopTokens (radiusLg, radiusPill, motionBase, cardShadow(color)) in
  lib/core/theme/tokens.dart. Never a hex colour. Accent ONLY as a fill (BoxDecoration color of the record/send
  discs and the hold mic); never accent text, icon, stroke or bar. t.error only on the 8 dp recording dot.
- Shared widgets (lib/core/widgets/): showToast (app_toast.dart), showConfirmDialog (app_dialog.dart), AppButton
  (app_button.dart, variant text), BusySpinner (busy_spinner.dart, pass color: t.onAccent on accent discs).

FILES TO CREATE:
1. lib/features/chat/providers/voice_recorder_providers.dart — spec A6: voiceRecorderFactoryProvider,
   micPermissionProvider + class MicPermission {status(), request(), openSettings()}, voiceDraftDirProvider.
1b. lib/features/chat/voice_draft_store.dart — spec L1/L2: VoiceDraft, loadVoiceDraft, saveVoiceDraft,
   deleteVoiceDraft, wipeVoiceDrafts.
2. lib/features/chat/widgets/voice_waveform.dart — spec E2/E3: waveLevel, bucketLevels, VoiceWaveform (CustomPainter,
   RepaintBoundary, ExcludeSemantics).
3. lib/features/chat/widgets/voice_recorder_panel.dart — VoiceHoldStrip (spec B1, B2) and VoiceRecorderPanel
   (spec C, D; it owns the preview AudioPlayer and disposes it).
4. test/chat/voice_waveform_test.dart, test/chat/voice_recorder_test.dart and test/chat/voice_draft_store_test.dart
   — exactly the cases in the spec's "Test gates" (1–31). File IO in widget tests goes inside tester.runAsync.

FILES TO EDIT (only the parts named):
- lib/features/chat/widgets/message_input.dart: the voice parts listed above, per spec A–J: the new enum, the
  recorder from voiceRecorderFactoryProvider (created in initState), RecordConfig(encoder: AudioEncoder.aacLc,
  numChannels: 1, bitRate: 64000), the 100 ms tick (E1), the one Listener around the floating panel's child (A4),
  the permission flow (H), onStateChanged + AppLifecycleListener(onHide) (I1, I2), didUpdateWidget (I5), the
  failed-send file check (G2), dispose saving the voice draft without ref (I4, L3), loading the draft after the
  first frame (L4), TalkBack tap (J2: in _NormalInputRow pass onTap and tapHint: null when
  MediaQuery.accessibleNavigationOf(context) is true). Delete _RecordingRow, _VoicePreviewRow and
  _durationTextToSeconds. Do not touch _send, drafts, the reply bar, the share-in code, the upload rows, or
  _ComposerAction.
- docs/design/10-registry.md: add row C20 after C19, text from spec A7.
- lib/infrastructure/repositories/auth_repository_impl.dart: ONE line `await
  wipeVoiceDrafts(getApplicationDocumentsDirectory);` right after `await wipeMediaCache();` (line 392), plus the
  import. Nothing else in that file.

DO NOT TOUCH (automatic FAIL): message_repository_impl.dart, media_upload_service.dart, chat_provider.dart,
voice_message_bubble.dart, message_bubble.dart, chat_screen.dart, app.dart, lib/features/app_lock/, any existing
test (test/chat/mic_hint_test.dart must pass unchanged). No `$e` / e.toString() in visible text.

GATES (run all, paste the tail of each in your report):
  flutter analyze            -> 0 errors
  flutter test               -> all green; report "baseline + N new = total" (baseline in the spec's Baseline line)
  git diff --check           -> clean
  git diff --stat            -> only the files listed above
  grep -n "Color(0x\|Colors\." lib/features/chat/widgets/voice_waveform.dart lib/features/chat/widgets/voice_recorder_panel.dart -> nothing

Report: files changed, test count, anything you could not do and why. Do not commit.
Claude grades the result; do not claim PASS.
```
