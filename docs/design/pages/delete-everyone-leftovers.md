# Delete for everyone leaves nothing behind (spec, rev 1)

Status: **spec PASS 2026-11-17, all defaults. Client part (§3) BUILT 2026-11-17**, 1417/1417
(baseline 1405 + 12 in `test/offline/delete_everyone_leftovers_test.dart`; two older tests now
expect `reply_preview: ''`). Device check pending, uncommitted. No server change, no live server
read yet.

Device round 1 (2026-11-17), FAIL then fixed: the Media tab and open reply quotes kept the
deleted photo/text until reopened. The quote now watches its parent row (`watchByAnyId`),
and the Media tabs and Starred drop ids from a live `deletedMessageIdsProvider` stream
(`watchDeletedServerIds`); +3 live tests. **Device round 2 PASS 2026-11-18.**

Build notes: the refetch filter (`_filterUnresolvedOrChanged`) skips rows deleted on both sides,
or the blanked body would refetch them forever. The start-up sweep skips its UPDATE when nothing
matches, because a Drift update re-emits every watcher even when it changes no row. Phase 2 (the client build) goes to a fresh session. The server part (§5) waits
for a live read the user must allow first.

Covers audit findings **F5** and **F6** in `docs/audits/2026-11-16-security-cloudflare-skill.md`
(both medium), the open live check **L6**, and one extra finding from this read (**R**, §1.4).

---

## 1. Why (code read 2026-11-17, `main` at `be0e2f1`)

Line numbers in `message_repository_impl.dart` are from the working tree, which has another
session's uncommitted edit in that file. Re-find them by name in phase 2.

### 1.1 A deleted message keeps its ciphertext on the phone

A delete for everyone only sets `isDeletedForEveryone`. Every write path keeps
`encryptedBody` and `iv`:

| Write path | Where | Keeps the body |
|---|---|---|
| Tombstone in the ingest commit | `ingest_boundary.dart:182-189` | Yes, writes only the flag |
| SSE flag change (pin/delete) | `ssePinDeleteCompanion`, repo :464-494 → ingest commit | Yes, copies `existing.encryptedBody` |
| Fetch / history sync mapper | repo :5732 (`is_deleted_for_everyone` read from the server; the sync deliberately fetches deleted rows, :4732) | Yes, stores the server ciphertext |
| Cancelled own send | `ingest_boundary.dart:163-170` | Yes |
| My own delete for everyone | `deleteMessage`, repo :2755-2800 | Yes, copies `msg.encryptedBody` |
| FCM background cache | `fcm_service.dart:495-520` | Writes the body and never reads the server's flag |

The decrypted text also stays in the in-memory `BodyCache` (`core/decrypt/body_cache.dart`),
which has no way to drop one id, only `clear()`.

### 1.2 F5: the reply quote reads the deleted parent

`reply_quote.dart:23-27` loads the parent by local or server id with no flag check. "Message not
available" shows only when **no row** is found (:206-208). A tombstoned row is found, so:

- a text parent goes to `MessageBodyText` (:236-246), which decrypts the kept ciphertext;
- a photo or video parent shows its thumbnail (`thumbServerId = original?.serverId`, :258).

### 1.3 F6: the media stays on the phone and in the gallery

- `mediaBlobStore.forgetLocal` (media_blob_store.dart:511-533, removes the blob rows, their files
  and the `media_clear` copies) runs only on expiry (repo :1005) and on a cancelled send
  (repo :2282). A tombstone never calls it, on either phone.
- The Media gallery (`media_gallery_service.dart:20-27`) lists `message_media` from the server by
  chat and type. All four tabs of `media_docs_screen.dart` use it (:303, :371, :442, :724). A tap
  opens the viewer by server id (:213-229) → `getDecryptedMedia` (repo :3373) →
  `requestBlob`: the local file if present, else a fresh **server download**.

### 1.4 R (new): every reply uploads a copy of the parent's text

`sendMessage` derives a preview of the parent (repo :1556, `_deriveReplyPreview` :5769, up to 60
characters of text), encrypts it with the chat key and sends it as `reply_preview` (repo :1634).
No phone reads that field any more: schema v11 dropped the local column and both ingest paths skip
it (repo :4921, :5601). So the parent's text lives on in every reply's server row, after the
parent is deleted for everyone, readable by any member's phone that holds the key. It is dead
data with a privacy cost.

### 1.5 The server, by the rules recorded 2026-11-15 (bible §7.6, §7.7)

- `messages` list/view rules check membership and expiry only. A deleted row stays listed with its
  `encrypted_body`, and the update rule forbids anyone but a superuser from changing
  `encrypted_body`/`iv`. So the ciphertext stays on the server for good.
