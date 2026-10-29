# Requests redesign implementation plan (Page 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Warm Pop redesign of the Friend Requests page (friend requests + group invites) per
`docs/design/pages/requests.html` Q1–Q14 and the grading contract `docs/design/pages/requests.md`.

**Architecture:** Keep the two AsyncNotifier sources + SSE wiring; move mutations onto the
notifiers (L4); extract request/invite cards into feature widgets; compose ALL page states from
registry pieces (R1/R2/R3/R5/R7/R9/R11/R12) with `context.t` tokens only. One home_screen edit:
hand-rolled red badge → R2 AppBadge.

**Tech Stack:** Flutter, Riverpod AsyncNotifier, PocketBase repos (unchanged contracts), Drift untouched.

**Spec:** `docs/design/pages/requests.html` + `docs/design/pages/requests.md` (the checklist is the
grading contract — every MUST maps to a task below).

## Global Constraints

(From `00-foundation.md` / `10-registry.md` — every task inherits these.)

- Tokens: accent `#EFA00B`; light bg `#FAF7F1` / dark `#171512`; use `context.t.*` ONLY — no
  `Theme.of(context).colorScheme`, no `withValues(alpha…)`, no hex literals (C3 grep gate).
- Space grid: 4/8/12/16/20/24/32/40/48 only; card radius `WarmPopTokens.radiusMd` (16); no magic
  numbers off-grid (disc 52 = 13×4 allowed).
- Motion: 150 / 250 / 400 ms; reduced-motion parks shimmer/spinners, instant exits.
- Registry-only components: R1 AppAvatar (incl. accentSoft + readable-initials amendments),
  R2 AppBadge, R3 AppButton (`busy` slot), R5 showToast, R7 EmptyState, R9 SectionHeader,
  R11 Skeleton (duration-restart build), R12 StatusBanner pattern.
- Copy: exactly the strings in requests.md sections C/G/H/I/J — no `$e`, no new ad-hoc strings
  without adding them to the checklist first.
- L4: screen file imports NO `*_repository_impl.dart`; mutations live on notifiers.
- Baseline: suite 258/258; `flutter analyze` 0 errors (97 info/warning tolerated).
- No commit without user PASS (standing rule).

## Review Focus

(Inputs most likely to bite — each has a pinned test in the owning task.)

1. **Invites source failing while friends load** — today the invites error is swallowed and the
   friends error blanks the page. Partial banner + surviving content must be tested with one
   provider in error and one in data.
2. **Double-accept race** — `acceptRequest` is a multi-second multi-call PB flow; a second press
   must not fire. Card-level lock test with a delayed fake.
3. **Open-while-offline** — strip + all-four-disabled + hint; and the inverse: stale cache render
   vs full error when nothing is cached.
4. **Hostile data** — empty displayName (RangeError today :126), `Unknown`/`Someone`/`Group`
   fallbacks, duplicate pending rows from one sender.
5. **Badge swap ripple** — home zero-flash async boundary and `read_paths_char_test` override
   seam (`pendingRequestCountProvider`) must keep passing after AppBadge adoption.

---

### Task 1: Notifier mutations (L4) + action outcomes

**Files:**
- Modify: `lib/features/friend_requests/providers/friend_request_provider.dart`
- Test: `test/friend_requests/request_actions_test.dart` (new)

**Interfaces:**
- Produces: `IncomingRequestsNotifier.accept(String id)`, `.decline(String id)`;
  `IncomingGroupInvitesNotifier.accept(String id)`, `.decline(String id)` — each `Future<void>`,
  try/catch inside, rethrows `false`-style outcome via a small sealed result OR throws and screen
  catches (pick: notifiers THROW; screen catches → toast — keeps notifier dumb).
- Produces: per-source refresh via existing `ref.invalidate` targets inside notifier methods.

- [ ] **Step 1: failing tests** — fake repos: accept happy path invalidates both friend providers;
  decline happy path invalidates requests only; repo throw → future completes with exception
  (screen contract); group variants invalidate invites.
- [ ] **Step 2: run → fail** (`flutter test test/friend_requests/request_actions_test.dart`).
- [ ] **Step 3: implement** notifier methods calling `ref.read(friendRepositoryProvider)` /
  `messageRepositoryProvider` then invalidating.
- [ ] **Step 4: run → pass**; commit `feat(requests): notifier accept/decline actions`.

### Task 2: Card widgets (C1–C3, D1–D2, hostile data)

**Files:**
- Create: `lib/features/friend_requests/widgets/request_card.dart`,
  `lib/features/friend_requests/widgets/group_invite_card.dart`
- Test: extend `test/friend_requests/requests_screen_test.dart` (new file, card-level pumps here)

**Interfaces:**
- Produces: `RequestCard({required FriendRequest request, required bool locked, required bool offline, required VoidCallback onAccept, required VoidCallback onDecline})`;
  `GroupInviteCard({required GroupInvite invite, ...same})` — pure display + callbacks.

- [ ] **Step 1: failing tests** — renders name/@meta with tokens; empty displayName → R1 fallback
  initial (no RangeError); invite fallbacks (`Group`, `Someone`, "You were invited to join");
  offline → both actions disabled exactly one Opacity ancestor + hint text; locked → busy spinner
  on accept, both disabled; group disc carries glyph badge.
