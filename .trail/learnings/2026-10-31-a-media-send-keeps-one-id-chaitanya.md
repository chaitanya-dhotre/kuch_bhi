---
title: "A media send keeps one id from pick to sent, and a schema change here means hand-writing the drift generated code"
author: Chaitanya
date: 2026-10-31
branch: main
cost: { minutes: 85, tokens: 450125 }
id: l-a0b0e2fa
scope: repo
status: active
src: agent
touches:
  - docs/design/pages/media-send-work-log.md
  - lib/services/upload_progress.dart
  - test/offline/media_send_harness.dart
  - test/offline/media_send_one_bubble_test.dart
  - test/offline/media_send_resume_test.dart
  - test/offline/media_blob_meta_test.dart
  - docs/design/pages/media-send-handoff.md
  - lib/infrastructure/repositories/message_repository_impl.dart
  - lib/infrastructure/media/media_blob_store.dart
  - lib/data/local/database/app_database.g.dart
---

## Decided
- A media send's local id is a PocketBase-style id that is also the server record id. The message create is stamped at its ack (server id, server time), before the upload, so a page fetch during the upload finds the row instead of inserting a second one. Fresh send, resume and Try again all run the same upload function, which reads everything from the row and its blob rows.
- The sent file is moved into the media cache as a ready blob with the upload latch set, and its metadata (size, length, expiry, real name) is stored on the blob row, so the sender never re-downloads and a cache hit after a restart keeps the bubble's shape and the video length.
- A cancelled upload is hidden by marking the row deleted-for-everyone locally and kept until the server copy is marked too, so an offline cancel survives a restart.
- The upload stall bound is 8s only while the HTTP client is still pulling bytes. After the last byte is pulled the socket still drains its buffer and the server writes the file, so that wait gets 60s.

## Tried and ruled out
- Running build_runner for the schema change: drift_dev and riverpod_generator both crash on this Dart SDK (the locked analyzer cannot read dot-shorthand) and leave the generated files deleted. Restore them with git, then add the column by hand at every generated site, copying an existing nullable column of the same table.
- Renaming the text send's queue lift so it also lifts media: it changes the frozen text send path. The media ack uses its own lift; the text path is byte-identical.

## Watch out
- Logout did not delete decrypted media files; it only cleared tables and secrets. It now wipes the media cache folder.
- The old pending-retry pass pushed a pending voice or video row through the TEXT outbox whenever its duration sat in the body cache. Media rows are skipped there now.
- In widget tests, the media store's startup work cannot run inside the fake clock; build it in setUpAll. A repo message stream's cancel never finishes in the test harness, so don't await it.

In the code: lib/infrastructure/repositories/message_repository_impl.dart (sendMediaMessage, _uploadMediaMessage, cancelMediaUpload, resumeMediaUploads); lib/infrastructure/media/media_blob_store.dart (registerLocal, mediaMetaJson, wipeMediaCache); lib/services/upload_progress.dart; lib/data/local/database/app_database.g.dart (hand-written v12 meta column); docs/design/pages/media-send-work-log.md.