- `message_media` list/view rules check membership and `message_id.expires_at` only. A deleted
  message's photo stays listed and downloadable until its `expires_at`, when `media_expiry.pb.js`
  deletes it. Whether the `file`/`thumbnail` fields are **protected** (needing a file token) is
  not recorded.

This is what L6 asks. It is a code-and-notes read, not a live one (§5).

---

## 2. Which places show a deleted message today

| Place | Today | Why | Change |
|---|---|---|---|
| Chat list, bubbles | Hidden | `watchMessages` filters the flag (messages_dao.dart:19-24) | None |
| In-chat search | Hidden | Searches only the chat list's items (chat_screen.dart:544-548) | None |
| Home preview | Hidden | `conversationLastMessageProvider` filters (message_body_provider.dart:145-151) | None |
| Pinned | Hidden | `watchPinnedMessages` filters (messages_dao.dart:384-389) | None |
| Albums | Hidden | album query filters (messages_dao.dart:400-406) | None |
| Copy / star in selection | Skipped | chat_screen.dart:850-855, :880-883 | None |
| **Reply quote** | **Shows text or thumbnail** | §1.2 | Q1 |
| **Starred, online** | **Shows** | `getStarredMessages` lists server star records and never reads the local flag (repo :3302-3338); the screen decrypts the body (starred_messages_screen.dart:285) and the thumbnail (:208) | S1 |
| **Starred, offline** | **Shows** | `messagesDao.getStarredMessages` has no flag filter (messages_dao.dart:369-374) | S1 |
| **Media gallery (4 tabs)** | **Shows** | §1.3 | G1 |
| **Media viewer** | **Opens** | Reached only from the gallery and Starred once bubbles are hidden; serves the local file or a server download | Closed by G1 + S1 + B2; server copy by §5 |
| Notifications | Tray entry stays | One entry per chat, text is the sender name plus "Sent you a message" (fcm_service.dart:607-627, 670-693); the server sends no preview | D-7 |

---

## 3. Changes (client, phase 2)

**B1. A deleted row keeps no ciphertext.** One rule, applied where rows are written:

- In `IngestBoundary.commit`: an upsert whose row has `isDeletedForEveryone = true` is written with
  `encryptedBody: ''` and `iv: ''`; the tombstone loop writes the same two blanks. This covers
  SSE, fetch, sync and cancelled sends in one place.
- `deleteMessage(forEveryone: true)` writes `''`/`''`.
- The FCM background cache skips the write when the fetched record has
  `is_deleted_for_everyone = true`.
- **Rows already on phones**: one idempotent sweep at start-up (D-2), after the database opens:
  `UPDATE messages_table SET encrypted_body = '', iv = '' WHERE is_deleted_for_everyone = 1 AND
  (encrypted_body != '' OR iv != '')`, plus `forgetLocal` for each such row's server id.

`DecryptPass` already skips empty bodies (decrypt_pass.dart:170, :350), so blank rows never churn
to `failed`.

**B2. A deleted row's media and plaintext are forgotten.** After the commit's transaction (file IO
stays outside it), for every row the commit flagged: `mediaBlobStore.forgetLocal(serverId)` and
`bodyCache.remove(localId)`. `BodyCache` gets that one-line `remove`. `deleteMessage(forEveryone)`
does the same on the sender's phone (D-3). A kill between the flag and the files leaves files the
B1 sweep removes on the next start.

**Q1. The quote treats a deleted parent as gone.** In `reply_quote.dart`, a found row with
`isDeletedForEveryone` takes the same branch as no row: the line "Message not available" in
`inkSoft` (the prior choice), no type icon, no thumbnail. Album covers already come from a
filtered query.

**S1. Starred hides deleted messages.** `getStarredMessages` skips a server star record whose local
row is flagged; the offline DAO query adds `isDeletedForEveryone = false`. The star record itself
stays on the server (D-4).

**G1. The gallery hides deleted messages.** `fetchMediaPage` adds
`&&message_id.is_deleted_for_everyone=false` to its filter (D-5). That covers media whose message
is not on this phone. Members can view `messages`, so the relation filter is allowed. Phase 2
proves it on a device (a deleted photo leaves the Photos tab).

**R1. Replies stop uploading a parent preview.** `sendMessage` sends `reply_preview: ''` and
`_deriveReplyPreview` goes, with any test that only covers it. Old builds still send it; nobody
reads it either way. Old values on the server are §5.

---

## 4. Decisions (defaults in bold)

