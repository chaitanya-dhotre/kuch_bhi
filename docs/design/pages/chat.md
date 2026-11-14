# Chat screen — acceptance checklist (Page 1)

Date: 2026-10-18 update to the 2026-10-17 checklist. Visual ground truth: **`docs/design/pages/chat.html`** (sections
S1–S20, numbered). Authority: `docs/design/00-foundation.md` (tokens/laws) →
`docs/design/10-registry.md` (shared pieces) → this checklist.

**How Astra uses this:** every MUST must be implemented or consciously reported
as not-done. SHOULD = stretch, do after MUSTs. A deviation from foundation
C1–C4 / L1–L4 that *looks better* is still a FAIL (surpass = better inside the
system). **How review grades this:** each line gets ✓ / ✗ + screenshot ref.

**Pass criteria (page complete when):** all MUSTs ✓ · `flutter analyze` 0 errors ·
`flutter test` green (baseline **213/213**; current run **243/243**) ·
mandatory test-gate files below green · device captures light + dark on M52
(plus Redmi S2 scroll smoke) · user PASS (standing rule: no commit without it).

**Status key:** `[x]` implemented and verified by code/tests or recorded device
evidence; `[ ]` still pending, partial, or blocked. Current implementation
status is also recorded in `chat-work-log.md`.

---

## A. App bar (S4)

- [x] **A1 MUST** 1:1 subtitle truth order: typing… → In chat → Online → Last seen →
  Offline; Online = success dot; typing = animated dots + info color; never two at once.
- [x] **A2 MUST** Group subtitle = live member count, singular/plural ("1 member").
- [x] **A3 MUST** Group avatar = group-glyph badge bottom-right; 1:1 avatar = photo/initial.
- [x] **A4 MUST** Tap group avatar/name → Group Info; tap 1:1 avatar/name → Profile.
  48dp targets.
- [x] **A5 MUST** Bar: no elevation line (bg = page bg); name ellipsizes; avatar never shrinks.
- [x] **A6 SHOULD** Presence loading shows nothing (no skeleton flash in the bar).

## B. Search mode (S5)

- [x] **B1 MUST** Closed→open: name block crossfades to pill field, 150ms, autofocus.
- [x] **B2 MUST** Open bar: field + `i/N` counter (tabular) + prev/next chevrons + ✕;
  chevrons disabled (35% opacity) at 0 matches.
- [x] **B3 MUST** Debounced 200ms search with generation cancel; stale results cleared
  immediately; nothing persisted.
- [x] **B4 MUST** Composer + pinned banner hide during search; restored on ✕ (same 150ms crossfade).
- [x] **B5 MUST** Two-level match: current row accent@8% + mark accent@30%; other rows
  accent@4% + mark accentSoft; in-text `<mark>` NEW (was row-only).
- [x] **B6 MUST** No-results: mascot (sleepy) + `Nothing found` + "No messages match '{q}'.";
  list dims 40%; counter 0/0; chevrons disabled.
  **Verified pass 4 (2026-10-20):** `_searchPending` gate keeps prior results during debounce +
  decrypt scan (`chat_screen.dart:332-337, 659-663`); `_SearchEmptyState` = 64×58 sleepy Capybara
  + exact copy. Pass-3 defects closed.
- [x] **B7 MUST** Enter/keyboard-next steps matches; navigation wraps; keyboard stays up.
- [x] **B8 MUST** Search goes through #body decrypt-on-query; terminal bodies never text-match;
  no raw ciphertext ever queried/rendered.

## C. List shell (S6)

- [x] **C1 MUST** Date pill separators: Today / Yesterday / "d MMMM" / "d MMMM y" (older);
  above first message of day; rollover corrects while chat open.
- [x] **C2 MUST** Sender runs: same sender, same day, ≤ **5 min** apart (chat calm B3,
  was 2). Group: name once per **streak** of that sender (13/18 600, 12 in from the bubble
  edge, 4 above); 28 dp disc (surface2 + 1 dp line) beside the run's **last** bubble,
  bottom-aligned to the bubble (C9/C10). Gaps: 2 inside a run, 12 before a new run; day
  pill 16 above (C1–C3). Runs never cross date sep. 1:1: same mechanics, no avatar/name.
