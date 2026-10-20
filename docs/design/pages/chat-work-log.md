# Chat screen redesign — work log

Date: 2026-10-18  
Checklist: `docs/design/pages/chat.md`  
Visual references: `docs/design/pages/chat.html`, `docs/mockups/2026-10-05-home-chat.html`

## User-requested changes

The requested chat-page changes were:

1. Redesign the entire chat page as one full-page warm-pop canvas, with no visible
   AppBar/body/composer colour seams.
2. Keep the page on the same background colour and use floating surfaces for the
   pinned-message banner, search bar, reply preview, composer, attachment control,
   send control, and microphone control.
3. Make message bubbles consistent across text, emoji, image, video, voice,
   document, link-preview, system, expired, and optimistic states.
4. Preserve existing chat behavior: E2E decrypt/predecrypt, P7 derived previews,
   offline policy, media viewers, reactions, selection, search, replies, uploads,
   recording, loading, empty, error, and history states.
5. Record the completed checklist items in `chat.md` and document the full change
   set in this file.

## Completed implementation

### Page shell and surfaces

- `chat_screen.dart` now uses `context.t.bg` as the route canvas.
- Header content is rendered on the canvas; visible AppBar/body seams were removed.
- Presence subtitles implement the truth order: typing, in-chat, online, last seen,
  offline. Group member counts use singular/plural copy.
- Group and 1:1 avatar/name taps route to Group Info/Profile.
- Search is a floating surface with autofocus, 200ms debounce, generation cancel,
  counter, previous/next navigation, wraparound, close, persistent row tint, and
  in-text marks.
- Composer and pinned banner hide during search and return on close.
- Loading, error, offline, history-end, empty, and scroll-to-latest states remain
  available on the same canvas.
- Pinned messages use a floating tokenized surface with pin count, preview,
  decrypt-state handling, cycle controls, and jump/landing flash behavior.
- Reply previews use a floating tokenized surface with a clipped accent rail and a
  48dp cancel target. A rounded-corner paint failure from a non-uniform border was
  fixed with a uniform border plus clipped accent rail.
- Composer is a floating keyboard-safe panel with tokenized border/shadow treatment.
  Attachment, send, and microphone controls use 48dp targets.

### Bubble geometry and media

- `ChatBubbleGeometry` and `ChatBubbleFrame` provide shared bubble anatomy:
  - 84% maximum width.
  - 12dp near-side and 64dp far-side margins.
  - 2dp vertical rhythm.
  - 18dp corners and 6dp run-end tail.
  - Mine-only soft shadow.
  - 10.5px timestamp/tick placement with consistent opacity.
- Text, emoji, image, video, voice, document, link-preview, system, deleted, and
  expired states use the shared geometry rules.
- Group sender runs carry sender name/avatar only on run start; tails/timestamp are
  kept on run end; date separators break runs.
- Optimistic media placeholders are per type rather than the generic 140px box.
- `DeliveryTick` is the canonical status renderer for queued, sending, sent,
  delivered, read, and failed states.
- `ExpiryBadge` and the expired-media placeholder are shared across media types.
- Image/video/voice/document media retain their viewers, controls, overlays,
  download states, expiry states, and retry paths.

### Interaction, decrypt, and offline behavior

- Landing flash is shared by search, pinned-message, reply, and starred-message
  jumps. Off-device targets fetch/poll for up to 2 seconds and show the finding or
  not-found toast instead of failing silently.
- Reply previews remain derived from the parent message body; no stored preview
  string was reintroduced.
- Transient decrypt states use the whole-bubble skeleton shell. Terminal states use
  real bubble chrome with lock/warning copy and the resend instruction.
- Search never queries or renders raw ciphertext; terminal bodies are excluded from
  text matching.
- Long-press menu supports reply, copy, star, pin, select, delete, reactions,
  preview header, offline-disabled actions, and destructive delete confirmation.
- Selection mode swaps the header for an action bar, adds bubble selection styling,
  survives scroll, and exits before route back navigation.