| # | Question | Options |
|---|---|---|
| D-1 | Quote text for a deleted parent | **"Message not available" (same as a missing parent, prior choice)** / "Message deleted" |
| D-2 | Clean rows already on phones | **Start-up sweep, no schema bump** / Drift migration (bumps three migration tests and hand-written generated code) |
| D-3 | Sender's own phone | **Also blanks the body and forgets its media** / keeps its own copy |
| D-4 | Star record of a deleted message | **Hide it, keep the server record** / also unstar on the server |
| D-5 | Gallery filter | **Server-side relation filter in the query** / join against local rows (misses media not on the phone) |
| D-6 | Viewer already open when the delete lands | **Stays open; the next open is blocked** / close it live |
| D-7 | Tray notification of a deleted message | **Leave it (no message text in it)** / cancel the chat's entry when its newest message is deleted |
| D-8 | Reply draft in the composer whose parent gets deleted | **Leave it (the draft's preview is in memory; once sent, its quote reads "Message not available")** / drop the draft |
| D-9 | Stop sending `reply_preview` (R1) | **Yes** / keep sending it |
| D-10 | Live read L6 (§5) | **Ask the user before any SSH or server read** (needs a yes, not part of this PASS) |
| D-11 | Server fix after L6 | **(a) hook + rule + one-off cleanup** / (b) rule only / (c) client only |

---

## 5. Server part (L6), needs the user's go-ahead

The client changes in §3 stand alone: phones stop showing, keeping and listing deleted content.
They do not stop a modified client from downloading what the server still serves.

**L6 read (read-only, after a yes; over Tailscale SSH, on a `.backup` copy of `data.db`):**

1. How many `messages` rows have `is_deleted_for_everyone = 1` and a non-empty `encrypted_body`.
2. How many `message_media` rows point at such messages, and whether their files are on disk.
3. Whether `message_media.file` and `.thumbnail` are protected fields.
4. How many rows have a non-empty `reply_preview`.
5. The live `message_media` list/view rules (to confirm §1.5 still holds).

**Fix (D-11 a, default), planned only after the read and a second yes:**

- A flat `onRecordAfterUpdateSuccess("messages")` hook: when `is_deleted_for_everyone` turns true,
  delete the message's `message_media` rows (PocketBase removes the files) and blank
  `encrypted_body`, `iv` and `reply_preview` with a superuser save. Both body fields are
  **Required** in the schema (bible §7.6), so the save must skip validation
  (`$app.saveNoValidate`) or the field options must change; the dry run decides.
- `message_media` list/view rules gain `&& message_id.is_deleted_for_everyone = false`.
- One-off cleanup of rows already deleted (items 1, 2, 4 above), after a dated backup.
- Same method as N1–N9 and membership-rules: dry run on a copy, rollback tested, then live, and
  the hook follows the `pb-hook-pitfalls` rules (flat hooks, no heredoc that eats `$app`).

---

## 6. Tests (phase 2)

- Ingest: a tombstone blanks `encryptedBody`/`iv` and calls `forgetLocal` once per id; a repeat
  tombstone is a no-op; an upsert carrying the flag is blanked; a cancelled send is blanked.
- `deleteMessage(forEveryone: true)` blanks and forgets; delete for me keeps the body.
- Start-up sweep blanks old flagged rows and leaves others alone; running it twice changes nothing.
- `BodyCache.remove` drops one id and keeps the rest.
- Reply quote: a flagged parent renders "Message not available" and no thumbnail (widget test).
- Starred: a flagged local row is left out online (fake server list) and offline (DAO query).
- Gallery: the filter string carries the relation clause.
- Send: a reply's create body has `reply_preview: ''`.

**Device check (two phones):** A sends a text and a photo, B replies to both and stars both,
B opens the gallery. A deletes both for everyone. On B: both quotes read "Message not available"
with no thumbnail; Starred and the Photos tab no longer list them; the photo is gone from the
app's cache folder. Same after B force-quits and reopens. A's phone shows the same.

---

## 7. Watch-outs for phase 2

- Cancelled own sends are flagged too. The cancel paths use the local id only
  (`_markCancelledOnServer`, repo :2290), and a text cancel goes through its outbox entry, so a
  blank body should not matter. Confirm before relying on it.
- `mediaFileProvider` (chat_provider.dart:63) is not auto-disposed: it can hold a path to a file
  `forgetLocal` just deleted. Every entry point is closed by §3, so the cost is a broken image in
  a viewer already open (D-6).
- The SSE handler builds its companion from a row read before the commit; B1 lives inside the
  commit so it wins either way (same reason as the cancelled-send rule, learning 2026-11-01).
- `reply_quote.dart` resolves local id first, then server id; the flag check goes on whichever row
  comes back.
