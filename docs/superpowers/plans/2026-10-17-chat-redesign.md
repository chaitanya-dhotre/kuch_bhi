# Chat Screen Redesign — Implementation Plan (Page 1 of UI/UX pass)

> **For agentic workers:** execute task-by-task. Steps use checkbox (`- [ ]`)
> syntax. The **acceptance checklist `docs/design/pages/chat.md` is the binding
> contract**; this plan is its execution argument. User's implementer: Astra.
> Reviewer: Claude (checklist verdict + screenshots).

**Goal:** Restyle/restructure the chat screen to the approved spec in
`docs/design/pages/chat.html` without breaking the pinned decrypt/preview/predecrypt laws.

**Architecture:** Visual + interaction pass over existing widgets; no data-layer
changes. New: run-grouping, landing flash, unified tick widget, unified expiry,
selection mode, composer morph/cancel. Preserved: `MessageBodyText` machine,
derived previews (P7), tap-down predecrypt, offline policy.

**Tech Stack:** Flutter/Riverpod/Drift (existing). Tests: flutter_test.

**Specs (read before Task 1):**
- `docs/design/pages/chat.html` — visual ground truth (S1–S20)
- `docs/design/pages/chat.md` — MUST/SHOULD checklist (grading)
- `docs/design/00-foundation.md` — tokens + laws
- `docs/design/10-registry.md` — shared pieces (import, don't reimplement)

## Global Constraints

- Tokens ONLY (`context.t` / `WarmPopTokens`) — no hardcoded hex in `lib/`.
- No violet/purple/gradients on chrome. One accent (`#EFA00B`).
- All implicit animations ≤250ms; highlight decay 400ms; pressed 150ms.
- Message bodies render ONLY through `MessageBodyText` (C1) — never a parallel Text.
- P7: no stored preview strings — previews derived via #body 'preview' slot.
- `flutter analyze` = 0 errors after every task; `flutter test` green (baseline 213/213).
- No commit until user PASS (standing rule).
- Checklist IDs (A1, D2…) = the acceptance unit; plan tasks map to them.

## Review Focus (what tests will NOT catch)

1. Run-grouping across date separators (C2) — must not merge across sep or over 2min gaps.
2. Landing flash visible on ALL four jump sources (M1) — sources live in 3 files.
3. Whole-bubble skeleton (H2) must not regress terminal states (H1) — skeleton shell ONLY in transient.
4. Reverse-list keyboard behavior (C6) — verify on device, not in widget tests.
5. font_scale 1.3 clipping of ticks/chips/app bar (Q5) — device capture.

---

### Task 1: Foundations first — unified tick + expiry widgets

**Files:**
- Create: `lib/features/chat/widgets/delivery_tick.dart` (G1/G2)
- Create: `lib/features/chat/widgets/expiry_badge.dart` (J7)
- Modify: `message_bubble.dart`, `image_message_bubble.dart`, `video_message_bubble.dart`,
  `voice_message_bubble.dart`, `document_message_bubble.dart` (call sites)

**Interfaces:**
- Produces: `DeliveryTick({required String status, double size = 13})` where status ∈
  `queued|sending|sent|delivered|read|failed`; `ExpiryBadge({required String label})`
  (label = "23h"/"1d"); `ExpiredPlaceholder({required IconData glyph})`.

- [ ] **Step 1:** Failing test `test/chat/unified_tick_test.dart`: pump `DeliveryTick` for each
  status; assert icons (clock / spinner / check / check2 / check2-blue / warn) and that `read`
  uses `t.info`. Run → FAIL (missing widget).
- [ ] **Step 2:** Implement `delivery_tick.dart` per S10 legend (colors from `context.t`).
- [ ] **Step 3:** Replace `_TickIndicator` / `_VoiceTick` / `_DocTick` / media overlay ticks with
  `DeliveryTick` (keep status mapping logic where it lives). Delete dead variants.
- [ ] **Step 4:** Implement `expiry_badge.dart` + `ExpiredPlaceholder`; replace `ExpiryBadge`,
  voice/doc expiry text labels, `ExpiredMediaPlaceholder` (J7).
- [ ] **Step 5:** Run new test + full suite → GREEN. `flutter analyze` → 0.

### Task 2: Bubble anatomy — tails, run grouping, margins, sender names (D1–D2, C2)

**Files:**
- Modify: `message_bubble.dart` (tails, margins, run props), `chat_screen.dart`
  (`_buildItems` run computation), `message_bubble_sender_test.dart`

**Interfaces:**
- Produces: `MessageBubble(..., {bool runStart, bool runEnd})` (or equivalent positional
  run flags); `_ChatItem._MsgItem` carries run position from a pre-pass over rows.

- [ ] **Step 1:** Failing test `test/chat/run_grouping_test.dart`: seed 3 same-sender msgs
  <2min apart + 1 after 5min + date separator case; assert name+avatar ONLY on run start,
  tail only on run end, no merge across separator (C2). Run → FAIL.
- [ ] **Step 2:** Implement run pre-pass in `_buildItems()` (reverse list: runStart =
  senderId/time differs from next-younger in display order; separator resets).
- [ ] **Step 3:** Apply tails (18/6 per side per S7 — run middle = no tail),
  unify video margins to 12/64 (J9), sender-name color = existing `_senderPalette`.
- [ ] **Step 4:** Group bubble: avatar 28px in runStart row slot (hidden spacer otherwise);
  1:1 = no avatar/name slots ever.
- [ ] **Step 5:** Update `message_bubble_sender_test.dart` for new structure; full suite GREEN.
- [ ] **Step 6:** System pill icon taxonomy (D5): leading icons per S7 (timer/group/person/lock/info);
  keep pill chrome, no interactions. Extend bubble test. GREEN.

### Task 3: Decrypt visuals — whole-bubble skeleton shell + terminal sub-line (H1–H3)

**Files:**
- Modify: `message_body_text.dart` (shell chrome param), `message_bubble.dart` (shell wiring),
  `test/message_body_text_loading_test.dart` (extend, don't weaken)

- [ ] **Step 1:** Failing tests: transient body inside bubble paints shell (surface/surface2 +
  radius 18) while bars show; terminal paints REAL chrome + "Ask them to resend" sub-line;
  terminal NEVER shell. Run → FAIL.
- [ ] **Step 2:** Implement: bubble chrome switches on `decryptState == transient` only —
  shell = resolved bubble look with skeleton-colored body area; keep laws 1–10
  (ciphertext geometry, grace alphas, sticky, size-lock, fade).
- [ ] **Step 3:** Terminal row: icon + "Can't decrypt" + 12px sub-line.
- [ ] **Step 4:** Run H5 mandatory gates + full suite → GREEN.

### Task 4: Landing flash — one wrapper for every jump source (M1–M4)

**Files:**
- Modify: `chat_screen.dart` (`_HighlightWrapper` → flash API, `_jumpToMessage`),
  `pinned_message_banner.dart` (tap path unchanged — flash lives in chat screen)

- [ ] **Step 1:** Failing test `test/chat/jump_flash_test.dart`: call `_jumpToMessage`
  (or extracted `flashMessage(localId)`) → target bubble builds with flash accent@~26% →
  pump 400ms → resolved to normal; reduced-motion variant = 200ms single fade.
  Run → FAIL.
- [ ] **Step 2:** Implement: single entry point wraps ANY jump (search/pin/reply/starred all
  route through `_jumpToMessage` already — flash triggers post-scroll there).
- [ ] **Step 3:** Search persistent tint stays (B5) — flash is additive.
- [ ] **Step 4:** Add "Finding message…" toast after 1s during fetch-poll (M3); fail toasts already exist.
- [ ] **Step 5:** Full suite GREEN.

### Task 5: App bar + search mode (A1–A6, B1–B8)

**Files:**
- Modify: `chat_screen.dart` (`_mainBar`, `_searchBar`, presence wiring), new `no-results`
  block; `test/chat/search_mode_test.dart` (new)

- [ ] **Step 1:** Failing tests: crossfade exists (both bars share slot, AnimatedSwitcher 150ms);
  no-results shows mascot + copy; composer+pin hidden while searching (B4);
  counter/chevron disable at 0. Run → FAIL.
- [ ] **Step 2:** Implement subtitle truth order + group count plural (A1–A2);
  tap avatar/name → routes (A4); Semantics labels on actions (Q1 partial).
- [ ] **Step 3:** Implement search: field swap, in-text `<mark>` rendering (B5),
  no-results state (B6), wrap nav + Enter=next (B7).
- [ ] **Step 4:** Full suite GREEN.

### Task 6: List shell — skeleton/empty/error, separators, end-marker, FAB (C1–C9)

**Files:**
- Modify: `chat_screen.dart` (`_buildItems`, loading/error branches, FAB), `test/chat/list_shell_test.dart` (new)

- [ ] **Step 1:** Failing tests: skeleton rows in loading (C7); error = banner+retry copy (C8/C9);
  end-of-history pill once (C4); FAB visibility + count badge (C5); separator labels (C1).
  Run → FAIL.
- [ ] **Step 2:** Implement all; empty state = `EmptyState(withMascot, …)` (R7) with copy from S3.
- [ ] **Step 3:** Full suite GREEN.

### Task 7: Pinned banner restyle + cycle/jump split (I1–I4)

**Files:** Modify: `pinned_message_banner.dart`, `test/pinned_message_banner_loading_test.dart` (extend)

- [ ] **Step 1:** Failing tests: no stripe; chevron tap cycles WITHOUT calling onTap-jump;
  preview tap jumps; terminal preview intact (H4). Run → FAIL.
- [ ] **Step 2:** Implement: remove left stripe, add chevrons (multi only), split tap targets,
  hide-during-search wiring (screen side).
- [ ] **Step 3:** H5 gates + suite GREEN.

### Task 8: Media polish — optimistic per-type, progress, link card, margins (J1–J9)

**Files:** Modify: `message_bubble.dart` (optimistic branch), image/video/voice/doc bubbles,
`link_preview_card.dart`; `test/chat/media_states_test.dart` (new)

- [ ] **Step 1:** Failing tests: optimistic renders per-type (J6); download % overlay (J8);
  link card fallback (J5); voice speed cycle visible (J3). Run → FAIL.
- [ ] **Step 2:** Implement per checklist; overlay pill consolidation (J1/J2).
- [ ] **Step 3:** Full suite GREEN.

### Task 9: Composer — morph, cancel, restriction, drafts, strip label (K1–K10, E4)

**Files:** Modify: `message_input.dart`, `chat_screen.dart` (restriction strings);
`test/chat/composer_modes_test.dart` (new)

- [ ] **Step 1:** Failing tests: mic↔send AnimatedSwitcher 250ms (K3); upload ✕ cancel fires
  callback (K6); strip label = "Replying to {name}" (E4); restriction line renders (K7);
  draft survives rebuild (K8). Run → FAIL.
- [ ] **Step 2:** Implement; wire `isLoading` real path (K4); attach icon → paperclip (K2).
- [ ] **Step 3:** Full suite GREEN.

### Task 10: Long-press sheet + selection mode + reactions (L1–L6, F1–F5)

**Files:** Modify: `message_context_menu.dart`, `reaction_bar.dart`, `chat_screen.dart` (selection bar + state);
`test/offline/message_menu_offline_widget_test.dart` (update keys); new `test/chat/selection_mode_test.dart`

- [ ] **Step 1:** Failing tests: preview header present; Select entry enters selection —
  bar swap, bubble ring toggle, back exits first (L5); offline rows opacity+hint intact (L3);
  reaction chip tap toggles own reaction (F2), ghost ＋ appears with ≥1 reaction (F3),
  detail sheet avatars (F5). Run → FAIL.
- [ ] **Step 2:** Implement sheet updates + selection state machine (keep menu as THE shared C4);
  reaction chip toggle + ghost-add popover + count pop (F1–F5).
- [ ] **Step 3:** Update menu test keys; full suite GREEN.

### Task 11: Menu sheet + disappearing dialog + failure/offline strips (N1–N3, O1–O3)

**Files:** Modify: `chat_screen.dart` (popup → sheet, dialog chrome, offline strip);
`test/chat/menu_dialog_test.dart` (new)

- [ ] **Step 1:** Failing tests: menu = sheet with icons + current value (N1/N2);
  offline strip copy + auto-clear (O1); dialog checkmark on current (N2). Run → FAIL.
- [ ] **Step 2:** Implement per S17/S18 copy exactly.
- [ ] **Step 3:** Full suite GREEN.

### Task 12: A11y + mascot + verification pass (P1–P2, Q1–Q5)

**Files:** Modify: `chat_screen.dart` + touched widgets (Semantics), tests as needed

- [ ] **Step 1:** Semantics labels everywhere (Q1–Q2); reduced-motion gating on new anims (Q4).
- [ ] **Step 2:** Mascot placements wired (P1): empty (neutral), no-results (sleepy),
  error (key mood) via `EmptyState`/Capybara moods.
- [ ] **Step 3:** Run ALL gates: `flutter analyze` (0 errors), full suite (≥213/213),
  H5 mandatory files.
- [ ] **Step 4:** Device captures: M52 light + dark (each S3 state you can reach),
  Redmi S2 scroll smoke, font_scale 1.3 shot, reduced-motion shot → `docs/design/pages/captures/`.
- [ ] **Step 5:** Self-grade against every MUST in `chat.md`; list ✗ + reasons.
  Hand to review. **No commit until user PASS.**

---

## Sequencing rationale

1–4 are cross-cutting vocabulary (ticks, grouping, decrypt, flash) that later
tasks consume; 5–8 independent surfaces; 9–11 interactions; 12 closes gates.
Tasks 5/6/7/8 may be parallelized if desired (disjoint files after 1–4).