- Reaction chips toggle on tap; long-press opens a detail sheet with real avatars and
  a red Remove action. The add-reaction chip opens the emoji picker.
- Composer modes cover normal text entry, mic/send morph, recording, voice preview,
  image/video/document upload rows, restriction state, draft persistence, reply
  strip, upload cancellation UI, and send loading state.
- Recording supports pulse/timer, five-minute auto-stop, slide/release cancellation,
  sub-one-second discard, and the Hold to record message.
- Video compression exposes determinate progress. Upload cancellation uses generation
  guards to prevent stale completion from restoring cancelled UI.
- Offline strips, retry/discard failure surfaces, and `Available online` action hints
  follow the defined offline policy.
- Disappearing-message dialog includes current-value checkmark, scope copy, and
  confirmation snackbar.
- Empty and no-results states use the intended capybara placements; the mascot rig
  parks animation under reduced-motion.

### Review-fix pass R1–R5

- **R1 / H3:** `MessageBodyText` now renders `Ask them to resend` only for
  `bubble` and `bubble.mine` contexts. Preview, pinned, reply, and context-menu
  terminal states keep a single-line `Can't decrypt` presentation.
- **R2 / D4:** `isEmojiOnly` now counts grapheme glyphs with `characters`; one to
  three emoji glyphs remain chrome-less, while four or more use the normal bubble.
- **R3 / P1:** chat load errors now include the 72dp key-mood Capybara and retain
  the existing error copy and Retry action.
- **R4 / Q2:** each `MessageBubble` exposes one safe merged semantics label with
  sender, body/type, local time, and status. Visual body/sender/timestamp nodes
  are excluded from duplicate announcements; interactive child controls remain
  reachable.
- **R5 / Q4:** composer recording pulse now parks when reduced motion is enabled
  and resumes when motion is disabled.

## Verification evidence

### Automated checks

| Check | Result |
|---|---|
| `/home/chaitanyadhotre/development/flutter/bin/flutter test` | PASS — 243/243 tests |
| Targeted `dart format --output=none --set-exit-if-changed` on changed chat/UI/test paths | PASS |
| `git diff --check` | PASS |
| Scoped analyzer on changed chat/UI/test paths | PASS — no issues |
| Full `flutter analyze` | No errors; exit 1 from 97 existing warnings/info outside the edited chat paths |
| Debug APK build/install/launch on `emulator-5554` | PASS |

### Device evidence

Latest captures are in `docs/design/pages/captures/`:

- `chat-floating-home.png`
- `chat-floating-light.png`
- `chat-floating-light-2.png`
- `chat-floating-dark.png`
- `chat-floating-search.png`

The search capture confirms the floating search surface, result counter,
previous/next controls, close control, and hidden composer/pinned surfaces.
The emulator was restored after capture: night mode off, font scale 1.0,
animation scales 1.0, hard-keyboard IME setting 0.

## Checklist result

Completed items are ticked in `chat.md`.

Remaining explicit items:

- **F4 SHOULD:** reaction count pop animation is deferred.
- **J8 MUST:** re-scoped as a media-pipeline backlog item. The current pipeline
  exposes loading/final states but no determinate download percentage.
- **Q5 MUST:** the existing font-scale capture predates the final floating-shell
  pass; recapture is required.

Additional review gaps:

- M52 and Redmi S2 device proof was not available; verification used the attached
  Pixel-style API 37 emulator.
- True cancellation after repository upload dispatch still needs data-layer support;
  current cancellation safely guards preprocessing/compression and stale UI.
- User `PASS` is still required before any commit. No commit was created.

## Main files changed

