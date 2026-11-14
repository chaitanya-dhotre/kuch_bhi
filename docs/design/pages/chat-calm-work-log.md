# Chat calm — build work log (2026-11-14)

Spec: `chat-calm.md` (PASS 2026-11-14, all defaults). Board: `chat-calm.html`.
Built by Claude in one session. Nothing committed: spec, board, this log, code
and learnings go in one commit after the user's device PASS.

## Gates

| Gate | Where | Result |
|---|---|---|
| Baseline | `flutter test` before any change | 1312 / 1312 |
| 1 A1/A2/A3 at W 360/384/411/554 × aspect 3:1, 16:9, 1:1, 9:16 | `test/chat/bubble_geometry_test.dart` | pass |
| 2 B1 corner table, both sides | same | pass |
| 3 B2 no time in a bubble, one meta line, equal 38 dp heights | `test/chat/chat_calm_test.dart` | pass |
| 4 B3 4 min joins, 6 min splits, name once per streak | `test/chat/run_grouping_test.dart` | pass |
| 5 B6 link start-aligned | `chat_calm_test.dart` | pass |
| 6 voice / document / photo one width at 384/411/554 | `chat_calm_test.dart` | pass |
| 7 contrast of every D1/D2 text pair ≥ 4.5 : 1 | `chat_calm_test.dart` | pass |
| 8 own fill = bubbleMine both themes; only accent fill = play disc; D-5 border light only | `chat_calm_test.dart` | pass |
| 9 E1 no photo disc; E2 size only on a known "not on disk" | `test/media/media_download_state_test.dart` | pass |
| 10 R11 one controller per group, 300 ms delay, reduced motion = no ticker, no `shimmer` import | `chat_calm_test.dart` | pass |
| D-3 A levels in the body; every reader strips them | `test/chat/voice_body_test.dart`, `voice_recorder_test.dart` | pass |
| 11 existing geometry + album tests updated; full suite; analyze | — | **1340 / 1340**, `flutter analyze` 0 errors (113 pre-existing warnings/infos, none new) |

## What changed (by spec section)

- **Tokens (D1/D2):** `primary50…900` primitives; `accentPressed` = primary/600;
  new roles `bubbleMine`, `accentText` (also on the AMOLED theme in `app_theme.dart`).
- **A / B1 / C:** `ChatBubbleGeometry` rewritten (`textMaxWidth`, `attachmentWidth`,
  `mediaHeight`, `albumTileHeight`, `radius(isMine, runStart)`, gaps 2/12, padding
  12×9 and 10). Bubbles take `runStart` instead of `runEnd`. No bubble shadow.
- **B2/B4/B5:** the time is no longer inside any bubble. `MessageBubble` draws one
  line (`ChatBubbleTimestamp`: time 11/14 inkSoft, ticks, star) under the run's last
  bubble, or every bubble in info mode. That also covers stickers, emoji-only and
  unknown stickers, which drew their own time before (Nov 13 info-mode learning).
- **B3:** run gap 5 min; new `streakStart` flag → group name once per streak.
- **C8:** reactions lifted 8 dp onto the bubble edge; "+" chip removed.
- **C9/C10:** group disc beside the run's last bubble, bottom-aligned to the bubble.
- **D3:** Home row time inkSoft (`accentText` when unread), prefix inkSoft 600,
  group badge icon inkSoft.
- **E1–E7:** photo/video/album/voice/document/link rebuilt to the A2 width. Voice
  uses `VoiceWaveform` with a new fixed-bar mode (`bars: 36`). Video pill shows the
  size from a new `LocalMediaFile.fileSize` (read from the server row's existing
  `file_size`, stored in the blob meta; no server change).
- **F / R11:** `skeleton.dart` rewritten: `SkeletonGroup` (one breathing controller,
  300 ms delay, reduced motion = static), `Skeleton` gains `color` and
  `borderRadius`. `shimmer` removed from `pubspec.yaml`. Chat loading state drawn in
  the real shapes; content fades in over 150 ms (`AnimatedSwitcher`).
- Reply quote sender name → `accentText` (marigold text on surface2 was ~2 : 1).

## Decisions and deviations

