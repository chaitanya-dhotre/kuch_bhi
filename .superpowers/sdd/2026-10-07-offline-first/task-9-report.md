# Task 9 report — Placeholder UI + drop `decrypted_body` + cancellable search

**Status: DONE.** RED 6/6 (right reasons) → GREEN 6/6 → full suite **124 pass**
(119 + 5 new; read_paths 3 kept its count with sanctioned expectation updates)
→ `flutter analyze` **0 errors, 88 issues (= legacy baseline)**.
Commit subject: `[Offline P4] Placeholder UI + drop decrypted_body + cancellable search`
(own hash cannot appear in its body).

**Device captures (brief Step 5): DEFERRED** — progress.md ruling (2026-10-07,
Task 4 line): "device/emulator captures deferred to batch checkpoints … widget
tests are the per-task gate". The capture clause is satisfied by that ruling;
this task's gate = widget/unit tests, all green.

## Files

| # | File | Change |
|---|------|--------|
| 1 | `lib/features/chat/widgets/message_body_text.dart` | NEW — `MessageBodyText` + `_BodyPlaceholder` (keyed) + `ConversationPreviewText` |
| 2 | `lib/data/local/database/tables/messages_table.dart` | `decryptedBody` column REMOVED (v10 note) |
| 3 | `lib/data/local/database/app_database.dart` | schemaVersion **10**; `from < 10` upgrade = seed session cache for in-flight rows + `ALTER TABLE … DROP COLUMN decrypted_body`; NEW `@visibleForTesting AppDatabase.forExecutor` |
| 4 | `lib/data/local/database/app_database.g.dart` | build_runner regen (−84 lines, `decrypted_body` gone) |
| 5 | `lib/data/local/database/daos/messages_dao.dart` | `getUndecryptableRows` filter → `decrypt_state IN ('pending','key_missing')`; `getMessageByServerId` dupe preference → cache-resident; `findSystemMessage` → cache compare; `cacheDecryptedBody` → cache put + state-only DB write |
| 6 | `lib/core/utils/group_visibility.dart` | `isGroupRowVisible(decryptedBody:)` → `isGroupRowVisible(decryptState:)` (same rule, state projection) |
| 7 | `lib/features/chat/providers/message_body_provider.dart` | + `drainStampWireProvider` (carry-in invalidation bridge), + `conversationLastMessageProvider` |
| 8 | `lib/features/chat/widgets/message_bubble.dart` | body read → `bodyCache` fast-path + `ref.watch(messageBodyProvider(id))`; text/emoji/system surfaces → `MessageBodyText`; voice `durationText` → resolved body |
| 9 | `lib/features/chat/screens/chat_screen.dart` | + public `ConversationSearchController` (200ms debounce, generation cancel token, ephemeral match list); `_onSearchChanged` delegates; `isMatch` highlight from match set |
| 10 | `lib/core/widgets/chat_tile.dart` | + optional `subtitleWidget` (string path byte-compatible for existing callers/tests) |
| 11 | `lib/features/home/screens/home_screen.dart` | `_ConversationTile` → ConsumerWidget + `ConversationPreviewText` |
| 12 | `lib/infrastructure/repositories/message_repository_impl.dart` | all column refs removed; enqueue `bodyCache.put`; drain/media `onBodyStamped`; ingest decrypt → cache put (pre-commit); `searchMessages` = decrypt-on-query; `_rowToMessage` hydrates entity from cache; system emits cache-put |
| 13 | `lib/features/chat/widgets/reply_quote.dart` | row-body labels → `bodyCache.get` |
| 14 | `lib/features/groups/screens/create_group_screen.dart` | system-row body → cache put (field removed) |
| 15 | `pubspec.yaml` / `pubspec.lock` | dev dep `sqlite3: ^2.9.4` (already in graph as drift's transitive; promotion = lock's only change) |
| 16 | `test/offline/placeholder_ui_test.dart` | NEW — brief tests 1,2,3,4 + carry-in test 6 |
| 17 | `test/offline/read_paths_char_test.dart` | sanctioned expectation updates (brief test 5) |
| 18 | `test/group_visibility_test.dart` | signature/values follow the state gate |
| 19 | `test/repair_query_test.dart` | `_row` seeds `decryptState` instead of the dropped field |
| 20 | `test/offline/ingest_boundary_test.dart`, `outbox_core_test.dart`, `outbox_worker_test.dart` | compile-forced companion-field removals; outbox_core/worker body seeds → `bodyCache.put` (real sender reads the cache now) |
| 21 | `test/offline/send_fetch_char_test.dart`, `always_commit_test.dart` | **compile-forced** retarget of dropped-column assertions to `bodyCache` (see corrections 1) |
| 22 | `test/message_bubble_sender_test.dart`, `terminal_banner_test.dart` | hermetic `messageBodyProvider` override (bubble now always watches it — T4's outbox-override precedent) |

## AS-BUILT signatures (handoff for T10+)

```dart
// lib/features/chat/widgets/message_body_text.dart
class MessageBodyText extends ConsumerWidget {
  const MessageBodyText({super.key, required String messageId,
      required String styleContext, TextStyle? style});
  // styleContext: 'bubble.mine' | 'bubble' | 'emoji' | 'system' | 'preview'
  static ValueKey<String> placeholderKey(String messageId); // body-placeholder-<id>
  // build: bodyCache.get sync fast-path ?? ref.watch(messageBodyProvider(id));
  //   body != null → Text(slot style; preview = 1-line ellipsis);
  //   else → _BodyPlaceholder (🔒 + skeleton bar) under placeholderKey —
  //   covers loading AND resolved-null (key_missing/failed); never '', never throws.
}
class ConversationPreviewText extends ConsumerWidget {
  const ConversationPreviewText({super.key, required Conversation conversation,
      required String fallback, TextStyle? style});
  // last row (conversationLastMessageProvider): type=='text' → MessageBodyText
  // ('preview'); anything else / no row → stored lastMessagePreview ?? fallback.
}

// lib/features/chat/providers/message_body_provider.dart
final Provider<void> drainStampWireProvider;   // repo.onBodyStamped →
    // ref.invalidate(messageBodyProvider(id)); armed inside decryptPassProvider
    // (every null-resolving read funnels through the coalescer's
    //  ref.read(decryptPassProvider); T8-suite overrides skip the body)
final StreamProvider.autoDispose.family<MessagesTableData?, String>
    conversationLastMessageProvider;           // newest non-deleted row / conv

// lib/features/chat/screens/chat_screen.dart (public, test-importable)
typedef ConversationBodyResolver = Future<String?> Function(String messageId);
class ConversationSearchController {
  ConversationSearchController({required ConversationBodyResolver resolveBody,
      Duration debounce = const Duration(milliseconds: 200)});
  final Duration debounce;                     // pinned 200ms (brief)
  void Function(List<int> matchIndices)? onResults;
  @visibleForTesting int cancelCount;          // instrumented cancel token
  List<int> lastMatches;                       // newest generation only
  void setQuery(String query, {required List<(int, String)> candidates});
  void dispose();
  // keystroke → ++generation (aborts in-flight at next checkpoint) →
  // debounce Timer → per-id resolveBody (= messageBodyProvider.future in
  // production) → matches land ephemerally; never touches DB/bodyCache
  // beyond the provider's own reads (spec §19.1).
}

// message_repository_impl.dart
void Function(String messageId)? onBodyStamped; // fired after dual-truth txn
    // lands real ciphertext (_sendTextOp ~:1000, media upload stamp ~:1280)

// group_visibility.dart
bool isGroupRowVisible({required DateTime createdAt,
    required DateTime? memberJoinedAt, required String decryptState,
    required String type});
// non-media visible iff decryptState=='ready' (own optimistic rows keep the
// column default 'ready'); media exempt; pre-join hidden — same as pre-drop.

// app_database.dart
int get schemaVersion => 10;
AppDatabase.forExecutor(QueryExecutor);        // @visibleForTesting
// onUpgrade from<10: SELECT local_id,decrypted_body WHERE body IS NOT NULL AND
// (encrypted_body='' OR '__pending__') → bodyCache.put (session-only),
// then ALTER TABLE messages_table DROP COLUMN decrypted_body.
```

Carry-in B (T8 review Important) — AS-BUILT flow:

1. `sendMessage` txn success → `bodyCache.put(localId, plaintext)` (spec §5.1).
2. `_sendTextOp` reads plaintext from `bodyCache` (column gone); after the
   dual-truth txn → `onBodyStamped?.call(localId)`.
3. `decryptPassProvider` arms `drainStampWireProvider` → handler
   `ref.invalidate(messageBodyProvider(id))` (alive-guarded,
   identical-guarded on dispose).
4. Same pattern for the media-upload stamp; media duration stubs cache-put at
   insert; `_emitSystemMessage`/`_emitLocalSystemMessage`/create-group cache-put.

## TDD evidence

**RED** (`flutter test test/offline/placeholder_ui_test.dart` + updated
read_paths — captured pre-implementation; stub files only where the brief
creates new entry points):

```
00:00 +0 -1: T9.1 bubble with key_missing row renders placeholder … [E]
  Expected: exactly one matching candidate
    Actual: _KeyWidgetFinder:<Found 0 widgets with key [<'body-placeholder-msg_keymiss000001'>]: []>
10:00 +0 -2: T9.2 conversation preview shows placeholder, fills when provider emits [E]
  (stub MessageBodyText/ConversationPreviewText → UnimplementedError in build)
10:00 +0 -3: T9.3 migration bytes … [E]
  Expected: false  Actual: <true>   (sqlite_master still carries decrypted_body)
10:00 +0 -4: T9.4 search: rapid ab keystrokes … [E]
  UnimplementedError: ConversationSearchController — Task 9 in progress
10:00 +0 -5: T9.6 own-sent NEVER placeholder … [E]
  Expected: 'own hello'  Actual: <null>   (enqueue cache put missing — carry-in B)
00:00 +0 -5: Some tests failed.

read_paths (sanctioned expectation updates, RED against old surfaces):
  bubble: Found 0 [body-placeholder-l1] (old '🔒 Encrypted' string path)
  preview: Found 0 [body-placeholder-<id>] (old 'New message' string path)
  search: Expected ['l_beta', 'l_alpha'] Actual: [] (column-based filter pre-rewrite)
```

All six failures are at the named entry points for the missing feature — no
compile-stage RED was accepted (each stub file compiled; see T8 precedent).

**GREEN** (after implementation):

```
00:03 +8: All tests passed!   (placeholder 5 + read_paths 3, paired run)
00:00 +1: T9.3 migration bytes: sqlite_master has no decrypted_body; … — All tests passed
00:07 +124: All tests passed!   (FULL suite — flutter test)
88 issues found. (flutter analyze — 0 errors, == 88 baseline)
```

**Suite count:** 119 (T8 baseline) + 5 (new placeholder tests) = **124**.
No other file changed its test count.

**Migration proof (gate):** `test/offline/placeholder_ui_test.dart` T9.3
queries REAL bytes: `SELECT sql FROM sqlite_master … name='messages_table'`
(fresh onCreate + upgraded file) asserts `decrypted_body` absent, and
`SELECT * FROM messages_table` row map has no such key; part (b) pre-seeds a
literal v9 DDL + plaintext row via `package:sqlite3`, opens through
`AppDatabase.forExecutor(NativeDatabase(file))` (production onUpgrade), then
asserts column gone, row+ciphertext survive, `PRAGMA user_version == 10`.
Output line: `00:00 +1: All tests passed!` (plain-name T9.3).

**v9→v10 path exists:** `app_database.dart` `if (from < 10)` block (above);
exercised by T9.3(b) against real bytes, not code inspection.

## Carry-in B evidence (test 6, RED first)

T9.6 sequence (all assertions green in final run):

1. `sendMessage` held at a gated create → row still `__pending__` →
   `bodyCache.get(localId) == 'own hello'` (RED before fix: `null`).
2. Bubble frame 1: `find.text('own hello')` present, placeholder ABSENT —
   zero-flash (sync cache fast-path in `MessageBodyText`).
3. Simulated backgrounding: `bodyCache.clear()` + remount → keyed placeholder
   FOUND (explicit from-null baseline — proves step 4 must RE-resolve).
4. Gate opens → drain writes ciphertext + `status='sent'` → `onBodyStamped`
   fires (instrumented: `wired=true`, `handler alive=true`, second `runFor`
   + `cache put` observed during debugging; instrumentation removed after) →
   placeholder ABSENT, `find.text('own hello')` present, no exception.

Invalidation is load-bearing: without step 4's invalidate the provider holds
the phase-3 null forever (row streams never invalidate the family — exactly
the T8 concern).

## Corrections vs brief (reality rule)

1. **`send_fetch_char_test.dart` + `always_commit_test.dart` are NOT
   byte-identical (dispatch N violation — forced).** Both reference
   `MessagesTableData.decryptedBody`; dropping the column makes them
   **fail to compile** (the dispatch's own test 3 mandates the drop). Minimal,
   semantic-preserving retarget: assertions read `bodyCache.get(<id>)` —
   same contracts ("enqueue lands plaintext", "keyless rows never get a
   body", phase-2 predicate/heal proof) with the plaintext home moved to the
   session cache. Diffs are 3 sites + 1 import per file (shown in
   `git diff`); every other `test/offline/char_*` file — `char_harness.dart` —
   and `read_paths`' non-expectation code are untouched. Reality rule:
   smallest spec-satisfying choice; no assertion's PASS/FAIL meaning changed.
2. **Drain-stamp wire lives in `decryptPassProvider`, not
   `messageBodyProvider`.** Reading the wire from `messageBodyProvider`
   forced repo construction into T8's provider-only test containers
   (`Bad state: pocketbaseClientProvider must be overridden` — reproduced,
   fixed). Coverage is equivalent: a provider value of `null` can only come
   from the coalescer flush, which does `ref.read(decryptPassProvider)` —
   so any provider that could sit on a placeholder has the wire armed.
3. **`Message.decryptedBody` (domain entity) KEPT, hydrated from
   `bodyCache.get(r.localId)` in `_rowToMessage`.** The dispatch rewires
   three named surfaces to the provider; dropping the entity field would
   force edits through reply_quote/starred/context-menu/pinned/voice/chat
   reply-preview + tests constructing `Message(...)`. Entity value = session-
   cache snapshot (never DB) — non-dispatched consumers keep working; the
   three dispatched surfaces use the provider (live) per spec §5.1.
4. **`isGroupRowVisible` signature changed** (`decryptedBody` →
   `decryptState`) — the column no longer exists to pass. Rule mapped
   1:1: non-media visible iff `decrypt_state == 'ready'` (pre-drop: body
   non-null). Own optimistic rows carry the column default `ready` → stay
   visible. `group_visibility_test.dart` restated against the state column
   (same expectations).
5. **Widget-test two-queue drain rule (test-side).** The fake clock advances
   only on `pump`, real-queue completions (HTTP/FFI) only inside
   `runAsync`; a half-finished fake-zone drift op wedges the harness
   teardown (`db.close()` → 10-minute timeout, reproduced). Tests use a
   documented `_drain` helper (alternate `runAsync(50ms)` + `pump(60ms)` —
   the 60ms advances the coalescer's 50ms window). Discovery cost: three
   probe rounds; all instrumentation removed (decrypt_pass.dart byte-equal
   to HEAD, verified by empty `git diff`).
6. **v9 DDL for the upgrade proof is a captured literal** (printed from
   drift's own `sqlite_master` at schemaVersion 9, pre-drop) embedded in the
   test; `package:sqlite3` promoted to dev dependency (already in the lock
   via drift — lock delta = 2 lines); `AppDatabase.forExecutor` added
   (`@visibleForTesting`) because `AppDatabase.test()` only ever exercises
   onCreate.
7. **Migration seeds the session cache for in-flight rows before dropping
   the column** (`encrypted_body='' OR '__pending__'` + body present →
   `bodyCache.put`). Without it the v9→v10 upgrade would orphan queued sends
   (their only plaintext copy dies with the column). Memory-only — spec §3
   intact; brief said "no backfill needed — provider handles" for readable
   ciphertext rows, which is unchanged.
8. **Brief's "SELECT * FROM messages" → real table name
   `messages_table`** (drift's actual `sqlite_master` name); assertions use
   the real bytes either way.
9. **Search surfaces:** brief's debounce/cancel/ephemeral-map landed in
   `chat_screen.dart` (`ConversationSearchController`); `repo.searchMessages`
   (exercised by read_paths test 3) was rewritten to the same
   spec §5.1 shape (metadata prefilter → `decryptPass.runFor(missing)` →
   cache filter → ephemeral hits) because its column filter could not
   compile post-drop.
10. **`ConversationSearchController` + `_drain` are public** so tests import
    them without pumping the full ChatScreen (presence/FCM stack) — brief's
    "instrument cancel token" seam.
11. **Media/system/local narrative bodies** (duration stubs, system rows,
    create-group row) cache-put at their existing insert sites — they are
    bodies by the spec's definition and the column was their only home.

## Self-review

- Placeholder key is `ValueKey('body-placeholder-<id>')` exactly (brief);
  placeholder renders `🔒` + skeleton bar — never `find.text('')`; ciphertext
  never reaches the bubble (T9.1 asserts `find.textContaining('QUFB')` absent).
- No plaintext at rest: column dropped (fresh + upgrade, real bytes);
  every writer of the old column either writes state-only, writes ciphertext,
  or puts the session cache (grep: `decryptedBody` survives only as the
  entity field + comments).
- Epoch discipline: ingest cache puts sit after the existing
  `sessionStillValid` guards (same window as the old column write);
  DecryptPass's T8 guards unchanged (file byte-identical).
- Guard 5 (moved code): no moved blocks — all edits are in-place rewrites of
  body reads/writes; `_sendTextOp`/`_cacheMsg*` structure preserved.
- Char-test byte check: `char_harness.dart` untouched; `send_fetch`/
  `always_commit` deltas = corrections 1 (compile-forced, minimal);
  `read_paths` = sanctioned.
- Analyze: initial delta +5 (3× `invalid_use_of_visible_for_testing` on the
  wire field, unused `_searchQuery` after highlight rewrite, unused drift
  import) — all fixed; final **88 == baseline, 0 errors**.
- No push, no superuser/PB elevated auth, zsh syntax, single commit at end.

## Concerns / carry-forward

1. **Kill-before-drain durability (ledgered, out of scope by dispatch):**
   plaintext lives only in the session cache between enqueue and drain —
   app killed/backgrounded in that window orphans the op (`_sendTextOp`
   defers on cache miss forever). The durable fix is T2's forward-carry
   (encryption at enqueue + keyless-queue design, spec §5.2 literal); this
   task's dispatch explicitly pins the drain-writes-ciphertext model
   (invalidation at the drain stamp), so the redesign stays out. Migration
   seeding (correction 7) covers the UPGRADE instance of this window only.
2. **Duplicate-id success path** stamps `serverId/status` via the ack but
   not ciphertext — after a cache eviction such a row needs the next fetch
   to re-land ciphertext before its body resolves (pre-existing shape;
   now visible because the column is gone).
3. **Local-only system rows** (`_emitLocalSystemMessage`) have no
   ciphertext ever — after cache eviction they hold the placeholder
   permanently until a matching server echo arrives (group rows get one;
   DM local-only rows do not).
4. **Group `key_missing` rows stay hidden** from `watchMessages`
   (state gate keeps char test 3 / always_commit byte-contract green —
   the placeholder in GROUPS is reachable only for `ready` rows whose cache
   is cold, own-sent rows, and DMs where `joinedAt == null`). Spec §14's
   "key-delay → placeholders" for group history therefore still shows an
   empty list until the key lands — same as pre-T9; flipping that surface
   would have broken the pinned char expectations (N). Ledger for T11/T12.
5. **Multi-container wiring**: `onBodyStamped`/`onApplied` are
   last-writer-wins across containers (T8 ledgered the same for
   `onApplied`) — fine while the app has one root container.
6. **FCM background inserts** still default `decrypt_state='ready'` with no
   ciphertext (T7-deferred one-liner `Value('pending')`) — post-T9 such rows
   render placeholders instead of being invisible; remains on the T11–12
   ledger.
7. **`getStarredMessages`/starred PB preview** reads `message_preview` from
   the server (entity field) — unaffected; the local star toggle now uploads
   `bodyCache.get(localId) ?? ''` (cold cache → empty preview on the server
   sidecar record — degrade, ledgered here).
8. **Spec §8 batch triggers** (post-commit / key-arrival `runFor` batches)
   still not wired (T8 concern 3, plan scope) — search now calls `runFor`
   directly, which incidentally exercises the batch path once per query.
