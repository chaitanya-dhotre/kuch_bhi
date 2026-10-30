---
title: "Opening a chat re-created a receipt for every already-read message, which flooded PocketBase's create rate limit"
author: Chaitanya
date: 2026-10-30
branch: main
cost: { minutes: 8, tokens: 39694 }
id: l-30bf6504
scope: repo
status: active
src: agent
---

## Decided
Mark-read lists ALL of my receipts in the conversation (not only unread ones), updates only the unread ones, and creates receipts only for incoming messages that have none. Smallest correct change; no batching or retry needed.

## Tried and ruled out
Batching via /api/batch or retry-on-429: they would hide the flood, not stop it. The creates were never needed: the receipts already existed.

## Watch out
The old filter had `read_at=""`, so the "already has a receipt" set missed every read message and each open fired one create per old incoming message. Live 2026-10-30: receipt creates 44x200, 6,700x400 (unique index), 4,326x429 under the default *:create 20 per 5 s. The 400 fallback also rewrote read_at on each open. A genuinely missing receipt that 429s is not lost: the next open retries it.

In the code: MessageRepositoryImpl.markConversationRead; test test/offline/mark_read_receipts_test.dart. Live check: sudo sqlite3 -readonly /opt/pocketbase/pb_data/auxiliary.db, table _logs, json_extract(data,'$.status')=429.
