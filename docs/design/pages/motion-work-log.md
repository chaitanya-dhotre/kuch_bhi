# Motion pass: work log

Spec: `motion.md` (PASS 2026-11-15: M-1 A, M-2 yes, M-3 slide, M-4 none,
M-5 B). Board: `motion.html`. Built 2026-11-15 by Claude in one session.
Not committed: one commit after the user's device PASS.

## Gates

| Gate | Where | Result |
|---|---|---|
| Baseline `flutter test` at build start | — | 1340 pass + 1 load flake (`send_fetch_char_test`, passes alone) = 1341 |
| 1 tokens + L8 grep | `test/core/motion_tokens_test.dart` | pass |
| 2, 2a (C1), 3, 4, 6, C10 | `test/chat/motion_test.dart` | pass (8) |
| 2a (D2), 5, 7, 8, 9 | `test/core/motion_widgets_test.dart` | pass (8) |
| 10 full suite | `flutter test` | **1359 / 1359** (1341 + 18 new) |
| 10 analyze | `flutter analyze` | 0 errors (warnings are older, untouched files) |

Existing tests changed: `test/media/album_screen_test.dart` only, its
`contentOffset` 100 → 24. That test measures the album page on the push's
first frame; the old Android transition started 100 dp right, B2 starts 24.

## What was built (spec item → code)

- A tokens: `lib/core/theme/tokens.dart` (6 durations, 3 curves, 2 springs,
  derived 240/190/300/180/360, `scrim`, `motionOf`, `springTo`). L8 lines
  that must stay raw carry `// motion-allow: <reason>` (recorder, typing
  dots, Chat calm placeholders, timers).
- B1 `core/widgets/press_scale.dart` on AppButton, AppChip, composer
  actions (attach, stickers, send, mic), reaction chips. Plain app-bar
  `IconButton`s keep Material's ripple only.
- B2 `core/theme/page_motion.dart`, set in `app_theme.dart`. A predictive
  back gesture still hands over to Flutter's own Android builder.
- B3 `chatAvatarHeroTag` in `app_avatar.dart`; Home row + chat app bar.
- B4 `app_sheet.dart` / `app_dialog.dart` (+ `dialogTheme.barrierColor`);
  the disappearing dialog uses `dialogMotion` too.
