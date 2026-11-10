# Mascot pass (Page 10): Capy, the chill guardian (spec + acceptance checklist)

Date: 2026-11-09. Status: **spec PASS 2026-11-10 (user), all 9 deferred decisions at their defaults.** Phase 2 = implementation in a fresh session. Page 10 of `00-foundation.md` §8.
Visual ground truth: **`docs/design/pages/mascot.html`** (S1 expression sheet, S2 views and where each is used,
S3 the offline bath sequence, S4 in-app placements, S5 rig, S6 phases). Background and earlier rounds:
`docs/design/mascot/inventory.md` (every place, role, action, view; ideas I1–I5), `docs/design/mascot/round2.html`.
Art source: `docs/design/mascot/styles/gen_s1v2.py` writes `styles/s1v2/scene.rml` (4 views) and
`styles/expressions/scene.rml` (19 frames). Authority: `00-foundation.md` → `10-registry.md` → this page.

User decisions this page rests on (2026-11-07 to 11-09): Rive now, authored by Claude as RML with the Rive CLI,
not the CustomPainter rig first; the capybara stays and is redesigned, yuzu on its head; style **S1 Sticker**
(round 2, "it must read as a capybara, not a seal"); defaults D2–D8 of `inventory.md` accepted; **all ideas
I1–I5 accepted** ("implement whenever"); **eye rule**: idle = relaxed curved-line eyes, doing something = round
eyes, intense or focused work = a focused look. Performance limit from the spike: one animated capybara is
smooth on the Redmi S2, six drop it to ~40 fps.

This replaces backlog §5 "Rive deferred, layer the approved SVG, no redraw" and the W3 spec's "source of truth:
the approved SVG paths in a CustomPainter".

## ⛔ Frozen (a breach is an automatic FAIL)

- **F1** The mascot never blocks, delays or replaces a user action. Nothing waits on a Rive load, a state
  machine or an animation end. If the `.riv` fails to load, the slot shows nothing (no error, no spinner).
- **F2** At most **2** animated capybaras on screen. Every other one is a still pose (its state machine set to
  `still`).
- **F3** Reduced motion (`MediaQuery.disableAnimations`): idles stop on the mood's still pose; one-shots (pet,
  hop, wave, celebrate, flush) jump to their end pose. Nothing moves.
- **F4** Decorative: every `Capy` sits in `ExcludeSemantics`. The words next to it carry the meaning. Pet is
  a bonus, never the only way to do anything.
- **F5** Never inside a message bubble, never behind readable text, never on every screen. One exception, in
  Phase 4: a **sticker** the user chooses to send (I2).