- [x] **C3 MUST** Load-older: near-top ≤200px auto-loads 40/page with 3px accent indeterminate bar.
- [x] **C4 MUST** End-of-history: one-time centered pill "This is the beginning of your chat…";
  bar never shows again after.
- [x] **C5 MUST** Scroll-to-latest FAB: appears >1 viewport from newest; accent ring + unread
  count badge when new messages below; tap = 250ms animateTo newest.
- [x] **C6 MUST** Keyboard-open keeps latest message visible (reverse-list contract).
- [x] **C7 MUST** Loading = shape-matching skeleton (bubble rows + separator pill), never a
  bare spinner (foundation §6). Chat calm §F: real B1 shapes and A sizes, own side
  `bubbleMine`, their side surface2, one `SkeletonGroup` breath, after 300 ms; content
  fades in over 150 ms.
- [x] **C8 MUST** Empty = mascot EmptyState ("Say hello to {name}" + encryption line), composer live.
- [x] **C9 MUST** Error = "Couldn't load this chat." + Retry (never raw `Error: $e`).

## D. Bubbles (S7)

- [x] **D1 MUST** (chat calm B1/A1/D2) Radius 18; sender-side bottom corner always 6,
  sender-side top 6 unless the bubble starts a run, far side 18. Text max
  `min(W×0.78, 420)`, padding 12 × 9, text 15/20 → one-line bubbles 38 dp. Mine =
  `bubbleMine` (primary/100 light, primary/900 dark) with **ink** text; theirs = surface +
  1 dp line border in light mode (none in dark). No shadow. Text always start-aligned (B6).
- [x] **D2 MUST** (chat calm B2/B4/B5) The time leaves the bubble: one line under the
  run's last bubble, 4 dp below, 11/14 inkSoft, aligned to the bubble's side; ticks after
  the time on own runs; the failed ⚠ tick and a star (starred) sit on the same line. In
  info mode (K2) every bubble gets the line. Photos and videos have no time pill.
- [x] **D3 MUST** Long-token overflow: `word-break:break-word`, no horizontal clip at 1.3 font scale.
- [x] **D4 MUST** Emoji-only (1–3 glyphs): chrome-less, 40px, time line below (D2), alignment by side;
  4+ glyphs render in a normal bubble.
  **R2 fixed (2026-10-18):** `isEmojiOnly` now counts grapheme glyphs; four or more emoji
  glyphs use the normal bubble.
- [x] **D5 MUST** System pills: centered surface2 italic + leading icon; icon taxonomy
  (timer/group/person/lock/info); no interactions; not swipable, not long-pressable.
- [x] **D6 MUST** Deleted-for-everyone: italic "🚫 Message deleted" (both sides styled).

## E. Reply (S8)

- [x] **E1 MUST** Quote: 3px accent left rule, radius 10, sender 10.5/700 + one-line preview;
  mine-on-accent quote bg white@12%, theirs accentSoft.
- [x] **E2 MUST** Quote body via #body 'preview' slot (never a stored string); media parent =
  34px thumb or type icon; deleted parent dims 60% + "Message deleted".
- [x] **E3 MUST** Tap quote → jump with landing flash (F1); unavailable → toast "Message not in this chat".
- [x] **E4 MUST** Composer strip shows **"Replying to {name}"** (was literal "Reply") + preview + ✕;
  strip returns after recording ends.
- [x] **E5 MUST** Swipe-to-reply: clamp 80px, threshold 72px, medium haptic once/gesture,
  elastic 180ms, icon scale 0.6→1.0 (C5 registry).

## F. Reactions (S9)

- [x] **F1 MUST** (chat calm C8) Chips overlap the bubble's lower edge by 8, on the
  sender's side, 4 in from the corner; theirs-reaction chip = surface2 + 1.5 bg ring, mine =
  accentSoft + 1.5 accent ring.
- [x] **F2 MUST** Tap chip = toggle own reaction; long-press chip = detail sheet (was tap=sheet only).
- [x] ~~**F3 MUST** Ghost ＋ chip when ≥1 reaction exists~~ **Removed (chat calm C8,
  2026-11-14):** long-press → message menu ＋ is the way to add a reaction.
- [ ] **F4 SHOULD** Count-change pop: scale 1→1.12→1 (250ms spring); instant under reduced-motion.
  **Deferred:** reaction count pop animation is not implemented.
