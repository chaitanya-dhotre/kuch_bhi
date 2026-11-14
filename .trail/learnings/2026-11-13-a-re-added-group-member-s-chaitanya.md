---
title: "A re-added group member's earlier history can be shown by trusting the keys instead of storing their first join time"
author: Chaitanya
date: 2026-11-13
branch: main
cost: { minutes: 5, tokens: 135072 }
id: l-1393592b
scope: repo
status: active
src: agent
touches:
  - docs/design/pages/group-rejoin-history.md
  - lib/core/utils/group_visibility.dart
---

## Decided
Spec drafted 2026-11-13 (group-rejoin-history, awaiting the user's PASS; user chose "show it"). Before the member's current join time, a row shows only when it decrypts with a key this account holds, media included; after the join nothing changes. No first-join time is stored anywhere, so it works on a fresh install too.

Why it is enough: removal and leave keep the member's own group key rows on the server (since 2026-10-13), and every rotation (join, key-gap reconcile, removal) only makes a new version for the members of that moment. So a re-joiner gets their first-membership keys back from the key walk, never gets the versions made while they were out, and a brand-new joiner holds no version from before their join. The keys were always the real barrier; the join-time gate only added hiding of pre-join media rows, which skip the decrypt check.

## Tried and ruled out
Earliest own key row time as a stored floor, or a server first_joined_at column: same result while the keys hold, with a fetch, storage and invalidation (or a live schema change) on top.
Re-wrapping the gap versions for the re-joiner: reveals what the group said after removing them.

## Watch out
Group media downloads decrypt with the newest group key only, so a photo sent before the latest key change fails on any phone that has not cached it (code read, not yet seen on a device). The spec fixes it by trying every key the account holds.
Removals before 2026-10-13 deleted the member's key rows; that history stays hidden.

In the code: lib/core/utils/group_visibility.dart isGroupRowVisible; message_repository_impl.dart _groupCutoff/_rowsToMessages, removeMemberFromGroup step 4, _rotateGroupKeyNow, _reconcileGroupKeyGaps; media_blob_store.dart decrypt step (resolveKey at message_repository_impl.dart:149). Spec docs/design/pages/group-rejoin-history.md.
