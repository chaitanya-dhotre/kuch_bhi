# Mascot pass (Page 10) phase 2: work log

Spec: `mascot.md` (PASS 2026-11-10, all 9 deferred decisions at their defaults). Backlog §2, §5.

## Rive asset (§C), 2026-11-10

Source of truth: `mascot/capy/` (`rive.yaml` + `scene.rml`), seeded once by
`docs/design/mascot/phase2/seed_capy.py` from the `gen_s1v2.py` art. Hand-edit the RML from now on; the seed
script is kept for provenance and overwrites the scene if re-run.

Build: `~/.rive/bin/rive mascot/capy --publish --output-dir=../../assets/mascot` (signed in, Free plan).

| Check | Result |
|---|---|
| `rive mascot/capy --verify` | 0 errors, 0 warnings |
| `rive inspect --json` problems | `[]` |
| `assets/mascot/capy.riv` | **50 801 bytes** (budget 60 KB) |
| Feather / gradients | none |
| Clips per artboard | Sit 1, Front 0, Head 1, Onsen 1 (the muzzle; both bellies drawn inside the outline instead) |
| Visible shapes at rest | Sit 20, Front 17, Head 11, Onsen 15 (+6 with 3 yuzus) |
| `--bench=600` advance / render p50 | Sit 0.013 / 0.108 ms · Front 0.012 / 0.099 · Head 0.009 / 0.098 · Onsen 0.010 / 0.105 (desktop GPU) |
| Publish log | **"watermarked"** (Free plan). Device item 13 decides whether the Cadet month is needed (decision 6) |

Rig as built:

- View model `Capy`: `mood` (enum chill…focused), `pose` (enum none, pet, celebrate, guard), `still`,
  `reducedMotion`, `holding`, triggers `pet`, `hop`, `wave`, `celebrate`, `flush`, numbers `lookX`, `queued`.
- Every artboard: state machine `Capy` = Idle (3.4 s breathe | still), Mood (6 face sets by opacity, 150 ms
  any-state cross-fade), Props (4.6 s loop: blink on round eyes, chill content squeeze, z drift, sweat bob,
  sparkle twinkle, Onsen steam + ripple | still), Action (rest, hold, one-shots; ignored under
  `reducedMotion`). Front adds a Pose layer.
- Sit: `Back` root bone + `Head` bone, body path skinned to both; face, yuzu and ears ride the Head bone, ears
  drawn behind the body with a DrawRule.
- Onsen: `Q1`–`Q3` opacity and rise bound to `queued` through range mappers + a 0.35 s interpolator, so a new
  waiting text floats in; `flush` throws one yuzu out of the pool.
- Front `lookX` shifts the face ±6; Head `lookX` tilts ±0.12 rad.

Headless proof (C5), renders in `docs/design/mascot/phase2/`:

- `moods.png`: 4 views × 6 moods with `--data mood=…`, matches the S1 sheet.
- `actions.png` (commands in `actions.commands`): rest, pet, back to rest, hop, hold, wave, celebrate, flush,
  queued 1, pose guard + lookX 1, pose celebrate + lookX −1, pet under reducedMotion (nothing happens).
- `still=true` and `reducedMotion=true`: three captures over 2 s identical for every view and mood; with both
  off, frames differ (it moves).

Bugs found and fixed in the rig before Flutter: the Action layer's rest state keyed nothing, so a hold squash
stuck after release (rest now resets everything only Action keys); the Front wave arm stayed inside the body
(raised to −3.1 rad).

## Flutter (§D, §E)

- `rive: ^0.14.11`, `assets/mascot/` in pubspec. `Factory.rive` (what the spike measured).
- `lib/features/mascot/capy.dart`: `Capy` widget, `CapyView/Mood/Pose`, `CapyRig`/`CapySource` seam for
  tests, `CapyLoader` cache. Pet = tap → `pet` + `appHaptic(HapticsType.light)`; long press → `holding`;
  own opaque `GestureDetector` (F8). `hops` / `flushes` counters fire triggers; `waveOnShow` for X1.
- `lib/features/mascot/capy_spots.dart`: X1–X10 as data.
- `lib/features/mascot/offline_bath_banner.dart`: E1 for Home and chat, `nextBathPhase` (offline → sending →
  done, hidden never reopens while online), 10 s cap after reconnect, "All sent." held 1.6 s.
- `queuedCountProvider` (`outbox_status_provider.dart`): `text_send` in `queued|sending`, all chats.
- C4 (a): `_ChatEmptyFade` in `chat_screen.dart` keeps the empty state on top for 400 ms (0 under reduced
  motion), fading while the capybara hops.