- `lib/features/chat/screens/chat_screen.dart`
- `lib/features/chat/providers/chat_provider.dart`
- `lib/features/chat/chat_run_grouping.dart`
- `lib/features/chat/widgets/message_bubble.dart`
- `lib/features/chat/widgets/message_body_text.dart`
- `lib/features/chat/widgets/message_input.dart`
- `lib/features/chat/widgets/pinned_message_banner.dart`
- `lib/features/chat/widgets/reply_quote.dart`
- `lib/features/chat/widgets/delivery_tick.dart`
- `lib/features/chat/widgets/expiry_badge.dart`
- `lib/features/chat/widgets/image_message_bubble.dart`
- `lib/features/chat/widgets/video_message_bubble.dart`
- `lib/features/chat/widgets/voice_message_bubble.dart`
- `lib/features/chat/widgets/document_message_bubble.dart`
- `lib/features/chat/widgets/link_preview_card.dart`
- `lib/features/chat/widgets/reaction_bar.dart`
- `lib/features/chat/widgets/message_context_menu.dart`
- `test/chat/`
- `test/message_body_text_loading_test.dart`
- `test/pinned_message_banner_loading_test.dart`
- `test/offline/`
- `docs/design/pages/chat.md`

## Next action

Recapture the post-fix font-scale state if required by review, then obtain user
`PASS`. F4 remains accepted deferred; J8 is tracked outside the redesign in the
media-pipeline backlog. Commit only the intended chat redesign and documentation
files after `PASS`.

---

## Review pass 1 — Claude, 2026-10-18

**Independently verified (not taken on trust):**

| Claim | Method | Result |
|---|---|---|
| 235/235 tests | full `flutter test` rerun | ✓ All tests passed (exit 0) |
| analyze 0 errors | full `flutter analyze` rerun | ✓ 0 error-severity lines; 97 warnings/info (baseline ~101) |
| L5 Listener predecrypt law | code grep | ✓ `Listener(onPointerDown)` intact, home_screen.dart:370 |
| J8 "no determinate progress" | lib-wide grep for downloadProgress/bytesReceived | ✓ confirmed — no progress source exists |
| M52/Redmi proof absent | `adb devices` | ✓ only emulator-5554 attached |
| Enter=next search | code | ✓ `onSubmitted → _nextMatch` chat_screen.dart:1101 |

**Visual grading (5 captures):** floating shell consistent light+dark; pinned/search/composer
floating with token radii+shadows (no seams — user direction honored); bubbles/tails/runs/date
pills/ticks (incl. info-blue read)/reactions+ghost-＋/reply-quote/paperclip composer all match
spec; search surface hides composer+pinned with dimmed chevrons at 0/0. `≡` circle in the search
capture: **no matching icon in lib — system/emulator overlay, not app code.**

**Findings:**

- **R1 MUST-fix:** terminal sub-line "Ask them to resend" not gated by `styleContext` —
  leaks into `'preview'` (home tiles show 2-line terminal previews; reply-quote + pinned
  previews affected). Violates preview single-line law. Gate to bubble contexts.
  (`message_body_text.dart:396-437`)
- **R2 MUST-fix:** D4 "4+ emoji → normal bubble" not implemented (`isEmojiOnly` ≤12 chars);
  6-glyph row renders chrome-less, mis-centered, timestamp orphaned. Checklist D4 reopened.
- **R3:** floating-shell delta vs `chat.html` (flush pinned/composer drawings) = accepted
  user-directed change; board gets an as-built delta note at PASS.

**Adjudications:** F4 SHOULD deferred = accepted. J8 MUST = **blocked** (pipeline gap,
verified) → re-scope as media-pipeline backlog item at user ruling. P1/Q2/Q4 remain fix
items. Q5 + M52/Redmi proof = device capture battery pending phone connection.

**Verdict: not yet PASS** — fix list = R1, R2, P1, Q2, Q4; then capture battery
(light/dark/font-1.3/reduced-motion on M52 + Redmi scroll smoke) → user PASS → commit.

## Review pass 2 — R1–R5, 2026-10-18

