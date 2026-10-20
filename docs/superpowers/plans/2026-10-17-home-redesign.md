# Home Screen Redesign — Implementation Plan (Page 2 of UI/UX pass)

> **For agentic workers:** execute task-by-task; checkboxes = progress.
> **Binding contract:** `docs/design/pages/home.md` (MUSTs + Laws L1–L12) with visual
> ground truth `docs/design/pages/home.html` (H1–H12). Sequencing note: this plan can
> start AFTER or IN PARALLEL with the chat plan — disjoint files except registry
> amendments (Task 1 touches shared widgets; coordinate if both plans run concurrently).

**Goal:** Restyle the home surface to spec: search pill, pinned indicator, presence dots,
sender prefixes, badge clamps, conversation long-press sheet, tile-shaped skeleton,
offline strip — without breaking P7 previews, tap-down predecrypt, or P6 banner laws.

**Architecture:** Visual pass + wiring already-orphaned data (`setPinned`); one registry
amendment set (AppAvatar flag, AppBadge clamp, C4 action-list variant). No schema changes.

**Tech Stack:** Flutter/Riverpod/Drift (existing).

**Specs (read before Task 1):** `home.html`, `home.md`, `00-foundation.md`, `10-registry.md`.

## Global Constraints

- Tokens ONLY (`context.t`) — L10 grep gate must stay green (no raw hex).
- Laws L1–L12 in home.md are non-negotiable; each task lists the laws it touches.
- Animations ≤250ms; shimmer parks under reduced-motion (R11).
- `flutter analyze` 0 errors per task; suite green (baseline 213/213).
- No commit until user PASS.
- **CRITICAL:** never convert the tile `Listener(onPointerDown)` to GestureDetector (L5).

## Review Focus (tests won't catch)

1. Listener predecrypt still firing after tile rework — grep + manual `[Msg] TAPDOWN` canary (no widget test exists).
2. Placeholder keys unchanged after sender-prefix insertion (`body-placeholder-*` still found by tests).
3. Banner no-flash-in: cold start with backup-required account must NOT blink the strip.
4. Search + FAB + keyboard interplay on device (FAB hide/show, scroll restore).
5. `99+` clamps: badge geometry at font_scale 1.3.

---

### Task 1: Registry amendments (shared — do FIRST)

**Files:**
- Modify: `lib/core/widgets/app_badge.dart` (clamp ≥100 → `99+`, widen pill)
- Modify: `lib/core/widgets/app_avatar.dart` (optional `accentSoft` fill flag)
- Create: `test/registry_amendments_test.dart`

**Interfaces:**
- Produces: `AppBadge(count)` behavior change (all call sites inherit);
  `AppAvatar(url:, initials:, radius:, accentSoft: false)`.

- [ ] **Step 1:** Failing tests: badge renders `99+` at 100+ and raw `3` at 3; AppAvatar with
  `accentSoft: true` paints accentSoft bg. Run → FAIL.
- [ ] **Step 2:** Implement both (foundation §8 registry notes: record amendments in
  `10-registry.md` R1/R2 rows — one-line PR note, do not edit silently).
- [ ] **Step 3:** Full suite GREEN (badge count assertions in `chat_tile_test` may need `99+` cases added).

### Task 2: App bar (home.md A1–A4)

**Files:** Modify: `home_screen.dart` (badge hold-until-true, Semantics, avatar swap),
delete private `_AppAvatar` (now R1+flag); `test/chat_tile_test.dart` if touched.

- [ ] **Step 1:** Failing tests: badge hidden during pendingCount load (no 0 pop);
  `99+` at 100; Semantics labels present. Run → FAIL.
- [ ] **Step 2:** Implement A1–A4; title/bar laws verified visually (A4 = no code beyond existing).
- [ ] **Step 3:** Full suite GREEN.

### Task 3: Search pill (B1–B6)

**Files:**
- Create: `lib/features/home/widgets/home_search_bar.dart`
- Modify: `home_screen.dart` (state + filter application + FAB hide)
- Create: `test/home_search_test.dart`

- [ ] **Step 1:** Failing tests: filter matches name substrings both sections; counts update;
  both-empty single no-results line WITHOUT mascot; clear restores list; Semantics label (B1/B3/B4).
  Run → FAIL.
- [ ] **Step 2:** Implement: local state `String _query`; filter conversations+friends before build
  (display-name only — NEVER previews, B3); focused styling (B2); FAB `Visibility` on focus (B5).
- [ ] **Step 3:** Full suite GREEN.

### Task 4: Tile anatomy (D1–D8) — L1–L5 territory, careful