- Deleted: `capybara.dart`, `capybara_painter.dart`, `test/capybara_rig_test.dart`, tokens `mascotBreathe` /
  `mascotBlink` (timing lives in the `.riv` now). Mascot colour tokens stay (palette + token export).

Deviations from the spec text, each deliberate:

1. D2 says "a provider": the cache is a static `CapyLoader`, because `EmptyState` renders in many tests and
   screens without a `ProviderScope`. Under `flutter test` it returns null (no Rive native library on the
   host); tests inject a fake with `CapyLoader.debugSource`.
2. D1 grew `waveOnShow`, `hops`, `flushes`: declarative counters are how a parent fires a one-shot.
3. C4 (a) fires when the empty state leaves for any first message, sent or received.
4. E1 "All sent." hop waits 400 ms after the last flush: two triggers in one frame and the Action layer takes
   only one.
5. The banner hides Retry on "All sent." (nothing left to retry).

## Gates

2026-11-10, on top of `ceb1b36`:

- Full suite **1173/1173** (baseline 1161; −4 old `capybara_rig_test`, +16 new in `test/mascot/`, the rest
  unchanged). First run caught 2 home tests with a pending drift timer: the banner subscribed to the outbox
  count while hidden. Fixed: the count is auto-disposed and only watched while the banner shows.
- `flutter analyze`: 0 errors, nothing new in touched files. `git diff --check` clean.
- `flutter build apk --release --target-platform android-arm,android-arm64`: OK, 96.1 MB.
- `trail check`: exit 1, but all 6 failing hits are in `app_router.dart`, `app_database*.dart` and
  `message_repository_impl.dart` from the unpushed `8c3acce`/`ceb1b36`, not this change. The rest are
  "worth a look" word matches in `docs/backlog.md` and `disappearing-work-log.md`.
- Not run: a device pass (the list below), an independent review.

## Device check list (M52 + Redmi S2, light and dark)

The spec's 13 items, with what to look at for each:

1. Every X1–X10 placement shows the new capybara at its size and mood; nothing clipped at font scale 1.3.
   Where: login (X1), Home with no chats (X2), Home load error (X3: airplane mode on a cold start), Requests
   empty and error (X4, X5), a new chat (X6), a group with undecryptable history (X7), in-chat search with no
   match (X8), chat load error (X9), Create group with no friends and Profile unavailable (X10, 120 dp).
2. Login: one wave, then still.
3. Airplane mode on Home: the bath banner appears; the capybara faces the text; eyes are curved lines.
4. Send 3 texts offline: 3 yuzus float in; a 4th shows "4 waiting" with 3 yuzus.
5. Airplane off: "Back online, sending…", round eyes, one yuzu leaves per message actually sent, then a hop
   and the banner leaves.
6. Same in a chat screen.
7. Tap the capybara in the banner: it pets with a haptic (both phones), and Retry does not fire.
8. Long press any capybara: it melts and comes back on release.
9. New chat, send the first message: the empty capybara hops and fades.
10. System "remove animations" on: nothing moves anywhere; the banner still counts.
11. Redmi: Home with the banner + an empty state, scroll: no visible jank; perf overlay p99 build + raster
    under 16 ms (record the numbers here).
12. Kill the network for > 10 s with a failed message: the banner still leaves 10 s after reconnecting.
13. No "Rive" watermark or splash in any placement. The publish log said "watermarked", so check closely; if
    one shows, decision 6 applies (buy the Cadet month, re-publish).

## Device result, 2026-11-10

User: **PASS**, M52 + Redmi S2. Every item worked and no watermark or splash showed (item 13, so decision 6 needs
no Cadet month). Not checked on the phones: the error placements (X3 Home load error, X5 Requests error, X7
undecryptable history, X9 chat load error) and the failed message in item 12, which are hard to trigger.
Widget tests cover X9, X10 and the 10 s cap; the X1–X10 table test covers the rest.

# Phase 3: security moments (§G), 2026-11-11

Spec §G PASS 2026-11-11, all 8 decisions at their defaults. Baseline `a871498`, suite 1173/1173.

## Rig (G0, R1–R3)

