# Multi-select: pick many messages and act on them (acceptance checklist)

Date: 2026-11-02. Backlog **12.8**. Visual ground truth: **`docs/design/pages/multi-select.html`** (sections S1–S9,
numbered; S3 = the drag range; S5 = the delete choice; S7 = albums in a selection; S9 = diff summary).
Authority: `docs/design/00-foundation.md` (tokens/laws) → `docs/design/10-registry.md` (shared pieces) → this
checklist. Page letters A–H are page-local; decisions are numbered (bottom). Line refs as of `5580d1e`:
`cs` = `lib/features/chat/screens/chat_screen.dart`, `mb` = `lib/features/chat/widgets/message_bubble.dart`,
`cm` = `lib/features/chat/widgets/message_context_menu.dart`, `asc` = `lib/features/chat/screens/album_screen.dart`,
`rep` = `lib/infrastructure/repositories/message_repository_impl.dart`, `pol` =
`lib/features/chat/message_offline_policy.dart`.

**Starting point (audited 2026-11-02, `trail ask/skeleton` + `sed -n` ranges; no code run against a device, no live
PocketBase read).** Suite baseline: see "Baseline" at the bottom (expected 900/900 at `5580d1e`).

**Facts, confirmed in code (not assumed).**
1. **Selection is a set of local ids and nothing else.** `_selectedMessageIds` (`cs:186`); selection mode is derived
   as "the set is not empty" (`cs:188`), so it ends by itself when the set empties.
2. **The only way in is the long-press menu's Select** (`cm:427-431`), which calls `onSelect`; in the chat that
   **adds** the item's rows and never removes them (`cs:770-774`). There is no deselect.
3. **A tap while selecting does what it does outside selection**: opens a photo, plays a voice note, opens a link,
   jumps from a reply quote, opens the album collage, toggles a reaction chip. The bubble's only own gesture is the
   long-press menu (`mb:233-242`); every inner widget keeps its taps. `SwipeToReply` still wraps the bubble
   (`mb:417`), so a sideways drag still starts a reply while selecting.
4. **The selection bar** (`cs:970-1000`): ✕ **Exit selection**, **N selected**, one delete icon **Delete selected
   messages**. No live region, no scale-down on the count, no disabled state (it never shows at 0).
5. **Delete is for me only.** `_deleteSelected` (`cs:1002-1010`) → wave 4's `confirmAndDeleteForMe` (`cm:25-46`,
   **Delete 3 messages?** / **These messages will be deleted for you only.**). Never offers delete for everyone,
   even when every selected message is yours.
6. **Selected look**: the bubble gets an accent 8% fill + a 55% accent border (`mb:449-457`). Nothing else on the
   row changes.
7. **The album collage already has a fuller selection** (12.5 E4a–E4c, shipped `5580d1e`): its own flag
   `_selecting` (`asc:52`), tap and long-press toggle (`asc:90-94`, `asc:560`), it **stays in selection at 0** with
   delete disabled (38%), the count is a live region and scales down (`asc:363-375`), and delete offers **Delete for
   me / Delete for everyone** when every selected item is yours (`asc:171-236`, R19 sheet, offline hint). The chat
   and the collage draw two different bars today.
8. **In the chat an album selects as one unit** (`cs:768-774`, albums F1): all its rows go in, the count counts rows
   (**5 selected** for a 5-photo album).
9. **Single-message actions** (`cm:379-546`): Copy only when the row has a decrypted text body (`cm:433`,
   `Clipboard.setData`, toast **Copied**); Star toggles one row (`rep:2592`); Delete for everyone needs `isMine` and
   a `serverId` (`cm:340-342`) and is disabled offline (`pol:44-49`, hint **Available online**).
10. **Star writes the phone first, then the server unawaited** (`rep:2598-2650`): a star is one `starred_messages`
    **create**; an unstar is a list + delete. The live server limits creates to **20 per 5 s** (rate limits the user
    enabled, see the receipt-429 fix). Star sync **only adds** (`rep:4745-4752`): a star the server still holds is
    written back as starred on the next sync. So a 429'd **unstar** comes back, and a 429'd **star** never reaches
    the server.
