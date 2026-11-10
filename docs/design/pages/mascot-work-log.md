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
