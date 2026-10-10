# Task 12 report — Fake repositories + USE_FAKES dev seam

**Status:** DONE
**Commit:** `4d94f58` — `[Offline P6] FakeMessageRepository + USE_FAKES seam (mock-build strategy)`
(trailer: `Co-Authored-By: Claude Code <noreply@anthropic.com>`)
**Base:** task started from `40bd9e0`; orchestrator ledger commit `6f293ac` landed mid-task, my commit sits on top. Branch `feature/offline-first`, no push.

## Files

| File | State |
|---|---|
| `test/offline/use_fakes_boot_test.dart` | created — boot/seam test |
| `lib/core/config/fake_message_repository.dart` | created — the fake class (see Ruling R1) |
| `test/fakes/fake_message_repository.dart` | created — barrel re-export (brief's file-map path) |
| `lib/core/config/data_source.dart` | created — `const bool useFakes = bool.fromEnvironment('USE_FAKES')` |
| `lib/main.dart` | modified — conditional `messageRepositoryProvider` override |
| `docs/captures/off_use_fakes_boot.png` | created — device capture |

## TDD RED excerpts (verbatim)

**RED-1 — Step 1: class missing (brief Step 2 expected failure):**
```
test/offline/use_fakes_boot_test.dart:21:8: Error: Error when reading 'test/fakes/fake_message_repository.dart': No such file or directory
import '../fakes/fake_message_repository.dart';
       ^
test/offline/use_fakes_boot_test.dart:36:18: Error: Method not found: 'FakeMessageRepository'.
    final fake = FakeMessageRepository();
                 ^^^^^^^^^^^^^^^^^^^^^
00:00 +0 -1: Some tests failed.
```

**RED-2 — discrimination probe (override commented out → test must fail; proves the test proves the seam):**
```
Expected: exactly one matching candidate
  Actual: _TextWidgetFinder:<Found 0 widgets with text "Fake Boot Chat": []>
   Which: means none were found but one was expected
home renders conversation seeded into FakeMessageRepository
...
00:00 +0 -1: app screens read from FakeMessageRepository with NO PocketBase [E]
00:00 +0 -1: Some tests failed.
```

**RED-3 — lib/ cannot import test/ (drove Ruling R1):**
```
error • Target of URI doesn't exist: 'package:kuch_bhi/test/fakes/fake_message_repository.dart' • lib/main.dart:9:8 • uri_does_not_exist
error • The function 'FakeMessageRepository' isn't defined • lib/main.dart:74:55 • undefined_function
```
Relative variant also failed identically:
```
error • Target of URI doesn't exist: '../test/fakes/fake_message_repository.dart' • lib/main.dart:9:8 • uri_does_not_exist
```

**RED-4 — named factory suppressed implicit default ctor:**
```
error • The class 'FakeMessageRepository' doesn't have an unnamed constructor • lib/core/config/fake_message_repository.dart:48:18 • new_with_undefined_constructor_default
```

**RED-5 — drift close-timer invariant** (resolved with the repo's established unmount+1ms flush, same as `read_paths_char_test.dart`):
```
Pending timers: Timer (duration: 0:00:00.000000, ...), created:
#6      StreamQueryStore.markAsClosed (package:drift/.../stream_queries.dart:154:11)
A Timer is still pending even after the widget tree was disposed.
```

## GREEN outputs (exact)

- `flutter test test/offline/use_fakes_boot_test.dart` → `00:00 +1: All tests passed!`
- `flutter test` (full) → `00:07 +137: All tests passed!` (baseline 136/136 + 1 new)
- `flutter analyze` → `86 issues found.` — **0 errors**, count == baseline (86)
- `flutter test test/grep_gates_test.dart` → `00:00 +13: All tests passed!` (gate 13 green; `data_source.dart` carries only `bool.fromEnvironment`, no network SDK)

## Audit-F carries 1–5

1. **Hard `as MessageRepositoryImpl` casts** (message_body_provider:29/:126, chat_provider:65) — **NOT HIT** (resolution (a)). Boot path builds no `MessageBodyText`: `conversationLastMessageProvider` yields null rows (empty in-memory DB) → `ConversationPreviewText` falls back to the stored `lastMessagePreview` string → `decryptPassProvider` / `drainStampWireProvider` / `mediaFileProvider` never read. No casts touched or softened. Device run log: no TypeError.
2. **bodyCache process-global** — **NOT HIT** (same reason: no body reads on this path). No seed/clear added; left untouched.
3. **conversationLastMessageProvider / home_screen:112 default appDatabaseProvider** — **HIT by code path**: `ConversationPreviewText` watches it; default body would open the real file DB via `path_provider` (MissingPluginException swallowed as AsyncError). **Resolved:** test overrides `appDatabaseProvider` with `AppDatabase.test()` (in-memory). home_screen:112 (banner dismiss) never triggered (banner not tapped).
4. **M2 mediaFileProvider / M3 chat_screen** — **NOT HIT** (home screen only). No provider overridden for them.
5. **Gate 13** — `lib/core/config/data_source.dart` + `fake_message_repository.dart` scanned; gate suite 13/13 green.

## Deviations / Rulings

- **R1 (file layout):** fake class lives at `lib/core/config/fake_message_repository.dart`, NOT `test/fakes/…`. Evidence: `lib/main.dart` must construct the fake, but `package:kuch_bhi/test/…` and relative `../test/…` both fail to resolve from lib/ (RED-3 above — package URIs root at `lib/`). `test/fakes/fake_message_repository.dart` is kept as a barrel `export` so the brief's test-side import path works unchanged.
- **R2 (test assertion):** brief's sketch asserts only `takeException() == null`. That is vacuous — HomeScreen swallows provider errors into AsyncError states, so the test would pass WITHOUT the fake (no override, no exception). Added a seeded-conversation render assertion (`find.text('Fake Boot Chat')`); discrimination proven by RED-2 probe.
- **R3 (main wiring):** brief sketch uses `FakeMessageRepository()`; device step requires home to render fake data, and a bare ctor is empty → empty-state, not fake rows. main uses `FakeMessageRepository.demo()` (seeds 2 conversations). Plain ctor retained for tests.
- **R4 (stream shape):** brief sketch shares one `StreamController<List<Message>>` across all `watchMessages` — a send in conv A would cross-talk into conv B's watchers. Implemented a `void` broadcast ping + per-conversation map re-read instead. `watchConversations` got the same broadcast tail (brief sketch was one-shot; local sends need list updates).
- **R5 (fake scope):** implemented `resyncOnResume() → no-op` and `getIncomingGroupInvites() → []` beyond the brief's read list. `app.dart` calls `resyncOnResume()` on EVERY cold start (loud UnimplementedError at boot otherwise); home's badge reads `getIncomingGroupInvites()`. Both are semantically correct fake answers (no sockets to resync; no invites), not silent stubs of real behavior. Everything else still fails LOUD via `noSuchMethod`.
- **R6 (theme):** test wraps `MaterialApp(theme: warmPopLight())` — `context.t` is `Theme.of(this).extension<ColorTokens>()!` (null-assert without it).
- **R7 (uncommitted):** this report file is left uncommitted for the orchestrator (orchestrator commits after review per protocol).

## Device capture

- Emulator `emulator-5554` present. Network cut BEFORE run: `svc wifi disable` + `svc data disable` → `ping 8.8.8.8` = `connect: Network is unreachable`.
- `flutter run -d emulator-5554 --dart-define=USE_FAKES=true` booted; log shows PB/FCM/presence all failing host lookup (`kuch-bhi.duckdns.org` errno 7) — network genuinely down; session restored from local Drift token; router settled on `/home`.
- Screenshot: home renders both fake rows — **Offline Demo Group** ("Running on fakes — zero network", unread 2) and **Demo Peer** ("This row is served by FakeMessageRepository").
- Capture committed: `docs/captures/off_use_fakes_boot.png`.
- After capture: app force-stopped, network re-enabled (ping OK).
- Notes (not defects of this task): backup banner shows offline (`hasPocketBaseBackup` returns false on network error → banner true); pre-existing drift "AppDatabase created twice" warning from `FcmDebugHelper`.
