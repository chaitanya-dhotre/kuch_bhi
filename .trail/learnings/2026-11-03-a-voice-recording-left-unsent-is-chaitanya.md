---
title: "A voice recording left unsent is kept as a per-chat draft, and a paused recording can't be played, so listening ends it"
author: Chaitanya
date: 2026-11-03
branch: main
cost: { minutes: 3, tokens: 46344 }
id: l-aa774f24
scope: repo
status: active
replaces: l-49bdd1bb
src: agent
touches:
  - docs/backlog.md
  - lib/data/local/database/daos/messages_dao.dart
  - lib/infrastructure/ingest/ingest_boundary.dart
  - lib/infrastructure/offline/outbox_worker.dart
  - lib/infrastructure/repositories/message_repository_impl.dart
  - test/offline/media_send_harness.dart
  - test/offline/text_send_cancel_test.dart
  - docs/design/pages/voice-recorder.md
  - docs/design/pages/voice-recorder.html
  - lib/features/chat/widgets/message_input.dart
---

## Decided
(12.6 voice recorder spec, user PASS 2026-11-03.) Pause and resume use the recorder plugin's own pause()/resume()
on one file. An AAC/MP4 file can't be played until it is stopped, so "Stop and listen" ends the recording. The user
chose that leaving a chat keeps the recording as that chat's voice draft (stopped and saved; a draft is finished:
play, send or delete, never record more). Going to the background only pauses, so you can resume after a call.
The waveform is getAmplitude() on one 100 ms timer that also drives the clock.

## Tried and ruled out
- Listening and then recording more (WhatsApp style): needs joining audio files, so a new package.
- Saving a draft on every background: never loses a recording, but no resume after a call. Not chosen.
- Drafts in the temp folder: Android may clear it. They live in the documents folder and sign-out wipes them.

## Watch out
- The media send MOVES the file into the media store and deletes it if the send then throws, so a preview "kept for
  resend" can point at a missing file. Check the file exists before keeping the preview, and never treat a draft's
  audio as still there after a send.
- The plugin already pauses on audio-focus loss (calls) and reports it on onStateChanged; nothing listened before.
- The first mic press opens the permission dialog with the finger down; on "Allow" recording started with no finger
  on the mic. Never record from the press that asks.

In the code: lib/features/chat/widgets/message_input.dart (recorder); record 6.2.0 lib/src/record.dart;
media_blob_store.dart registerLocal (rename) + wipeMediaCache; auth_repository_impl.dart:392 sign-out wipe.
Spec: docs/design/pages/voice-recorder.md sections A–L.