- [x] **F5 MUST** Detail sheet: real avatars (was generic glyph), own row "Remove" in error color.

## G. Tick legend (S10)

- [x] **G1 MUST** ONE canonical set everywhere (text, emoji, image/video pill, voice, doc):
  clock=queued · spinner=sending · 1✓=sent · 2✓@54%=delivered · **2✓ info-blue=read (NEW)** ·
  warn=failed.
- [x] **G2 MUST** Failed tick = error color + row-level retry affordance (H2) on every media type.

## H. Decrypt body (S11 — preserves a70f020)

- [x] **H1 MUST** All laws of `message_body_text` intact: ciphertext-geometry bars only,
  150ms grace alpha .10→.18, terminal = lock/warn + "Can't decrypt" (NEVER skeleton),
  sticky last-body, 100ms size-lock + AnimatedSize, 100ms fade swap.
- [x] **H2 MUST** **Whole-bubble skeleton shell (user-approved polish):** transient state renders
  bubble chrome as skeleton shell (same radius/colors as resolved) with bars inside; terminal
  states render on REAL chrome (not skeleton shell).
- [x] **H3 MUST** Terminal sub-line "Ask them to resend" (12px inkFaint) — NEW.
  **R1 fixed (2026-10-18):** sub-line is gated to `bubble`/`bubble.mine`; preview, pinned,
  reply, and context-menu renderers remain single-line.
- [x] **H4 MUST** Pinned banner + ReplyQuote thread decryptState (no '🔒 Encrypted' literals anywhere).
- [x] **H5 MUST** Mandatory gates green: `message_body_text_loading_test`,
  `pinned_message_banner_loading_test`, `offline/placeholder_ui_test`,
  `offline/read_paths_char_test`, `offline/sealed_preview_test`.

## I. Pinned banner (S12)

- [x] **I1 MUST** NO left color stripe (foundation side-stripe ban); pin glyph carries accent.
- [x] **I2 MUST** Chevrons cycle pins WITHOUT jumping; tap on preview = jump (F1 flash).
- [x] **I3 MUST** Multi state shows "Pinned · i/N"; media previews use type constants;
  terminal preview = lock + "Can't decrypt".
- [x] **I4 MUST** Hidden during search, restored on close.

## J. Media (S13)

- [x] **J1 MUST** (chat calm A2/A3/E1) Image: width `clamp(W×0.66, 240, 340)`, height
  `width ÷ aspect` clamped 0.56–1.25 × width, cover, edge to edge, B1 radius, no border, no
  time pill, **no download disc** (D-4 A; the label still says "not downloaded"); tap →
  MediaViewerScreen (Hero), which downloads.
- [x] **J2 MUST** (E2) Video: same box; 44px play circle; bottom-left pill "0:42", plus
  " · 8.1 MB" only on a known "not on disk"; tap → MediaViewerScreen; never inline playback.
- [x] **J3 MUST** (E3) Voice: width A2, padding 10; 40 solid-accent play disc (onAccent
  icon) · 36 bars (played ink, rest ink@30%; tap/drag seeks once loaded) · duration 13/18
  inkSoft; speed chip only while playing. Bars are generated from the message id (D-3 B)
  until real levels ship.
- [x] **J4 MUST** (E4) Document: width A2, padding 10; 40 tile (ink@8%, radius 10, ink
  icon) · name 15/22 600 one line, middle-ellipsis · "PDF · 2.4 MB" 13/18 inkSoft. No marigold.
- [x] **J5 MUST** (E6) Link preview: one surface2 tile, width A2, link glyph + title 15/22
  600 (2 lines) + host 13/18 inkSoft; no second border.
- [x] **J6 MUST** Optimistic placeholder is PER-TYPE (chat calm F): photo/video = flat
  surface2 box in the final size with a 28 dp glyph; voice = static bars @30% + spinner disc;
  doc = tile + "Uploading document…". Ink on the tint, never onAccent (E7).
- [x] **J7 MUST** Unified `ExpiryBadge` (timer + "23h"/"1d") top-right on ALL media; one
  `ExpiredMediaPlaceholder` pattern for expired content (dim + glyph + "Media expired").
- [ ] **J8 MUST** Download progress: determinate "Downloading N%" overlay (was spinner-only).
  **Re-scoped backlog:** current media pipeline exposes loading/final states but no determinate
  download percentage. This is a media-pipeline capability gap, not a chat redesign miss.
