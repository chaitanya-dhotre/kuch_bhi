# Mascot pass (Page 10): Capy, the chill guardian (spec + acceptance checklist)

Date: 2026-11-09. Status: **spec PASS 2026-11-10 (user), all 9 deferred decisions at their defaults.** Phase 2
COMMITTED `a871498` 2026-11-10 (device PASS). **Phase 3 (§G, security moments) spec PASS 2026-11-11 (user), all 8
decisions at their defaults**; implemented 2026-11-11 (gates green, 1186/1186), device PASS 2026-11-11
(`mascot-work-log.md`, phase 3). **§H (X8b, still searching) spec PASS 2026-11-11, all 5 decisions at their defaults.**
**§J (phase 4, capybara stickers) spec PASS 2026-11-11 (user), all 8 decisions at their defaults.** **§K (phase 5:
looks, app-bar buddy, failed-send sheet, About, app icon) spec PASS 2026-11-12 (user), all 9 decisions at their defaults; onboarding + Loaf parked.** **5a COMMITTED `d49afbf` 2026-11-13. 5b (launcher
icon A, Front on bath teal, + `AppLogoTile`) device PASS 2026-11-14, COMMITTED 2026-11-14: phase 5 done.** Page 10 of
`00-foundation.md` §8.
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
| 4 · stickers (I2) | **Specced in §J below.** 10 stickers from the Front/Sit/Onsen views, sent as a `sticker` message holding only an id; art bundled, works offline, encryption unchanged; still images in chat. Needs a live PocketBase check (and a field change if `type` is a select) and an old-client fallback. |
| 5 · more | **Specced in §K below** (5a looks + C1 + C5 + S1 · 5b icon · onboarding + Loaf parked). **O1** onboarding (3 scenes, + Loaf view) · **C1** chat app-bar buddy (Head 32, tap = info mode) · **C5** failed-send sheet (Head 48, worried) · **S1** Settings › About (Sit 96) · **I4** night and festival looks (nightcap after 23:00; Diwali, Holi, New Year by date) · **I1** app icon / splash from the Head view |
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

## I. K1b · Restore: the key toss and the envelope vault (spec PASS 2026-11-11, all decisions at their defaults; built, device PASS 2026-11-11)

The user's idea from the phase 3 device run (work log, "New ideas"): a big capybara in the centre checks the key and
throws it up when it matches, then slides to the top and, during the download, takes envelopes (the messages), opens
each with its eyes closed (privacy) and files it in a small vault beside it. This **replaces §G2** (K1: Front 96,
celebrate once, then `active`). Everything else in §G stays.

Pictures: `mascot.html` **S9**. Every capybara there is a headless render of the rig with the additions below, made by
`docs/design/mascot/k1/apply_k1.py` (patches a copy of `mascot/capy/scene.rml`; `render.sh` + `frames.commands` render
the frames). The build applies the same edits to `mascot/capy/scene.rml` by hand, then the script is retired.

### ⛔ Frozen for K1b (on top of F1–F8 and P1–P4; a breach is an automatic FAIL)

- **Q1** The key flow is untouched, byte for byte: `_restore`, `_restoreHistory` (and its frozen `go(home)`),
  `restorePrivateKey`, `syncAllHistory`, `encryptionSyncProvider`. The overlay only *reads* what it already gets: the
  phase and the four counts.
- **Q2** Nothing waits on the capybara. Home arrives the moment `_restoreHistory` sends it, mid-toss, mid-slide or
  mid-envelope. A wrong key, a missing backup or an error closes the overlay exactly as today (no capybara beat first).
- **Q3** No copy changes. The check stage shows today's two strings ("Unlocking your chats", "Checking your key…");
  the card, its counts and While you wait are today's.
- **Q4** One animated capybara on this screen (F2); the envelopes never outrun the real download (I3).

### I0. Rig additions (Front only; Sit, Head and Onsen unchanged)

| # | What | How |
|---|---|---|
| R5 | **Vault** beside the capybara | Root node at (196, 214), origin at its feet: a rounded box in water teal `#A9DCD6`, a door in ripple teal `#7FC4BC`, a white **chat bubble on the door** as its label, a key-gold dial, a slot on top, two ink feet. 6 shapes. Hidden (opacity 0) in every pose but `vault` (decisions 3, 4). |
| R6 | **Envelope** | Node under Breathe, in the paws (0, −58), opacity 0: back, letter (rises 22 when opened), front pocket, flap hinged at its top edge (scaleY −1 = open) with a blush seal. 5 shapes. Under the arms, over the body. |
| R7 | **Eyes shut** (`Face_shut`) | First child of `Look` (drawn in front of every mood face): two body-colour lids over the eyes, closed arcs with two lash ticks each. Only the `envelope` one-shot shows it, so it works over any mood. 2 shapes. |
| R8 | pose enum value **`vault`** | `pose_vault`: Place x 120 → 80 and scale 1 → 0.8 (the capybara steps left), the vault fades in, the key is put away, arms in the guard hold. Every other pose now hold-keys Place (x 120, scale 1) and the vault (hidden). Transition 400 ms, or a **cut** when `reducedMotion` (listed first, so it wins). |
| R9 | trigger **`tossKey`** (1.0 s) | From `guard`: crouch, spring, the key flies up past the right ear spinning twice, sparks, arms up, falls back into the paws, a small bounce. |
| R10 | trigger **`envelope`** (1.5 s) | An envelope flies in from the top left into the paws · eyes shut and a small turn away · the flap opens, the letter peeks up, back in, flap closes · eyes open · it arcs into the vault slot, shrinking · the vault squashes and its dial turns. |

- **I0.1 MUST** C3/C4 as before: R9/R10 live on the Action layer and are ignored under `reducedMotion`; `rest`
  hold-keys everything only the Action layer moves (Key x and rotation; Envelope x, y, rotation, scale, opacity; Flap;
  Letter; Face_shut; Vault scale; Dial). `--verify` clean, `inspect` problems empty.
