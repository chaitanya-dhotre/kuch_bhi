# Mascot pass (Page 10): Capy, the chill guardian (spec + acceptance checklist)

Date: 2026-11-09. Status: **spec PASS 2026-11-10 (user), all 9 deferred decisions at their defaults.** Phase 2
COMMITTED `a871498` 2026-11-10 (device PASS). **Phase 3 (§G, security moments) spec PASS 2026-11-11 (user), all 8
decisions at their defaults**; implemented 2026-11-11 (gates green, 1186/1186), device PASS 2026-11-11
(`mascot-work-log.md`, phase 3). **§H (X8b, still searching) spec PASS 2026-11-11, all 5 decisions at their defaults;
device PASS 2026-11-11** (`mascot-work-log.md`, X8b). Page 10 of `00-foundation.md` §8.
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
| 3 · security moments | **Specced in §G below.** K2 app lock · K1 key restore success · K3 group key rotation · E4 cold-start sync hold · X8 search looks around |
| 4 · stickers (I2) | 8–12 stickers from the Front/Sit poses, sent as a `sticker` message holding only an id; art bundled, works offline, encryption unchanged; still images in chat. Needs a live PocketBase field + rule change and an old-client fallback. Own spec. |
| 5 · more | **O1** onboarding (3 scenes, + Loaf view) · **C1** chat app-bar buddy (Head 32, tap = info mode) · **C5** failed-send sheet (Head 48, worried) · **S1** Settings › About (Sit 96) · **I4** night and festival looks (nightcap after 23:00; Diwali, Holi, New Year by date) · **I1** app icon / splash from the Head view |
| dropped | C2 swipe companion (D5), typing-indicator capybara (D4) |

## G. Phase 3: security moments (spec PASS 2026-11-11, all decisions at their defaults)

Pictures: `mascot.html` **S7** (every frame is a headless render of the rig with the phase 3 additions). Rig
additions as a script: `docs/design/mascot/phase3/apply_phase3.py` (patches a copy of `mascot/capy/scene.rml`;
`render.sh` + `frames.commands` render the frames). Phase 3 applies the same edits to `mascot/capy/scene.rml` by hand
and republishes `assets/mascot/capy.riv`.

### ⛔ Frozen for phase 3 (on top of F1–F8; a breach is an automatic FAIL)

- **P1** The lock screen never waits on the mascot. Unlock (PIN and fingerprint), the wrong-PIN shake, the lockout
  countdown, Forgot PIN and app-lock **E4** ("right PIN → overlay gone at once") behave exactly as today. The
  capybara only *reads* what the lock already has: the digit count (`PinPad.onChanged`) and `_unlock`'s result.
- **P2** Key code is untouched, byte for byte: `restorePrivateKey`, `syncAllHistory`, `_restoreHistory`'s frozen
  `go(home)`, `removeMemberFromGroup`, `_rotateGroupKey`, `encryptionSyncProvider`, `SyncRouteGate`, the router's
  `redirect`. The capybara reacts only to state those already expose (restore phase, the remove result, the splash's
  1 s timer).
- **P3** The splash never stays up longer because of the capybara, and never shows an empty box: it only swaps in
  when `CapyLoader.ready` is already non-null.
- **P4** No copy changes except K3's one new line (decision 5).

### G0. Rig and widget additions

| # | Where | What | Why |
|---|---|---|---|
| R1 | Front, Head | `lookX` eased over 0.2 s (`DataConverterInterpolator` chained after the range mappers); Front face slide ±6 → **±10** | the PIN-dot follow must glide, and ±6 is under 2 dp at 72 dp |
| R2 | Front | trigger **`swapKey`** (0.9 s): the held key drops and fades, a new one drops in from above into the paws, sparks flash, a small bounce | K3 |
| R3 | Sit | trigger **`lookAround`** (1.6 s): turns to look the other way (a 100 ms scale-flip turn), turns back, small shrug bob | X8 |