- [x] **J9 MUST** Side margins unified (chat calm A7): 12 on the bubble's own side; the
  far side is whatever A1/A2 leave.

## K. Composer (S14)

- [x] **K1 MUST** Modes: normal (empty→mic / typed→send), recording, voice preview,
  image/video/doc upload rows, restriction — each matches S14 specimens.
- [x] **K2 MUST** Attach icon = paperclip (was image glyph); 48dp target.
- [x] **K3 MUST** Mic↔send morph 250ms in one slot; latest user direction uses a 48dp control slot (no layout shift).
- [x] **K4 MUST** Send spinner path wired (fix dead `isLoading=false`).
- [x] **K5 MUST** Recording: pulse dot, error timer, "Slide/Release to cancel" at dragX<−80,
  auto-stop 5:00, <1s discard + toast "Hold to record".
- [x] **K6 MUST** Upload rows get ✕ cancel + toast "Upload cancelled"; video = determinate %.
- [x] **K7 MUST** Restriction = read-only line (lock glyph + one of 3 existing strings), not a
  bare replacement with no styling.
- [x] **K8 SHOULD** Draft persistence per-conversation (in-memory, survives leaving chat).
- [x] **K9 MUST** Attach + quality sheets use shared sheet language (radius 20, handle, 13/600 rows).
- [x] **K10 MUST** Focus restores after sheets; field 1–5 lines then internal scroll.

## L. Long-press menu (S15 — shared, home imports later)

- [x] **L1 MUST** Sheet: drag handle, message preview header (sender + first line, NEW),
  32-emoji row + ＋, actions Reply/Copy/Star/Pin/Select(NEW)/Delete×2.
  **Verified pass 4 (2026-10-20):** `isScrollControlled` + `SingleChildScrollView` chrome —
  scroll-safe test green at 393×873 AND 360×720 (worst-case widths, drag reaches
  "Delete for everyone"); Copy derives live body from `bodyCache ?? messageBodyProvider`
  (zero `decryptedBody` references remain) + dedicated regression test.
- [x] **L2 MUST** Haptic on open.
- [x] **L3 MUST** Offline-disabled rows = 38% opacity + "Available online" right hint (never hidden);
  applies to react/pin/delete-for-everyone (`message_offline_policy`).
  **Verified pass 4 (2026-10-20):** `Opacity(0.38)` wrapper removed — dim comes solely from
  `ListTile` disabledColor; hint rides as trailing text; regression test asserts no second
  Opacity ancestor.
- [x] **L4 MUST** Delete×2 → destructive confirm dialog; copy only when body exists.
- [x] **L5 MUST** Multi-select mode: Select entry → bar swaps to action strip (count + actions),
  bubbles get accent ring + soft fill, system back exits selection first, preserved across scroll.
- [x] **L6 MUST** This is THE long-press sheet (C4) — home page will import it; no chat-local copy.

## M. Jump highlight (S16 — user-requested)

- [x] **M1 MUST** Landing flash on ALL sources: search next/prev, pinned banner, reply quote,
  starred onJump — bubble chrome tint accent@26% → 0 over 400ms ease-out; target centered.
- [x] **M2 MUST** Reduced-motion: single 200ms fade, same tint.
- [x] **M3 MUST** Off-device target: fetch + poll ≤2s; "Finding message…" toast after 1s;
  fail → toast "Message not found in this chat" (never silent).
- [x] **M4 MUST** Search keeps persistent row tint PLUS the land flash.

## N. Dots menu + disappearing (S17)

- [x] **N1 MUST** Menu = Warm Pop sheet (radius 20, handle) with icons per row; Disappearing row
  shows current value trailing; group-only row absent in 1:1.
  **Verified pass 4 (2026-10-20):** menu awaits `getConversationById` and renders trailing from
  `_disappearingDurationLabel(row.disappearingDuration)`; sheet uses `WarmPopTokens.radiusLg`
  (20). Live (emulator): trailing renders "Off" on an actually-Off conv; write path updates
  PocketBase + local row so the read sees truth.