11. **Delete for everyone on a row with no server id** (`rep:2527-2552`) only marks the phone (media with an upload
    latch is cancelled instead, `rep:2522-2524`). The menu never offers it there (fact 9).
12. **System rows** (`type == 'system'`, group events) render in the same list (`mb:67`) and have no menu.

**Routing.** Spec: Claude (this session). Phase 2: one screen + one shared widget + one repo method; the drag
gesture and autoscroll need device judgment. **Claude implements A–F** (gesture, actions, repo), Mimo/Astra may take
G's semantics tests under Claude's grading. The grading pass is a fresh-context reviewer, never the implementer.

**Pass criteria (page complete when):** all MUSTs ✓ · `flutter analyze` 0 errors · `flutter test` green (baseline
re-run at phase 2 start, plus the new tests; **no existing test edited**, the album-screen selection tests included)
· test-gate files below green · `git diff --check` clean · `trail check` clean · frozen-method diff vs HEAD empty ·
fresh-context review with no open BLOCK, findings in `multi-select-work-log.md` · device captures of the device-check
list · user device PASS (no commit without it).

**Spec status: user PASS 2026-11-02; every deferred decision = its default (1–14).** Phase 2 goes in a fresh session.

**Live PocketBase.** None needed. No schema, rule or hook change. (Star pacing, D6, works inside today's limits.)

**Status key:** `[x]` implemented AND verified by code/tests or recorded device evidence; `[ ]` pending.

---

## ⛔ Frozen (read first: a breach here is an automatic FAIL)

E2E and key code anywhere, the decrypt pass, receipts, the SSE handler's control flow, the outbox worker and its
senders, the send paths (text, media, album), the resume pass, `cancelMediaUpload`, `deleteMessage`, the existing
`toggleStar` (single-message star keeps it), the long-press menu's rows and copy (`cm`, except that album Star calls
D6's method, decision 12), every bubble's own state rules, the album collage's **behaviour** (its bar moves to the
shared piece, H1, with identical output), `SwipeToReply`'s own code.

**Unfrozen by this page, and only these:**
- `cs`: selection state, the row wrapper for tap / long-press / drag, autoscroll, the bar, the actions.
- `mb`: a `selecting` flag that blocks the bubble's inner gestures and `SwipeToReply`, and the selected look (C1).
- NEW `lib/features/chat/widgets/selection_bar.dart` (H1): the shared bar + the shared delete flow, moved out of `asc`.
- `asc`: calls the shared bar and delete flow instead of its private copies; nothing else.
- `rep` + its interface: one new method `setStarred(List<String> localIds, bool starred)` (D6).
- `cm`: the album Star row calls `setStarred` (decision 12). Nothing else in `cm`.

---

## A. Entering and leaving (S1, S2; decisions 1, 2)

- [ ] **A1 MUST** Entry stays the long-press menu's **Select** (`cm:427`): selection opens with that message (or that
  album, all its rows) selected. The keyboard goes down (`FocusScope.unfocus`); the typed draft and a pending reply
  stay.
- [ ] **A2 MUST (decision 1)** Selection is its own flag, as in the collage: it **stays open at 0 selected**. At 0
  every bar action is disabled (38%, not-enabled semantics); the count reads **0 selected**. A drag that passes back
  over its start never ends selection mid-gesture.
- [ ] **A3 MUST** Leaving: ✕ (**Exit selection**), Android back (before the chat pops, as today `cs:583-589`), or after
  a finished action (Copy, Star, Delete, D2–D5). Leaving the chat drops the selection (screen state only).
- [ ] **A4 MUST** Search: entering selection from a search result hides the search bar as today; leaving selection
  brings the search bar back with its query and match position.
- [ ] **A5 MUST** The bar swap (`cs:600-614` `AnimatedSwitcher`) is a 150 ms fade; reduced motion → no fade
  (duration zero).

