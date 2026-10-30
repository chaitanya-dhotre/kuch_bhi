---
title: "Starred messages keep only ids on the server, and turning off Android backup also needs device-transfer rules"
author: Chaitanya
date: 2026-10-30
branch: main
cost: { minutes: 8, tokens: 144721 }
id: l-a0383ffb
scope: repo
status: active
src: agent
touches:
  - test/offline/starred_no_plaintext_test.dart
  - test/grep_gates_test.dart
  - lib/infrastructure/repositories/message_repository_impl.dart
  - lib/features/starred_messages/screens/starred_messages_screen.dart
  - lib/services/fcm_service.dart
  - lib/main.dart
  - android/app/src/main/AndroidManifest.xml
  - android/app/src/main/res/xml/data_extraction_rules.xml
  - docs/audits/security-wave-1-work-log.md
---

## Decided
- A star sends only ids to the server (user, message, conversation, sender). The starred list takes each body from the device: the in-memory decrypted-body cache by the message's local id, else the shared body renderer's placeholder. Uploading the decrypted preview put plaintext at rest on the server, which breaks E2E for every starred message.
- When the server call fails (offline), the starred list shows the locally starred rows instead of an empty screen.
- Android backup is off with allowBackup="false" plus data-extraction rules that exclude every domain for both cloud backup and device-to-device transfer.

## Tried and ruled out
- allowBackup="false" on its own: on targetSdk 31+ it stops cloud backup but NOT device-to-device transfer, so the unencrypted Drift DB (which holds a JWT copy) would still move to a new phone.
- A fullBackupContent file: with allowBackup="false", Android 11 and older back up nothing, so the file would be dead config.

## Watch out
- Old builds still upload a plaintext preview on every star, so clean the live column only after every device runs the new build.
- Stars made offline never reach the server (not in the outbox), and an unstar on another device is never synced down.

In the code:
- toggleStar / getStarredMessages in lib/infrastructure/repositories/message_repository_impl.dart
- starred card text → MessageBodyText(messageId: msg.localId, ...) in lib/features/starred_messages/screens/starred_messages_screen.dart
- android/app/src/main/res/xml/data_extraction_rules.xml, AndroidManifest android:dataExtractionRules