- [x] **N2 MUST** Disappearing dialog: checkmark on current selection (NEW), "Applies to new
  messages only" subtitle, tap-out cancel; confirm = snackbar "Disappearing: X".
  **Verified pass 4 (2026-10-20):** `selectedDuration` initializes from the persisted row; live
  emulator: checkmark lands on actual value, tap-out cancels cleanly. Real-app confirm pops +
  snackbars un-awaited. Note: Use-Fake smoke repo throws in the setter before pop (dialog stays
  open) — test-env only, fake-repo no-op queued to backlog.
- [x] **N3 MUST** All rows 48dp targets.

## O. Failure & offline (S18)

- [x] **O1 MUST** Offline strip above list: accentSoft + copy "You're offline — messages will send
  when you're back." + Retry; auto-clears 250ms on reconnect; composer never pushed.
- [x] **O2 MUST** Queued non-terminal failure = row banner + one-tap Retry; terminal = on-bubble
  error fill + warn tick + Retry/Delete (two surfaces distinct).
- [x] **O3 MUST** Copy rules from S18; no error codes in UI.

## P. Mascot (S19)

- [x] **P1 MUST** Placements ONLY: empty conv (neutral, 108), no-results (sleepy, 64),
  load error (key mood, 72) per matrix; never in bubbles/app-bar/loading/behind text.
- [x] **P2 MUST** Reduced-motion parks breathe/blink.
  **R3 fixed (2026-10-18):** load error now uses the 72dp key-mood Capybara with the existing
  retry surface.

## Q. A11y + motion (S20)

- [x] **Q1 MUST** Semantics labels on every icon-only control (back/search/dots/attach/send/mic/chevrons).
- [x] **Q2 MUST** Merged semantics per message row: sender + body/type + time + status.
  **R4 fixed (2026-10-18):** `MessageBubble` exposes one safe composed row label and excludes
  duplicate visual body/sender/timestamp semantics while retaining actionable child nodes.
- [x] **Q3 MUST** Contrast ≥4.5:1 body / ≥3:1 large, both themes (engine-verifiable pairs in S1).
- [x] **Q4 MUST** Reduced-motion: shimmer parks, dots/pulse freeze, highlight single fade, pops instant.
  **F8b fixed (review pass 5, 2026-10-21):** `_OptimisticSkeletonBox` now returns a static token
  surface under `disableAnimations`; normal motion retains `Shimmer.fromColors`. Covered for
  optimistic image/video/voice placeholders. F4 pop remains accepted deferred.
- [x] **Q5 MUST** font_scale 1.3 capture: no clipped app bar / ticks / chips.

  **Verified 2026-10-20:** `captures/chat-redmi-font-1.3.png` — post-floating-shell recapture on
  Redmi S2; app bar, bubble, ticks, composer unclipped. Dark twin `captures/chat-redmi-dark.png`
  also recaptured post-shell (floating composer on dark canvas, no seams).

## R. Test gates (mandatory re-run)

- [x] `test/message_body_text_loading_test.dart`
- [x] `test/pinned_message_banner_loading_test.dart`
- [x] `test/offline/placeholder_ui_test.dart`
- [x] `test/offline/read_paths_char_test.dart`
- [x] `test/offline/sealed_preview_test.dart`
- [x] `test/offline/tap_predecrypt_test.dart` (tap-down Listener law — do not touch)
- [x] `test/message_bubble_sender_test.dart` (update for run-grouping if structure changes)
- [x] `test/offline/message_menu_offline_widget_test.dart` (menu keys — update for Select row)
- [x] Full suite **258/258** · scoped analyze **0 issues**; full analyze has no errors but retains
  97 existing warnings/info outside the edited chat paths.

## S. Explicitly out of scope (do NOT build on this page)

Forward · Edit · message-info · voice waveform/scrub · GIF/sticker tray ·
typing-indicator broadcast · multi-attachment batch · video_player_screen.dart
cleanup · media-spinner-duration / emoji-tofu residuals (backlog §10) · tablet layout.

---

### Deferred decisions (user may override at review)

1. **Read-tick color (G1):** info-blue is a NEW semantic use of `info` — flagged, one-line revert if user prefers opacity-only.
2. **Reaction tap=toggle (F2)** changes a shipped interaction — flagged as deliberate (long-press still opens sheet).
3. **In-text search marks (B5)** are new ink — if Astra hits ripple effects, row-tint-only is an acceptable fallback (report, don't silently drop).