## B. Gestures while selecting (S2, S3; decisions 3–6)

- [ ] **B1 MUST** **Tap a message → it toggles.** The whole row width is the target (the empty side beside a bubble
  too), never just the bubble. Inner taps are off while selecting: photos, videos, voice play, documents, links,
  reply-quote jumps, reaction chips, the album's tiles and its sideways scroll, failed-upload retry discs, download
  discs. `SwipeToReply` does not start.
- [ ] **B2 MUST** **Long-press a message → it toggles and starts a drag** (the collage's long-press toggles too). The
  long-press menu does not open while selecting. One `HapticFeedback.selectionClick()` at the start.
- [ ] **B3 MUST (decision 3)** **Drag range.** Keep the finger down after B2 and slide up or down: every selectable
  row between the start row and the row under the finger takes the start row's **new** state (start was off → the
  range turns on; start was on → the range turns off). Sliding back restores rows that leave the range to what they
  were before the drag. Lifting the finger ends it. Rows found by hit-testing the list at the pointer (a `MetaData`
  carrying the item's index on each row; no new dependency).
- [ ] **B4 MUST (decision 4)** **Autoscroll.** While dragging, a finger inside the list's top or bottom 64dp scrolls
  that way, faster the deeper it is (0 at the band's edge, 1600 dp/s at the list's edge); the range keeps
  following the row under the finger. Reaching the oldest loaded message triggers the usual older-history load.
  Reduced motion does not turn it off (it is the user's own movement, not decoration).
- [ ] **B5 MUST** Not selectable, skipped by taps and ranges: date separators, the history-end row, the
  history-load-failed row, **system rows** (fact 12). A range jumps over them.
- [ ] **B6 MUST (decision 5)** Outside selection, long-press stays the menu (unchanged). Drag-select works once
  selection is open.

## C. Look (S2, S4; decision 6)

- [ ] **C1 MUST (decision 6)** A selected row: the full row width tinted `t.accentSoft`, plus the bubble's existing
  accent fill + border (`mb:449`). An unselected row is unchanged. No check discs, no row shift.
- [ ] **C2 MUST** Light, dark and AMOLED from tokens only; no `Text` coloured `t.accent` / `t.error` (accent text
  fails contrast, the group-screens learning).
- [ ] **C3 MUST** Reduced motion: the tint switches with no animation. Otherwise a 100 ms colour fade at most.

## D. The selection bar and its actions (S4, S5, S6; decisions 7–12)

- [ ] **D1 MUST** Bar (56dp, H1): ✕ **Exit selection** · **N selected** (16/w600 ink, one line, scales down, live
  region) · **Copy** · **Star** or **Unstar** · **Delete**. Icon buttons 48×48, `t.inkSoft`; tooltips **Copy
  selected messages**, **Star selected messages** / **Unstar selected messages**, **Delete selected messages**.
  Disabled = the icon at 38% inside one `Opacity`, not-enabled semantics.
- [ ] **D2 MUST (decisions 7, 8) Copy.** Enabled when at least one selected row has a decrypted text body. Copies
  the text bodies in **chat order, oldest first**, joined by one blank line, no names or times. Skips photos,
  videos, voice notes, documents, albums, deleted-for-everyone rows and rows that couldn't be decrypted. One text →
  exactly its body (same as the menu's Copy). Toasts (R5): one copied → **Copied**; several →
  **Copied 3 messages**; some skipped → **Copied 3 of 5. Only text is copied.** Selection ends.
- [ ] **D3 MUST (decision 9) Star.** The icon reads **Unstar** (filled star) when every starrable selected row is
  starred, else **Star** (outline). Starrable = not deleted for everyone. Star stars the unstarred ones; Unstar
  unstars all. Through D6. Toasts: **Starred** / **Starred 4 messages** · **Unstarred** / **Unstarred 4
  messages**. Selection ends. Works offline (phone first, `pol:12`). Disabled when nothing is starrable.
- [ ] **D4 MUST Delete.** Same flow as the collage (albums E4b), now shared (H1):
  every selected row is yours **and** you are still a member (decision 10) → an R19 sheet, no header, two rows
  **Delete for me** and **Delete for everyone** (destructive; the second disabled offline with **Available
  online**); otherwise straight to delete for me. Delete for me = wave 4's `confirmAndDeleteForMe`, copy unchanged
  (**Delete message?** / **Delete 3 messages?**, **This message will be deleted for you only.** / **These messages
  will be deleted for you only.**). Delete for everyone = R20 **Delete message?** / **Delete 3 messages?**,
  **This message will be deleted for everyone in this chat.** / **These messages will be deleted for everyone in
  this chat.**, confirm **Delete**. Cancel on either → selection stays as it was.
- [ ] **D5 MUST (decision 11) Delete for everyone row rules.** Per row, at the moment of confirming: has a server id
  and isn't already deleted for everyone → `deleteMessage(id, forEveryone: true)`; an own unsent row (no server id)
  → `deleteMessage(id)` (for me; an unsent photo/video becomes a cancel, wave 4); already deleted for everyone →
  `deleteMessage(id)` (clears the tombstone for me). The count in the title is every selected row.
- [ ] **D6 MUST (decision 12)** NEW `setStarred(List<String> localIds, bool starred)` in the repo: writes every row on
  the phone first (one transaction, rows already in that state untouched), returns, then sends the server writes
  **one at a time in the background**: a star = one create, paced to **at most 15 creates per 5 s**; a 429 waits 5 s
  and retries the same row, up to 3 times, then logs and moves on. Unstar = today's list + delete per row (not a
  create, not paced). Rows with no server id are phone-only (as `toggleStar`). Same request bodies as `toggleStar`
  (ids only, no body, the starred learning).
- [ ] **D7 MUST** Every action resolves the selection against the **current** list when it runs: an id whose row has
  gone (expired, deleted on another device) is skipped; an album counts its current rows (a late row that joined
  after selecting is included). All gone → nothing happens, selection ends.

## E. Albums (S7; decisions 13, 14)

- [ ] **E1 MUST** In the chat an album stays **one unit** (albums F1): a tap or a range toggles all its rows; the
  count counts rows (**5 selected**). Partial picks happen only inside the collage.
- [ ] **E2 MUST** Copy skips albums (media). Star / Unstar on a selected album = every row (albums F7; Starred still
  shows one card). Delete = every row, under D4/D5.
- [ ] **E3 MUST (decision 13)** The collage keeps its own selection (E4a–E4c) and is **delete-only**: no Copy, no Star
  (album star is whole-album, albums decision 21). It now draws H1's bar with the Copy and Star slots absent, so the
  two bars look the same. Its behaviour and tests are unchanged.
- [ ] **E4 MUST** Opening the collage is a tap, which selects instead while selecting (B1). To pick single items of
  an album, leave chat selection and use the collage's Select.

## F. Edge cases (S8)

- [ ] **F1 MUST Own vs others'.** Delete for everyone is offered only when **every** selected row is yours (D4). One
  of theirs in the set → delete for me only. Same in DMs and groups.
- [ ] **F2 MUST Groups you left** (`isLeft`): delete for me only (the server's update rule needs a member).
- [ ] **F3 MUST Pending / failed / unsent own rows** are selectable. Copy works on a pending text (its body is on the
  phone). Star is phone-only until the row has a server id. Delete: D5. A failed photo/video deleted = a cancel
  (wave 4).
- [ ] **F4 MUST Deleted for everyone** (**🚫 Message deleted**) rows are selectable (so you can clear them); Copy and
  Star skip them; delete for me removes them.
- [ ] **F5 MUST Undecryptable** rows (**Can't decrypt**): selectable; Copy skips them; Star and Delete work.
- [ ] **F6 MUST Disappearing chats.** A selected row that expires leaves the list and the set (D7); the count drops.
  A drag whose start row expires ends. Starring does **not** keep a message (that is 12.7). No new copy.
- [ ] **F7 MUST Arrivals while selecting.** New messages arrive and render normally, unselected; the selection
  doesn't move. Older history loading (scroll or B4) keeps the selection.
- [ ] **F8 MUST Pinned messages**: no bulk pin (pins are capped at 3 and network-only). The pinned banner stays.
- [ ] **F9 MUST Size.** Selecting 500+ rows works (the set is ids); Copy of many texts is one clipboard write; Star of
  many returns at once (D6), the server catches up in the background.

## G. Accessibility (S6)

- [ ] **G1 MUST** While selecting, each selectable row is one button: its existing row label (`mb`
  `_messageRowSemantics`) + **, selected** / **, not selected**, `selected: true/false`, tap hint **Select** /
  **Deselect**. Its inner buttons are hidden from TalkBack while selecting (they don't respond, B1).
- [ ] **G2 MUST** The count is a live region (TalkBack reads **3 selected** on change).
- [ ] **G3 MUST** Drag-select has a non-drag path: tapping each message (B1). No range action for TalkBack in this
  page (decision 14).
- [ ] **G4 MUST** 360dp × 200% text + Plus Jakarta Sans: **120 selected** + three action icons fit one bar line (the
  count scales down); a selected row's tint covers the whole row at any text size.
- [ ] **G5 MUST** Reduced motion: A5 and C3.

## H. Shared piece (registry)

- [ ] **H1 MUST** NEW registry row **C18** `SelectionBar({count, onExit, onCopy?, starState?, onStar?, onDelete})` +
  `deleteSelectedMessages(context, ref, rows, {required bool canDeleteForEveryone})` in
  `lib/features/chat/widgets/selection_bar.dart`. The chat and the collage both use them; a null `onCopy` /
  `onStar` leaves that slot out. The collage's `_deleteChoice`, `_deleteSelected` and `_selectionBar` (`asc:171-236`,
  `asc:341-400`) move here unchanged in output; its existing tests pass **unedited**.

---

## Test gates (phase 2)

- [ ] NEW `test/chat/multi_select_test.dart` (widget, the chat screen with a fake repo):
  Select from the menu → **1 selected**, keyboard down · tap a second row → **2 selected**; tap it again → **1** ·
  tap the last → **0 selected**, still selecting, Copy/Star/Delete disabled · ✕ and back exit; back then pops the chat
  · a tap while selecting does **not** open a photo, play voice, open a link, jump from a quote, open the collage, or
  toggle a reaction (count the calls) · no reply starts on a sideways drag while selecting · a tap beside the bubble
  toggles · long-press while selecting does not open the menu · date/system rows never selected.
- [ ] Drag (same file): long-press row 2, drag to row 6 → rows 2–6 selected; drag back to row 4 → 2–4; release · start
  on a selected row → the range deselects · a range over a date separator skips it · drag into the bottom band →
  the list scrolls and the range grows (pump with fake time) · an album inside the range → all its rows.
- [ ] Actions: Copy with 2 texts + 1 photo → clipboard = `text1\n\ntext2` (oldest first) and the toast **Copied 2 of
  3. Only text is copied.** · one text → exactly its body, **Copied** · all media → Copy disabled · Star with 1 of 3
  starred → **Star**, calls `setStarred([the 2 unstarred], true)`, toast **Starred 2 messages** · all starred →
  **Unstar** · delete all-own online → the two-row sheet; offline → **Delete for everyone** dimmed + **Available
  online** · one theirs → straight to **Delete 2 messages?** for me · left group → for me only · confirm counts the
  calls per D5 (server id → for everyone; unsent → for me; tombstone → for me) · cancel keeps the selection · an
  expired id is skipped (D7).
- [ ] Semantics (same file, `getSemantics`): rows carry **selected** / **not selected** and `isSelected`; the count is
  a live region; disabled buttons are not enabled. 360×200% + Jakarta: **120 selected** fits, no overflow.
- [ ] NEW `test/offline/star_many_test.dart` (repo, fake PB): `setStarred` writes all rows before returning · 30 stars
  → creates never exceed 15 in any 5 s window (fake clock) · a 429 retries after 5 s, gives up after 3 · unstar = list
  + delete per row, unpaced · rows without a server id make no request · rows already in the target state untouched
  · request bodies have no body text.
- [ ] Existing tests green **unedited**: `album_screen_test` (selection included), `message_menu_sheet_test`,
  `star_offline_test`, every `test/chat/*` and `test/offline/*`.
- [ ] Count: the work log records **baseline + N = total**.
- [ ] Function-level diff vs HEAD of every frozen method in an edited file: empty.
- [ ] Full suite green · analyze 0 errors · `git diff --check` clean · `trail check` clean.

## Device check list (phase 2, M52 + Redmi; you do every action on your own messages)

Use a test chat or messages you are happy to star, copy or delete. Claude never does these in real chats.

1. Long-press a message → **Select** → the keyboard drops, the row tints, **1 selected**.
2. Tap three more messages, including the empty space beside one → **4 selected**; tap one again → **3**. Tapping a
   photo, a voice note, a link and a reply quote only toggles them; nothing opens or plays.
3. Deselect everything → **0 selected**, still selecting, the three icons dim. ✕ exits; back exits before leaving the
   chat.
4. Long-press a message while selecting and slide up across 8 messages → they all select as you go; slide back → the
   last ones unselect; lift. Start on a selected one → the slide unselects. (Gesture arena: widget tests can't prove
   this.)
5. Slide into the top edge → the chat scrolls up and keeps selecting; older history loads; slow in the band's
   outer part, fast at the edge.
6. Copy 3 texts and a photo → paste somewhere: the three texts, oldest first, blank line between; toast **Copied 3 of
   4. Only text is copied.**
7. Select 25 messages → **Star** → toast **Starred 25 messages**; Starred shows them. Leave the chat, reopen after a
   minute: still starred. On the other test device or after a fresh login: all 25 starred (server got them).
   Then **Unstar** all 25 → after a sync they stay unstarred.
8. Select only your own messages → Delete → the two-row sheet → **Delete for everyone** → **Delete 3 messages?** → they
   show **Message deleted** on both phones. Airplane mode → **Delete for everyone** dims with **Available online**.
9. Mix one of theirs in → Delete goes straight to **Delete 4 messages?** for you only.
10. Select an album and two texts → **7 selected** (5 photos + 2) → Star → Starred shows the album as one card + 2.
11. In the album's collage → Select → its bar looks like the chat's (no Copy, no Star) and deletes as before.
12. In a disappearing chat with a short timer, select a message about to expire → it leaves and the count drops.
13. Largest text + Plus Jakarta Sans, 360dp if available: the bar, a selected row. TalkBack: a row reads
    **…, selected**, the count is announced, a tap toggles.
14. Reduce animations: the bar and the tint switch instantly; autoscroll still works.

## Out of scope (do NOT build on this page)

Forward (doesn't exist) · **Add to list** (12.9; the bar has room for a 4th icon or a ⋮ later) · Select all · a
range action for TalkBack · bulk pin · bulk react · bulk reply · Save / Share several media · picking single album
items from the chat list · Copy for media · selection on Home (conversations) · a durable star queue (follow-up F-a)
· anything in ⛔.

**Follow-ups noticed (not this page):**
- **F-a** Star sync only adds (fact 10): an unstar that fails (offline, server error) comes back on the next sync. The
  same for single stars today. A durable fix = stars through the outbox like reactions.
- **F-b** Fact 11 for single messages: phase 2 checks whether deleting a still-queued text (no server id) for me stops
  its outbox send. If it still sends, backlog item; not fixed here.
- **F-c** The single menu offers **Delete for everyone** in a group you left (no `isLeft` check, `cm:340`).

---

## Diff vs current implementation

| # | Area | Today (file:line) | Spec | Checklist |
|---|------|-------------------|------|-----------|
| 1 | Mode | derived from a non-empty set (`cs:188`) | own flag, stays at 0 | A2 |
| 2 | Tap while selecting | inner action runs (`mb`) | toggles, whole row | B1 |
| 3 | Long-press while selecting | the menu (`mb:234`) | toggle + drag range | B2, B3 |
| 4 | Range | none | drag with autoscroll | B3, B4 |
| 5 | Deselect | impossible (`cs:770` adds only) | tap toggles | B1 |
| 6 | Look | bubble fill + border (`mb:449`) | + full-row `accentSoft` | C1 |
| 7 | Bar | ✕, count, delete (`cs:970`) | shared C18: ✕, count (live, scales), Copy, Star, Delete | D1, H1 |
| 8 | Delete | for me only (`cs:1002`) | all own → for me / for everyone sheet | D4, D5 |
| 9 | Copy / Star | single only (`cm:433-457`) | bulk | D2, D3 |
| 10 | Server star writes | unpaced, one per call (`rep:2615`) | paced bulk method | D6 |
| 11 | Collage bar | private copy (`asc:341`) | shared C18, same output | E3, H1 |
| 12 | Semantics | none per row in selection | selected / not selected, hints | G1 |

---

## Deferred decisions (default in bold; reply with a number to change one)

1. **Selection stays open at 0 selected** (actions dim; ✕ or back to leave), same as the collage. Needed so a drag
   that crosses back over its start doesn't drop you out. Alternative: leave selection when the last message is
   deselected (WhatsApp), and the collage changes to match.
2. **Entry only through the menu's Select.** Alternative: a long-press on a message selects it directly and the
   menu moves to… nowhere obvious (the menu holds react, reply, pin), so not recommended.
3. **Drag range = long-press while selecting, then slide** (Google Photos style); the range takes the start row's new
   state. Alternative: Telegram-style, drag along a check column at the row's edge (needs the check column of
   decision 6's alternative).
4. **Autoscroll band 64dp, up to 1600 dp/s.** Tuned on the device in phase 2 if it feels too fast or slow.
5. **Drag-select only once selection is open.** Alternative: the first long-press's menu opens on lift instead of at
   the long-press, so a long-press that moves turns into a range straight away (no menu round-trip, but the menu
   comes up a beat later every time).
6. **Look = full-row tint + today's bubble ring, no check discs.** Alternative: a 24dp check disc at the row's start
   on every row while selecting (matches the collage's discs; rows shift sideways by 40dp when selection opens).
7. **Copy joins texts with a blank line, no names or times.** Alternative: one line per message as
   **[2 Nov, 14:05] Asha: text** (useful when pasting a conversation elsewhere; longer).
8. **Copy skips media and says so in the toast** (**Copied 3 of 5. Only text is copied.**). Alternative: Copy is
   disabled whenever any media is selected.
9. **Star when not all are starred, Unstar when all are** (the album menu's rule). Alternative: two separate icons.
10. **A group you left → delete for me only.** Alternative: keep offering Delete for everyone (the server refuses it;
    the phone would show it deleted until the next fetch).
11. **Mixed own sent + own unsent → Delete for everyone still offered**; unsent ones are deleted for you (they never
    reached anyone). Alternative: offer Delete for everyone only when every selected row has reached the server.
12. **Bulk star paces server writes (≤15 creates per 5 s, 429 → retry)** and the album menu's Star (20 items) uses it
    too, so a 20-photo album star stops brushing the limit. Alternative: leave the album menu on its loop of
    `toggleStar` (frozen `cm` untouched; 20 creates at once sits right at the limit).
13. **The collage stays delete-only** but draws the same shared bar. Alternative: add Star per item in the collage
    (conflicts with albums decision 21, star = whole album).
14. **No TalkBack range action** (tap each). Alternative: a **Select all loaded** action in the bar's overflow.

## Baseline

Recorded 2026-11-02 at `5580d1e`, before any phase 2 change: **900/900** (`flutter test`, all passed, ~1 min).
Phase 2 re-runs it first and records it again.