**Files:** Modify: `lib/core/widgets/chat_tile.dart` (pin glyph slot, presence dot, corner-slot
exclusivity, unread triple signal), `home_screen.dart` (group prefix wiring, long-press pass);
`message_body_text.dart` (group prefix: sibling Text only — NO key changes);
tests: `chat_tile_test.dart`, extend `sealed_preview_test` if prefix visible there.

- [ ] **Step 1:** Failing tests: presence dot renders only when online==true; group glyph XOR dot;
  pin glyph present when isPinned; group preview shows “{Name}: ” before preview widget AND
  `body-placeholder-<id>` key still found; unread signals (ink/600, accent time, badge).
  Run → FAIL.
- [ ] **Step 2:** Implement D1–D7 per H7; wire `onLongPress` → Task 5 sheet (stub callback first
  if Task 5 not landed — forward reference allowed, flag in ledger).
- [ ] **Step 3:** **Manual law check:** grep `Listener(onPointerDown)` intact in
  `home_screen.dart`; run app, tap tile, confirm `[Msg] TAPDOWN fired` in logs (L5 — no test covers it).
- [ ] **Step 4:** Full suite GREEN (placeholder/sealed/read_paths gates mandatory).

### Task 5: Conversation long-press sheet (E1–E4)

**Files:** Modify: `lib/features/chat/widgets/message_context_menu.dart` (add action-list
parameter — C4 variant), `home_screen.dart` (build conv action set + wire);
Create: `test/conversation_menu_test.dart`

- [ ] **Step 1:** Failing tests: sheet opens with header + 3 rows; Pin toggles + snackbar +
  row re-sorts (seed pinned/unpinned); Mark-as-read absent when unread==0; info routes by type.
  Run → FAIL.
- [ ] **Step 2:** Implement: `showConversationMenu(context, {header, actions})` sharing sheet chrome;
  actions: pin (`setPinned` — first-ever caller), markRead, info (E2). Haptic open.
- [ ] **Step 3:** `message_menu_offline_widget_test` still green (message variant unchanged).
- [ ] **Step 4:** Full suite GREEN.

### Task 6: Body states (H1–H5) + backup banner (G1–G4)

**Files:** Modify: `home_screen.dart` (skeleton rows, error block, offline strip, empty
physics, refresh scope, banner tap/hold), `encryption_sync_provider` NOT changed (gate stays);
Create: `test/home_states_test.dart`

- [ ] **Step 1:** Failing tests: skeleton paints circle+2 bars per row; error block shows new
  copy + Retry invalidates both providers; empty list scrolls (physics) with refresh reachable;
  banner: whole-strip tap pushes route, dismiss writes setting, no render before first provider
  value (G3 — pump with pending provider = banner absent). Run → FAIL.
- [ ] **Step 2:** Implement H1–H5 + G1–G4. Offline strip copy = chat S18 string verbatim (reuse
  the same widget if chat plan already extracted one; else local copy identical).
- [ ] **Step 3:** Update any test pinning `'Could not load your chats.'` (home.md H2 flag).
- [ ] **Step 4:** Full suite GREEN (encryption_sync_offline + grep_gates mandatory).

### Task 7: FAB + sheet + perf (F1–F2, H7)

**Files:** Modify: `home_screen.dart` (FAB geometry/press, sheet chrome, ListView.builder)

- [ ] **Step 1:** Failing test: sheet rows render in shared chrome; builder builds only visible
  tiles (widget-count assertion). Run → FAIL.
- [ ] **Step 2:** Implement; pin-toggle move animates ≤250ms (implicit AnimatedContainer on
  order change or AnimatedList — pick simpler, report).
- [ ] **Step 3:** Full suite GREEN.

### Task 8: A11y + gates + captures (I1–I4)

**Files:** Modify: touched widgets (Semantics), `docs/design/pages/captures/` outputs.

- [ ] **Step 1:** Semantics pass (I1); reduced-motion checks (I3).
- [ ] **Step 2:** Contrast engine check for “Online” (I2) — record which path taken.
- [ ] **Step 3:** Run ALL gates (home.md list) + full suite + analyze.
- [ ] **Step 4:** Device captures: M52 light+dark (default/search/empty/loading/error/offline),
  Redmi S2 scroll smoke, font_scale 1.3 → `docs/design/pages/captures/`.
- [ ] **Step 5:** Self-grade every MUST in `home.md`; hand list of ✗ to review.
  **No commit until user PASS.**

---

## Sequencing rationale

T1 first (shared widgets). T2–T3 easy parallel after T1. T4 is the riskiest (preview keys) —
run gates carefully. T5 depends on nothing but T4's long-press wire. T6/T7 independent of T4/T5
after T1–T3. T8 closes. Suggested serial order as numbered if one implementer.
