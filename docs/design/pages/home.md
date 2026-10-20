# Home screen — acceptance checklist (Page 2)

Date: 2026-10-17. Visual ground truth: **`docs/design/pages/home.html`** (H1–H12).
Authority: `00-foundation.md` → `10-registry.md` → this checklist. Base mockup:
`docs/mockups/2026-10-05-home-chat.html` (approved light-Home frame).

**How Astra uses this:** MUST = implement or report not-done; SHOULD = stretch.
Deviations that break foundation C1–C4/L1–L4 = FAIL even if prettier.
**Pass criteria:** all MUSTs ✓ · `flutter analyze` 0 errors · suite green
(baseline **213/213** + listed gate updates) · light/dark captures on M52 · user PASS.

---

## §Laws (pinned — home.html cites these IDs)

- **L1 (P7):** previews derived at render via `ConversationPreviewText` — NEVER a stored
  `last_message_preview` (schema v11 removed it; reintroducing = plaintext-at-rest leak).
- **L2:** no-last-message fallback string is EXACTLY `'Tap to open chat'`.
- **L3:** non-text previews use EXACT constants: `📷 Photo` · `🎬 Video` · `🎤 Voice message` ·
  `📎 Document` · `📊 Poll` · `New message` (system+default).
- **L4:** unresolved text previews render keyed `ValueKey('body-placeholder-<messageId>')` —
  never blank, never ciphertext.
- **L5:** tile predecrypt fires on raw `Listener(onPointerDown)` (NOT GestureDetector.onTapDown —
  arena law), keep `unawaited(predecryptConversation)` + `[Msg] TAPDOWN` canary. a83e046 fix.
- **L6:** backup banner visibility = P6 tri-state: authenticated ∧ local key ∧
  `tryHasPocketBaseBackup() == false` strictly ∧ not dismissed ≤7d.
- **L7:** banner copy EXACT: `'Backup your encryption key to restore messages after reinstall. Tap to set up.'`;
  dismiss writes `backup_reminder_dismissed_at` + invalidate; tap → `AppRoutes.backupPinSetup`.
- **L8:** filter rules: unsynced DMs (otherUser null) hidden from Chats; friends with active DM
  excluded from Friends.
- **L9:** branch contract: RefreshIndicator → invalidate conversations; loading → skeleton (anatomy
  upgraded by H11 but trigger law stands); error branch retry-invalidates conversations + friendships;
  empty → `No chats yet` + Add-Friend CTA; friends-loading gate holds empty only when
  `friendsAsync.isLoading && !hasRenderableConversations`.
- **L10:** `home_screen.dart`/`add_friend_screen.dart` free of raw hex/`AppColors`/banned purples
  (grep_gates_test).
- **L11:** nav contract: title `Kuch Bhi`; requests icon → /friend-requests; avatar → /profile;
  FAB tooltip `New chat` → sheet rows `Add Friend`/`New Group`; friend-open failure snackbar
  `'Chat is not ready yet. Try again in a moment.'`.
- **L12:** time format: today `HH:mm` · yesterday `Yesterday` · <7d `EEE` · else `dd/MM`.

## A. App bar (H4)

- [x] **A1 MUST** Requests badge: raw 1–99, pill `99+` at ≥100 (new clamp); 2px bg ring; no
  0-badge flash while count loads (hold hidden until first true value).
- [x] **A2 MUST** Badge Semantics: “{n} pending requests” / “No pending requests”.
- [x] **A3 MUST** Profile avatar: accentSoft/photo, pressed accent ring (new), tap → /profile,
  48dp, Semantics “Your profile”; unified into R1 `AppAvatar` via optional flag (registry amendment).
- [x] **A4 MUST** Title 21/800 static; bar bg = page bg, no elevation line (chat S4 language).

## B. Search (H5)

- [x] **B1 MUST** Pill always visible, closed state copy “Search chats”, 42dp radius 999 (mockup).
- [x] **B2 MUST** Focus = accent 1.5px border; typing = live in-memory filter; ✕ clears + refocuses
  (only when text present).
