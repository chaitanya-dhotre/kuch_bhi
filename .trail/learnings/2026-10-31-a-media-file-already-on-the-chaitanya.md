---
title: "A media file already on the phone loads without its size, expiry or name, and the video compressor's trim length is really time cut from the end"
author: Chaitanya
date: 2026-10-31
branch: main
cost: { minutes: 15, tokens: 272233 }
id: l-3d7f7725
scope: repo
status: active
src: agent
touches:
  - docs/design/pages/media-send.md
  - docs/design/pages/media-send.html
  - lib/infrastructure/media/media_blob_store.dart
  - lib/data/local/database/tables/media_blob_table.dart
---

## Decided
- Not fixed yet (spec only, awaiting the user's PASS). The media-send spec proposes that the blob row keep the media's metadata (one nullable JSON column) so a cache hit returns width, height, expiry, mime type and the real file name.
- The trim default is the video compressor the app already has, because it trims in the same pass and needs no new dependency.

## Watch out
- When the blob row is already ready, requesting the media still runs the pipeline, whose fast path returns only the file and its prefixed basename. The in-memory media provider lasts one session, so after every app restart cached photos and videos fall back to 4:3 / 16:9, lose their expiry badge (and the viewer its expiry line), and documents show names like `abc123_f_report.pdf`. Anything that registers a local file as a ready blob (keeping the sender's copy, for example) hits this on every send.
- On Android, video_compress 3.1.4 passes its `duration` argument as the last argument of Transcoder 0.10.5's TrimDataSource, which means microseconds cut off the END, not a length. To keep 0:05–0:15 of a 40s clip, pass startTime 5 and duration 25 (length minus end). Both are whole seconds. Prove it on a device before relying on it.
- FFmpegKit was retired in 2025. Its Flutter forks are community-maintained only and add tens of MB of binaries.

In the code: lib/infrastructure/media/media_blob_store.dart _runPipeline fast path (~L192-207); lib/data/local/database/tables/media_blob_table.dart (no metadata columns); ~/.pub-cache/hosted/pub.dev/video_compress-3.1.4/android/.../VideoCompressPlugin.kt L140-142; spec docs/design/pages/media-send.md (smell 9, decisions 3 and 17).