| Item | Evidence | Result |
|---|---|---|
| R1 / H3 preview leak | `message_body_text.dart`; preview terminal test assertions | ✓ resend sub-line only in bubble contexts |
| R2 / D4 emoji count | `emoji_utils.dart`; `message_bubble_emoji_test.dart` | ✓ 1–3 grapheme glyphs chrome-less; 4+ normal bubble |
| R3 / P1 error mascot | `chat_load_error_test.dart` | ✓ 72dp key-mood Capybara + Retry |
| R4 / Q2 merged semantics | `message_accessibility_test.dart` | ✓ safe sender/body-type/time/status row label; no raw ciphertext |
| R5 / Q4 composer pulse | `media_link_widgets_test.dart` | ✓ pulse parks under reduced motion and resumes when enabled |

### R1–R5 verification

- Focused regression suite: **18 tests passed**.
- Full Flutter suite: **243/243 passed**.
- Scoped analyzer for all R1–R5 source/tests: **no issues**.
- Targeted formatter gate: **PASS**.
- `git diff --check`: **PASS**.

### Accepted review rulings

- **F4 SHOULD:** deferred by adjudication; no reaction-count pop animation is
  required for this redesign pass.
- **J8 MUST:** blocked by the media pipeline and re-scoped as a media-pipeline
  backlog item, not a chat redesign miss.
- **Floating-shell delta:** accepted user-directed as-built difference from
  `chat.html`; record this delta at final board/PASS review.

R1–R5 implementation is complete. No commit was created; user `PASS` remains the
commit gate.

## Review pass 3 — chat + home full verification — Claude, 2026-10-20

**Method:** independent suite/analyze rerun · code verification of R1–R5 · live device battery on
Redmi S2 `c7e9f10e` · adversarial review workflow `wf_304578d7-30f` (20 agents, 41 raw findings →
16 non-minor verified → **9 confirmed / 7 refuted**, 25 minors carried as-is).

### What stood (verified, not taken on trust)

| Claim | Method | Result |
|---|---|---|
| 248/248 tests, analyze 0 errors | full rerun | ✓ |
| R1 preview sub-line gate | code + live home tile | ✓ single-line terminal previews |
| R2 grapheme emoji rule | code + `message_bubble_emoji_test` | ✓ 1–3 chrome-less, 4+ bubble |
| R3 load-error mascot | code + test | ✓ 72dp + Retry |
| R4 merged row semantics | code + test | ✓ |
| R5 pulse parks | code + test | ✓ parks — but parks at scale 0.7 → Q4 reopened |
| L5 Listener predecrypt | live logcat | ✓ TAPDOWN conv=d8zam3bst08ybzt n=6 ms=2589 |
| P7 home preview | live tile ↔ in-chat bubble | ✓ `A*7aXg2@fRG5Am0` genuine plaintext |
| Q5 chat font 1.3 | `captures/chat-redmi-font-1.3.png` | ✓ unclipped → ticked |
| I4 home font 1.3 | `captures/home-redmi-font-1.3.png` | ✓ unclipped → ticked |
| Chat dark + scroll smoke | `chat-redmi-dark.png`, `chat-redmi-scroll-smoke.png` | ✓ floating shell, runs, tails, date pills |
| Enter double-send (my pass-2 claim) | adversarial refutation | ✗ **REFUTED** — maxLines:5 → multiline → `onSubmitted` never fires; button gated + sync clear. Latent hardening only. |

### Fix list (blocking PASS)

**MUST:**

1. **F1 C4 sheet overflow (critical, probe-confirmed regression):** `showMessageMenu` lacks
   `isScrollControlled` + scroll view; 9/16 cap clips actions (393×873 → 23px; M52 offline →
   Delete-for-everyone below screen; 360×720 → 109px; HEAD = 0). Gate test masks it (1080×2400).
2. **F2 D5 group prefix overflow (home):** `Flexible(flex: 0)` → unbounded main axis, ellipsis
   dead, ~20-char name overflows and zeroes the preview; no test covers the widget.