- [x] **B3 MUST** Filter = case-insensitive substring over conversation names + friend names ONLY
  (never previews — decrypt coupling forbidden); both sections filtered in place; counts update;
  empty sections collapse.
- [x] **B4 MUST** No-results: per-section “No {section} match ‘{q}’.” lines; both-empty → single line,
  NO mascot (mascot = zero-data only).
- [x] **B5 MUST** Clear restores scroll position; ephemeral (never persisted); FAB hides while focused.
- [x] **B6 MUST** No match-highlight marks on home (chat owns mark language).

## C. List structure (H6)

- [x] **C1 MUST** Section headers with live count pills; counts follow search; sections collapse when empty.
- [x] **C2 MUST** Filter laws L8 intact (no person in both sections).
- [x] **C3 MUST** Pinned rows: 12px pin glyph (inkFaint) before name; DB order unchanged
  (is_pinned DESC, last_message_at DESC); NO pinned sub-header.
- [x] **C4 MUST** Time rules L12 intact.
- [x] **C5 SHOULD** Time adds year when date ≠ current year.

## D. Tile anatomy (H7)

- [x] **D1 MUST** One ChatTile, four faces (DM/group/friend/unread) per H7 specimens; tile surface
  radius 16 pad 10/12, ripple press (existing).
- [x] **D2 MUST** Avatar corner slots mutually exclusive: group glyph (bg disc + accent glyph) OR
  presence dot (success + 2.5px surface ring) — presence dot NEW, null-safe (no dot when unknown).
- [x] **D3 MUST** Name rules + fallbacks unchanged (Group/Unknown/?).
- [x] **D4 MUST** Preview laws L1–L4 intact (derived, exact constants, exact fallback, placeholder key).
- [x] **D5 MUST** Group sender prefix NEW: “{Name}: {derived}” (own = “you:”); sibling Text BEFORE
  preview widget — placeholder keys untouched; 1:1 never prefixed.
  **Verified pass 4 (2026-10-20):** prefix is `Flexible(flex: 1, loose)` + `maxLines: 1` +
  ellipsis, preview `Expanded` — no `flex: 0` remains anywhere; long names ellipsize, preview
  never collapses to zero width. **Residual SHOULD:** no covering regression test for the bound.
- [x] **D6 MUST** Unread triple signal: preview ink+600 · time accent+700 · AppBadge accent;
  badge clamp `99+` (R2 amendment — same fix in app-bar badge).
- [x] **D7 MUST** Friend face copy unchanged: “Online” (success) / “Tap to start chatting” (inkSoft).
- [x] **D8 MUST** Long-press wired → E1 sheet; tap opens chat; Listener predecrypt law L5 untouched
  (NO GestureDetector.onTapDown anywhere near the tile).

## E. Conversation long-press sheet (H8)

- [x] **E1 MUST** Sheet = shared C4 chrome (handle, header avatar+name+preview, 13.5/600 rows, 48dp,
  haptic on open) — ONE widget with action-list param (registry C4 variant recorded).
- [x] **E2 MUST** Actions: Pin conversation (trailing current state On/Off) · Mark as read (only when
  unread>0) · Conversation info (group → Group Settings, 1:1 → peer profile).
- [x] **E3 MUST** Pin toggle: wire orphaned `setPinned` + immediate sort-to-top + snackbar
  “Pinned”/“Unpinned”.
- [x] **E4 MUST** Mute/Delete/Archive/Select NOT present (data absent — declared in H8 table).

## F. FAB + new-chat sheet (H9)

- [x] **F1 MUST** Single FAB 56dp radius 16 accent, tooltip “New chat”, press scale 0.96/150ms;
  hides while search focused; visible on empty state.
- [x] **F2 MUST** Sheet restyled to shared language (20px top, handle, existing rows/icons/nav) —
  no new rows.

## G. Backup banner (H10)

- [x] **G1 MUST** Copy EXACT (L7) · visibility gate unchanged (L6) · dismiss write + invalidate (L7).
- [x] **G2 MUST** Whole-strip tap → /backup-pin/setup (new target; only ✕ excluded).
- [x] **G3 MUST** No flash-in: hold hidden until provider first true value.
- [x] **G4 MUST** Placement above search pill; exits 250ms fade; no reserved gap.

