---
title: "Shares from other apps should come through a small channel of our own, not the popular receive plugin"
author: Chaitanya
date: 2026-11-02
branch: main
cost: { minutes: 1, tokens: 1939 }
id: l-15bc244e
scope: repo
status: active
src: agent
touches:
  - android/app/src/main/AndroidManifest.xml
  - lib/services/fcm_service.dart
---

## Decided
Proposed in the 12.1 share-in spec (2026-11-02, pending the user's spec review): receive Android SEND / SEND_MULTIPLE
through our own method channel in the main activity, copying a shared file only after the user picks a chat, off the
main thread, stopping at 100 MB, one folder per item under the app's private cache, deleted after the share, at start
and at logout. Use singleTask so a share always reaches the one running app.

## Tried and ruled out
receive_sharing_intent 1.9.0 (source read from its pub archive): copies every shared file on the main thread as the
app starts (a big video freezes launch); for files from main storage it returns a raw /storage/emulated/0 path without
copying, unreadable on Android 13+ without broad storage access; no size cap; copies into the cache root under the
original name (clashes overwrite) and never deletes them or its video thumbnails; logs every file name; its VIEW
branch would also report our kuchbhi:// link as a share; its build targets AGP 9.2.1 / compileSdk 37, newer than this app.

## Watch out
- With singleTop and an empty taskAffinity, a share can start a second app instance inside the sharing app's task.
- Reopening a killed app from Recents re-delivers the original SEND intent; ignore intents with
  FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY or an old share comes back.
- A document's name on the other phone is its file's basename and the send moves the file, so copy shared documents
  under their real display name.
- The notification-tap router wait gives up after 12 s; a share must wait through sign-in and key restore instead.

In the code: android/app/src/main/AndroidManifest.xml (launchMode, intent filters), MainActivity.kt (clipboard channel
pattern), lib/services/fcm_service.dart _waitForRouter, message_repository_impl.dart fileName: p.basename,
docs/design/pages/share-in.md decisions 1, 2, 18.
