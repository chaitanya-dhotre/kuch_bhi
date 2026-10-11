# P4 — Star local write + defined offline behavior for unwired actions

**Branch**: feature/offline-first · **Base**: ledger commit after P3 (suite 160/160, analyze 88/0)
**Commit**: `[Offline P10] Star local write + defined offline behavior for unwired actions`
**Scope**: star offline local-write contract + defined-offline UX for unwired menu actions. NOT wired offline (backlog): delete-for-everyone, reactions, pin-server-sync. Outbox FSM untouched. No schema bump. No new network SDK imports.

---

## 1. Recon map

### Star path (`MessageRepositoryImpl.toggleStar`, message_repository_impl.dart:1881)
1. Read `messages_table` row by `localId`.
2. **Write Drift FIRST** — `upsertMessage(... isStarred: Value(nextStarred) ...)` (local, no network).
3. If `serverId != null`: `unawaited` PB create/delete on `starred_messages`, errors swallowed with `debugPrint('[Star] PB sync failed (offline?)')`.

**Verdict**: star offline ALREADY persists locally. The unawaited PB failure is absorbed; `_myId()` is local-only (settings/secure-storage poll). Fetch path preserves the flag (`isStarred: Value(existing?.isStarred ?? false)` at :3618); `_syncStarredMessages` (:3418) only ADDS server stars, never clears local ones. **No prod change needed — pinned by a characterization test.**

### Media protected-set reader (`MediaBlobStore._isProtected`, media_blob_store.dart:460)
Derived predicate (spec §5.3): `uploadPending ∨ message.isStarred ∨ message.isPinned`, joined via `messages.getMessageByServerId(row.messageId)`. Reads the SAME Drift column `toggleStar` writes → local star protects blobs. Confirmed by test (below).

### Context menu actions (`message_context_menu.dart`, long-press from message_bubble:106)
| Action | Offline behavior BEFORE P4 | Verdict |
|---|---|---|
| Star | Drift write first, PB best-effort | **wired** (local durable) |
| Delete for me | Local tombstone first; fetch preserves `isDeletedForMe` | **wired** (local durable) |
| Reply / Copy | Pure local UI | **wired** |
| Pin | Local write exists BUT fetch (:3616) + SSE (`ssePinDeleteCompanion` :384) clobber `isPinned` from server truth → offline pin looks applied, then silently reverts | **unwired → defined-offline** |
| Delete for everyone | Server-first (`messages.update`), then local mark; fetch overwrites `isDeletedForEveryone` from server → offline = lie + revert | **unwired → defined-offline** |
| Reactions | 100% network (`reactions` collection), errors swallowed → silent no-op | **unwired → defined-offline** |

### Offline detection
- `connectivity_plus` is gate-13-banned outside `lib/infrastructure/`, `lib/services/`, `lib/core/network/`, main, firebase_options.
- Outbox worker (:152) has its own Connectivity listener (untouched — FSM out of scope).
- No pre-existing UI online-signal provider.

## 2. Chosen defined-offline UX shape + why

**Shape**: disabled-with-hint.
- Pin / Delete-for-everyone tiles: `ListTile(enabled: false, onTap: null, subtitle: Text('Available online'))` — greyed, non-tappable, hint visible.
- Reaction row: `IgnorePointer(ignoring: offline)` + `Opacity(0.35)` — visibly greyed, taps dead.
- Star / delete-for-me / reply / copy unchanged (enabled).

**Why disabled-with-hint over snackbar-on-tap**: a bottom-sheet menu is a decision surface; showing capability state up-front prevents the tap entirely and matches the user's first-listed option. Snackbar reserved for in-action outcomes (existing pin StateError, copy feedback).

**Fail-safe**: `isOnlineProvider` loading/error → `true` (online). Unknown signal never disables controls.

**Contract location**: pure policy `lib/features/chat/message_offline_policy.dart` (`MessageAction`, `messageActionRequiresOnline`, `isMessageActionEnabled`, `kOfflineActionHint = 'Available online'`) — unit-testable, no imports, menu is a thin renderer.