## H. Body states + refresh (H3/H11)

- [x] **H1 MUST** Skeleton anatomy NEW: 40px circle + name bar + preview bar per row + header bar,
  4 rows, shimmer 1.4s (R11 parks reduced-motion); trigger law L9 unchanged; instant swap to content.
- [x] **H2 MUST** Error state: mascot(key mood) + “Couldn’t load your chats” + “Check your connection
  and try again.” + Retry (invalidates both providers per L9). <b>Flagged:</b> replaces
  `StatusBanner('Could not load your chats.')` — update any test pinning the old string.
- [x] **H3 MUST** Offline strip = chat S18 copy verbatim + Retry; above error block when both;
  clears 250ms on reconnect.
- [x] **H4 MUST** Empty state: AlwaysScrollableScrollPhysics (pull-to-refresh reachable — new fix);
  copy kept: “No chats yet” / “Add friends to start chatting.” / CTA “Add a Friend” → AddFriendSheet;
  mascot 130 neutral.
- [x] **H5 MUST** Pull-to-refresh: accent-colored spinner; invalidates conversations AND
  friendships (new); failed refresh silent.
- [x] **H6 SHOULD** Partial-failure inline mini StatusBanner above Friends (friends error, chats OK).
  Verified pass 4: `friendsHasError` reachable with data present (was unreachable dead code).
- [ ] **H7 SHOULD** ListView → ListView.builder with item keys; pin toggle animates row move 250ms;
  no per-tile async on build (W3 frame rule).

## I. A11y (H12)

- [x] **I1 MUST** Semantics labels on all icon-only controls + merged tile label
  (“{name}, {preview|Online}, {time}, {n} unread, pinned”).
- [x] **I2 MUST** Contrast checks: accent time/badge both themes; “Online” success subtitle —
  engine verify ≥4.5:1 (w600 13px); if fails → fallback inkSoft text + keep success dot only
  (report which path taken).
- [x] **I3 MUST** Reduced-motion: shimmer parks, pin move instant, banner fade instant.
- [x] **I4 MUST** font_scale 1.3 capture: title/badges/pill unclipped.
  Verified 2026-10-20 on Redmi S2: `captures/home-redmi-font-1.3.png` — app bar, badges,
  search pill unclipped.

## Test gates (mandatory re-run)

- `test/chat_tile_test.dart` (tile structure — update if ListTile internals change)
- `test/offline/read_paths_char_test.dart` (real HomeScreen boot + placeholder keys)
- `test/offline/placeholder_ui_test.dart` (preview slot metrics/fallback)
- `test/offline/sealed_preview_test.dart` (P7 derivation)
- `test/offline/tap_predecrypt_test.dart` (repo contract — plus MANUAL check Listener still fires:
  this wiring has NO widget test, grep it in review)
- `test/offline/use_fakes_boot_test.dart` (fake-seam boot)
- `test/grep_gates_test.dart` (no raw hex — L10)
- `test/offline/encryption_sync_offline_test.dart` (P6 banner tri-state — L6)
- `test/message_body_text_loading_test.dart` (shared #body machine)
- Full suite ≥213/213 · analyze 0 errors.

## Out of scope (do NOT build here)

Mute · Delete/Archive conversation · tile select mode · swipe actions · invite-link/
share-profile sheet rows · sticky headers · collapse-on-scroll bar · FAB badge ·
AddFriendSheet internals (page 8) · non-text preview sender prefixes.

---

### Deferred decisions (flag for review)

1. **Error copy change (H2):** “Could not load your chats.” → “Couldn’t load your chats.” + mascot
   — test pin expected to update; revert possible if you want zero copy churn.
2. **“Online” contrast (I2):** success green may fail 4.5:1 on white at 13px — fallback path
   pre-approved (inkSoft text + dot).
3. **Presence dot (D2):** driven by `Conversation.isOnline` freshness — if stale on device,
   downgrade to Friends-only (report at review).
4. **Group “you:” prefix (D5):** copy choice — “you:” vs “You:” (lowercase shown in H7; one-word change).
