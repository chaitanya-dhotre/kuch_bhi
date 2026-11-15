# Motion pass (spec, rev 1)

Status: **spec PASS 2026-11-15 (M-1 A, M-2 yes, M-3 slide the rows, M-4 none, M-5 B: bubble grows out of the text field).** The user chose the two bolder options and accepts a rougher Redmi S2: nearly everyone who uses the app has a flagship. Item 5 of
`docs/design/feedback-2026-11-plan.md` (friends: animations feel "pretty
normal" or boring; U7: no animation in most places).
Board with live demos: `docs/design/pages/motion.html`.
Amends foundation §5 (motion tokens and laws), `chat.md` §F and §Q.
Builds on Chat calm (`858cd5a`).

## What moves today

- Page changes: Flutter's Android default. There is no
  `PageTransitionsTheme` in the theme (grep: 0 hits in `lib/`).
- The chat list is a reversed `ListView.builder`
  (`chat_screen.dart:997-1003`): a new message appears in one frame and
  pushes the rest up in the same frame.
- Reactions, ticks, unread badges, Home rows: no motion.
- Already moving: swipe-to-reply snap (`swipe_to_reply.dart:64`,
  `Curves.elasticOut`), send/mic swap, body fade, placeholders, the mascot.
- Tokens: only three durations (`tokens.dart:107-109`), no shared curves.

## Sources

- The user's pick, `charles-ux-animation`
  (github.com/LemonFace0309/charles-skills): its timing table, curves,
  press scale, stagger and exit rules are adopted below, translated from CSS
  to Flutter. Read only, not installed.
- Mobbin flows give still frames, not video, through the connector. Used:
  [Lapse, sending a message](https://mobbin.com/flows/56246965-fe40-4343-a12e-721c267c0875?tab=screens&utm_source=claude&utm_medium=ai-assistant&utm_source_platform=mcp)
  (the send button changes role as soon as the field empties),
  [Pinterest, replying](https://mobbin.com/flows/93779872-c307-4a0b-a780-1b7cf586171e?tab=screens&utm_source=claude&utm_medium=ai-assistant&utm_source_platform=mcp)
  (reaction row on top of the action sheet). The videos on mobbin.com are
  for the user to watch; anything they like can be added as a rev 2 note.

## A. Tokens and laws (foundation §5 rewrite)

| Token | Value | Use |
|---|---|---|
| `motionPress` | 120 ms | pressed states, colour shifts |
| `motionFast` | 150 ms | small fades, icon swaps, tick changes (unchanged) |
| `motionEnter` | 200 ms | a bubble, a chip, a menu arriving |
| `motionBase` | 250 ms | sheets, dialogs (unchanged) |
| `motionPage` | 320 ms | page push, shared avatar |
| `motionSlow` | 400 ms | highlight fades (unchanged) |
| `curveEnter` | `Cubic(0.32, 0.72, 0, 1)` | anything arriving |
| `curveExit` | `Cubic(0.55, 0, 1, 0.45)` | anything leaving |
| `curveMove` | `Cubic(0.77, 0, 0.175, 1)` | moving or resizing in place |
| `springSoft` | damping ratio 0.8, no visible bounce over 4 % | reactions, badge, mascot |
| `springDrag` | critically damped (ratio 1.0) | releasing a drag |

Laws:

- **L1 Frequency decides.** Things done many times a minute (typing,
  scrolling, opening the keyboard) get no added motion. Things done a few
  times a session get the tokens above. Nothing that is already on screen
  at first paint animates in.
- **L2 Same-frame response.** A press shows on the frame of the touch.
  Nothing waits for the server to start moving (send is already optimistic).
- **L3 Exits are shorter.** An exit runs at 75 % of its entrance and moves
  less.
- **L4 Transform and opacity only.** No blur, no animated shadow or clip on
  list items. Exceptions: the height of a single new bubble and the send
  overlay's size and radius (C1), and the Home rows' slide (D2).
- **L5 One thing leads.** At most one primary motion at a time; at most 2
  list items animating.
- **L6 Interruptible.** Input is never blocked; a new send snaps the
  previous bubble to its end state.
- **L7 Reduced motion** (`MediaQuery.disableAnimations`): every item below
  becomes instant, except page changes and sheets, which become a 150 ms
  fade. The same information still shows.
- **L8** Chat and core widgets take durations and curves from the tokens,
  never a raw `Duration` (grep gate, with an allow-list for the recorder
  and video player).

## B. Press and navigation

- **B1 Press.** Buttons, icon buttons, chips, reaction chips, the send
  button: scale to 0.96 over `motionPress`, back on release. Rows and
  tiles wider than 200 dp change background only (as today).
- **B2 Page push.** One `PageTransitionsTheme` for the app. Incoming page:
  from 24 dp to the right and opacity 0, `motionPage`, `curveEnter`.
  Outgoing page: 8 dp to the left and to opacity 0.6. Pop: the reverse at
  240 ms. Android predictive back keeps working.
- **B3 Home → chat.** The tile's avatar flies to the chat's app-bar
  avatar (`Hero`), `motionPage`, `curveMove`. **Rev 1.1:** the avatar flies
  with its group badge or online dot, and the chat's name flies with it;
  the flight cross-fades Home's look into the app bar's. The app-bar disc
  uses Home's colour and initials ("NG", not "N"). The offline banner flies
  between Home and the chat too (destination look only, so its capybara
  never runs twice).
- **B4 Sheets and dialogs.** Enter `motionBase` with `curveEnter`, exit
  190 ms with `curveExit`, scrim to 45 % black. One place sets this
  (`app_sheet.dart`, `app_dialog.dart`).

## C. Chat

- **C1 Send (M-5 B).** The message grows out of the text field. On send, a
  copy of the typed text in the field's box (same position, size and
  radius) is drawn in an overlay; over 300 ms with `curveMove` it travels to
  the new bubble's place while its size, corner radius and fill change from
  the field's to the bubble's (`bubbleMine`). Meanwhile the bubble's row in
  the list opens its height from 0 over the same 300 ms, so the list glides
  up; the real bubble is invisible until the overlay lands, then swaps in
  on one frame. The composer clears on the frame of the tap. Light haptic
  tick (existing `appHaptic`). A second send during the flight snaps the
  first to its end (L6). **Rev 1.1 (device round 1, 2026-11-15):** voice
  notes, stickers and emoji-only texts grow from the composer too (stickers
  are decoded at chat size when the sheet opens): a
  snapshot of the bubble starts small inside the field (or the composer,
  while the recorder shows) and grows to its place over the same 300 ms.
  Text longer than 4 lines, photos, videos, documents and sends while
  scrolled up use the simple version: rise 12 dp, scale 0.96 from the
  bottom-right, fade in, `motionEnter`.
- **C2 Arrive.** An incoming bubble does the same from the bottom-left,
  8 dp, 180 ms. Only when the chat is open and the list is at the bottom.
  If the user has scrolled up, nothing animates in the list; the
  jump-to-bottom button's count pops instead (C7).
- **C3 Never on history.** Opening a chat, scrolling up, a restore, a
  search jump: no bubble animates. Only messages created after the screen
  opened, and only once each.
- **C4 Ticks.** Sending → sent → delivered → read cross-fades over
  `motionFast`. No bounce.
- **C5 Reactions.** A new chip pops from scale 0.6 and opacity 0 with
  `springSoft` (about 300 ms). A count change slides the number 6 dp up or
  down with a cross-fade, `motionFast`. Removing a chip: scale to 0.8 and
  fade, 120 ms. Light haptic on add.
- **C6 Long-press menu.** The bubble lifts to scale 1.03 over
  `motionFast`; the rest dims under a 45 % scrim; the menu and the emoji
  row grow from the bubble's side at scale 0.95, `motionEnter`. The first
  six emojis follow 30 ms apart. Exit 150 ms.
- **C7 Jump-to-bottom button and its count.** Fade and scale 0.9 → 1,
  `motionFast`; the count pops with `springSoft` when it changes.
- **C8 Swipe to reply.** The release uses `springDrag` instead of
  `elasticOut` (no wobble); the reply icon scales with the drag from 0.6
  to 1.
- **C9 Voice.** Play ↔ pause icons cross-fade with a 0.8 → 1 scale,
  `motionFast`; played bars fill continuously (linear); the speed chip
  fades in when playback starts.
- **C10 Deleting a message.** The bubble fades and its height closes over
  190 ms.

## D. Home

- **D1 New message on a row.** The row's background flashes primary/50
  (dark: accentSoft) and fades over `motionSlow`; the unread badge pops
  with `springSoft`. The preview text cross-fades over `motionFast`.
- **D2 Reorder (M-3).** When a chat moves to the top, the rows slide to
  their new places over `motionBase` with `curveMove` (the moving row
  travels up, the rows it passes move down one slot). Only rows on screen
  animate; a row coming from below the screen edge fades in at the top
  instead. Pinned rows keep their order. A second reorder during the slide
  retargets from the current positions.

## E. Errors

- **E1 Wrong PIN or recovery key.** The field shakes: x = 0, −10, 10, −6,
  6, −3, 0 dp over 360 ms, with the existing error haptic. Nothing else in
  the app shakes.

## Redmi S2 budget

- L4 and L5 are the budget. The Redmi runs 60 Hz with a slow GPU and may
  have 1–2 Rive mascots on screen.
- Gate: profile build on the Redmi, a 10-message send burst, a page push
  and a long-press menu: at most 2 frames over 16.7 ms in each, measured
  with `adb shell dumpsys gfxinfo com.chai.kuch_bhi` before and after.
- The user accepts a rougher Redmi (2026-11-15). So the pass gate is the
  **M52**: at most 2 frames over 16.7 ms per case. On the Redmi the numbers
  are recorded, and the only hard rule is no freeze over 100 ms and no
  wrong end state. If the Redmi is clearly bad, C1 and D2 fall back to
  their simple versions when the device's refresh budget is missed three
  sends in a row (a small runtime switch, not a device list).

## Decisions (defaults in bold)

| # | Question | Options |
|---|---|---|
| M-1 | Page change | **A: slide 24 dp + fade (B2)** · B: fade only · C: keep the Android default |
| M-2 | Avatar flies from Home to the chat (B3) | **Yes** · No |
| M-3 | Home row moving to the top | **Instant, with the flash and badge pop (D1)** · also slide the rows (more work, more risk on the Redmi) |
| M-4 | A mascot moment in this pass | **None**: the mascot already moves; add nothing here · one celebration on the first message of a new chat |
| M-5 | Send strength | **A: rise 12 dp, 200 ms (C1)** · B: the bubble grows out of the text field (closer to iMessage, 300 ms, needs a shared-element overlay) |

## Must not undo

- Back never waits for a server write (2026-11-03 learning); B2 must not
  delay the pop.
- Mascot rules: at most 1–2 animated mascots, idles park under reduced
  motion.
- Placeholders from Chat calm stay as they are.
- Haptics go through `appHaptic` only; the `haptic_feedback` pin stays.
- A screen never uses `ref` in `dispose` (2026-10-31 learning): animation
  controllers are disposed without it.
- The refetch and resync paths re-emit lists often (13.2 learnings): C3
  must key "already animated" by message id so a re-emit never replays an
  entrance.

## Test gates

1. Tokens: the eleven values in A exist and are the only source (L8 grep
   gate).
2a. C1: a short text send shows one overlay that ends exactly on the
    bubble's rect and is removed; long text, media and scrolled-up sends
    use the simple version. D2: a reorder ends with every row at its slot;
    two reorders 100 ms apart end correctly.
2. C1/C2: a message created after the screen opened gets one entrance; the
   same message after a list re-emit gets none; history gets none.
3. C2: scrolled up → no entrance, the button's count changes.
4. L6: two sends 50 ms apart leave both bubbles at rest with no exception.
5. L7: with `disableAnimations`, no item in B–E starts a ticker; pages and
   sheets use a 150 ms fade.
6. C5: add, change count, remove; chip ends at scale 1 or is gone.
7. B2: the theme's builder is used by a pushed route; pop completes even
   when the leaving page has a pending future (back never waits).
8. B3: the Home avatar and the chat avatar share a `Hero` tag per chat.
9. E1: a wrong PIN runs the shake once and leaves the field at x = 0.
10. Full `flutter test` green against the baseline taken at build start;
    `flutter analyze` 0 errors.

## Device check list (Redmi and M52)

1. Open and close a chat five times: the page slides, the avatar flies,
   back is instant to respond.
2. Send 10 short messages fast: each rises in, none stutters, order is
   right.
3. Receive messages with the chat open at the bottom, then scrolled up.
4. React, change a reaction, remove it; long-press a bubble.
5. Play and pause a voice note; swipe to reply and let go.
6. Home: get a message in another chat, watch the row flash and the
   badge pop.
7. Wrong PIN on the app lock: one shake.
8. Turn on "Remove animations" in Android settings: everything is instant
   or a short fade, nothing is missing.
9. Redmi with the offline banner mascot showing: steps 1–2 again, still
   smooth.
10. Frame numbers from `gfxinfo` recorded in the work log.

## Out of scope

Typing indicator, message effects (confetti and the like), animated
stickers, new mascot animations, sound, the media viewer's own transitions,
onboarding.

## Diff vs current (files a build touches)

`lib/core/theme/tokens.dart`, `lib/core/theme/` (page transitions theme),
`lib/core/widgets/app_button.dart`, `app_chip.dart`, `app_sheet.dart`,
`app_dialog.dart`, `chat_tile.dart`, `app_avatar.dart` (Hero tag),
`lib/features/chat/screens/chat_screen.dart`,
`lib/features/chat/widgets/message_bubble.dart`, `reaction_bar.dart`,
`message_context_menu.dart`, `delivery_tick.dart`, `swipe_to_reply.dart`,
`voice_message_bubble.dart`, `lib/features/home/screens/home_screen.dart`,
the PIN pad in `lib/features/app_lock/`, `docs/design/00-foundation.md`,
`docs/design/pages/chat.md`.
