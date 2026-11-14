# Chat calm: sizing, shape, colour and placeholders (spec, rev 1)

Status: **spec PASS 2026-11-14, all defaults (D-1 A, D-2 A, D-3 A, D-4 A, D-5 A, D-6 5 min).** Items 1 + 2 + 3 of
`docs/design/feedback-2026-11-plan.md`, plus its "Round 2" section (U2–U6).
Board: `docs/design/pages/chat-calm.html` (light and dark, before and after).
Amends: foundation §2 (colour), §4 (radius, spacing), §6 (loading), `chat.md`
§C/§D/§F/§J, registry R11. Motion is **not** here (next spec).

## What was said

| # | Feedback | Section |
|---|---|---|
| F4 | Bubbles vary in size; photos and videos waste space; marigold is everywhere; skeleton looks bad | A, D, F |
| F7 | Sent voice and document bubbles are too marigold | D, E |
| U2 | Bubbles with the time appear in between and feel out of place | B |
| U3 | Pills, but the last one has a weird shape, also mid-chat | B |
| U4 | Download button on photos that already look clear | E1 |
| U5 | Voice bubble is plain and matches nothing | E3 |
| U6 | Spacing is not consistent | C |

## References (Mobbin, saved in `docs/Inspiration/feedback-2026-11/`)

Ahead is not on Mobbin (0 results), so the palette follows the designer's
description and the user's shade-card skill.