- [ ] **Step 2: run → fail.**
- [ ] **Step 3: implement** cards: R1 AppAvatar r52, R3 AppButton pair, `context.t` colors only.
- [ ] **Step 4: run → pass**; commit.

### Task 3: Screen shell + two-source states (B1–B5, F, G, E)

**Files:**
- Rewrite: `lib/features/friend_requests/screens/friend_requests_screen.dart`
- Test: `test/friend_requests/requests_screen_test.dart`

**Interfaces:**
- Consumes: Task 1 notifier methods, Task 2 cards.

- [ ] **Step 1: failing tests** — (a) both loading → 3 skeleton cards, zero `CircularProgressIndicator`;
  (b) friends data + invites error → friend cards visible + "Some requests didn't load." + Retry;
  (c) both error → "Couldn't load requests." + subtitle + Retry, no `$e`; (d) both empty+settled →
  EmptyState copy/CTA; (e) friends empty + invites data → no empty state, header + invites;
  (f) invites still loading + friends data → NO empty flash (skeleton or friends-only);
  (g) header hidden at 0 invites, shows count pill at ≥1.
- [ ] **Step 2: run → fail.**
- [ ] **Step 3: implement** — per-source `when`s, R11 skeleton, R7 empty (Capybara neutral +
  CTA dispatching existing Add-Friend entry), R9 header, RefreshIndicator invalidating both
  providers, canvas bg `context.t.bg`.
- [ ] **Step 4: run → pass**; commit.

### Task 4: Action wiring + toasts + announce (I1–I3, K3)

**Files:**
- Modify: screen (card callbacks → notifier methods + local busy set + R5 toasts + announce)
- Test: `test/friend_requests/request_actions_test.dart` + screen test additions

- [ ] **Step 1: failing tests** — double-press while delayed fake in flight → repo called once;
  failure path → toast "Couldn't update. Try again." + card unlocked; accept friend → "Friend added";
  invite accept → "Joined {name}"; decline → silent exit; SemanticsService announce "{name} removed".
- [ ] **Step 2: run → fail.**
- [ ] **Step 3: implement** with per-card `Set<String> _busyIds`, try/catch around notifier calls.
- [ ] **Step 4: run → pass**; commit.

### Task 5: Offline strip + policy (H1–H3)

**Files:**
- Modify: screen; possibly tiny helper reusing `connectivitySignalProvider`
- Test: screen test additions

- [ ] **Step 1: failing tests** — offline: strip copy visible; all four actions disabled + single
  opacity layer + "Available online"; offline + cached data renders list (no error); offline +
  no data → full error state; reconnect (fake signal flip) → strip clears.
- [ ] **Step 2: run → fail.**
- [ ] **Step 3: implement** strip under bar (accentSoft), gate card callbacks on connectivity.
- [ ] **Step 4: run → pass**; commit.

### Task 6: Home badge → R2 (J1–J2)

**Files:**
- Modify: `lib/features/home/screens/home_screen.dart` (`_RequestsButton`)
- Test: extend `test/registry_amendments_test.dart` or home tests; run `read_paths_char_test`

- [ ] **Step 1: failing test** — requests button: count 0 → no badge; 3 → R2 badge; 120 → "99+";
  semantics label "{n} pending requests"/"No pending requests"; tooltip kept.
- [ ] **Step 2: run → fail.**
- [ ] **Step 3: implement** — replace hand-rolled pill with `AppBadge(count: …, color: accent)`;
  keep `_pendingRequestCountAsyncProvider` boundary; annotate home.md I1 (badge now R2 accent).
- [ ] **Step 4: run → pass** including `test/offline/read_paths_char_test.dart`; commit.

### Task 7: A11y merges + grep gates (K1–K4)

**Files:**
- Modify: cards/screen (merged labels, decorative discs), `test/grep_gates_test.dart`
- Test: gate + card semantics pumps

- [ ] **Step 1: failing tests** — semantics dump: one card label "Friend request from {name}, {username}"
  (invite variant too), discs excluded; gates: no `colorScheme`/`withValues(alpha`, no
  `CircularProgressIndicator`, no `repository_impl` import under `lib/features/friend_requests/screens`.
- [ ] **Step 2: run → fail.**
- [ ] **Step 3: implement** ExcludeSemantics + container labels; extend gates.
- [ ] **Step 4: run → pass**; commit.

### Task 8: Badge provider test + full sweep + device + log

**Files:**
- Create: `test/friend_requests/pending_count_test.dart`
- Create: `docs/design/pages/requests-work-log.md`
- Update: `docs/design/pages/requests.md` ticks

- [ ] **Step 1: failing test** — `pendingRequestCountProvider`: 3 friends + 2 invites → 5; loading →
  0; either error → 0 (collapse contract).
- [ ] **Step 2: implement; run → pass.**
- [ ] **Step 3: full suite + analyze + `git diff --check`.**
- [ ] **Step 4: device battery** — emulator + Redmi if connected: light/dark captures, offline
  toggle, double-tap, empty/fake-account states → `docs/design/pages/captures/requests-*.{png}`.
- [ ] **Step 5: work log with evidence table; tick checklist; no commit until user PASS.**

---

## Handoff

Spec + checklist + plan travel together to Astra. Review = checklist verdict + captures + suite
green + user PASS (foundation §9). Deferred decisions (badge red→accent, handoff toast, decline
toast, empty subtitle) listed in requests.md footer — surface them at review.