- **G0.1 MUST** R1–R3 follow C3/C4: one-shots live on the Action layer and are ignored under `reducedMotion`; Front
  `rest` hold-keys the key's y (only the Action layer moves it, learning 2026-11-10); `.riv` stays ≤ 60 KB (now
  50.8 KB; R1–R3 add about 1 KB); `--verify` clean, `inspect` problems empty. New ids start at `0:511`.
- **G0.2 MUST** `Capy` gains: `double lookX = 0` (synced like `mood`; forced to 0 under reduced motion, so nothing
  glides); `CapyOneShot? playOnShow` (enum `wave, swapKey, lookAround`), which **replaces** `waveOnShow` (X1 moves to
  `playOnShow: wave`); `int celebrates = 0` (one `celebrate` per increase, the `hops`/`flushes` pattern). Still
  capybaras play one-shots and return to still (as pet does today).
- **G0.3 MUST** `CapyLoader.source` is kicked off unawaited in `main()` right before `runApp` (`lib/main.dart:70`),
  so the lock screen and the splash usually have the file by their first frames. Nothing awaits it (F1).

### G1. K2 · App lock

| | |
|---|---|
| Hook | `lib/features/app_lock/lock_overlay.dart:304`: `_unlockContent`'s `AppLogoTile(size: 64)` becomes the capybara (decision 3). Digits from `PinPad(onChanged:)` (`widgets/pin_pad.dart:28`, already there, unused by the overlay); wrong PIN from `_unlock` (`lock_overlay.dart:121`) returning false. |
| View · size | **Front 72**, `pose: guard` (holds the key), not flipped (decision 1). |
| Moods | `focused` while you type · `worried` for 1.2 s after a wrong PIN, and the whole time `isWaiting()` (lockout countdown) · no unlock beat (decision 2). |
| Eyes | `lookX` follows the dots: 0 digits → 0 (looks at you); n digits → −1 + (n − 1) × 0.4 (dot 1 = −1, dot 6 = +1). Delete moves it back. Pure function `pinLookX(n)`. |
| Animated | yes (the only capybara visible; the app is `Offstage` under the lock). |
| Not here | the Forgot PIN and create steps, the privacy cover (they keep the logo). |

- **G1.1 MUST** Fingerprint unlock, the 6th-digit check and the lockout timer are not touched (P1). The 1.2 s
  `worried` is a plain `Timer` in the overlay state, cancelled in `dispose`.
- **G1.2 MUST** I3/I4 of app-lock still hold: 360×640 at 200% text scrolls with no overflow (72 vs 64 dp: +8 dp);
  TalkBack focus still lands on the title.
- **G1.3 CHECK** Capybaras under the lock (`Offstage` keeps them mounted) must not cost the Redmi frames while you
  type. Device item 5 measures it. Only if it fails: wrap the gated child in `TickerMode(enabled: !gate)` in
  `LockOverlay.build`.

### G2. K1 · Key restore success

| | |
|---|---|
| Hook | `lib/features/auth/screens/backup_pin_screen.dart:954` `_RestoreOverlayState._buildRestore`: a centred capybara above the progress card (first child of the `Column` at :981, then 12 dp). Phase from `widget.phase`; changes seen in a new `didUpdateWidget`. |
| View · size | **Front 96**, animated (the overlay is the whole screen; decision 7). |
| Sequence | `deriving` (checking the key): `guard` + `focused` → phase leaves `deriving` (key accepted): `pose: celebrate`, `celebrates += 1` **once** → after 1.2 s: `pose: none`, `active` (downloading) → `ready`: `happy`. Pure function `restoreCapy(phase, celebrated)` → (pose, mood). |
| Not here | the saving card (`_buildSaving`: setup, change, upgrade, Start Fresh) gets no capybara. |