Applied `docs/design/mascot/phase3/apply_phase3.py`'s edits to `mascot/capy/scene.rml` (run once against the
real scene, diffed: 44 lines, then copied in; the script is retired, its `once()` asserts now fail on the patched
scene by design). New ids `0:511`–`0:519`: `LookEase` 0.2 s interpolator chained after `LookToX` (Front, ±10) and
`LookToTilt` (Head); triggers `swapKey` 0:514 / `lookAround` 0:515; Front `swapkey` animation 0:516 + state 0:517,
`rest` hold-keys the Key's y; Sit `lookaround` 0:518 + state 0:519. Both one-shots sit on the Action layer behind
`reducedMotion == false`.

| Check | Result |
|---|---|
| `rive mascot/capy --verify` | 0 errors, 0 warnings |
| `rive inspect --json` problems | `[]` |
| `assets/mascot/capy.riv` | **51 596 bytes** (was 50 801; budget 60 KB). Publish log "watermarked" as in phase 2 (item 13 there found no mark) |
| `--bench=600` advance / render p50 | Sit 0.013 / 0.108 ms · Front 0.012 / 0.095 ms (unchanged) |

C5 captures (`docs/design/mascot/phase3/c5.png`, rendered from the real rig with `frames.commands` on the light
background): row 1 = K2 centre, **lookX mid-ease (+4 frames)**, left, right, worried, swapKey a/b/c; row 2 =
swapKey d/end, K1 celebrate, active, X8 before, **lookAround turned**, back + shrug, sleepy. Pixel diffs: centre vs
left 527, mid-ease vs left 407 (between the two ends); swapKey a vs c 349; lookAround a vs b 5414.

## Flutter

- `Capy` (G0.2): `lookX` (clamped −1…1, set in `build` next to `reducedMotion`, 0 under reduced motion);
  `playOnShow: CapyOneShot?` replaces `waveOnShow` (X1 = `wave`); `celebrates` counter like `hops`/`flushes`.
  `CapyRig.setLookX` added. `CapySpot.build(oneShot:)` lets X8 skip its one-shot.
- G0.3: `unawaited(CapyLoader.source)` in `main()` right before `runApp`.
- G1 `lock_overlay.dart`: the unlock step's logo tile → Front 72 guard, animated; `PinPad.onChanged` → digit
  count → `pinLookX` (in `capy_spots.dart`); `_unlock` returning false → `worried` for 1.2 s (Timer, cancelled in
  dispose); `isWaiting()` → worried. `_showUnlock` resets the count. Forgot/create keep the logo.
- G2 `backup_pin_screen.dart` (additions only): `restoreCapy(phase, celebrating:)`; `_RestoreOverlayState.
  didUpdateWidget` celebrates once when the phase leaves idle/deriving; Front 96 above the progress card.
- G3 `group_settings_screen.dart`: `_confirmRemove`'s `_guard(onSuccess:)` stores the name; `_keyRotatedCard`
  above the members section (Front 56 guard, still, `playOnShow: swapKey`, keyed by name so a second remove
  replays). Copy `groupKeyRotatedCopy` in `app_strings.dart`.
- G4 `splash_screen.dart`: `_slow && CapyLoader.ready != null` → `AnimatedSwitcher` (150 ms, 0 under reduced
  motion) from the logo to Front 88 guard focused, inside an 88 box.
- G5 `chat_screen.dart` (hand-edited, not formatted): `_SearchEmptyState` is stateful (1.6 s → sleepy).
  **Deviation from the spec's premise:** "Nothing found" does *not* stay mounted while you type: every keystroke
  sets `_searchPending`, which swaps in the list until the 200 ms debounced search answers. So the "already looked
  around" flag lives on the chat state (`_lookedAround`), reset when results show, the query clears or search
  closes. The behaviour is decision 8's default exactly; only where the flag lives differs.

## Gates

| Gate | Result |
|---|---|
| Unit | `pinLookX` (0, 1, 3, 6, delete back); `restoreCapy` table; one `celebrate` per increase; `playOnShow` once per mount; `lookX` clamp + 0 under reduced motion |
| Widget, lock (`lock_screen_test.dart`) | digits → `lookX`, delete back; wrong PIN worried 1.2 s → focused; lockout worried; **all 20 existing app-lock tests unchanged and green** |
| Widget, restore | guard+focused while the key check is held open; one `celebrate` when it passes; none on later phases; active after 1.2 s; happy on ready; Home still arrives |
| Widget, group | success → card with the name + the toast, `swapKey` once, still; failure and the 30 s timeout → no card |
| Widget, splash | capybara only after 1 s with the file loaded, 88×88, spinner still there; no file → logo |
| Widget, X8 (`search_capy_test.dart`) | `lookAround` once, sleepy at 1.6 s, no replay while typing (mutation-checked), replays after results and after a clear; reduced motion → sleepy, no trigger |
| Frozen (P1/P2) | `_restoreHistory` identical to HEAD (56 lines), `backup_pin_screen.dart` has 0 deleted lines; `encryption_service`, `message_repository_impl`, router, `encryption_sync_provider`, `app_lock_controller`, `pin_pad` untouched |
| Full suite | **1186/1186** (1173 + 13 new) |
| `flutter analyze` | 0 errors (113 infos/warnings, none new) |
| Release build | OK: `app-armeabi-v7a-release.apk` 43.4 MB, `app-arm64-v8a-release.apk` 48.1 MB |