**Signal**: `lib/infrastructure/offline/connectivity_signal.dart` — `ConnectivitySignal` + `connectivitySignalProvider` + `isOnlineProvider` (StreamProvider). connectivity_plus lives here (gate-13 sanctioned); features import only the provider.

## 3. RED → GREEN

### RED
1. `test/offline/unwired_action_offline_test.dart` — compile-fail RED (policy file absent): network-required set = {pin, deleteForEveryone, react}; offline gating; hint string.
2. `test/offline/message_menu_offline_widget_test.dart` — menu not yet wired (would show tiles enabled offline).

### Characterization (star — already green)
3. `test/offline/star_offline_test.dart` — REAL repo + MockClient that throws on every HTTP call: `toggleStar` flips `is_starred` locally without throwing; unstar flips back; `evictIfNeeded` over 300MiB cap spares the offline-starred blob (100MiB, LRU-oldest) and evicts the unprotected tail. Passed on first run — confirms the pre-existing local-first ordering; pins it against regression. No prod change was required for star.

### GREEN (minimal)
- `lib/features/chat/message_offline_policy.dart` (new, pure).
- `lib/infrastructure/offline/connectivity_signal.dart` (new; Connectivity listener + providers; optimistic-online default).
- `lib/features/chat/widgets/message_context_menu.dart`: watch `isOnlineProvider` (`.value ?? true`); gate reaction row (IgnorePointer+Opacity), pin tile, delete-for-everyone tile; `_tile` gains `enabled` param (null onTap + hint subtitle when disabled).
- Widget tests added to prove the visible half: offline menu disables pin/delete-for-everyone with hint + greys reactions; online menu fully enabled, hint gone.

## 4. Gates

| Gate | Before | After |
|---|---|---|
| flutter test | 160/160 | **166/166** (star char + 3 policy + 2 widget) |
| flutter analyze | 88 issues, 0 errors | **88 issues, 0 errors** (no new-file findings) |
| grep_gates | 13/13 | **13/13** (connectivity_signal under lib/infrastructure/ — sanctioned; features files import provider only) |

## 5. Device status

emulator-5554 attached, `com.chai.kuch_bhi` installed and running (pid 8571) — **but no debug/VM-service session and the installed binary predates P4**. Device verify (airplane-toggle + relaunch + `docs/captures/p4-star-offline.png`) would require a full cold rebuild + re-login; skipped per task constraint ("if quick… if session is gone, skip"). Star local-write correctness is proven against the REAL repository + REAL Drift + REAL eviction join in `star_offline_test.dart`; the remaining device-only delta is relaunch UI visibility, which reads the same `is_starred` column via the existing message stream.

## 6. Deviations

1. **Star required no prod change** — recon showed `toggleStar` already writes Drift before the best-effort PB sync (ruling anticipated a possible gap; none found). Delivered as a characterization/pin test instead of a fix.
2. **Mixed disabled treatments** — tiles use disabled-with-hint; the 30-emoji reaction row uses greyed+inert (IgnorePointer) rather than 30 disabled sub-list-tiles. Same contract (defined, visible, never silent), less chrome.
3. **Pin treated as unwired despite a local write** — its local `is_pinned` is clobbered from server truth on next fetch/SSE, so offline pinning is a temporary lie; gated offline per ruling. Wiring pin properly = outbox op + server-preserve, post-merge backlog.
4. **Commit tag `[Offline P10]`** — used exactly as specified in the task (task is P4 in the pre-merge series; tag follows the dispatch instruction, not the series letter).

## 7. Follow-ups (post-merge backlog, per ruling)
- Wire delete-for-everyone + reactions offline (outbox ops) — priority 1.
- Wire pin offline (outbox op + fetch/SSE preserve local pin until server ack).
- Optional: surface `isOnlineProvider` as an app-level offline banner (signal now exists).
