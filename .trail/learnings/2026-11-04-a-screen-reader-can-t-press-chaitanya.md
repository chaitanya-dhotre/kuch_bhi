---
title: "A screen reader can't press a control whose semantics exclude their children, and a first-frame share must never wait on disk"
author: Chaitanya
date: 2026-11-04
branch: main
cost: { minutes: 51, tokens: 782276 }
id: l-1ea3e328
scope: repo
status: active
src: agent
touches:
  - docs/design/pages/voice-recorder.md
  - docs/design/pages/voice-recorder-work-log.md
  - lib/features/chat/widgets/voice_recorder_panel.dart
  - lib/features/chat/voice_draft_store.dart
  - lib/features/chat/widgets/message_input.dart
  - test/chat/voice_recorder_test.dart
---

## Decided
Round-trip grading of the voice recorder, 2026-11-04. A custom round button that sets excludeSemantics to avoid a label being read twice must also pass onTap and enabled on that Semantics, because excluding children removes the GestureDetector's tap action too. Test screen-reader paths with tester.semantics.tap and find.semantics.byLabel: a plain tester.tap passes on a control TalkBack can't press.

A voice draft yields to a share, not the other way round. The share keeps its first-frame timing; the draft retries every 500 ms while the composer is busy.

## Tried and ruled out
Awaiting the draft load before taking the share: real file IO never finishes under the widget tests' fake clock, which broke six share tests, and a share has no reason to wait on disk anyway.

## Watch out
- A state guard on "not idle" misses the window while start() is pending: sending closed during it and the mic ran on, invisible, under the restriction banner. Re-check after any await that turns the mic on.
- Green tests that passed first time proved nothing here: one new test never exercised its ordering. Revert each fix in a scratch copy and see that a test fails; and read the full suite's result, not just analyze.
- record_android gives up audio focus on pause() and doesn't ask again on resume(), so after Pause then Resume a call no longer pauses the recording.

In the code: lib/features/chat/widgets/voice_recorder_panel.dart _disc; message_input.dart _startRecording, _loadVoiceDraft, _trackDraftSave. Work log: docs/design/pages/voice-recorder-work-log.md.
