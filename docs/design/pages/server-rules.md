# Server rules: close the over-broad ones (spec, rev 1)

Status: **LIVE 2026-11-15** (spec PASS all defaults; dry run and rollback test passed; applied with the user's go-ahead). **Device PASS 2026-11-15.** Found while specifying
history sync; confirmed by a read-only live read on 2026-11-15
(`KUCH_BHI_PROJECT_BIBLE.md` §7 now holds the live rules).
Server-only change: no app build is needed if the checks below pass.
Nothing here has been run yet, not even on a copy.

## What is wrong

Message text and media stay end-to-end encrypted, so none of this exposes
what people wrote. It exposes who talks to whom and when, and lets a
signed-in user tamper with other people's chats.

The common cause: a rule says "you are a member of **some** chat"
(`@collection.conversation_members.user_id ?= @request.auth.id`) with no
link to the row being read.

| # | Collection, rule | Today a signed-in user can | Risk |
|---|---|---|---|
| R1 | `conversations` list, view | list every chat on the server (names, icons, settings) once they are in any chat | high |
| R2 | `conversations` update | rename any chat, change its icon, its disappearing timer, "only admins can message" | **high** |
| R3 | `conversation_members` list | list every membership: who is in which chat, with roles | high |
| R4 | `message_receipts` list | once they have sent any message, list every receipt: who read which message id, when | medium |
| R5 | `message_receipts` create | create a receipt in another person's name, already marked read. A forged read turns ticks blue and starts that message's disappearing clock on the server (`disappearing_stamp.pb.js`) | **high** |
| R6 | `message_receipts` update | the recipient can re-point their receipt at another message or chat | low |
| R7 | `message_media` create | attach a media row to any message in any chat | medium |
| R8 | `starred_messages`, `deleted_messages_for_me` create | create rows for another user (a "deleted for me" row hides a message on that user's phone at the next sync) | medium |
| R9 | `polls` list, view, update | same as R1/R2 (the app does not use polls today) | low |

Looked at and left alone: `messages`, `group_keys`, `group_invites`,
`reactions`, `friend_requests`, `friendships`, `blocked_users`,
`scheduled_messages`, `users` (list by any signed-in user is needed for
search; the key-backup fields are hidden by the 2026-10-30 hook).

## What the app needs from these collections (code read)

| Collection | Calls that must keep working |
|---|---|
| `conversations` | create (DM and group); `getOne` by a member, and by an invited user for the invite card (`friend_repository_impl.dart:466`); update of name, icon, `disappearing_duration`, `only_admins_can_message` by a member; delete by the creator when group creation fails (`group_create_service.dart:83`); realtime |
| `conversation_members` | list by `conversation_id` (members of my chat); list by `user_id="<me>"`; list by `user_id="<other>"` to find our shared DM (must return only chats we share); create, role update and delete as today; realtime |
| `message_receipts` | recipient creates their own (delivered, read; `fcm_service.dart:563`, `message_repository_impl.dart:2601,6151`); **the sender pre-creates an empty receipt for each other member** (`:6216`); recipient updates `delivered_at`/`read_at`; sender lists receipts on their own messages by `message_id` and by `conversation_id` (history-sync index); recipient lists their own; realtime |
| `message_media` | the sender creates one row for their own message; members list and view |
| `starred_messages`, `deleted_messages_for_me` | create for myself; list and delete my own |
| `polls` | nothing |

## New rules

`M` below stands for "I am a member of this row's chat":
`@collection.conversation_members.conversation_id ?= <chat id field> && @collection.conversation_members.user_id ?= @request.auth.id`.

| # | Rule | New value |
|---|---|---|
| N1 | `conversations` list, view | `created_by = @request.auth.id` \|\| `M` (chat id = `id`) \|\| a pending invite for me exists (`@collection.group_invites.conversation_id ?= id && @collection.group_invites.invited_user_id ?= @request.auth.id && @collection.group_invites.status ?= "pending"`) |
| N2 | `conversations` update | `M` (chat id = `id`) `&& @request.body.created_by:isset = false && @request.body.type:isset = false` |
| N3 | `conversation_members` list | `@request.auth.id = user_id` \|\| `M` (chat id = `conversation_id`) |
| N4 | `message_receipts` list | `@request.auth.id = recipient_id` \|\| I sent that message (`@collection.messages.id ?= message_id && @collection.messages.sender_id ?= @request.auth.id`) |
| N5 | `message_receipts` create | `@request.auth.id = recipient_id` \|\| (I sent that message `&& delivered_at = "" && read_at = ""`) |
| N6 | `message_receipts` update | `@request.auth.id = recipient_id && @request.body.message_id:isset = false && @request.body.conversation_id:isset = false && @request.body.recipient_id:isset = false` |
| N7 | `message_media` create | `message_id.sender_id = @request.auth.id` |
| N8 | `starred_messages` create, `deleted_messages_for_me` create | `@request.auth.id = user_id` |
| N9 | `polls` list, view, update | `M` (chat id = `conversation_id`) |

Everything not in this table keeps its live rule.

## Decisions (defaults in bold)

| # | Question | Options |
|---|---|---|
| S-1 | Who may change a group's name, icon and settings on the server | **Any member, as today** (N2 only adds the link to the chat; the app already limits the buttons) · admins only (a behaviour change; needs its own check of every settings screen) |
| S-2 | The creator of a chat keeps read access to its row after leaving or being removed (the `created_by` branch in N1, needed while a new chat has no member rows yet) | **Accept** · drop the branch if the dry run shows creation works without it |
| S-3 | Old receipts whose message row has been deleted (90 days after it disappeared) become invisible to the sender | **Accept**: nothing on the phone still needs them |
| S-4 | Clean up forged or stray rows, if any exist | **Report only** in the dry run (counts of receipts whose recipient is not a member, media rows whose message has another sender, star/delete rows for unknown users); deleting anything is a separate yes |

## How it is applied (phase 2)

1. **Dry run on a copy** (no live change): `.backup` the live `data.db` to
   `/tmp/pbtest`, apply one migration file with all of N1–N9, start the
   same binary on `127.0.0.1:8099` with a throwaway route that mints auth
   tokens for two existing test users (the 2026-10-30 pattern), and run the
   request table below with `curl`. Also time the two heaviest lists (N3 by
   `conversation_id`, N4 by `conversation_id`) against today's rules; if a
   list is more than 3× slower or over 300 ms, stop and report.
2. Report the dry-run table and the S-4 counts to the user. **Go-ahead
   needed before the live step.**
3. Live: backup `data.db` to
   `/home/ubuntu/pb_backups/data.db.<date>-rules-pre`, move the migration
   into `pb_migrations`, restart PocketBase, check `_migrations`, re-run
   the request table against the live server with the test users.
4. Device check (below) on the current app build.
5. Rollback: `migrate down` (the migration's down step restores the nine
   old rule strings exactly), or restore the backup.
6. Bible §7 updated to the new rules; one commit with this spec, the
   migration file (kept under `docs/server/migrations/`), the work log and
   the bible.

## Request table (dry run and live re-check)

`A` and `B` share a DM and a group; `C` is in neither; `A` is the group's
admin; `B` has sent messages in both.

| # | Request | Before | After |
|---|---|---|---|
| T1 | `C` lists `conversations` | every chat | only C's own |
| T2 | `A` lists `conversations`; `A` gets the shared group by id | works | works |
| T3 | `C` updates the shared group's name | 200 | 404 |
| T4 | `B` (member) updates the group's `disappearing_duration`; tries to set `created_by` | 200; 200 | 200; 400/404 |
| T5 | `C` lists `conversation_members` for the shared group | all rows | empty |
| T6 | `A` lists `conversation_members` with `user_id="<B>"` | all of B's | only chats A shares with B |
| T7 | `C` lists `message_receipts` for the shared DM | all rows | empty |
| T8 | `B` lists receipts for the DM with `recipient_id!="<B>"` | rows on everyone's messages | rows on B's own messages only |
| T9 | `C` creates a read receipt as `A` on B's message | 200 | 400 |
| T10 | `B` (sender) creates an empty receipt for `A` on B's own message; then tries one with `read_at` set | 200; 200 | 200; 400 |
| T11 | `A` creates their own delivered receipt, then updates `read_at`; tries to change `message_id` | 200; 200 | 200; 400/404 |
| T12 | `C` creates a `message_media` row on B's message; `B` creates one on B's own | 200; 200 | 400; 200 |
| T13 | `C` creates a `deleted_messages_for_me` row and a star for `A`; `A` creates their own | 200; 200 | 400; 200 |
| T14 | A new DM and a new group: create chat, add both members, read it back | works | works |
| T15 | A pending invite: the invited user reads the group row; after declining, cannot | works | works; 404 |
| T16 | Realtime: `A` subscribed to `conversations`, `conversation_members`, `message_receipts` gets events for the shared chat and none for C's | — | as stated |

Test rows created in the dry run live only in the copy. On the live
re-check, T9–T13 use throwaway rows in a test chat and are deleted
afterwards (list them in the work log).

## Device check list (current build, M52 and Redmi, test accounts)

1. Home loads; every chat is there; open a DM and a group.
2. Send text, a photo and a voice note both ways; ticks go grey, double,
   blue; "message info" shows the right people.
3. Start a new DM with a friend; create a group; invite, accept, decline.
4. Add and remove a member; change the group name, icon, timer and "only
   admins can message".
5. Star a message, delete one for me, react.
6. A disappearing chat: a read message still disappears on time.
7. Sign out, sign in, restore history: chats, ticks and members are right.
8. Leave the app idle for a minute, then receive a message: it arrives
   live (realtime still passes the rules).

## Must not undo

- The removal check lists `conversation_id=X && user_id=me`: N3's first
  branch keeps it working for a removed member.
- History sync's receipt index (`conversation_id` + `recipient_id != me`)
  expects receipts on **my** messages only; N4 returns exactly those.
- Hooks use `$app` and are not subject to rules (`disappearing_stamp`,
  `fcm_notify`).
- The message update rule's deny-lists (albums, disappearing) are not
  touched.
- Flat hooks, no heredocs through ssh for files with `$app` (pb-hook
  pitfalls); the migration is written locally and copied.

## Out of scope

Admin-only group settings (S-1), cleaning existing rows (S-4), rate limits,
the `users` list rule, the verification and change-email mail links (they
point at the blocked `/_/` path like the reset link did; separate small
fix), any app change.