3. **F3 N1:** dots-menu trailing `const Text('Off')` hardcoded; also default M3 sheet, not
   shared radius-20 shape. Read `disappearingDuration` (table field exists, entity exposure +
   repo read needed).
4. **F4 N2:** dialog `selectedDuration = 0` init — checkmark always starts on "Off".
5. **F5 L1 Copy dead (live-verified Redmi):** `message.decryptedBody ?? ''` null post-T9 column
   drop → Copy hidden despite visible body; read bodyCache/render-time body instead.
6. **F6 L3 double-dim:** `Opacity(0.38)` over `ListTile(enabled:false)` ≈ 0.14 effective (1.4:1);
   exactly one 38% layer.
7. **F7 R5 park scale:** `_pulseCtrl.value = 0` → Tween begin 0.7 → mic stuck 30% small during
   recording; park at 1.0.
8. **F8 shimmer reduced-motion:** new image/optimistic `Shimmer` never checks `disableAnimations`
   (package has no MediaQuery) → loops forever; wire `enabled:` to reduced-motion.
9. **F9 search flicker (B6):** every keystroke wipes `_matchItemIndices` before the 200ms debounce
   + decrypt scan → transient "Nothing found"; keep prior results until new scan resolves.
10. **F10 ChatTile semantics:** `Semantics(container, label)` + `MergeSemantics` → composed label
    then re-reads every child string (probe: `Aarav, …\nA\nAarav\n09:42…`); exclude visual children.
11. **F11 avatar accentSoft dark contrast:** initials 4.34:1 < AA 4.5 (old surface2 = 4.79) —
    foundation C-law gate.

**SHOULD (same pass, cheap):** no-results mascot 86×78 vs 64×58 + extra copy sentence (B6) ·
pinned-banner counter `_index+1` vs `% length` can print out-of-range i/N (I3) ·
`skeleton.dart` duration update no-op after first build (R11) · chat loading uses static
containers, home uses R11 shimmer — converge on shared Skeleton · decide H6 (banner is currently
unreachable dead code).

**Re-scoped to backlog (reported-not-done, not redesign misses):** upload cancel after
`sendMediaMessageProvider.send()` dispatch (Astra already disclosed; pairs with J8) ·
25 workflow minors: registry duplications (offline strip vs R12, emoji list, badge clamp, R9
header, ConversationMenuAction dual API, banner semantics dup), robustness (voice play re-entry,
reaction toggle try/catch, bulk-delete error path, mounted guards, link launchUrl, initState
post-frame, dispose mid-recording), grep-gate missing `home_search_bar`, cross-year C5 date rule.

### Adjudications

- 7 non-minor findings refuted by adversarial verify (image/video guards pre-existing,
  loadMore never rejects, search-index guards pre-existing at HEAD, Enter path unreachable) —
  accepted; not in fix list.
- K6 upload-cancel post-dispatch: accepted re-scope with J8 (data-layer capability).
- M52 still absent: device-gap stands (Redmi battery complete).

**Verdict: NOT PASS** — F1–F11 → suite/analyze green → re-grade reopened lines
(B6/L1/L3/N1/N2/Q4 + home D5) → user PASS → commit. No commit created.

## Review pass 4 — fix-pass verification — Claude, 2026-10-21

Astra's pass-4 (F1–F11 + SHOULD batch) graded independently: suite/analyze rerun + adversarial
workflow `wf_de2d8948-4e9` (9 agents, one verifier per claim) + live emulator checks.