- **I0.2 MUST** `.riv` ≤ 60 KB. Measured draft: 51.6 → **55.6 KB** (+3.9 KB); with X8b's glass (+1.1 KB, §H) about
  **56.7 KB**. New ids **0:540–0:566** (0:520–0:533 are X8b's). Whichever of §H and §I is built second rebases its
  edits onto the other's `scene.rml`.
- **I0.3 MUST** Front shape cap (C1 says ≤ 30 visible): in pose `vault` with an envelope in flight about 36 are
  visible. Allowed here only, because this screen has one capybara (the spike: one animated capybara is smooth on the
  Redmi); device item 9 measures it.

### I1. Flutter

| | |
|---|---|
| Hook | `lib/features/auth/screens/backup_pin_screen.dart` `_RestoreOverlayState._buildRestore` (only the restore view; `_buildSaving` is untouched). Phase changes seen in its `didUpdateWidget` (as today). |
| `Capy` | `CapyPose.vault` added. **`celebrates` is replaced by `tosses`** (fires `tossKey`) and **`envelopes`** (fires `envelope`), one trigger per increase as `hops`/`flushes` do. K1 was `celebrates`' only user; the rig keeps its `celebrate` (decision 8). |
| Stages | **Check** (mounted while the key is checked): Front **200** centred in the screen, `guard` + `focused`, under it the two strings centred, the title still a header. No card, no While you wait yet (decision 7). → **Toss** (phase leaves `deriving`): `tosses += 1`, mood `happy`, still centred. → **Dock** 1.0 s later (decision 6): over **450 ms** (`easeInOutCubic`) the space above the capybara shrinks to 0 and its box shrinks 200 → **120**, while the rig's `vault` pose steps it aside and fades the vault in; the progress card and While you wait fade in (200 ms) under it at once. → **Download**: `vault` + `active`, envelopes (I3). → **Ready**: `vault` + `happy`, no more envelopes. |
| Late mount | If the overlay first mounts already past `deriving` (a legacy PIN restore, which runs the history sync only after the recovery-key upgrade), it starts docked: no check stage, no toss, no slide. |
| Pure function | `restoreCapy(phase, {required bool docked})` → (pose, mood): not docked + checking → (`guard`, `focused`); not docked + past checking → (`guard`, `happy`); docked → (`vault`, `happy` if `ready` else `active`). |

- **I1.1 MUST** The centre is a computed space above the capybara, not an `Align`, so the card can appear while the
  capybara slides: `gap = max(0, (viewport − 200 − 12 − textHeight) / 2)` with `textHeight` from the text scaler
  (two lines at 22 and 18 dp). The slide is one `TweenAnimationBuilder` (0 → 1) driving both the gap and the size.
- **I1.2 MUST** The dock delay is a plain `Timer` cancelled in `dispose`. Nothing else is gated on it (Q2).

### I2. Reduced motion (F3: nothing moves)

The check stage looks the same (the rig's idle is already still). On accept: `happy` for the same 1.0 s, no toss (the
rig ignores the trigger). The dock is a **cut**: gap and size jump (duration 0), the pose cuts (R8), the card shows
without a fade. No envelopes are counted, so the screen holds the capybara, the vault and the card, still. Every word
and timing is the same as with motion.

### I3. How the envelopes follow the real download

- **I3.1 MUST** While docked, in `downloadingMsgs` or `decrypting`, with motion on: a `Timer.periodic(1.6 s)` (the
  1.5 s envelope plus a breath). On each tick, if the progress signature `(convIndex, msgCurrent)` changed since the
  last tick, `envelopes += 1`; if not, the capybara waits (it breathes and blinks). So the envelopes keep pace with the
  download, stop when it stalls, and never queue up or play on after it ends.
- **I3.2** One envelope is not one message (4,000 messages would take 100 minutes): it is a pace, never a tally. The
  numbers stay in the card's count line.
- **I3.3 MUST** No envelopes in `finalisingKey` or `fetchingConvs` (nothing downloaded yet) or `ready`. The timer stops
  on `ready`, on reduced motion and in `dispose`.

### I4. 200% text, 360×640

The check stage scrolls if the two strings at 200% do not fit beside the 200 box (the gap is then 0). Docked, the
column is today's plus 24 dp (120 box vs 96) and scrolls as today. No overflow in either stage or mid-slide.

### K1b test gates

- Rig: the R5–R10 edits in `mascot/capy/scene.rml`, `--verify` clean, `inspect` problems empty, size ≤ 60 KB,
  captures of `tossKey` (apex) and `envelope` (eyes shut, filed), the `vault` pose under `reducedMotion` is a cut (no
  in-between frame).
- Unit: `restoreCapy` table (checking / tossing / docked downloading / docked ready); `Capy` fires one `tossKey` per
  `tosses` increase and one `envelope` per `envelopes` increase.
- Widget (fake rig, fake async): mounted at `deriving` → size 200, `guard`/`focused`, card absent; phase →
  `finalisingKey` → one `tossKey`, `happy`; +1.0 s → pose `vault`, card present, +450 ms → size 120. Mounted at
  `finalisingKey` → docked at once, no `tossKey`. Downloading with counts moving → one `envelope` per 1.6 s; counts
  still → none; `ready` → none after; reduced motion → no envelopes and size 120 with no in-between frame. 360×640 at
  200% text: no overflow in both stages. Existing restore-overlay tests pass, their celebrate checks rewritten.
- Frozen: function-level diff vs HEAD empty for Q1's methods and `_buildSaving`.
- Full suite green, `flutter analyze` 0 errors, release build of both ABIs.

### K1b device check list (M52 + Redmi S2, light and dark)

1. Fresh install, restore with the recovery key: a big capybara in the middle holds the key with a focused face while
   "Checking your key…" shows.
2. Key accepted: it throws the key up past its ear, catches it, happy; then slides up and shrinks, steps aside, and the
   vault appears beside it; the card and While you wait fade in.
3. Download: envelopes fly in; it shuts its eyes and turns a little away while each opens, then files it in the vault
   (the vault squashes, the dial turns). On a slow connection it waits between envelopes; it never runs ahead.
4. Home arrives as soon as before (time it against phase 3: no wait for a toss, slide or envelope).
5. Wrong recovery key: the error shows at once, as today.
6. Legacy 6-digit PIN restore: after saving the new key, the restore screen starts with the capybara at the top beside
   the vault; no toss.
7. System "remove animations": no toss, no slide (it jumps to the top), no envelopes; the words and timings are the
   same.
8. 200% text on a 360×640 screen: both stages scroll, nothing cut off.
9. Redmi: perf overlay during the download, p99 build + raster under 16 ms (record the numbers).
10. TalkBack: "Unlocking your chats" is the header in both stages; the capybara, vault and envelopes are never read.

### K1b out of scope

Copy changes, the saving-a-backup card, a vault that fills up with progress, sounds, haptics, any key, router or sync
change, a capybara beat on a wrong key.

### K1b deferred decisions (default in bold; reply with a number to change one)

1. **Check-stage size:** **200** / 160.
2. **Docked size:** **120 (the capybara is as big as today's 96, the vault beside it)** / 96 (everything 20% smaller).
3. **Vault label:** **a white chat bubble on the door, no word** / the word "Chats" drawn into the rig (about 4 dp
   tall at 120, never translated, never read out) / a "Chats" caption in Flutter under the vault.
4. **Vault colours:** **water teal with a key-gold dial** (palette colours so far used only by the bath and the sweat
   drop) / a brown wooden strongbox (shade `#B27A42`, gold fittings).
5. **Envelope pace:** **at most one every 1.6 s, only while the counts move** / one per finished chat (a long single
   chat then shows nothing for a long time).
6. **Toss then dock:** **the toss plays in the centre, the dock starts 1.0 s after the key is accepted** / dock at once
   and toss while sliding (the card shows 1 s sooner).
7. **Check stage:** **the capybara and the two strings only; the card and While you wait come with the dock** / today's
   full card under the big capybara from the start.
8. **The rig's old `celebrate`:** **keep it (phase 5 may use it); only K1 stops using it** / delete it (about −1 KB).

## J. Phase 4 · Capybara stickers (idea I2) (spec PASS 2026-11-11, all decisions at their defaults)

Friends send each other a capybara sticker from the composer. A sticker is a tiny message that holds only a sticker
id; the art ships inside the app, so nothing is uploaded, it works offline through the existing outbox, and the
encryption is unchanged. This is F5's one exception: the capybara inside the chat, because the user chose to send it.

Pictures: `mascot.html` **S10** (forelegs redrawn 2026-11-11 after the user's review). Every sticker there is a headless
render of the rig plus sticker-only shapes, made by
`docs/design/mascot/stickers/apply_stickers.py` (patches one copy of `mascot/capy/` per sticker) → `render.sh` (renders
each on white and on black, since CLI captures are opaque) → `matte.py` (recovers the alpha from the two renders and adds
the white die-cut edge). Drafts: `docs/design/mascot/stickers/previews/*.png` (384 px, transparent).

Code line numbers below are at `e4ad70e`.

### ⛔ Frozen for phase 4 (on top of F1–F8; a breach is an automatic FAIL)

- **T1** Encryption unchanged. The sticker id travels only inside `encrypted_body`, encrypted like a text. The server
  learns "this message is a sticker" (as it learns "photo" today), never which sticker. No new key path, no new crypto.
- **T2** No upload, no download, no network for the art. Stickers are assets in the APK. A sticker sent offline queues
  in the drift outbox like a text and sends on reconnect.
- **T3** Old app versions never break: they show the sticker as a readable text line (J2.3). Nothing an old app does
  with a sticker crashes or blocks its chat.
- **T4** The live server is read or changed only with the user's yes, and the field change (if any, J4) is live
  **before** a build that can send stickers is installed on any phone.
- **T5** Never touch the user's real chats: every server test runs on a copy of `data.db` on a throwaway port.
- **T6** Stickers in the chat are still images, never `Capy` widgets or Rive (J1.2). They do not count toward F2.
- **T7** The wire body format (J2.2) and the ten ids are permanent once shipped: a later app may add ids, never rename
  or reuse one.

### J1. The sticker set

| id | Label (picker, TalkBack, fallback) | View | Built from | Sticker-only shapes |
|---|---|---|---|---|
| `hi` | Hi | Front | `active` (round eyes) | right foreleg raised from the side, two wave ticks; built-in arm lines hidden |
| `lol` | LOL | Front | `happy` (^ eyes, open mouth, sparkles) | two joy tears in water teal at the outer eye corners |
| `sorry` | Sorry | Front | `pet` pose (paws in) + `worried` (sweat drop) | — |
| `love` | Love | Front | `pet` + `happy` | a blush heart held at the chest, a small one floating top right |
| `thanks` | Thanks | Front | `pet` + `happy` | a yuzu held out in the paws (a gift) |
| `sleepy` | Sleepy | Sit | `sleepy` (z z) | — |
| `on-my-way` | On my way | Sit | `active` mid-`hop` | three ink speed lines and two dust puffs behind it |
| `chill` | Chill | Onsen | `chill`, `queued` 2 | steam hidden (inside the die-cut edge it read as "$$") |
| `guarding` | Guarding | Front | `guard` (holds the key) + `focused` | — |
| `celebrate` | Celebrate | Front | `happy` | both forelegs raised, six confetti bits in palette colours; built-in arm lines hidden |

- **J1.1 MUST** Art: S1 style and A3 palette only (F7: no purple, no gradients). Every sticker has a **white die-cut
  edge** (6 px at 384, ≈ 2 dp at 128 dp) so the dark outline reads on the dark chat background (decision 2). A raised
  paw is a **short foreleg shaped like the legs** (user, 2026-11-11: a capybara's front limbs are short like its legs,
  never long arms): a stub about 35 units long, 22 thick (13 body-colour core inside the ink), drawn **in front of** the
  body like the feet, starting just inside the body's side edge so the paw breaks the outline (user pick "B, at the
  edge"), with a body-colour joint hiding the ink's rounded end at the base, and ending in a small shade-colour paw with
  two toe ticks. Ruled out on review: long arms behind the body (monkey arms growing from the back); a thick stub wholly
  inside the outline (reads as a sausage stuck on the chest). Profile views face left as drawn.
- **J1.2 MUST** **Still images, not Rive** (decision 1). Why: a chat can hold 20 stickers on screen, and F2 allows 2
  animated capybaras (the spike: six Rive capybaras drop the Redmi to ~40 fps); a still `Image` is decoded once and
  cached, scrolls like a photo, needs no `.riv` load (F1), and also serves the 32 dp reply thumbnail and the starred
  list. Sticker shapes stay out of `capy.riv`, which keeps its ≤ 60 KB budget.
- **J1.3 MUST** Format: one **384 × 384 lossless WebP with alpha** per sticker at `assets/stickers/<id>.webp`
  (`Image.asset` decodes WebP on Android; 384 px = 128 dp at 3×). Measured on the drafts: 10 PNGs 220 KB, as lossless
  WebP **96 KB** in all. Registered in `pubspec.yaml` as the `assets/stickers/` folder.
- **J1.4 MUST** Source of truth: `docs/design/mascot/stickers/` (`apply_stickers.py`, `render.sh`, `matte.py`). The build
  regenerates the ten files with `zsh docs/design/mascot/stickers/render.sh <scratch>` and converts the PNGs to WebP; if the
  rig changes later, the stickers are re-rendered the same way. The drafts in `previews/` are deleted at build time
  (the WebP files replace them).
- **J1.5** The catalogue lives in one Dart file, `lib/features/stickers/stickers.dart`: `const kStickers = [Sticker('hi',
  'Hi'), …]` in picker order, plus `stickerById(String id)`. Adding a sticker later = one art file + one line.

### J2. The message

- **J2.1 MUST** New message `type` **`sticker`**. The row is a normal `messages` row: same conversation, sender,
  receipts, reactions, reply, star, pin, delete, disappearing timer. Drift `messages.type` is already a free text column:
  **no drift schema bump** (only the column comment gains `'sticker'`).
- **J2.2 MUST** Wire body (the plaintext that is encrypted into `encrypted_body`): **`Sticker: <id>`**, e.g.
  `Sticker: on-my-way`. Ids match `^[a-z]+(-[a-z]+)*$`. The app reads the id with that exact pattern; a body that
  does not match, or an id not in `kStickers` (sent by a newer app), renders the **unknown sticker** line: "Sticker"
  plus "Update Kuch Bhi to see it" in `inkSoft`, in a normal text bubble.
- **J2.3 MUST (old app fallback)** Today's app sends any type it does not know to `_TextBubble` with the decrypted body
  (`message_bubble.dart:396`), so an old app shows the line **"Sticker: hi"**; its chat list shows "New message"
  (`conversationPreviewLabel`'s default, `message_body_text.dart:573`); its notification is built from the push's own
  `preview` field, or "Sent you a message" when that is empty (`fcm_service.dart:627`), the same for old and new apps
  (W0 item 2). Copy is not offered (its `_copyable` is text only). Device item 9 proves it.

#### J2.4 Send path (reuse the text send; no new outbox kind)

| Where | Change |
|---|---|
| `MessageRepository` (+ `fake_message_repository.dart`) | new `sendSticker(conversationId, stickerId, {replyToId})`: the same enqueue as `sendMessage` (`message_repository_impl.dart:1135`) with body `Sticker: <id>` and row `type: 'sticker'`, outbox kind **`text_send`** (so the queue, F-b cancel, burst-order lift and the bath banner's waiting count all work unchanged). |
| `_sendTextOp` (~:1440–1600) | the server create sends `'type': row.type` instead of `'text'` (:1535); the two local upserts (:1506, :1570) keep the row's type instead of writing `'text'`. |
| `const kTextLikeTypes = {'text', 'sticker'}` (one place, beside the type labels) | used at every text-only gate that must also cover stickers: the pending-retry loop (:2340), `retryMessage`'s media branch (:2376, else a sticker would go to the media upload), the unsent-delete cancel (:2665), `liftQueuedTextSends` (`messages_dao.dart:443`), and the sender prefix in the chat list (`home_screen.dart:1127`). |

- **J2.4.1 MUST** Every other `type == 'text'` check stays text-only on purpose: emoji-only and link detection, Copy
  (`chat_screen.dart:766`), the body prefetch list (`messages_dao.dart:129`).
- **J2.4.2 MUST** Sticker sends from the sheet get a reply quote when a reply is open (then the reply clears, as a text
  send does). No draft text is touched.

#### J2.5 Where a sticker shows

| Surface | What it shows | Hook |
|---|---|---|
| Chat bubble | `StickerBubble`: the image at **128 dp** (decision 3), no bubble fill; under it, aligned to the sender's side, the time + ticks row (the media timestamp style). While the body is still decrypting: an empty 128 box (no jump, no shimmer); unknown id → J2.2's line. | new `else if (message.type == 'sticker')` branch before `emojiOnly` in `message_bubble.dart` (~:390) |
| Reactions, swipe to reply, long-press menu, multi-select | unchanged (they wrap the bubble). Menu: no Copy. | — |
| Chat list preview | **"🍊 Sticker"** (decision 5), the sender prefix as for a text | `conversationPreviewLabel` (`message_body_text.dart:573`) + `kPreviewStickerLabel` in `app_strings.dart` |
| Reply quote (in the bubble and above the composer) | a **32 dp** thumbnail of the sticker + "Sticker" | `reply_quote.dart` `_mediaTypes` (:107) and the label switch (:84); the encrypted `reply_preview` is `kPreviewStickerLabel` (`_deriveReplyPreview`, :5483) |
| Pinned banner | "Sticker" + 24 dp thumbnail | `pinned_message_banner.dart:42` |
| Starred list | a 48 dp thumbnail + "Sticker" in the media-row style | `starred_messages_screen.dart:282` |
| Notification | the push hook's `preview` for the type, else "Sent you a message" (`fcm_service.dart:627`). If W0 finds the hook labels types (e.g. "📷 Photo"), W1 adds `sticker` → "🍊 Sticker" there; otherwise unchanged | server hook (W0/W1) |
| Chat search | **never matches a sticker** (its body "Sticker: hi" would match "hi") | `searchMessages` prefilter (`message_repository_impl.dart:3405`) adds `type != 'sticker'` |
| Media & docs gallery, albums | not listed (a sticker has no `message_media` row) | — |
| Background push isolate | stores the row with `rawType` as is (`fcm_service.dart:493`): already fine | — |

- **J2.5.1 MUST** Semantics: unlike every other capybara (F4), a sticker is content, so `StickerBubble` is read:
  **"Sticker, Hi"** followed by the bubble's usual sender/time/status announcement. The 32/24/48 dp thumbnails are
  `ExcludeSemantics` (their "Sticker" text is read).
- **J2.5.2 MUST** Images are decoded at their shown size (`cacheWidth = dp × devicePixelRatio`) so 20 stickers in a
  chat cost 20 small textures, not 20 × 384².

### J3. The picker

| | |
|---|---|
| Button | a new `_ComposerAction` **"Stickers"** (`Icons.emoji_emotions_outlined`, 21 dp, same 40 dp round button as Attach) to the right of Attach (`message_input.dart:1761`), always visible while the chat can send. Hidden in the read-only state (group you left), as Attach is. |
| Sheet | the house sheet `showAppSheet` (`lib/core/widgets/app_sheet.dart:9`, registry R19), title **"Stickers"** as a header. A 4-column grid of **72 dp** tiles (8 dp gaps, 16 dp side padding): 10 stickers = 3 rows. Height = its content (about 310 dp with the handle and title); at 200% text only the title grows, and the grid scrolls inside the sheet if it must. |
| Tap | sends at once, a light haptic (`appHaptic(HapticsType.light)`), and the sheet **closes** (decision 4). The sticker lands in the chat as a queued bubble like a text. |
| Offline | the sheet works the same; the sticker queues (T2) and the bath banner counts it as waiting. |
| Keyboard | opening the sheet hides the keyboard; closing it does not bring it back. |

- **J3.1 MUST** Accessibility: the button's label is **"Stickers"** (tooltip on a long press, as the other composer
  actions); each tile is a button labelled **"Send sticker: Hi"** (… "On my way", etc.), focus order = picker order; the
  48 dp minimum touch target holds (72 dp tiles). The picker images are `ExcludeSemantics` under the tile's label.
- **J3.2 MUST** A double tap sends one sticker (the tile ignores taps while its send call is in flight; the sheet is
  already closing).

### J4. The live PocketBase change

Nothing has been read or written on the server for this spec (T4). What the client sends is known: the messages create
body carries `type` as plain text beside `encrypted_body` (`message_repository_impl.dart:1535`). Whether the server
accepts `sticker` depends on how `messages.type` is defined, which no doc in this repo records.

- **W0 (read only, asks the user first).** Over Tailscale, `sqlite3 -readonly` on `data.db`: the `messages` row of
  `_collections` (fields, `createRule`, `updateRule`), and `grep -n type` over `pb_hooks/*.js` (`fcm_notify.pb.js`,
  `disappearing_stamp.pb.js`, any create check). Three answers decide W1:
  1. `type` is a **select** → W1 adds the value `sticker`. A **plain text** field → no field change.
  2. Does any rule or hook allow-list types, or map a type to the push's `preview` (the app shows `data['preview']`
     as the notification body)? → add `sticker` there ("🍊 Sticker" for a preview).
  3. Is `type` in both `updateRule` branches' deny-list (`type:isset = false`)? (learning 2026-11-01: the update rule
     only blocks fields it names.)
- **W1 (only what W0 shows is needed; asks the user first).** One migration
  `pb_migrations/<ts>_updated_messages_type_sticker.js` with a down step: add `sticker` to the select values (if a
  select); append `type:isset = false` to both `updateRule` branches **if absent** (decision 7). Recipe as for albums W1
  and disappearing W1 (memory `server-topology`): back up `data.db` to `/home/ubuntu/pb_backups/data.db.<date>-stickers-pre`,
  dry-run on a `.backup` copy with `migrate up` on a throwaway dir (T5), create one `sticker` row there as a test, then
  `scp` → `sudo mv` into `pb_migrations` → restart → check `_migrations`. Hook edits, if any, follow `pb-hook-pitfalls`
  (flat hooks, scp not heredoc).
- **W2** If W0 shows a plain text field, no allow-list and `type` already locked: **no live change at all**, and the spec
  says so in the work log.

### J5. Phase 4 test gates

- Art: `render.sh` builds all ten with `--verify` clean per copy; `assets/stickers/*.webp` are 384 × 384 with alpha,
  ≤ 120 KB in all; a test lists `assets/stickers/` and checks it equals `kStickers` ids one to one.
- Unit: `stickerIdOf(body)` (`Sticker: hi` → `hi`; `Sticker: on-my-way` → `on-my-way`; `Sticker: Hi`, `Sticker: hi!`,
  `hi`, `Sticker:` → null); unknown-but-valid id → the unknown line; `kTextLikeTypes` gates (a pending sticker retries
  through the text op, never `_uploadMediaMessage`); `conversationPreviewLabel('sticker')`; `searchMessages` never
  returns a sticker row whose body contains the query.
- Repository (fake PB): `sendSticker` writes a `sticker` row + one `text_send` op; the create body has `type: sticker`
  and an `encrypted_body` that decrypts to `Sticker: hi`; offline → queued, reconnect → sent with the same id;
  delete before ack cancels it (F-b) like a text; a reply carries `reply_to_id` and an encrypted "🍊 Sticker" preview.
- Widget: `StickerBubble` shows the image at 128 with the label "Sticker, Hi"; while undecrypted, an empty 128 box;
  unknown id → the line; the picker sheet has 10 tiles with "Send sticker: …" labels, a tap calls `sendSticker` once
  and closes the sheet; the long-press menu of a sticker has no Copy; reply quote, pinned banner and starred row show
  the thumbnail; 360×640 at 200% text: the sheet and a sticker bubble do not overflow.
- Server: W0 notes in the work log; if W1 ran, the dry run's sticker create succeeded on the copy and `_migrations`
  lists the file live.
- Full suite green (baseline below), `flutter analyze` 0 errors, release build of both ABIs (APK grows by ≈ 0.1 MB).
- `trail check` before the commit.

### J6. Phase 4 device check list (M52 + Redmi S2, light and dark)

1. Composer: the Stickers button sits beside Attach; TalkBack reads "Stickers".
2. Open it: 10 stickers in a 4-column sheet; each looks like its preview in S10, crisp, with a white edge on dark.
3. Tap Hi: it sends, the sheet closes, a light haptic; the other phone shows the sticker at the same size, no bubble.
4. Long press a sticker: react, reply, star, pin, delete work; no Copy. Swipe to reply works.
5. Reply to a sticker: the quote shows its thumbnail and "Sticker"; the reply arrives with the quote on the other phone.
6. Chat list: "🍊 Sticker" (with "You: " for your own); pinned banner and Starred show the thumbnail.
7. Airplane mode: send 2 stickers: they queue, the bath banner counts 2; airplane off: both send, in order.
8. Search the chat for "hi": a sent Hi sticker is never a match.
9. **Old app**: with the Redmi on the pre-sticker build (`e4ad70e`), send a sticker from the M52: the Redmi shows a
   text bubble "Sticker: hi", the chat list "New message", the notification as usual, and nothing breaks. Then update
   the Redmi: the same message now shows the sticker.
10. Redmi: a chat with 20+ stickers scrolls smoothly; perf overlay p99 build + raster under 16 ms (record numbers).
11. 200% text on 360×640: the sheet and the sticker bubbles fit; nothing cut off.
12. Disappearing chat: a sticker disappears on the same timer as a text.
13. TalkBack: a received sticker reads "Sticker, Hi" and the sender/time; picker tiles read "Send sticker: Hi".

### J7. Phase 4 out of scope

Animated stickers, user-made or downloadable packs, sticker search, "recent" or favourite stickers, stickers in
notifications or the app icon, a keyboard-height picker panel, sending a sticker to several chats (forwarding does not
exist), festival stickers (phase 5 I4), any change to the `Capy` widget or `capy.riv`.

### J8. Phase 4 deferred decisions (default in bold; reply with a number to change one)

1. **Format:** **still images (WebP, ≈ 96 KB for all ten)** / Rive stickers that animate once when they arrive (breaks
   F2 in any chat with more than two; needs a per-bubble artboard).
2. **Edge:** **white die-cut edge (the classic sticker look; the outline reads on dark)** / no edge (on dark the
   outline almost disappears: S10 shows both).
3. **Size in the chat:** **128 dp** / 112 / 152.
4. **After a tap:** **send and close the sheet** / stay open for another sticker.
5. **Chat list and reply label:** **"🍊 Sticker"** / "Sticker" with no emoji.
6. **The set:** **the ten in J1** / swap any (say which; e.g. a "searching" sticker from the X8b glass, or "ok").
7. **Lock `type` in the update rule if it is open:** **yes, in the same migration (a later edit of `type` would change
   how old apps show a message)** / leave the rule alone.
8. **Old app line:** **"Sticker: hi"** / "Sticker: hi (update Kuch Bhi to see it)" (longer, but it tells old users
   why; it is the permanent wire text, T7).

## K. Phase 5 · the rest of the mascot pass (spec PASS 2026-11-12, all decisions at their defaults)

The last mascot phase: night and festival looks (**I4**), the chat app-bar buddy (**C1**), the failed-send sheet
(**C5**), Settings › About (**S1**) and the launcher icon / splash (**D7**). Two sub-phases, each its own commit after
its own device PASS: **5a** looks + C1 + C5 + S1 (one rig change), **5b** the icon (after you pick one). Code line
numbers below are at `49a6ec4`.

**Parked (user, 2026-11-12):** **O1 onboarding** waits for a reference review of other apps' onboardings (and a
redesign pass, K5), and the **Loaf** view is dropped ("does not look good at all"; the draft lying capybara was cut
from the Head view onto a long body). D6 stays open for whatever onboarding later needs.

Pictures: `mascot.html` **S11**. Every capybara there is a headless render of the rig with the R11 additions, made by
`docs/design/mascot/phase5/apply_phase5.py` (patches a copy of `mascot/capy/`) → `render.sh` (+ `rig.commands`) on the
light and dark page colours. Icon options: `docs/design/mascot/phase5/icon.py` (renders on white and black, recovers
the alpha, builds the adaptive layers and the masked previews). The build applies the same edits to
`mascot/capy/scene.rml` by hand and retires the script.

### ⛔ Frozen for phase 5 (on top of F1–F8; a breach is an automatic FAIL)

- **V1** No key, router or sync change: `BackupPinScreen`, the router's `redirect` and `SyncRouteGate` are untouched.
- **V2** Info mode only *shows*: no receipt is sent, nothing is written to drift or the server, it is not saved, and
  it ends when you leave the chat.
- **V3** The failed-send sheet's Retry and Discard call the same `retryOp` / `discardOp` as the banner's buttons
  (`message_bubble.dart:436–441`); the banner stays as it is apart from becoming tappable.
- **V4** Looks come from the phone's own clock and a table in the app. No network, no server date.
- **V5** F2 on the chat screen: the app-bar buddy is always still, so E1 + X6 (or E1 + X8b) stay the only two that
  move.
- **V6** Stickers and their art are unchanged (T6, T7): no hats on stickers.
- **V7** The icon change keeps `applicationId` and the version-code scheme: the new build installs over the old one
  (split-per-ABI, learning 2026-11-11), never needs an uninstall.

### K0. Rig additions

| # | Where | What | How |
|---|---|---|---|
| R11 | Sit, Front, Head, Onsen | **Looks** (I4): view-model enum **`look`** = `none, night, diwali, holi, newYear` (enum `0:600`, values `0:601–0:605`, property `0:606`) and a new **Look** layer per state machine (one 1-frame animation per value, cut, no blend). | **Nightcap** (water-teal cone that flops back, white brim and stripe, a mini yuzu as the pom-pom) and **party hat** (leaf-green cone with yuzu dots, white brim, leaning toward the snout, mini yuzu on the tip): both hide the yuzu while worn (it becomes the pom-pom). **Diya** (Diwali): a clay lamp in shade brown with a yuzu flame and a white core, on the ground in front of Sit and Front, under the chin on Head, floating on the bath in Onsen; the yuzu stays. **Holi**: 3–4 colour-powder dabs (blush, ripple teal, leaf, yuzu; no purple) on the head and body; the yuzu stays. Nightcap, party hat and diya are each drawn **once** as a component artboard (`Acc_night`, `Acc_party`, `Acc_diya`, ids `0:900–0:902`) and placed into the four views as `NestedArtboard`s; the Holi dabs are one small shape per view (their places differ). Front wears the hats at 0.8 (it has 36 units above its yuzu). |

- **K0.1 MUST (size, measured on the draft)** Published `capy.riv` today: **56 634 B**. With R11 as nested artboards:
  **63 657 B** (+7.0 KB). Drawn into each view instead of nested: 69.6 KB. Of every published file, **13.9 KB is the
  Free-plan watermark** (published minus built: 56 634 − 42 703); the content goes 42.7 → 50.0 KB. So R11 **breaks the
  60 KB budget (C4)** and no second file can fix it: a hat must sit on the same artboard as the head it rides on. →
  **decision 1**: raise C4 to **64 KB published** (default).
- **K0.2 MUST** C3/C4 otherwise hold: `--verify` clean, `inspect` problems empty (both checked on the draft), no
  Feather, no new clips. The Look layer is not gated by `reducedMotion` (a look is a still picture, not motion). New
  ids `0:600–0:606`, `0:611+` and `0:900–0:902`.

### K1. I4 · Night and festival looks (5a)

| | |
|---|---|
| Logic | New `lib/features/mascot/capy_look.dart`: pure **`capyLookAt(DateTime local) → CapyLook`** and a static `CapyLook.current` (`ValueNotifier`). One `Timer` set to the next boundary (05:00, 18:00, 23:00, midnight) re-evaluates it; so does app resume (the phone may have slept past a boundary). Every `Capy` listens and sets `look`. |
| Rules (phone's local time) | **newYear**: 31 Dec 18:00 → 1 Jan 23:59. **diwali**: Lakshmi Puja day −2 … +2 (Dhanteras to Bhai Dooj). **holi**: the evening before Holi from 18:00, and Holi day. **night**: 23:00–05:00 on any other day. Priority newYear > diwali > holi > night (decision 3). |
| Date table | `const kDiwali = {2027: (10, 29), 2028: (10, 17), 2029: (11, 5), 2030: (10, 26)}`, `const kHoli = {2027: (3, 22), 2028: (3, 11), 2029: (3, 1), 2030: (3, 20)}` (New Delhi panchang; Diwali 2026 was 8 Nov). **MUST**: re-check both against drikpanchang.com (New Delhi) at build time; Holi especially (one calendar lists 4 Mar 2027 for some northern traditions). After 2030 the festivals stop silently: `shortcut: dates end 2030, add years when the table runs out`. |
| Where | Every `Capy` (all 4 views). Not stickers (V6), not the launcher icon. |
| Mood | Unchanged: the nightcap is a hat, not a mood. A placement that is `chill` stays `chill` at 23:30, with the cap. |
| Test hook | `const String.fromEnvironment('CAPY_LOOK')` overrides the clock when set (e.g. `--dart-define=CAPY_LOOK=diwali`): device checks don't change the phone's date (which breaks sign-in tokens). Empty in normal builds. |

### K2. C1 · Chat app-bar buddy (5a)

| | |
|---|---|
| Hook | `lib/features/chat/screens/chat_screen.dart` app bar: a new `IconButton` right before "Search messages" (:1274), 48 × 48, child **Head 32** (decision 4), not flipped (it faces the name, as drawn), `animated: false`, `pettable: false`. Not shown in the search or selection bars (they replace the app bar). |
| Tap | Toggles **info mode** + `appHaptic(HapticsType.light)`. Mood `chill` (curved eyes) when off, **`active`** (round eyes, "looking") when on: the rig's 150 ms face cross-fade is the only motion, so it stays a still capybara (V5). |
| Info mode | Every bubble shows its **time and ticks**, not only the last bubble of a run (today `ChatBubbleShell` shows them only when `runEnd`, `expiry_badge.dart:140`). One `InheritedWidget` `ChatInfoMode(on:)` around the message list; `ChatBubbleShell` reads it: `showTimestamp && (runEnd \|\| ChatInfoMode.of(context))`. No per-bubble plumbing. Starts off on every chat open (V2, decision 5). |
| Words | `tooltip` / semantics label **"Show message times"** / **"Hide message times"**, `isSelected: infoMode` (TalkBack reads a toggle). The capybara stays in `ExcludeSemantics` (F4: the button's label carries the meaning). |
| 360 dp | The name loses 48 dp; it already ellipsises. |

### K3. C5 · Failed-send sheet (5a)

There is no failed-send sheet today: a message that fails for good shows `TerminalFailureBanner`
(`message_bubble.dart:742`) under its bubble with "Failed to send", the **raw error class** (`bad_request`,
`http_500`, `encrypt_failed`…) and Retry / Discard. C5 adds the sheet and says why in plain words.

| | |
|---|---|
| Open | The banner's title row ("Failed to send" + a 15 dp `chevron_right`) becomes a button (label "Why it failed"); the raw class line moves into the sheet. Retry and Discard stay on the banner. |
| Sheet | `showAppSheet` (R19), header **"Message not sent"**. A row: **Head 48 `worried`** (sweat drop), flipped so it faces the text, still · the reason (15/22 ink) and under it "Code: bad_request" (12 inkSoft). Then **Retry** (filled) and **Discard** (text, error colour), full width. Either closes the sheet, then calls exactly what the banner's button calls (V3). |
| Reasons (decision 6) | `bad_request` → "The server turned this message down." · `forbidden` → "You can't send to this chat any more." · `dead_link` → "This chat isn't on the server any more." · `payload_too_large` → "This message is too big to send." · `encrypt_failed` → "It couldn't be locked (encrypted) on this phone." · anything else → "Something went wrong while sending it." One pure `failedSendReason(String? errorClass)`. |
| Never | next to the bubble: the banner keeps its icon, no capybara there (inventory C5). |

### K4. S1 · Settings › About (5a)

`lib/features/settings/screens/about_screen.dart:45`: `AppLogoTile()` (88) becomes **Sit 96**, `chill`, still,
pettable: a tap plays the pet (eyes close, blush, squish, I3) with the light haptic; that squish + happy face is the
"giggle" (decision 7: no sound). +8 dp; the page already scrolls (200% text fine).

### K5. O1 · Onboarding (parked)

Parked by the user on 2026-11-12, together with the Loaf view. It comes back as its own spec after a review of how
other apps onboard (a reference library such as Mobbin needs its paid plan: the free connector refuses every search)
and the in-chat redesign. What this draft learned stays useful: the hook is a local flag set on a new account
(`auth_provider.dart:177` register, `google_onboarding_screen.dart:87` Google username), shown by `BackupPinScreen` in
setup mode before its key step (setup starts at `_Step.key`, :120), with Skip on every scene.

### K6. D7 · App icon and splash (5b; pick one in S11)

Today the launcher icon is still **Flutter's default** (`mipmap-*/ic_launcher.png`, no adaptive icon); the native
launch window is a flat `launch_bg`; the Flutter splash shows `AppLogoTile` (a lock on the accent). On Android 12+
(the M52) the system splash draws the launcher icon, so at every cold start you see the Flutter logo, then the lock
tile.

| | |
|---|---|
| Art | A **full-body** capybara, `chill` (curved eyes: the calm brand face), no hat (user, 2026-11-12: Front or Sit, not the Head bust). Options in S11 (decision 8): **A Front on bath teal** `#A9DCD6` · **B Front on cream** `#FAF7F1` · **C Sit on bath teal** · **D Sit on cream**. Front is symmetric and fills the circle; Sit is drawn at 54% of the canvas so its back clears the circle mask. |
| Adaptive icon | `mipmap-anydpi-v26/ic_launcher.xml`: background `@color/ic_launcher_background`, foreground `@mipmap/ic_launcher_foreground` (108 dp canvas, art inside the 66 dp safe circle: 108/162/216/324/432 px), **monochrome** `@mipmap/ic_launcher_monochrome` (the line art: outline, eyes, nostrils, snout patch) for Android 13 themed icons. `ic_launcher.png` per density (48 dp) as the legacy fallback. Generated by `icon.py` (a `--ship <res-dir>` mode added at build); no new dependency (no `flutter_launcher_icons`). |
| Splash | Android 12+ shows the new icon on `launch_bg` by itself. **`AppLogoTile`** draws the same art (the foreground PNG on the background colour, same `radiusXl` tile), so cold start goes icon → same picture → (after 1 s, phase 3 E4) the guarding capybara, with no lock tile in between (decision 9). Its other users (lock create/forgot steps, the privacy cover, app-lock settings) get the same picture. |
| Keeps | `applicationId`, version code, the app name (V7). |

### K7. Test gates

- **Rig (5a)**: R11 in `mascot/capy/scene.rml`; `--verify` clean, `inspect` problems empty, `capy.riv` ≤ the budget of
  decision 1; captures: each look on each view (compare with S11), and a look while `pet` and `hop` play (the hat moves
  with the head).
- **Unit (5a)**: `capyLookAt` table: 22:59 → none, 23:00 → night, 04:59 → night, 05:00 → none, 31 Dec 17:59 → none
  (or night if after 23:00), 31 Dec 18:00 → newYear, 1 Jan 03:00 → newYear (beats night), Diwali day −2/+2/+3,
  Holi eve 17:59/18:00, Holi day 23:30 → holi (beats night); the next-boundary function; `CAPY_LOOK` override.
  `failedSendReason` for every class and null.
- **Widget (5a, fake rig)**: every `Capy` gets `look` from `CapyLook.current` and changes when it changes. Chat app
  bar: the button is there with "Show message times", a tap → `isSelected`, mood `active`, every bubble of a run shows
  its time; a second tap → only run ends; reopening the chat → off; not in search or selection bars. Failed banner tap
  → the sheet with the reason and code; its Retry / Discard call `retryOp` / `discardOp` once with the banner's op id.
  About: Sit 96, tap → one `pet`. 360×640 at 200%: app bar, sheet, About do not overflow.
- **Frozen**: function-level diff vs HEAD empty for `SyncRouteGate.redirect`, `BackupPinScreen`, `retryOp`,
  `discardOp`.
- **5b**: `icon.py --ship` writes every density; `aapt dump badging` on the release APK names the adaptive icon; the
  APK installs over the previous build (V7).
- Each sub-phase: full suite green (baseline below), `flutter analyze` 0 errors, release build of both ABIs,
  `trail check` before the commit.

### K8. Device check list (M52 + Redmi S2, light and dark)

**5a**
1. Build with `--dart-define=CAPY_LOOK=night`: every capybara (Home empty, chat empty, bath banner, lock screen,
   About, the app-bar buddy) wears the nightcap, the yuzu as its pom-pom. Repeat for `diwali` (a lamp beside it,
   floating in the bath), `holi` (colour dabs, no purple), `newYear` (party hat).
2. A normal build after 23:00: the nightcap appears without a restart (leave the app open across 23:00, or open it
   after). Before 23:00 and after 05:00: no cap.
3. Pet and hop with a hat on: the hat stays on the head.
4. Chat: the small capybara left of the search icon; tap → round eyes, every message shows its time and ticks; tap
   → back. Leave and reopen the chat: off. TalkBack: "Show message times", toggle.
5. Chat with the bath banner and an empty chat (two moving): the app-bar capybara does not move; Redmi perf overlay
   p99 build + raster under 16 ms (record numbers).
6. A message that fails for good (e.g. send to a group you were removed from): the banner, tap "Failed to send" →
   the sheet with the worried capybara, a plain reason and the code; Retry resends, Discard removes it.
7. Settings › About: the sitting capybara; tap → it squishes and blushes, light haptic.
8. Reduced motion: looks still show; nothing moves; info mode still toggles.
9. 200% text at 360×640: chat app bar, the sheet and About fit.

**5b**
10. Home screen and app drawer: the new icon on both phones (circle on Redmi, squircle on M52), crisp; M52 themed
    icons on → the line-art capybara in the wallpaper tint.
11. Cold start on the M52: system splash shows the icon, then the same picture in the Flutter splash, no lock tile flash.
12. The update installs over the previous build; chats intact.

### K9. Out of scope

Onboarding and the Loaf view (parked, K5); sounds; an animated launcher icon or animated splash; looks on stickers or
the icon; festivals beyond Diwali, Holi and New Year (Eid, Christmas… later: one enum value + art each); a look picker
in Settings; info mode that stays on; read-by lists in groups; a name for the capybara in copy (I5 stays "no name",
phase 2 decision 1); the Cadet plan purchase.

### K10. Deferred decisions (default in bold; reply with a number to change one)

1. **`capy.riv` budget (looks make it 63.7 KB):** **raise C4 to 64 KB published** / buy the Rive Cadet month (no
   watermark: 49.7 KB) / looks on Sit and Head only (est. ~61.5 KB, still over 60 without a raise).
2. **Festivals:** **Diwali, Holi, New Year (+ the nightcap)** / add one more now (say which).
3. **Looks priority and windows:** **New Year > Diwali (5 days) > Holi (eve + day) > night 23:00–05:00** / Diwali on
   the main day only.
4. **C1 size and place:** **Head 32 left of the search icon** / Head 28 / inside the title (before the avatar).
5. **Info mode:** **off on every chat open** / remembered per chat until the app closes.
6. **Failed-send reasons:** **the six lines in K3** / your own wording.
7. **About "giggle":** **the pet squish + happy face, no sound** / add a short sound (a new audio asset).
8. **App icon:** **A Front on bath teal** (symmetric, fills the circle, the brown and the yuzu stand out on light and
   dark wallpapers) / B Front on cream (blends into light launchers) / C Sit on teal (more capybara-shaped in profile,
   smaller in the circle) / D Sit on cream.
9. **`AppLogoTile`:** **becomes the icon picture (splash matches the launcher)** / keep the lock tile.

### K11. Build notes (5a, 2026-11-12)

- Rig: `apply_phase5.py` output applied to `mascot/capy/scene.rml` as is (the script stays as the record and must
  not be re-run on the patched rig; `render.sh` now renders `mascot/capy` itself). Published **63 657 B**,
  `--verify` clean, `inspect` problems empty. Holi and Diwali dates re-checked on drikpanchang (New Delhi): unchanged.
- At the hop's peak the hat's tip is cut by the artboard top for a few frames (Sit X6 first-send hop; Front never
  hops in the app). The hat stays on the head.
- The spec's `ChatBubbleShell` is `ChatBubbleFrame` in the code. Stickers, emoji-only, unknown-sticker and the
  plain-text bubble draw their own time on `runEnd`; they read `ChatInfoMode` too, so info mode reaches every bubble.
- The banner's title button reads "Failed to send. Why it failed" to TalkBack (the status stays audible).
- `startCapyLookClock()` runs in `main()`; widget tests never start it (no pending timer), and set
  `CapyLook.current` themselves.

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

Phase 4: `main` at `e4ad70e` (pushed). Last full suite recorded in the work log **1196/1196** (X8b/K1b gates, shared
checkout). Re-run before phase 4 starts.

Phase 5: `main` at `49a6ec4` (phase 4, not pushed). Last full suite **1216/1216** (phase 4 gates). Re-run before 5a
starts. Rive CLI is now **1.9.2** (`rive update` was required to render, 2026-11-12).
