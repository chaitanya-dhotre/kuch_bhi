---
title: "The Rive mascot is driven from Flutter through declarative counters, its Action layer must reset what it keys, and its file loads from a static cache rather th…"
author: Chaitanya
date: 2026-11-10
branch: main
cost: { minutes: 29, tokens: 495379 }
id: l-4bd505e3
scope: repo
status: active
src: agent
touches:
  - lib/features/mascot/capy.dart
  - lib/features/mascot/capy_spots.dart
  - lib/features/mascot/offline_bath_banner.dart
  - test/mascot/capy_test.dart
  - test/mascot/offline_bath_banner_test.dart
  - docs/design/pages/mascot-work-log.md
---

## Decided
- The capybara's `.riv` is loaded once by a static `CapyLoader`, not a Riverpod provider: `EmptyState` (which shows the default mascot) renders in many tests and some screens without a ProviderScope. Under `flutter test` the loader returns null (no Rive native library on the host); widget tests inject a fake rig with `CapyLoader.debugSource`.
- One-shots (hop, flush, wave) are fired declaratively: the parent bumps an int (`hops`, `flushes`) or sets `waveOnShow`, and `Capy.didUpdateWidget` fires one trigger per increase.
- The yuzu-bath banner's phase logic is a pure `nextBathPhase` (offline → sending → done; hidden never reopens while online), with the 10 s cap and the "All sent." beat as widget timers.
## Tried and ruled out
- An Action-layer "rest" state with an empty animation: whatever a one-shot or the hold keyed last (the 0.85 squash) stayed on screen after release. Rest must hold-key every property only the Action layer animates (Act scale/y/rot, Sit paw, Onsen flush yuzu).
- Firing the final flush and the "All sent." hop in the same frame: the Action layer takes one any-state transition per frame, so one trigger is lost. The hop now waits 400 ms.
- Watching the outbox count while the banner is hidden: a drift stream subscription left a pending timer at dispose in home widget tests. The provider is autoDispose and only watched while the banner shows.
## Watch out
- Rive enum conditions compare against the DataEnumValue's id (`TransitionValueEnumComparator value="0:61"`), and keyframes default to `hold`: write `interpolationType` on every key.
- The Free-plan publish logs "watermarked"; device check item 13 decides whether the Cadet month is needed.
- `dart format` on chat_screen/home_screen rewrites hundreds of unrelated lines (files predate the current formatter); format only new files.
In the code: lib/features/mascot/capy.dart, capy_spots.dart, offline_bath_banner.dart; mascot/capy/scene.rml (rig source); docs/design/pages/mascot-work-log.md.