| Screen | What we take |
|---|---|
| [Luma direct chat](https://mobbin.com/screens/c0336929-b466-4123-8f52-f7b95a947eb3?utm_source=claude&utm_medium=ai-assistant&utm_source_platform=mcp) | photo at ~65 % of the width, no frame; grouped corners; one quiet status line under the run, not in the bubble |
| [X direct chat](https://mobbin.com/screens/85f63b6c-d4e3-4531-869b-5322979927e6?utm_source=claude&utm_medium=ai-assistant&utm_source_platform=mcp) | time under the bubble, outside it; tall photo capped in height |
| [Yubo photo](https://mobbin.com/screens/b4d82ac6-caba-47b1-b69c-168dad536b0a?utm_source=claude&utm_medium=ai-assistant&utm_source_platform=mcp), [Yubo voice](https://mobbin.com/screens/309514ed-6055-4ad1-a258-a512f684e194?utm_source=claude&utm_medium=ai-assistant&utm_source_platform=mcp) | voice note = play disc, waveform bars, duration, speed chip, in one pill |
| [TextNow voice](https://mobbin.com/screens/fb3468cc-c076-4de9-b9c2-11eed0a538bf?utm_source=claude&utm_medium=ai-assistant&utm_source_platform=mcp), [Replika voice](https://mobbin.com/screens/8af2a2b7-e8a1-40d2-8ae4-57cc04338a65?utm_source=claude&utm_medium=ai-assistant&utm_source_platform=mcp) | waveform as the body of the bubble; voice bubble narrower than a full text bubble |
| [Luma group, dark](https://mobbin.com/screens/e8eb6d85-bb28-4bee-a01e-b6f866be6b67?utm_source=claude&utm_medium=ai-assistant&utm_source_platform=mcp) | sender name once per streak; avatar at the bottom of the streak; reaction chips overlapping the bubble's lower edge |
| [Bumble](https://mobbin.com/screens/b501d183-5f31-462e-ae64-ea190208d339?utm_source=claude&utm_medium=ai-assistant&utm_source_platform=mcp) | a solid yellow own bubble, like ours today: it works there because nothing else on the screen is yellow. We go the other way (tint) because we also have marigold buttons, badges and a mascot |
| [Brainly document](https://mobbin.com/screens/4e5d56a8-3cb4-4ca6-8cc0-d4c7d05a29cd?utm_source=claude&utm_medium=ai-assistant&utm_source_platform=mcp) | document = icon tile, name, type line; compact, not full width |
| [yope, dark](https://mobbin.com/screens/d5e25af9-bd76-451b-ab38-65e22d4567e4?utm_source=claude&utm_medium=ai-assistant&utm_source_platform=mcp) | one accent spot per screen on a near-black surface |

Before shots of our app (Redmi, dark): `…/current/`.

## A. Sizing (one rule per thing)

`W` = screen width in dp. Test phones: Redmi 554, Pixel 9 / M52 411, S24 384.

| # | Thing | Rule | 384 | 411 | 554 |
|---|---|---|---|---|---|
| A1 | Text bubble max width | `min(W × 0.78, 420)` | 300 | 321 | 420 |
| A2 | Attachment width (photo, video, album, voice, document, link card) | `clamp(W × 0.66, 240, 340)` | 253 | 271 | 340 |
| A3 | Photo and video height | `width ÷ aspect`, clamped to `0.56 × width … 1.25 × width`, cover | 142–316 | 152–339 | 190–425 |
| A4 | Placeholder | same box as A2/A3; aspect from the stored width and height, else 4:3 | | | |
| A5 | Album | width A2, tile height `0.72 × width`, gap 4 | 182 | 195 | 245 |
| A6 | Sticker | 128, no chrome (unchanged) | | | |
| A7 | Side margins | 12 on the bubble's own side; the far side is whatever A1/A2 leave | | | |

Today: text 84 % of the screen, photos a fixed 210 (38 % on the Redmi), voice
and documents always the full text width
(`expiry_badge.dart:47-59`, `voice_message_bubble.dart:192,230`,
`document_message_bubble.dart:98`).

## B. Shape and time

- **B1 Corners.** Radius 18. On the sender's side the bottom corner is
  always 6, and the top corner is 6 unless the bubble starts a run. The two
  corners on the far side are always 18. So a lone bubble and the first of a
  run look as a bubble does today, and every later bubble of the run has the
  same shape as the one before it. No bubble in a run has a shape of its own
  any more.
- **B2 Time leaves the bubble.** The time and ticks sit on one quiet line
  **under the last bubble of a run**, outside it: 11/14, inkSoft, aligned to
  the bubble's side, 4 dp below, ticks after the time on own runs. Every
  bubble is then only its content, so one-line bubbles are all 38 dp tall.
  Photos and videos lose the dark time pill on the picture.
  Today the time is a row inside the run's last bubble
  (`expiry_badge.dart:140-161`), which makes it taller than its neighbours.
- **B3 Runs.** Same sender, same day, gap ≤ **5 minutes** (today 2,
  `chat_run_grouping.dart:95-96`). In groups the sender name shows once per
  streak of that sender, not once per run.
- **B4** The disappearing-message badge, the edited/starred marks and the
  failed-send mark move to the same line as the time.
- **B5** Timestamp size 11/14 (today 10.5, off the type scale).
- **B6** Text inside a bubble is always start-aligned. Today a short link
  above a wide preview card is right-aligned (`message_bubble.dart:1010`).

## C. Spacing

| # | Gap | Value | Today |
|---|---|---|---|
| C1 | Between bubbles of one run | 2 | 4 |
| C2 | Before a new run | 12 | 4 |
| C3 | Around a day pill | 16 above, 12 below | uneven |
| C4 | Bubble padding, text | 12 × 9 | 12 × 8 |
| C5 | Bubble padding, voice and document | 10 all round | four different sets |
| C6 | Leading slot in voice and document | 40 × 40 | 30 and 38 |
| C7 | Inner radii | 10, or pill | 12, 10, 8, 2 |
| C8 | Reaction chips | overlap the bubble's lower edge by 8, on the sender's side, 4 from the corner; the always-visible "+" chip is removed (long-press adds a reaction) | own row under the bubble |
| C9 | Group sender disc | 28, bottom-aligned to the run's last **bubble**; fill surface2 with a 1 dp line border | aligned to the reaction row, dark on dark |
| C10 | Sender name | 13/18 600, 12 from the bubble's edge, 4 above the first bubble | 14 left, 1 below |

## D. Colour

### D1 Shade card (the user's `ui-color-system` skill; seed = 500)

| Step | Hex | Ink on it | Use |
|---|---|---|---|
| primary/50 | `#FEF5EA` | 14.1 | selected rows, jump flash |
| primary/100 | `#FFE9CF` | 12.9 | **own bubble, light** (D-1 option A) |
| primary/200 | `#FFD59E` | 11.0 | own bubble, light, option B; chip borders |
| primary/300 | `#FEBF67` | 9.3 | marigold text and icons on dark (10.2 : 1 on surface) |
| primary/400 | `#F9AC33` | 7.9 | — |
| **primary/500** | `#EFA00B` | 7.0 | the accent: primary actions only |
| primary/600 | `#CC8808` | 5.1 | pressed (replaces `#D98F08`) |
| primary/700 | `#A56D01` | — | — |
| primary/800 | `#744C01` | — | marigold text on light (7.1 : 1 on bg) |
| primary/900 | `#492F06` | 10.7 (dark ink) | **own bubble, dark** |

Neutrals and status colours keep today's tokens. Screens still read
`context.t.*` only; the ramp is the primitive layer under those names.

### D2 Roles

| Role | Light | Dark |
|---|---|---|
| Own bubble (`bubbleMine`, new) | primary/100 | primary/900 |
| Text on own bubble | ink, 12.9 : 1 | ink, 10.7 : 1 |
| Their bubble | surface + 1 dp `line` border (white on cream is 1.07 : 1 today) | surface, no border |
| Time line under a run | inkSoft on bg, 5.35 : 1 | inkSoft on bg, 5.95 : 1 |
| Marigold text (`accentText`, new): sender prefix on Home, links in own bubble | primary/800 | primary/300 |
| **Solid accent** | send and mic, new-chat button, primary button, unread badge, voice play disc, playback progress, focus ring | same |
| Soft accent | selected chip or row = primary/50 fill + 1.5 dp primary/500 border + ink text | accentSoft dark + same border |
| No longer accent | bubble fills, the 2 dp border on own photos and albums, load-more bar, group badge icon, Home row time | |

Fixes found on the way: the time on own bubbles is 3.49 : 1 today
(`expiry_badge.dart:235`); it moves out of the bubble (B2) and becomes 5.35 : 1.

Target, checked on device screenshots: solid marigold covers **under 5 %** of
a chat screen at rest (today roughly a third in a chat with long own messages).

### D3 Home (colour only, three lines)

Row time → inkSoft (marigold only when unread). Sender prefix ("you:",
"Chait galx:") → inkSoft 600. Unread badge stays solid accent. Nothing else
on Home changes here.

## E. Attachments

- **E1 Photo.** Fills the bubble edge to edge, radius from B1, no border, no
  fill behind it. **No download disc** (the preview is sharp at this size):
  a tap opens the viewer, which downloads. A failed or expired photo keeps
  today's states.
- **E2 Video.** Same box. Centre play disc 44; bottom-left pill with the
  duration, plus the file size while the video is not on the phone
  ("0:42 · 8.1 MB"). The download disc is replaced by that pill.
- **E3 Voice.** Width A2. Row: 40 play disc (solid accent, onAccent icon) ·
  waveform of 36 bars (played bars ink, the rest ink at 30 %) · duration.
  Speed chip only while playing, right of the duration. Tap or drag on the
  waveform seeks. Reuses `VoiceWaveform` (`voice_waveform.dart`).
  The bar heights: see decision D-3.
- **E4 Document.** Width A2. Row: 40 icon tile (ink at 8 %, ink icon, radius
  10) · file name 15/22 600, one line, middle-ellipsis · "PDF · 2.4 MB"
  13/18 inkSoft. No marigold.
- **E5 Album.** Width A2, tiles as A5, inner radius 10, no border; the count
  chip stays top-right.
- **E6 Link preview.** Card width A2 inside the bubble's padding; one
  surface2 tile, no second border; title 15/22 600 two lines, host 13/18
  inkSoft.
- **E7 Upload and failure states** keep their behaviour; they take the new
  colours (ink on the tint, never onAccent).

## F. Loading placeholders (registry R11 rewrite)

| Rule | Value |
|---|---|
| Motion | opacity 1.0 ↔ 0.55, easeInOut, 1600 ms, back and forth. No moving highlight |
| One clock | a `SkeletonGroup` at the top of a loading layout drives every block inside it, so they breathe together |
| Shape | the real one: chat placeholders use B1 corners, own side in `bubbleMine`, their side in surface2; sizes from A |
| Media before the preview | flat surface2 box in the final size with a 28 dp photo or video glyph in inkFaint |
| Uploading voice | static bars at 30 % and the upload disc; no shimmer next to a spinner |
| Delay | a placeholder appears only after 300 ms of loading; content fades in over 150 ms |
| Reduced motion | static, full opacity |
| Package | `shimmer` is removed from `pubspec.yaml` |

Today: two motions, a pulse that snaps back every 1.2 s
(`skeleton.dart:60`, no reverse), one clock per block, grey pills on both
sides (`chat_screen.dart` `_ChatLoadingState`). "Can't decrypt" is never a
placeholder (unchanged law).

## Decisions (defaults in bold)

| # | Question | Options |
|---|---|---|
| D-1 | Own bubble tint, light | **A: primary/100 `#FFE9CF`** (calmest; 1.10 : 1 against the page, so it reads by position and shape) · B: primary/200 `#FFD59E` (warmer, 1.29 : 1). Both are on the board |
| D-2 | Where the time goes | **A: one line under the run (B2)** · B: inside the last bubble, at the end of the last text line |
| D-3 | Voice waveform heights | **A: real levels**: the sender adds 36 levels to the encrypted message, old messages and old apps fall back to B · B: bars generated from the message id (decorative, the same for both people) |
| D-4 | Photo download disc | **A: removed (E1)** · B: preview blurred until downloaded · C: small corner chip with the size |
| D-5 | Their bubble in light mode | **A: 1 dp line border** · B: no border |
| D-6 | Run gap | **5 minutes** · 2 (today) · 10 |

## Must not undo

- Terminal decrypt states are never placeholders (a70f020).
- A media bubble only says "not downloaded" when it knows (2026-10-30
  learning); E2's size label follows the same rule.
- Album tiles fill the box the album gives them; tests use a photo shaped
  unlike the tile (2026-11-02 learning).
- Accent ink on a faint accent shell is unreadable in dark mode (2026-10-30
  learning): text on `bubbleMine` is ink, never onAccent or accent.
- Grep gate: no hard-coded colours in screens; the ramp lives in
  `lib/core/theme/tokens.dart` only.
- Reduced motion parks placeholders.

## Test gates

1. `ChatBubbleGeometry`: A1, A2, A3 values at W = 360, 384, 411, 554 and
   aspect 3:1, 16:9, 1:1, 9:16.
2. B1 corner table for first, middle, last and lone, both sides.
3. B2: no bubble contains a time; a run's last unit is followed by one meta
   line; one-line text bubbles in a run have equal height.
4. B3: 4 min gap joins, 6 min splits; sender name once per streak.
5. B6: a short link above a preview card is start-aligned.
6. Voice, document and photo bubbles have the same width at each W.
7. Token contrast test: every pair in D1/D2 computed, text ≥ 4.5 : 1.
8. Golden-free colour check: an own text bubble's fill is `bubbleMine` in
   both themes; no `t.accent` fill in a bubble except the voice play disc.
9. E1: a photo with no full file shows no download disc; E2: a video shows
   the size only on a known "not on disk".
10. R11: one controller per `SkeletonGroup`; reduced motion → no ticker;
    no placeholder before 300 ms; `shimmer` is not imported anywhere.
11. Existing: `test/chat/bubble_geometry_test.dart`,
    `test/chat/album_bubble_test.dart` updated to the new numbers; full
    `flutter test` green against the baseline taken at build start;
    `flutter analyze` 0 errors.

## Device check list (Redmi and M52, light and dark)

1. A chat with short and long texts: bubbles in a run share one shape, the
   time is under the run, no bubble is taller because of a time.
2. Portrait, landscape and panorama photos, a video, an album: all one
   width, none taller than 1.25 × width, no border, no download disc on
   photos.
3. Voice note: waveform, play, seek, speed chip only while playing; same
   width as a photo.
4. Document and link preview: same width, no nested boxes, no marigold.
5. Group chat: name once per streak, disc beside the last bubble, reaction
   chips on the bubble's edge, no "+" chip.
6. Own bubbles are the tint in both themes; text is easy to read; solid
   marigold is only on the buttons, badges and play discs.
7. Open a chat on a slow network: placeholders breathe together in the
   real shapes; nothing jumps when content lands.
8. Redmi: scrolling a long chat stays smooth.
9. Reduced motion on: placeholders are still.
10. Home: row times and prefixes are grey; unread rows still stand out.

## Out of scope

Motion (send, arrive, reactions, page changes): the next spec. Composer, app
bar, long-press menu, media viewer, pinned banner. Home beyond D3.

## Diff vs current (files a build touches)

`lib/core/theme/tokens.dart`, `lib/core/widgets/skeleton.dart`,
`lib/features/chat/chat_run_grouping.dart`, and in
`lib/features/chat/widgets/`: `expiry_badge.dart`, `message_bubble.dart`,
`image_message_bubble.dart`, `video_message_bubble.dart`,
`voice_message_bubble.dart`, `document_message_bubble.dart`,
`album_bubble.dart`, `link_preview_card.dart`, `reaction_bar.dart`,
`reply_quote.dart`; `lib/features/chat/screens/chat_screen.dart` (loading
state, meta line), `lib/features/home/screens/home_screen.dart` (D3),
`pubspec.yaml` (drop `shimmer`), `docs/design/00-foundation.md`,
`docs/design/10-registry.md`, `docs/design/pages/chat.md`.