- **G2.1 MUST** The overlay still leaves only through the frozen `go(home)` (P2); a `ready` that lasts one frame
  simply never shows `happy`. Reduced motion: the arms-up `celebrate` pose shows for 1.2 s, no motion.

### G3. K3 · Group key rotation

There is no rotation banner today: rotation runs inside `removeMemberFromGroup` (awaited, so a successful remove
means the new key exists) and the admin only sees the toast "Alex removed". K3 adds one small card.

| | |
|---|---|
| Hook | `lib/features/groups/screens/group_settings_screen.dart:230` `_confirmRemove`: `_guard(onSuccess:)` stores the removed name in state; the card shows at the top of the members section (next to the `membersError` banner, :407) until you leave the screen. A second remove replaces the name. Failed or timed-out removes show nothing. |
| Card | `t.surface2`, radius md, 12 padding: **Front 56** `guard`, `playOnShow: swapKey`, not animated (it swaps once, then holds the key still) · text 15/22 ink: **"New group key made. Alex can't read new messages."** (decision 5). |
| Keeps | the "Alex removed" toast and its announcement (house contract). |

- **G3.1 MUST** The card is plain text for TalkBack (the capybara excluded, F4); no buttons, no dismiss.

### G4. E4 · Cold-start sync hold

| | |
|---|---|
| Hook | `lib/features/auth/screens/splash_screen.dart:73`: when `_slow` (after 1 s) **and** `CapyLoader.ready != null`, the `AppLogoTile()` (88) cross-fades (150 ms, the spinner's own fade) into **Front 88** `guard` + `focused`, animated, in the same 88 box: no layout jump (decision 6). The spinner below stays. |
| Fast start | under 1 s: the logo only, as today. File not loaded: the logo stays (P3). |

- **G4.1 MUST** On cold start with the lock on, the splash sits `Offstage` under the lock: at most 2 animated (lock
  + splash), so F2 holds.

### G5. X8 · Search looks around

| | |
|---|---|
| Hook | `lib/features/chat/screens/chat_screen.dart:1693` `_SearchEmptyState` (a `StatelessWidget` today) becomes stateful; spot `X8` in `capy_spots.dart:45` changes to `active` + `playOnShow: lookAround`. |
| Sequence | "Nothing found" appears → round eyes, looks the other way, back, shrug (1.6 s) → `sleepy` (a 1.6 s `Timer`). |
| Replays | each time "Nothing found" appears again (results → none, or after a clear); not while you keep typing into a no-results query (decision 8). The widget does *not* stay mounted while typing (each keystroke shows the list until the debounced search answers), so the chat state remembers that it already looked around. |
| Animated | still + one-shot (chat screen budget: E1 banner + X8 ≤ 2). Reduced motion: `sleepy` at once, no trigger. |

### Phase 3 test gates

- Rig: `apply` the R1–R3 edits to `mascot/capy/scene.rml`, `--verify` clean, `inspect` problems empty, size ≤ 60 KB,
  captures of `swapKey` and `lookAround` (two each) and `lookX` mid-ease (frame +4 is between the two ends).
- Unit: `pinLookX` (0→0, 1→−1, 6→1, delete back); `restoreCapy` table (deriving / past deriving before and after
  1.2 s / ready); `Capy` fires one `celebrate` per increase and `playOnShow` once per mount; `lookX` forced 0 under
  reduced motion.
- Widget (fake rig): lock overlay passes the digit count to `lookX`; a wrong PIN → `worried`, back to `focused` after
  1.2 s; `isWaiting` → `worried`; **every existing app-lock test passes unchanged** (P1). Restore overlay: one
  `celebrate` when the phase leaves `deriving`, none on later phase changes. Group settings: a successful remove shows
  the card with the name; a failed or timed-out one does not; the toast still shows. Splash: the capybara only after
  1 s and only with `CapyLoader.ready` set, else the logo. X8: `lookAround` once on show, `sleepy` after 1.6 s, no
  replay while typing; reduced motion → `sleepy`, no trigger.
- Frozen: function-level diff vs HEAD empty for every method in P2, `unlockWithPin`, `authenticateWithBiometrics`,
  `PinPad._digit`.
- Full suite green (baseline below), `flutter analyze` 0 errors, release build of both ABIs.

### Phase 3 device check list (M52 + Redmi S2, light and dark)

1. Lock screen: the capybara holds the key; its face slides along with each digit; delete slides it back.
2. Right PIN: the app is there at once, exactly as fast as before phase 3.
3. Wrong PIN: worried face + sweat drop while the keypad shakes, focused again after about a second. Lockout
   countdown: worried the whole time.
4. Fingerprint unlock: no delay.
5. Redmi: open a chat with the offline banner and an empty chat, lock, type a PIN: keys respond at once; perf overlay
   p99 build + raster under 16 ms (record numbers; G1.3 only if this fails).
6. Fresh install + restore with the recovery key: the capybara guards the key while it checks, throws its arms up
   when the key is accepted, then watches the download; Home arrives as before.
7. Remove a member from a group: the card swaps the key once and names them; the toast still shows. Leave the
   screen and come back: the card is gone.
8. Cold start on slow mobile data (splash over 1 s): the logo turns into the guarding capybara, spinner below, no
   jump. A fast start: logo only, no flash.
9. Chat search for a word that isn't there: it looks around, shrugs, gets sleepy. Keep typing: no replay. Clear and
   search again: it replays.
10. System "remove animations": the lock face doesn't slide, no celebrate motion (arms-up still), no swap, no
    look-around; all the words and timings above unchanged.
11. TalkBack: the lock screen still focuses the title; no capybara is announced; the K3 card's text is read.
12. Lock screen and restore screen at 200% text, 360×640: scroll, no overflow.

### Phase 3 out of scope

Phase 4 stickers, phase 5 items, any copy other than K3's line, any key, router or sync change, a capybara on the
Forgot PIN / create-PIN steps or the saving-a-backup card, rotation UI for join or key-gap rotations (no screen shows
them today).

### Phase 3 deferred decisions (default in bold; reply with a number to change one)

1. **K2 view:** **Front 72 holding the key (its face slides to follow the dots)** / Head 72 as first planned (a
   profile can only nod: S7 shows both).
2. **Unlock beat (`happy` + hop):** **drop it: app-lock E4 makes the lock leave at once, so it would never be seen** /
   a 150 ms fade-out with a happy face (E4's maximum; a blink at most).
3. **Lock screen logo:** **the capybara replaces the logo tile** / keep the logo and add the capybara above it
   (+80 dp).
4. **K3 card:** **shows after a remove until you leave the screen** / disappears after 6 s / no card (K3 dropped,
   toast only).
5. **K3 line:** **"New group key made. Alex can't read new messages."** / "Key changed. Alex is locked out of new
   messages." / your own.
6. **E4 splash:** **after 1 s the logo turns into the guarding capybara (same box)** / keep the logo and add the
   capybara under the name (everything shifts up ~50 dp on every cold start).
7. **K1 size:** **96** / 120.
8. **X8 replay:** **each time "Nothing found" appears** / only the first time per search session.

## H. X8b · Still searching (spec PASS 2026-11-11, all decisions at their defaults)

From the phase 3 device run: in a long chat whose older messages are not decrypted yet, chat search shows **0/0**
with the chat list still visible, which reads as "no match" while the app is still decrypting and searching.
Pictures: `mascot.html` **S8** (headless renders of the rig with R4, made by
`docs/design/mascot/search/apply_search.py`; `render.sh` + `frames.commands`; sheet `search/frames.png`).

**Why 0/0 shows early** (`lib/features/chat/screens/chat_screen.dart`, line numbers at `9236c01`):

1. The counter has no "still searching" case: `'${_matchItemIndices.isEmpty ? 0 : _matchIndex + 1}/${_matchItemIndices.length}'`
   (:1410). From the first keystroke until the search answers, the match list is empty, so it prints 0/0.
2. While `_searchPending` the body keeps showing the chat list (:945–948 only swaps in "Nothing found" once the
   search is not pending), so the screen looks like a finished search with no hits.
3. In a long chat that wait is long: `ConversationSearchController._scan` (:155) looks up the bodies one after
   another, each through `messageBodyProvider` (a decrypt when not cached), each capped at 2 s (`_resolveSearchBody`,
   :265). Hundreds of undecrypted messages = many seconds of 0/0.
4. Found on the way: if a body lookup throws, `_scan` dies unawaited, `onResults` never runs and `_searchPending`
   stays true for good. Today that is a frozen 0/0; with a searching state it would be a capybara searching forever.

### ⛔ Frozen for X8b (on top of F1–F8)

- **H1** What search finds is unchanged: the same `ConversationSearchController` (200 ms debounce, per-keystroke
  cancel, candidates, ephemeral matches), no new decrypt path, no database writes, `searchMessages` untouched.
- **H2** After a search really finishes, everything is as today: matches → the list jumps to the newest match;
  none → X8 "Nothing found" (looks around once per no-results stretch, then sleepy; §G5, learning 2026-11-11).
- **H3** F2 on the chat screen: the E1 offline banner + the searching capybara = 2 animated. X6 (empty chat) never
  shows with a search state (search states only replace a non-empty list). X8 stays still + one-shot.

### H0. Rig addition (R4)

| # | Where | What |
|---|---|---|
| R4 | Sit | pose enum value **`search`** (`0:520`). A magnifying glass (rim in the outline brown, a pale see-through lens over the eye, a white glint, a short handle) in the near front paw, raised to the eye. New **Pose** layer on Sit: `pose_search` sweeps paw + glass in a slow 2 s loop (toward the snout and down, back, a little up), `pose_search_still` holds it centred when `still` or `reducedMotion`, `pose_none` puts the paw back down. Front ignores `search` (its Pose layer has no transition for it). |

- **H0.1 MUST** C3/C4 hold: the near paw moves to the front of Sit's draw order (first child = front in this rig) so
  the raised glass sits over the face; at rest it overlaps nothing of the head, so every existing Sit frame is
  unchanged (drafted: the resting `chill` frame is pixel-identical to the current rig, 0 px differ). `--verify` clean,
  `inspect` problems empty, `.riv` ≤ 60 KB (51.6 KB now; the draft build grows 1 053 bytes). New ids `0:520`–`0:533`.

### H1. Flutter

| | |
|---|---|
| Spot | `capy_spots.dart`: **`X8b searching`** = Sit 72, `focused`, `pose: search`, **animated** (it is working: the glass sweeps). `CapyPose` gains `search`. |
| Busy state | New `_SearchBusyState` next to `_SearchEmptyState`: `EmptyState(title: 'Searching…', subtitle: 'Looking for “pizza”.', mascot: X8b)` (decision 3). Shows when search is open, the query is not empty, the search is still running and no matches are on screen, **and** either the search has run past the grace time (decision 4) or "Nothing found" was showing (typing on from "Nothing found" picks the glass straight back up instead of flashing the chat list). |
| Grace | A `Timer` of debounce + 300 ms, restarted on every keystroke and cancelled when results arrive, on clear and on close. A search that answers within it never shows the capybara: no flash in short or already-decrypted chats. |
| Counter | While a search is running: **"…"** instead of a number (decision 2). It never shows 0/0 for a search that hasn't finished. Arrows as today (they need matches). |
| Matches on screen | Refining a query that has matches keeps the list and its highlights until the new answer (decision 1); only the counter shows "…". |
| Stuck guard | `_resolveSearchBody` treats a lookup that throws like one that times out (no body), so every search finishes (point 4 above). |
| Hand-over to X8 | Results come back empty → the busy state leaves and "Nothing found" mounts as today: the glass is gone and it looks around (or stays sleepy if it already did in this stretch, H2). |
| Reduced motion | The busy capybara holds the glass still, centred (`pose_search_still`); same words, same timings. |

- **H1.1 MUST** `chat_screen.dart` is hand-edited, never `dart format`ted.
- **H1.2 MUST** The busy state, like X8, remounts per stretch; nothing it must remember lives in its widget
  (learning 2026-11-11). It only reads the chat state.

### X8b test gates

- Rig: R4 applied to `mascot/capy/scene.rml` by hand, `--verify` clean, `inspect` problems empty, size ≤ 60 KB,
  captures: rest unchanged, sweep (two frames differ), still pose under `reducedMotion`, back to `none`.
- Widget (`test/chat/search_capy_test.dart`, fake rig, body lookups held open with a `Completer`):
  slow search → "…" at once, busy state after the grace with Sit `pose: search`, `focused`, animated, and never
  "0/0" or "Nothing found" while it runs; it ends empty → "Nothing found", `lookAround` once, no glass; a fast search
  with matches → never the busy state, "…" then "1/n"; typing on from "Nothing found" → busy at once, no list, then
  sleepy "Nothing found" with no replay; a lookup that throws → the search still finishes; clear and close → no busy
  state, timer gone; reduced motion → busy capybara with `reducedMotion` true. Both existing X8 tests unchanged.
- `ConversationSearchController` tests unchanged and green (H1).
- Full suite green, `flutter analyze` 0 errors.

### X8b device check list (M52 + Redmi S2, light and dark)

1. A long chat with older messages not decrypted yet (e.g. right after a restore): search a word. The counter shows
   "…", then the capybara raises the magnifying glass and scans; it never shows 0/0 or "Nothing found" meanwhile.
2. The search finds it: the list comes back and jumps to the match, counter "1/n".
3. The search finds nothing: the glass goes, it looks around, shrugs, gets sleepy ("Nothing found").
4. Keep typing after "Nothing found": it picks the glass back up (no chat-list flash), then sleepy "Nothing found",
   no look-around replay.
5. A short or already-searched chat: search a word that is there: no capybara flash, "…" then the count.
6. Offline banner showing while searching: both move smoothly (2 animated).
7. System "remove animations": the glass is held still; words and timings the same.
8. TalkBack: "Searching…" and "Looking for …" are read; no capybara is announced.
9. 200% text at 360×640: the busy state fits like "Nothing found" (no overflow).

### X8b out of scope

Making the search itself faster (the scan looks up one body at a time; batching misses through
`DecryptPass.runFor`, as `searchMessages` does, would shorten the wait: a separate change), searching messages not
loaded into the chat yet, home search, any change to what counts as a match.

### X8b deferred decisions (default in bold; reply with a number to change one)

1. **Refining a query that has matches:** **keep the list and highlights, counter "…" until the new answer** / clear
   the matches on every keystroke (the capybara then shows on each pause in typing past the grace).
2. **Counter while searching:** **"…"** / a small 12 dp spinner / the last count, greyed.
3. **Copy:** **"Searching…" / "Looking for “pizza”."** / "Still looking…" / "Unlocking older messages to search
   them." (only true when it is decrypting, so not the default) / your own.
4. **Grace before the capybara shows:** **300 ms after the search starts (500 ms after the last keystroke)** / none
   (shows from the first keystroke; flashes in fast chats) / 700 ms.
5. **View and size:** **Sit 72 with the glass (same spot and capybara as "Nothing found")** / Front 72 holding the
   glass in both paws (a new Front pose; it then turns into the Sit for "Nothing found") / Sit 96.

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

Phase 3: `main` at `a871498` (phase 2; main 3 ahead of origin, leave them unpushed). Last full suite **1173/1173**
(phase 2 gates). Re-run before phase 3 starts.