| Item | Verdict | Key evidence |
|---|---|---|
| F1 C4 sheet scroll | **FIXED** | `isScrollControlled` + `SingleChildScrollView` chrome; scroll-safe test green at 393×873 and 360×720 (drag reaches Delete-for-everyone) |
| F2 D5 prefix bound | **FIXED** | `Flexible(flex:1, loose)` + ellipsis; zero `flex: 0` in tree. Residual: no covering test (SHOULD) |
| F3 N1 trailing truth | **FIXED** | dao `getConversationById` → `_disappearingDurationLabel`; radiusLg(20) sheet; write path PB+local |
| F4 N2 dialog init | **FIXED** | `selectedDuration` from persisted row; live: checkmark on actual value, tap-out cancels |
| F5 L1 Copy live body | **FIXED** | `bodyCache ?? messageBodyProvider` — zero `decryptedBody` refs; regression test |
| F6 L3 single dim | **FIXED** | `Opacity(0.38)` wrapper removed; no-double-opacity test |
| F7 R5 park scale | **FIXED** | `_pulseCtrl.value = 1.0` |
| F8 shimmer reduced-motion | **FIXED** | `_ImageSkeleton` and `_OptimisticSkeletonBox` static under `disableAnimations`; optimistic image/video/voice regression test green |
| F9 search flicker | **FIXED** | `_searchPending` gate; empty-state only after settled scan |
| F10 tile semantics | **FIXED** | composed label + `ExcludeSemantics` over visuals; probe dump clean |
| F11 avatar contrast | **FIXED** | WCAG picker; dark initials 11.4:1 |
| SHOULD batch | **FIXED** | mascot 64×58 + exact copy; pinned counter bounded; H6 reachable; chat loading = shared Skeleton; duration restart |

Gates rerun by Claude: **258/258** ✓ · analyze **0 errors / 97 baseline** ✓ (transient
`zz_probe` agent scratch self-removed). Live emulator (Use-Fake smoke account per user note):
disappearing dialog checkmark + tap-out verified; fake-repo setter throws before pop = test-env
only (fake-repo no-op queued to backlog).

Checklist re-graded: B6/L1/L3/N1/N2 re-ticked · Q4 closed after F8b fix ·
home D5 re-ticked (test-gap note) · home H6 ticked.

**Verdict: PASS-ready:** F8b guard mirrored in `_OptimisticSkeletonBox`; focused image/video/voice
test, full suite, analyzer, formatter, and diff checks pass. Then user `PASS` → commit.
No commit created.

## Review pass 4 — blocking fixes + SHOULD closure — 2026-10-20

**Method:** focused regression suite, full Flutter suite, full analyzer, emulator build/launch,
and visual inspection of Home, Chat, the chat action sheet, and Disappearing Messages dialog.

### Closed findings

- F1/F2/F5/F6/F9: context sheets are scroll-safe; group previews are bounded; Copy reads the
  live body cache/provider; disabled actions avoid a second opacity layer; search keeps prior
  matches and suppresses `Nothing found` until the replacement scan completes.
- F3/F4: chat action sheet uses shared 20dp chrome and reads the persisted disappearing duration;
  the dialog initializes its selected option from that value.
- F7/F8: reduced-motion recording pulse parks at `1.0`; image placeholders stop Shimmer and use
  a static token surface.
- F10/F11: ChatTile exposes one composed semantics node; dark accentSoft initials select a
  token-derived foreground meeting the 4.5:1 contrast gate.
- SHOULD: no-results mascot is `64x58` with exact no-results copy; pinned counter is normalized;
  Skeleton duration updates restart active timing; chat loading uses shared Skeleton; H6 keeps
  stale friend data during provider error so the partial-failure banner is reachable.

### Proof

| Claim | Method | Result |
|---|---|---|
| Focused review tests | targeted/widget suite | PASS |
| Full Flutter suite | `flutter test` | **257/257 PASS** |
| Analyzer | `flutter analyze` | 0 errors; 97 existing warnings/info |
| Formatting/diff gate | `dart format`, `git diff --check` | PASS |
| Android smoke | emulator-5554, debug fake-data run | APK built, installed, process alive |
| Visual chat proof | emulator screenshots | Home, chat, action sheet, dialog render without clipping |

### Remaining

- F4 reaction-count pop remains an accepted deferred SHOULD.
- H7 pin-row move animation remains outside this pass.
- Redmi/M52 physical-device proof was unavailable; emulator proof is current.
- No commit created; user PASS remains the commit gate.
