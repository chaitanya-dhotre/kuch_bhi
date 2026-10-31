# Bug wave 3: backlog 13.2 + 13.3 (2026-10-31)

Claude end to end (sync/receipt logic). User device PASS 2026-10-31.

## 13.3 "3 Oct Test" gains an unread on every chat open, preview stuck on a skeleton

Evidence (read-only copy of the M52's local drift DB, no server access):
`conversations_table` row `zrwszx3uifdjlkn` had `unread_count=9`, `last_read_local_id` empty,
`last_message_at=1791017126`. Its newest row `acdbq22ef7v3c9f` had `created_at=1791017126` and
`decrypt_state=pending`; every older row was `key_missing`.

Cause (two parts, same trigger):
- The resume delta is inclusive, and F2a (`_filterUnresolvedOrChanged`) keeps re-ingesting unresolved
  rows on every fetch on purpose. That is how a late key heals a row.
- After each re-ingest, `_cacheMessagesBatch` calls `_bumpConversationForIncoming(records.first)`. Its
  guard compared the record's millisecond `created` against drift's `lastMessageAt`, which drift
  stores in seconds. `10:00:00.123` is always after `10:00:00`, so the same row bumped the badge
  again on every fetch. Only this group showed it because its newest row is the only unresolved one.
- The same re-ingest wrote `pending` (key present, decrypt missed) over DecryptPass's `key_missing`.
  The preview's body provider had already resolved to null and nothing re-runs DecryptPass for that
  row, so `_BodyPlaceholder` showed a skeleton forever.

Fix (`lib/infrastructure/repositories/message_repository_impl.dart`):
- `_bumpConversationForIncoming`: compare at second precision. If the record is in the same second as
  `lastMessageAt`, it badges only when the row was not stored before this ingest (new
  `wasStored` arg: `existingById` in the batch path, `existing` in the single path). The first
  version skipped every same-second row, and the reviewer showed that a reply landing in the same
  second as my own send would never badge.
- `_ingestDecryptState`: a miss on unchanged ciphertext keeps an earlier `key_missing`/`failed`.
  Key arrival still heals: a successful decrypt returns `ready` first.

Rejected: skipping the bump when the row already exists locally. FCM background
(`_cacheMessageBackground`) inserts the row without bumping unread and relies on the fetch path to
badge it, so that would lose badges for messages received while the app was closed.

## 13.2 Receipt status re-written in a loop

Cause: `_updateMsgReceiptStatus` wrote the computed status even when it equalled the stored one.
In a group where not everyone has read, own messages stay `sent`/`delivered`, so every reconcile
(per fetch, per receipt event, per user reconcile) rewrote them and each write re-emitted the whole
message list. Fix: return early when computed == stored status. The empty status (tick still owed)
still gets written.

## Tests (+3, `test/offline/refetch_churn_test.dart`)

| Test | RED | GREEN |
|---|---|---|
| 13.3 refetch keeps unread + verdict | old code: unread 1 → 3 after two refetches; with only the count fix: verdict `pending` | yes |
| 13.3 same-second new message still badges | the first fix (skip every same-second row): 1, expected 2 | yes |
| 13.2 unchanged status writes nothing | old code: 2 list emits for 2 reconciles | yes |

## Gates

- `flutter test`: 752/752 (749 + 3). No existing test changed.
- `flutter analyze`: 0 errors. The one issue on a changed line is the existing `r.created` deprecation.
- `git diff --check`: clean. `trail check`: no conflicts.
- Frozen code, function-level diff: only `message_repository_impl.dart` changed in `lib/`. It touches
  `_cacheMessagesBatch` (bump call + ingest-state args), the single-row cache path (same two
  calls), `_ingestDecryptState`, `_bumpConversationForIncoming` and `_updateMsgReceiptStatus`.
  Nothing in `lib/core/decrypt/`, `encryption_service.dart`, key handling, upload or any `dispose()`.

## Independent review (fresh context)

PASS. It ran the new tests against HEAD in a throwaway worktree: both original tests fail there and
pass on the diff. One SHOULD (the same-second badge) was fixed with a RED test (above), and the stale
"no unread bump here" comment was fixed. Two NITs were left as is: the fixed 600 ms settle sleeps
follow the existing `idempotent_ingest_test.dart` pattern, and the verdict assertion's RED was
proven separately (above). Unchecked: whether the live server writes `conversations.last_message_at`.
No hook in the repo does.

## Device (M52, Claude via `flutter run` + Marionette, read-only)

- Before: "3 Oct Test" unread 9, newest row `pending`.
- After two full resyncs that re-fetched that group (startup, then a hot restart on the final code)
  plus two background/resume cycles: still 9, row `key_missing`, preview "Can't decrypt".
- Opening "Things To Fix Lol": 1× `watchMessages EMIT`, 0 receipt status writes (was 17 and 28).
- Nothing was sent, reacted to, starred or deleted. The 9 stays: it is the old wrong count, and it
  clears the first time the group is opened.

## Next

User device PASS 2026-10-31; committed with the test file and a learning.