- **D-3 (voice levels): built A** (planning session's answer, 2026-11-14). The
  sender's encrypted body is now the duration + one space + exactly 36 level
  glyphs (`▁…█`, 8 steps), e.g. `0:12 ▁▃▅▇…` (`lib/features/chat/voice_body.dart`:
  `voiceBodyWithLevels`, `parseVoiceBody`, `voiceBodyText`). No server change; the
  levels stay end-to-end encrypted. A body with no suffix or a malformed one
  (old messages, old senders) gets generated bars from the message id.
  Readers that strip the suffix: voice bubble, reply quote (2 places), pinned
  banner, starred screen, chat search. Home shows a constant label, notification
  text comes from the server payload, and there is no forward, so none of those
  see the body. Tests: `test/chat/voice_body_test.dart` (helper, bubble, reply
  quote, and a source check that every reader calls the helper).
  **Side effect for the user to confirm at device check:** a phone still on an
  older build shows the bars after the duration ("0:12 ▁▃▅▇…").
  Limit: if the app restarts between recording and upload, the body falls back
  to the duration alone (the send rebuilds it from the stored seconds), so that
  note gets generated bars.
- **Media expiry badge** (server retention, "2d") stays on the media, top right.
  B4 moves "the disappearing-message badge" to the time line; there is no
  per-bubble disappearing badge today, and the retention badge belongs to each
  media item, not the run's last bubble.
- **Selected row (12.8 C1)** now uses accentSoft + a 1.5 dp accent ring (D2 soft
  accent); `accentSoft` light stays `#FFF3DC` (≈ primary/50), not re-pointed.
- **Inline upload discs (≤ 40 dp)** in voice/document rows are ink@8 % with an ink
  icon (E7), not the old solid accent.
- **Document type line** reads the extension ("PDF"), not the mime string.
- **Sender name colours** keep the existing per-sender palette (the spec gives no
  colour; the board shows inkSoft).
- Files touched outside the spec's diff list, each needed by it:
  `app_theme.dart` (AMOLED tokens), `chat_tile.dart` (D3 time/badge),
  `message_body_text.dart` (ink on the tint, 15/20), `media_upload_disc.dart` (E7),
  `media_blob_store.dart` + `media_upload_service.dart` (E2 size),
  `sticker_widgets.dart` (B2), `voice_waveform.dart` (E3), `busy_spinner.dart` (comment).

## Tests changed

Old expectations that encoded the replaced design were rewritten, not deleted:
reaction "+" chip (2 tests), media download disc (3), own-bubble onAccent ink (2),
shimmer (2), album numbers (3), 2-minute run (1), multi-select photo made
landscape so the rows above it stay on screen with the taller A3 box (1).

## Not checked here

- On-device look (Redmi 554 dp, M52 411 dp, light and dark): the 10-item list in
  the spec. Release build installed on the Redmi only.
- Under-5 % solid marigold at rest: to be judged on device screenshots.
- Scrolling smoothness on the Redmi (item 8).

## `trail check` (4 conflicts, all reviewed, none applies)

- `chat.md:57` and `document_message_bubble.dart:166`: matched a web
  landing-page "Hero must fit the viewport" skill rule; not about chat bubbles.
  The document name going to one line is spec E4.
- `image_message_bubble.dart:247`: the Nov 2 album-tile learning (tiles must
  fill). Tile mode still returns the photo bare and the album test "covers the
  whole tile" passes; the single photo now fills an exact A2 × A3 box with cover.
- `message_bubble.dart:279`: the Nov 11 "new message type needs the server list"
  learning; no new message type here.
- Watch (from the Oct 31 learning): after an app restart a cached photo can lose
  its stored size and fall back to the 4:3 box (A4) until it reloads.

## Device round 1 (2026-11-14): text placeholders

User: placeholders didn't look like the board and changed size when the text
landed. Cause: a decrypting text body drew its own rounded box with grey bars
INSIDE the bubble (a box in a box, taller than 38 dp), sized from a rough
character guess (ciphertext length − 28, about 12 characters short).
Fix: the bubble itself is the placeholder (`SkeletonBreath` around the frame;
own side `bubbleMine`, theirs surface2, no border); the body only reserves
`estimateBubbleTextSize` (ciphertext → `len × 3/4 − 16` characters, laid out
in the real 15/20 style at the bubble's text width). Every `SkeletonGroup`
now reads its breath from the wall clock, so bubbles that start decrypting
at different times breathe together. Terminal decrypt states are untouched.
Test: `chat_calm_test.dart` "F: a decrypting text bubble is the placeholder…".
Suite 1341 / 1341, analyze 0 errors. Width can still differ a little (the
estimate uses typical English letter widths).

## Device PASS (2026-11-14)

User: all 10 items pass on the Redmi. Marigold seen only as the outline on
your own reaction chip (D2 soft accent) and on the scroll-to-latest button
(chat.md C5), and solid on the buttons, as specified.
