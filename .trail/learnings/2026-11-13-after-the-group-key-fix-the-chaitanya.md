---
title: "After the group-key fix, the restore's slowest step is the conversations step, which fetches each chat's member list one chat at a time"
author: Chaitanya
date: 2026-11-13
branch: main
cost: { minutes: 36, tokens: 361457 }
id: l-cf0c1885
scope: repo
status: active
src: agent
touches:
  - assets/mascot/capy.riv
  - docs/design/mascot/phase5/apply_phase5.py
  - docs/design/mascot/phase5/icon.py
  - docs/design/mascot/phase5/render.sh
  - docs/design/mascot/phase5/rig.commands
  - docs/design/pages/mascot.html
  - docs/design/pages/mascot.md
  - lib/features/chat/screens/chat_screen.dart
  - lib/features/chat/widgets/expiry_badge.dart
  - lib/features/chat/widgets/message_bubble.dart
---

## Decided
Device run 2026-11-13 (M52, release build, mobile data, the G1–G6 group-key build): each group's key walk took 1.0–2.4 s with 1–2 decrypt batches, even for groups with 14–19 versions and 3–5 dead ones. Chats took 2.6–4.7 s each. But "Full history sync starting" to the first chat took about 58 s with no log lines: that is the conversations step before the chat loop, which makes one member-list request per conversation, sequentially (26 chats at about 2 s each on mobile data). It is the next target for the 60 s restore goal, not the key walk.

## Watch out
The history-sync timing lines only cover the chat loop, so the conversations step is invisible in `[Sync]` totals; measure it from the "Full history sync starting" line to "chat 1/N".
Installing a plain `flutter build apk --release --target-platform android-arm64` over an earlier `--split-per-abi` build fails with INSTALL_FAILED_VERSION_DOWNGRADE (version code 1 vs 2001). Use `--split-per-abi`, or uninstall first when a data wipe is wanted anyway.

In the code: message_repository_impl.dart `_syncConversations` (conversation_members getFullList per conversation, expand user_id, inside the per-conversation loop), called at the start of `syncAllHistory`.