- C1–C3, C10 `features/chat/widgets/bubble_entrance.dart` +
  `chat_screen.dart` (`ChatEntrances` keyed by message id; overlay finds the
  bubble's own fill box, so it lands on its real rect, radius and colour);
  composer reports the field box (`message_input.dart` `onSendFlight`) and
  ticks `appHaptic(light)` on a text send.
- C4 `delivery_tick.dart`; C5 `reaction_bar.dart`; C6
  `message_context_menu.dart` (menu scale, 30 ms emoji stagger, 150 ms
  exit) + bubble lift in `message_bubble.dart`; C7 jump button in
  `chat_screen.dart` (also counts theirs that arrive while scrolled up);
  C8 `swipe_to_reply.dart`; C9 `voice_message_bubble.dart`.
- D1 `chat_tile.dart` (`flashKey`): row flash, preview cross-fade, badge
  pop. D2 `ReorderSlide` + `home_screen.dart` (`findChildIndexCallback`
  keeps a moved row's element).
- E1 `ShakeOnChange`: PIN dots (`pin_pad.dart`) and the recovery-key field
  (`lock_overlay.dart`).

## Choices made in the build

- The long-press menu is a bottom sheet, not a popover, so C6 is adapted:
  the bubble lifts behind the 45 % scrim (dimmed with the rest) and the
  sheet content grows from the bubble's side.
- Under Android "Remove animations" Flutter already runs every normal
  controller at 5 % of its duration, so the 150 ms page fade lasts ~8 ms
  on a phone. Spec L7 ("instant or a short fade") still holds.
- Reduced-motion sheets keep decision 8 (no slide) and add a 150 ms
  content fade on open.
- Exit curves are `curveExit.flipped`: Flutter evaluates a reverse curve
  on the falling value, and the unflipped ease-in would decelerate.
- Ticks, reaction chips and rows avoid `Opacity` at rest (FadeTransition),
  because existing tests count Opacity widgets for the offline dim.

## Frames (`adb shell dumpsys gfxinfo com.chai.kuch_bhi`)

Measured 2026-11-15 on both phones, release `--split-per-abi` arm64 build
(the phones carry version code 2001; the universal APK is refused as a
downgrade). Chat: the Capybara group (user's pick). Before = the build
installed 2026-11-14 21:10; after = this build.

**gfxinfo doesn't work here**: Flutter draws on its own SurfaceView, so
`dumpsys gfxinfo` sees 1–2 frames per case. The numbers below come from
`dumpsys SurfaceFlinger --latency` on the app's SurfaceView (BLAST)
layer, polled every 250 ms during the case (the M52 at 120 Hz keeps only
~1 s). Driver: adb taps; "over 16.7" = gaps between presented frames above
16.7 ms; "dropped" = gaps over 1.5 refresh periods; worst gap in ms.

| Case | M52 before | M52 after | Redmi before | Redmi after |
|---|---|---|---|---|
| page push (Home → chat) | 2 over 16.7 · 6 dropped · worst 25 | 4–5 over 16.7 · 12–13 dropped · worst 25 | 7 dropped · worst 84 | 5–8 dropped · worst 67 |
| back (pop) | 2 · 3 dropped · worst 75 | 0 · 2 dropped · worst 17 | 2 dropped · worst 67 (one 668 ms pause) | 2 dropped · worst 50 |
| long-press menu | 0 · 0 dropped · worst 9 | 2 · 7 dropped · worst 17 | 2 dropped · worst 50 | 4 dropped · worst 34 |
| 10-message send burst | **invalid**: the keyboard moved the send button, nothing was sent | 4 over 16.7 · 15 dropped · worst 25 | invalid (same) | 76 dropped of 253 · worst 67 |

The after burst ran on both phones at once in the same group, so each
phone was also animating the other's 10 arrivals. Order was right on both.

Reading against the gate:
- M52 (pass gate ≤ 2 frames over 16.7 ms per case): pop and long-press
  pass; **push (4–5) and burst (4) miss it**, worst frame 25 ms (3 vsyncs
  at 120 Hz). No freeze.
- Redmi: no freeze over 100 ms in any after case, end states right. The
  burst is rough (76 dropped frames); with no valid before burst there is
  no baseline. Whether this counts as "clearly bad" (which would trigger
  the C1/D2 fallback) is the user's call at the device check.
- Not yet checked on device: arrive while scrolled up, reactions, voice,
  swipe, Home flash/reorder, PIN shake, Remove animations (device check
  items 3–8).

## Device round 1 (user, 2026-11-15) and fixes

User: "Other things did pass." Reported, with two screen recordings:

| # | Report | Cause | Fix |
|---|---|---|---|
| 1 | Avatar a different colour in the chat than on Home | App bar used `accentSoft`, Home `surface2` | App bar uses Home's disc |
| 2 | Group / online badge doesn't move with the avatar | Hero wrapped only the disc | `ChatHero` wraps disc + badge; flight cross-fades the two looks |
| 3 | Offline banner should move too | — | Banner is a `ChatHero` (destination look only) |
| 4 | Home "NG", chat "N" | Two initials functions | Shared `nameInitials` |
| 5 | Multiple reactions on one image | Not motion: data rule | Asked the user (not changed) |
| 6 | Send has a line under it, text misaligned | Overlay sits outside Material: debug text style (yellow underline, monospace), the wrong font wrapped "Happy birthday", and the box's tight height stretched the text | Overlay wrapped in a transparent Material, text takes the row's DefaultTextStyle, loose height, +1 dp width |
| 7 | Name can move with the avatar | — | Name is a `ChatHero` |
| 8 | Voice notes and stickers could fly from the composer | Spec had them on the simple rise | Snapshot flight (`toImageSync` of the row, grown from the field); emoji-only texts use it too, they had no fill box and showed no flight at all |

Also found in the video: emoji-only sends showed nothing until they landed.
A list skips painting a 0-height row, so a grow now starts at 2 % height (~1 dp)
so the first frame can be snapshotted.

### Frames after round-1 fixes (2026-11-15 18:00, same method, Capybara)

| Case | M52 round 1 | M52 round 2 | Redmi round 1 | Redmi round 2 |
|---|---|---|---|---|
| page push | 4–5 over 16.7 · worst 25 | 4–6 over 16.7 · worst 42 | worst 67 | worst 84 · **2 gaps ≥ 100 ms** |
| back (pop) | 0 · worst 17 | 3 · worst 50 | worst 50 | worst 67 |
| long-press menu | 2 · worst 17 | 2 · worst 17 | worst 34 | worst 34 |
| 10-message burst | 4 · worst 25 | 4 · worst 25 | 76 dropped · worst 67 | 68 dropped · worst 83 · 1 gap ≥ 100 ms |

The avatar + badge + name cross-fade made push and pop a little heavier on
the M52 (worst 25 → 42 / 17 → 50 ms). The Redmi's ≥ 100 ms gaps may be idle
time between frames (the reader counts any gap, and nothing draws before
the tap lands); not yet told apart from a real freeze. Burst order right on
both phones (r1–r10).

### Round 2 device fixes (2026-11-15 18:30)

- **One reaction per person** (user: "No point of one person being able
  to send multiple reactions"): a new emoji now takes back my other
  reactions on that message through the existing remove path (queued
  offline like any undo). Test: `reactions_offline_test.dart` "one
  reaction per person". Older builds' extra reactions stay until each
  person reacts again.
- **Stickers did not fly on device**: the snapshot looked for "the first
  box narrower than the row" and found the swipe-to-reply icon (hidden,
  22 dp at the left). `ChatBubbleFrame` now marks its own box with
  `MetaData(ChatBubbleFrame.box)` (margin moved outside that box; chat
  calm gate 6 measures the box without it), and the flight looks for the
  mark. Stickers are also decoded at chat size when the sticker sheet
  opens, so the row's first frame has pixels.
- Redmi, recorded in Capybara: sticker, voice note (preview sheet send)
  and text ("Happy birthday": one line, app font, no underline) all fly
  from the composer to their bubble.
- Redmi 10-message burst on its own (no arrivals from the M52): 267
  frames, 44 dropped, worst 50 ms, no gap ≥ 100 ms, order right.
- Slip: after the reinstall Home's order shifted and one test sticker went
  to the Redmi ↔ M52 direct chat ("Chait galx") instead of Capybara.

### M52, round 2 build (2026-11-15 18:33, Capybara, recorded)

Sticker and voice note (preview send) grow out of the composer; text burst
m1–m10 in order.

| Case | frames over 16.7 ms | dropped | worst |
|---|---|---|---|
| page push, first open after launch | 6 | 16 | 42 ms |
| page push, second open | 0 | 0 | 8.5 ms |
| back (pop) | 1 | 7 | 25 ms |
| long-press menu | 3 | 18 | 25 ms |
| 10-message burst, alone | 4 | 17 | 25 ms |

Gate (≤ 2 over 16.7 ms per case): pop and the warm push pass; the first
push after launch, long-press and the burst miss by 1–4 frames, worst 25–42
ms. No freeze on either phone.