- **F6** No network for the mascot. One bundled `.riv`; no fetch, no CDN, no Rive runtime analytics.
- **F7** Mascot palette only (A3), constant in both themes. No purple. No gradients, no Feather blur.
- **F8** A tap on a capybara never also fires the control under it (the offline banner's own tap = Retry).

## A. The character

- **A1 MUST** Style **S1 Sticker**: one dark-brown outline, flat fills, a lighter belly, blush, the yuzu with a
  leaf on top of the head. Outline width 5 in the 240 box.
- **A2 MUST** The capybara cues stay (they are what fixed "looks like a seal"): long blunt box-ended snout with
  the dark muzzle patch **at the tip**; small eye high and set back; flat head top; no neck; small round ears
  at the back; bean body; toe ticks. Front view: wide flat head, eyes far apart at the sides, tall muzzle
  block, two nostril slits, split-lip mouth.
- **A3 MUST** Palette (constant both themes; added to foundation §2 after PASS):

  | Role | Colour | Note |
  |---|---|---|
  | body | `#C6894F` | existing |
  | shade (ears, feet) | `#B27A42` | existing |
  | belly | `#D9A066` at 59% | new |
  | snout | `#8B5E3E` | existing |
  | ink (outline, nostrils, mouth, brows) | `#5C3B28` | existing "nostril" colour; 9:1 on light bg |
  | eyes | `#3A2E22` | existing "face" |
  | blush | `#E8946A` at 59% (82% when happy) | new |
  | yuzu | `#EFA00B` + white highlight 78% | = the accent |
  | leaf | `#8DB255` | new |
  | key | `#E8A21D` | existing key-gold |
  | water / ripple, sweat drop | `#A9DCD6` / `#7FC4BC` | new, Onsen and worried only |
  | tongue | `#E07A6A` | new, open mouths |

- **A4 MUST** Four views (artboards, 240 × 240, square): **Sit** (three-quarter body, profile head), **Front**
  (sitting, facing you, paws free), **Head** (profile bust, for slots under 56 dp, eyes 1.4×), **Onsen** (Head
  soaking in a round pool, eyes 1.4×). Loaf (lying, side) comes with onboarding (Phase 5).
- **A5 MUST** Profile views face left as drawn. A placement may mirror them (`flip: true`) so the capybara faces
  its content; the offline banner always does (it faces the text).

## B. Expressions

Eye rule (user): **idle = curved-line eyes; doing something = round eyes; intense or focused = focused look.**

| Mood | Eyes | Mouth | Extras | Used when |
|---|---|---|---|---|
| `chill` (default) | ︶ relaxed curved lines | small smile | — | nothing is happening: empty states at rest, the bath |
| `active` | round dots | small smile | — | it is doing something: waving, looking, sending (flush) |
| `happy` | ^ arcs | open, tongue | bigger blush, 2 sparkles | success, after a pet, back online |
| `sleepy` | – flat lines | small "o" | "z z" | nothing found, idle overnight (I4) |
| `worried` | round + glint + brows up at the nose side | wobbly line | sweat drop | errors, missing key, wrong PIN |
| `focused` | half-lidded + brow down at the nose side | flat line | — | searching, app lock, guarding the key |

Front-only poses: `pet` (happy face, paws in), `celebrate` (arms up, yuzu pops up, 3 sparkles), `guard`
(focused face, holds the gold key at the chest).

- **B1 MUST** Each mood is a set of face shapes switched by opacity in the Mood layer (C3), cross-fading over
  **150 ms**. No mood changes the silhouette.
- **B2 MUST** At 40 dp the eye is ~3 px: there the props (z, sweat, sparkles) and motion carry the mood. The
  sheet in S1 shows both 120 dp and 40 dp.

## C. Rig: `assets/mascot/capy.riv`

Source of truth after PASS: a Rive project at `mascot/capy/` (`rive.yaml` + `scene.rml`), seeded once from
`gen_s1v2.py` output and hand-edited from then on (the generator is retired). Built with
`rive mascot/capy --publish --output-dir=assets/mascot` (needs `rive login`).

- **C1 MUST** Parts and bones (light rig; spike rule):

  | Artboard | Bones | Moving parts | Visible shapes |
  |---|---|---|---|
  | Sit | 2 (`Back` root, `Head`), body path skinned to both (as the spike) | head nod/tilt, ears, yuzu node, front paws (wave), face set | ≤ 30 |
  | Front | 0 (node transforms, origins at the feet / shoulders) | body squash, 2 arm nodes (3 poses each), key node, face set | ≤ 30 |
  | Head | 0 | head node (origin at the neck): nod, tilt, bob; yuzu node; face set | ≤ 18 |
  | Onsen | 0 | head node bob, 3 queue yuzus (Q1–Q3), steam loop, face set | ≤ 26 |

- **C2 MUST** One view model `Capy`, shared by all four artboards:

  | Property | Type | Meaning |
  |---|---|---|
  | `mood` | enum `chill, active, happy, sleepy, worried, focused` | face set (B) |
  | `pose` | enum `none, pet, celebrate, guard` | Front-only poses |
  | `still` | bool | idle layer parks on the still pose (F2) |
  | `reducedMotion` | bool | F3 |
  | `pet` | trigger | tap: eyes close, blush deepens, squish (~600 ms) |
  | `holding` | bool | long press: melts into a loaf (squash 0.85) and back on release |
  | `hop` | trigger | happy hop (~500 ms) |
  | `wave` | trigger | one wave (Sit, Front) |
  | `celebrate` | trigger | Front celebrate (~1.2 s) |
  | `lookX` | number −1…1 | eyes and head tilt toward a side (Front, Head) |
  | `queued` | number 0…3 | Onsen yuzus shown |
  | `flush` | trigger | Onsen: nudges one yuzu out of the pool |

- **C3 MUST** State machine per artboard, layers: **Idle** (breathe 3.4 s; blink every ~4.6 s only while the
  eyes are round; with `chill` a slow content squeeze instead), **Mood** (B1), **Action** (pet, hop, wave,
  celebrate, flush: each returns to Idle), **Props** (z loop while sleepy, sweat bob while worried, steam).
  Every layer has an EntryState; every artboard sets `defaultStateMachineId` (gotchas doc).
- **C4 MUST** Budgets: `.riv` ≤ 60 KB; no Feather; one clip per artboard at most; `rive inspect` problems
  empty; `--bench` per artboard recorded in the work log.
- **C5 MUST** Headless self-checks before any Flutter work: every mood × artboard rendered with
  `--data mood=…` and compared with this page's sheet; triggers proven with two captures each.

## D. Flutter: the `Capy` widget (`lib/features/mascot/capy.dart`)

- **D1 MUST** `Capy({required CapyView view, CapyMood mood = chill, double size, bool animated = false,
  bool flip = false, CapyPose pose = none, int queued = 0, bool pettable = true})`. Square; `size` is the
  side in dp.
- **D2 MUST** The `.riv` is loaded once and cached (a provider); each `Capy` makes its own artboard + view-model
  instance. Load failure → `SizedBox(size)` (F1).
- **D3 MUST** `still = !animated`; `reducedMotion = MediaQuery.disableAnimationsOf(context)`, updated on
  change. Wrapped in `RepaintBoundary` and `ExcludeSemantics`.
- **D4 MUST** Pet (I3): tap → `pet` + `appHaptic(HapticsType.light)`; long press → `holding` true until
  release. Its own `GestureDetector` (opaque) so F8 holds. A still capybara plays the pet and returns to still.
- **D5 MUST** Replaces `Capybara`/`CapybaraPainter` (`lib/features/mascot/`) and `EmptyState`'s default
  mascot. The old painter and `test/capybara_rig_test.dart` are deleted once nothing references them.
- **D6 MUST** Dependency `rive: ^0.14.11` (spike: builds with this project's AGP, +7.7 MB native lib per ABI).

## E. Placements, Phase 2

| # | Where | View | Mood | Animated | Size | Notes |
|---|---|---|---|---|---|---|
| X1 | Login header | Sit | chill | waves once on first show, then still | 112 | |
| X2 | Home, no chats | Sit | chill | still | 130 | |
| X3 | Home, load error | Sit | worried | still | 120 | was sleepy |
| X4 | Requests, empty | Sit | chill | still | 120 | |
| X5 | Requests, error | Sit | worried | still | 120 | was sleepy |
| X6 | Chat, empty | Sit | chill | idle; first send → hop (C4) | 108 | |
| X7 | Chat, older messages unavailable | Front | worried | still | 72 | was sleepy |
| X8 | Chat search, nothing found | Sit | sleepy | still | 72 | searching animation is Phase 3 |
| X9 | Chat load error card | Front | guard (focused + key) | still | 72 | |
| X10 | `EmptyState` default (create group ×2, profile unavailable) | Sit | chill (worried on the load error) | still | **120** (was 180) | |
| E1 | Offline banner, Home + Chat | Onsen, flipped | chill → active → happy | yes | 40 | I1, below |

- **E1 MUST (I1, the yuzu bath)** Replaces the cloud icon in both offline banners (`home_screen.dart`
  `_OfflineBanner`, the chat banner at `chat_screen.dart` ~1773). Copy unchanged (`kOfflineSendCopy`) plus,
  when `queued > 0`, a second line "N waiting". `queued` = outbox rows with `kind == 'text_send'` in state
  `queued` or `sending`, all chats (one new `StreamProvider<int>` over `outboxTable`).
  - Offline: mood `chill`, the pool shows `min(queued, 3)` yuzus; a new queued message floats one in.
  - Back online: the banner stays while `queued > 0` with copy "Back online, sending N…", mood `active`; each
    decrease fires `flush` once. At 0: copy "All sent.", `happy` + `hop`, then the banner collapses as today. It also collapses
    10 s after reconnecting whatever the count (a stuck or failed op must not pin the banner).
  - The banner's Retry and its tap-to-retry keep working; a tap on the capybara pets it instead (F8).
- **C4 MUST (send success)** (a) X6: the first message sent in an empty chat makes the empty-state capybara
  `hop` while it cross-fades out over 400 ms. (b) E1's flush. No per-message hop anywhere else.
- **I3 MUST (pet)** On every placement above.
- **E2 MUST** At most 2 animated per screen (F2): chat with the offline banner + empty chat = 2 (E1 + X6).

## F. Later phases (each gets its own short spec section before building)

| Phase | Items |
|---|---|
| 3 · security moments | **K2** app lock: Head 72, `focused`, `lookX` follows the PIN dots, `happy` + hop on unlock, `worried` on a wrong PIN · **K1** key restore success: Front `celebrate` · **K3** group key rotation: Front `guard`, swaps the key in the group settings banner · **E4** cold-start sync hold: Front `guard` · **X8** searching (looks left/right) |
| 4 · stickers (I2) | 8–12 stickers from the Front/Sit poses, sent as a `sticker` message holding only an id; art bundled, works offline, encryption unchanged; still images in chat. Needs a live PocketBase field + rule change and an old-client fallback. Own spec. |
| 5 · more | **O1** onboarding (3 scenes, + Loaf view) · **C1** chat app-bar buddy (Head 32, tap = info mode) · **C5** failed-send sheet (Head 48, worried) · **S1** Settings › About (Sit 96) · **I4** night and festival looks (nightcap after 23:00; Diwali, Holi, New Year by date) · **I1** app icon / splash from the Head view |
| dropped | C2 swipe companion (D5), typing-indicator capybara (D4) |

## Test gates (phase 2)

- Unit: `queuedCountProvider` counts only `text_send` in `queued|sending`; X1–X10 mapping table (view, mood,
  animated, size) as data with a test; banner state machine (offline → sending → done, 10 s cap).
- Widget: `Capy` with a fake loader: `ExcludeSemantics` present; load failure → empty box; reduced motion sets
  the property; a tap pets and does **not** fire the banner's retry; `EmptyState` default size 120.
- Rive asset: `rive mascot/capy --verify` clean, `inspect` problems empty, size ≤ 60 KB, C5 captures.
- Full suite green (baseline below), `flutter analyze` 0 errors, release build of both ABIs.

## Device check list (phase 2, M52 + Redmi S2, light and dark)

1. Every X1–X10 placement shows the new capybara at its size and mood; nothing clipped at font scale 1.3.
2. Login: one wave, then still.
3. Airplane mode on Home: the bath banner appears; the capybara faces the text; eyes are curved lines.
4. Send 3 texts offline: 3 yuzus float in; a 4th shows "4 waiting" with 3 yuzus.
5. Airplane off: "Back online, sending…", round eyes, one yuzu leaves per message actually sent, then a hop and
   the banner leaves.
6. Same in a chat screen.
7. Tap the capybara in the banner: it pets with a haptic (both phones), and Retry does **not** fire.
8. Long press any capybara: it melts and comes back on release.
9. New chat, send the first message: the empty capybara hops and fades.
10. System "remove animations" on: nothing moves anywhere; banner still counts.
11. Redmi: Home with the banner + an empty state, scroll: no visible jank; perf overlay p99 build+raster
    under 16 ms (record numbers).
12. Kill the network for > 10 s with a failed message: the banner still leaves 10 s after reconnecting.
13. No "Rive" watermark or splash is visible in any placement (Free plan check; see decision 6).

## Out of scope (do NOT build in phase 2)

Phases 3–5 items, stickers, the app icon, the Loaf view, media uploads in the waiting count, any PocketBase
change, any copy change other than E1's.

## Deferred decisions (default in bold; reply with a number to change one)

1. **Name (I5):** **no name in copy yet** / "Kapi" / "Yuzu" / your own.
2. **Offline copy:** **keep `kOfflineSendCopy` + "N waiting"** / playful ("Taking a soak till you're back").
3. **Waiting count:** **texts only** / texts + media uploads (needs the upload state, more work).
4. **Old painter:** **delete it after the swap** / keep it as a fallback.
5. **APK size (+7.7 MB per ABI):** **accept** / split per ABI at release.
6. **Watermark:** **build on Free; if a watermark shows on device (item 13), buy the Cadet month before
   release and re-publish** / buy now.
7. **Pet haptic:** **light** / none / selection.
8. **Sit or Front for X7/X9:** **Front** (it can hold the key, show empty paws) / Sit.
9. **Phase order after 2:** **3 security → 4 stickers → 5 more** / stickers first.

## Baseline

`main` at `ceb1b36` (unpushed `8c3acce`, `ceb1b36` left alone). Last full suite **1161/1161**. Re-run before
phase 2 starts.