## Device check list (phase 3, M52 + Redmi S2, light and dark)

1. Lock screen: the capybara holds the key; its face slides along with each digit; delete slides it back.
2. Right PIN: the app is there at once, exactly as fast as before phase 3.
3. Wrong PIN: worried face + sweat drop while the keypad shakes, focused again after about a second. Lockout
   countdown (5 wrong PINs): worried the whole time.
4. Fingerprint unlock: no delay.
5. Redmi: open a chat with the offline banner and an empty chat, lock, type a PIN: keys respond at once; perf
   overlay p99 build + raster under 16 ms (record the numbers here; G1.3's TickerMode only if this fails).
6. Fresh install + restore with the recovery key: the capybara guards the key while it checks, throws its arms up
   when the key is accepted, then watches the download; Home arrives as before.
7. Remove a member from a group: the card swaps the key once and names them; the "… removed" toast still shows.
   Leave the screen and come back: the card is gone.
8. Cold start on slow mobile data (splash over 1 s): the logo turns into the guarding capybara, spinner below, no
   jump. A fast start: logo only, no flash.
9. Chat search for a word that isn't there: it looks around, shrugs, gets sleepy. Keep typing: no replay. Clear and
   search again: it replays.
10. System "remove animations": the lock face doesn't slide, no celebrate motion (arms-up still), no swap, no
    look-around; all the words and timings above unchanged.
11. TalkBack: the lock screen still focuses the title; no capybara is announced; the K3 card's text is read.
12. Lock screen and restore screen at 200% text, 360×640: scroll, no overflow.

## Device result (phase 3), 2026-11-11

User: **PASS**, every item. Seen on item 7: the member leaves the list at once, then the key card and the
"… removed" toast show together 1–2 s later. That is by design: both wait for the key rotation to reach the
server, and the card must not claim a new key before one exists.

New ideas from the run, not part of phase 3:
- Chat search in a long chat shows 0/0 while older messages are still being decrypted, so it looks like "no
  match". Wanted: a searching state (capybara with a magnifying glass) until the search is really done, then
  today's X8 behaviour.
- Restore (K1) redesign: a big capybara in the centre checks the key and throws it up on a match, then slides to
  the top and, during the download, takes envelopes (messages), opens them with its eyes closed (privacy) and
  files them in a small vault ("Chats").

# X8b: still searching (§H), 2026-11-11

Spec §H PASS 2026-11-11, all 5 decisions at their defaults. Baseline `9236c01`.

## Rig (R4)

Applied `docs/design/mascot/search/apply_search.py` to `mascot/capy/scene.rml` (run against the real scene, diffed:
52 lines, copied in; the script then retires). New ids `0:520`–`0:533`: Pose enum `search`; Sit `Scan` 0:521 and
`Glass` 0:522 (Handle/Lens/Glint) inside `PawLHolder`, which moved to the front of Sit's draw order; Sit `Pose` layer
0:530 with `pose_none` 0:527, `pose_search` 0:528 (2 s loop), `pose_search_still` 0:529.

| Check | Result |
|---|---|
| `rive mascot/capy --verify` | 0 errors, 0 warnings |
| `rive inspect --json` problems | `[]` |
| `assets/mascot/capy.riv` | **52 647 bytes** (was 51 596; budget 60 KB). Note: `--output-dir=assets/mascot` resolves under `mascot/capy/`; the file was moved into `assets/mascot/` |
| Resting Sit (`chill`) frame | pixel-identical to the phase 3 rig (0 px differ) |

Captures: `docs/design/mascot/search/frames.png` (rest, search frames 10/30/60/90, still, none, X8 turned, sleepy; light
and dark).

## Flutter

- `CapyPose.search`; spot `X8b searching` (Sit 72 focused, animated, pose search) in `capy_spots.dart`.
- `chat_screen.dart` (hand-edited, not formatted): `_SearchBusyState` ("Searching…" / "Looking for “q”."); shows while
  the search runs with no matches on screen and either `_searchSlow` (a `Timer` of debounce + 300 ms, restarted per
  keystroke until it fires, cancelled on results, clear, close and dispose) or `_lookedAround` (typing on from
  "Nothing found"). Counter shows "…" while `_searchPending`. `_resolveSearchBody` returns null when a lookup throws.

## Gates

| Gate | Result |
|---|---|
| Widget, X8b (`search_capy_test.dart`, bodies held from open by a `Completer` or made to throw) | slow search: "…", no busy within the grace, then "Searching…" with Sit `search` focused animated, never 0/0 or "Nothing found" meanwhile, a match → "1/1"; ends empty → "Nothing found", `lookAround` once, pose none; typing on → busy at once, then sleepy with no replay; fast search → never busy; a throwing lookup → the search finishes; clear and close → no busy; reduced motion → `reducedMotion` true. Mutation-checked: dropping the catch, the "…" counter or the `_lookedAround` branch each fails a test |
| Both existing X8 tests | unchanged, green |
| Placement table (`capy_test.dart`) | + `X8b sit focused 72 anim search`; animated spots now 2 (X6, X8b: never on one screen) |
| Full suite | **1195/1195** (shared checkout: includes the K1b session's uncommitted work) |
| `flutter analyze` | 0 errors (113 infos/warnings, none new) |

## Device check list (X8b, M52 + Redmi S2, light and dark)

Spec §H list, items 1–9.

# K1b: restore key toss + envelope vault (§I), 2026-11-11

Spec §I PASS 2026-11-11 (user, all 8 decisions at their defaults). Built in the same checkout as X8b (§H), which
was being built at the same time; the rig carries both.

- Rig: `docs/design/mascot/k1/apply_k1.py` applied on top of X8b's uncommitted R4 `scene.rml` (hash-checked, so
  nothing changed underneath). `--verify` clean, `inspect` problems empty. `assets/mascot/capy.riv` 51 596 →
  **56 634 B** (X8b +1 051, K1b +3 987), under 60 KB. Ids 0:540–0:566.
- Flutter: `Capy` gets `CapyPose.vault`; `celebrates` is replaced by `tosses` (tossKey) and `envelopes` (envelope).
  `_RestoreOverlayState` adds the check stage (200), toss, a 1.0 s dock timer, a 450 ms gap+size tween to 120, the
  card fading in at the dock, and a 1.6 s envelope timer that fires only when `(convIndex, msgCurrent)` moved. Under
  reduced motion the dock is a cut and there are no envelopes.
- Tests: restore_overlay_test has 5 new K1b tests (centre → toss → dock → envelope pace → ready; late mount; reduced
  motion; 360×640 at 200% text in both stages and mid-slide; header in both stages). `_startRestore` now waits for the
  dock. capy_test: tossKey/envelope per increase. Watch out: a test must pump a frame after a progress update before
  the next envelope tick, because `pump(duration)` runs timers before it builds, so the tick still sees the old counts.
  A real device always draws a frame in between.
- Frozen: `_restore`, `_restoreHistory`, `_buildSaving` byte-identical to HEAD; encryption_service,
  message_repository_impl, encryption_sync_provider untouched.
- Gates: full suite **1196/1196** (includes X8b's tests as they stood); `flutter analyze` 0 errors (113
  infos/warnings, same as baseline); release `--split-per-abi` arm + arm64 OK (48.1 MB arm64), installed on the M52
  as an update. Redmi not connected.

## Device result (K1b), 2026-11-11

User: **PASS** (M52; the Redmi was not connected for this build).

# Phase 4: capybara stickers (§J), 2026-11-11

Spec §J PASS 2026-11-11 (user, all 8 decisions at their defaults).

## W0, live read (user yes, read only)

`sqlite3 -readonly` on live `data.db` + grep of `pb_hooks/*.js` and `fcm_webhook.py`:
1. `messages.type` is a **select** (`text, image, video, voice, poll, system, document, file`, maxSelect 0), so a
   sticker create was refused → W1 needed.
2. No rule or hook allow-lists or labels types. `fcm_notify.pb.js` has no `preview`; the webhook sends
   `type: new_message` only, so the notification stays "Sent you a message" for old and new apps. No hook change.
   `disappearing_stamp.pb.js` stamps every non-`system` row, so stickers get the same timer as a text.
3. `type:isset = false` is already in **both** `updateRule` branches → no rule change (decision 7 satisfied as is).
Live counts at read time: text 546, image 80, system 37, voice 11, video 10, file 9.

## W1, live migration (user yes)

- Backup `/home/ubuntu/pb_backups/data.db.20261111-stickers-pre` (`.backup`).
- Migration `pb_migrations/1794400000_updated_messages_type_sticker.js`: re-adds the `type` select by its id
  (`select625724656`) with `sticker` appended; down step restores the 8 values. Rules untouched.
- Dry run (T5) on a `.backup` copy in `/tmp/pbtest` with no hooks: a throwaway migration saving one `sticker` row
  **failed before** ("type: Invalid value sticker.") and **succeeded after**; rules hash unchanged; `migrate down`
  restored the 8 values. Copy deleted.
- Live: `scp` → `sudo mv` into `pb_migrations` → `systemctl restart pocketbase` → `_migrations` lists the file,
  `type` values end in `sticker`, `/api/health` 200. Live before any sticker build is installed (T4).

## Art

`zsh docs/design/mascot/stickers/render.sh <scratch>`: all ten copies `rive rig --verify` clean (0 errors, 0
warnings). The renders are pixel-identical to the reviewed drafts (`magick compare -metric AE` = 0 for all ten).
Converted with `magick -define webp:lossless=true` to `assets/stickers/<id>.webp`: 384×384 sRGBA, **98 052 B** for
all ten (≤ 120 KB). `previews/` is to be deleted (the WebP files replace them).

## Client

- `lib/features/stickers/stickers.dart`: `kStickers` (picker order), `stickerById`, `stickerBody`, `stickerIdOf`
  (`^Sticker: ([a-z]+(?:-[a-z]+)*)$`).
- `lib/features/stickers/sticker_widgets.dart`: `StickerImage` (cacheWidth = dp × dpr), `stickerThumb`,
  `StickerBubble` (128, chrome-less, media time pill under it; empty 128 box while decrypting; unknown id → "Sticker"
  + "Update Kuch Bhi to see it"), `showStickerSheet` (house sheet, 4-column grid, one send per open sheet).
- Repo: `sendSticker` and `sendMessage` share one enqueue (`text_send`, row type passed through); `_sendTextOp`
  sends and keeps `msg.type`; `kTextLikeTypes` (app_strings) at the pending-retry loop, `retryMessage`, the unsent
  delete cancel, `liftQueuedTextSends`, the home sender prefix; `_deriveReplyPreview` → "🍊 Sticker"; search skips
  `type = sticker`.
- Bubble: sticker branch before emoji-only; row label "Sticker, Hi. From …". Menu: no Copy. Reply quote, pinned
  banner, starred list: 32/24/48 dp thumbnail + "Sticker". Composer: "Stickers" button right of Attach.
- No drift schema bump (column comment only).
- Tests: `test/stickers/sticker_send_test.dart` (6, real repo on the fake PB: create type + decrypted body, offline
  queue, F-b cancel, reply preview, retry through the text op, search) and `sticker_widgets_test.dart` (13: ids,
  assets = kStickers, labels, bubble 128 + "Sticker, Hi" + cacheWidth, undecrypted box, unknown line, 200% text,
  picker 10 tiles + labels + one send + closes, 200% sheet, menu without Copy, reply quote 32, pinned 24, starred 48).

## Gates (phase 4)

- Full suite **1215/1215** (1196 + 19). `flutter analyze` 0 errors (113 issues, same as baseline).
- Release `--split-per-abi`: arm64 **48.3 MB** (K1b 48.1), armeabi-v7a 43.5 MB.
- `trail check`: 2 flagged, both explained: `mascot.md:587` matched "keep the capybara soft" on words only (S1, no
  gradients); `message_repository_impl.dart:1140` matched "don't widen the frozen text send path to media": stickers
  are text sends by spec (J2.4), the lift is not renamed and media stays out.

## Device round 1 (phase 4), 2026-11-12

- User: **stickers appear in the chat search results.** Cause: the chat screen searches on its own
  (`ConversationSearchController` over the loaded `_items`); the repo's `searchMessages` prefilter is not on that
  path. Fix: the candidate list in `chat_screen.dart` skips `type == 'sticker'`. Test in `search_capy_test.dart` ("a
  sticker never matches…"): a row whose body is "Sticker: lunch" plus the text "lunch" → 1/1; fails without the fix
  (0 widgets with "1/1", it counted 2).
