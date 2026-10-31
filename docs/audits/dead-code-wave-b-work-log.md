# Dead-code wave B — work log

Audit: `docs/audits/2026-10-30-dead-code.md` **§2 only** (§1/§3 = wave A, committed as
`78d121e`). Base: `78d121e` on `main` (741/741 green). Work done **on top of `main`, not
committed** (per instructions).

**Method.** Every §2 site was re-checked against today's tree before editing (`trail grep`,
`trail callers`, plain `grep -rn` over `lib/` + `test/`, `flutter analyze`). The audit is
static and predates bug wave 2, wave A *and* commit `335b5d5` (recovery key replaces the
6-digit PIN), so several of its line numbers and one whole item no longer matched — those
are marked **skipped** below with the reason. Nothing outside the item list was touched.

**PASS/grade is left to Claude; not claimed here.**

---

## 1. Item-by-item

| # | Item | Status | Detail — files touched / why skipped |
|---|---|---|---|
| 1 | R1/R1a/R1b initials + `AppAvatar` | **done** | Every hand-rolled "trim → first char → upper" now calls `initialsOf`. Deleted 6 private helpers: `home_screen._initials`, `message_context_menu._initialsFor`, `request_card._initials`, `group_invite_card._initials`, `group_settings._initial`, `create_group._initial` + `_letter` (22 `initialsOf` call sites now, 0 hand derivations left in `lib/features`). Removed the **empty-name `RangeError`** at `chat_screen` (`conv.displayName.substring(0,1)` ×2) and `message_bubble` (`trimmedName.substring(0,1)`). Hand-built avatars → `AppAvatar` at **radius kept**: `chat_screen` ×2 (18, `accentSoft`), `message_bubble` ×1 (14), `create_group` ×1 (48, now `AppAvatar(image: FileImage(...))` — the R1a shape). `media_docs` ×2 were *icon discs, not avatars*: converted to plain 40px `Container` circles (pixel-identical) rather than forced through R1, so `CircleAvatar(` is gone from `lib/features` without inventing an avatar contract. |
| 1 | — `chat_tile._initials` | **skipped (deliberate)** | Not on the audit's R1 list, and it is a *different* algorithm (two-letter monogram: `"John Doe" → "JD"`), which `initialsOf` (first char only) cannot reproduce. Routing it would change every chat-list avatar. Left alone. |
| 2 | R3a `BusySpinner` | **done (8 per-row sites)** | `delivery_tick` (13px), `message_bubble` ×2 (30px / 18px), `voice_message_bubble` (16px), `document_message_bubble` (20px), `message_input` ×3 (18px send ×2, 16px voice). **Size, stroke width and ring tint kept per site** via a new optional `color` slot on `BusySpinner` (see §3.1) — without it the two send-button rings would have become accent-on-accent and disappeared. **6 loaders left as they are** because the item scopes them out ("full-screen/page loaders stay as they are"): `starred_messages` ×2 and `media_docs` ×4, all un-tinted `Center(child: CircularProgressIndicator())` page/section loaders — which is how the audit itself groups them ("four `Center(child: CircularProgressIndicator())` page loaders"). |
| 3 | R5 `showToast` | **done (13 sites)** | `home_screen` ×5, `chat_screen` ×3, `message_input` ×5. Message text carried **character-for-character**; `error: true` only where the old message was a failure ("Chat is not ready yet…", "Couldn't update pin.", "Couldn't mark chat as read.", "Message not found in this chat" ×2, "Microphone permission denied", "Could not start recording", "Could not save voice message"). `grep 'SnackBar(' lib/` now returns **only** `app_toast.dart`. |
| 4 | R11 `Skeleton` fill + de-Shimmer | **done (5 sites)** | Added `Skeleton.fill` (§3.2). Replaced `Shimmer.fromColors` in `message_bubble`, `image_message_bubble`, `video_message_bubble`, `document_message_bubble`, `media_docs_screen`. `grep Shimmer lib/` now hits only `skeleton.dart`. The `package:shimmer` import left `lib/` entirely; the `shimmer:` dependency stays in `pubspec.yaml` (it is still the one implementation `Skeleton.fill` rides on — see §3.2). |
| 5 | R14 `pageAppBar` | **done (5 of 6 bars)** | `friend_requests`, `group_settings` (the registry's own "moving onto it = SHOULD"), `create_group`, `starred_messages`, `media_docs`. `home_screen` **kept its own bar** (item scope). `pageAppBar` gained two pass-through slots, `leading` and `bottom`, because two of the five can't fit the plain bar (New group's back affordance, Media & Docs' `TabBar`) — recorded on the R14 row. |
| 6 | R20 hand-rolled "Start Fresh?" confirm | **skipped — no longer matches (and frozen)** | The audited `_showForgotPinDialog` (`backup_pin_screen.dart:331-354`) **does not exist any more**: `grep -rn 'showDialog(' lib/features` → 0 hits, `grep -rni 'start fresh?'` → one hit only, `backup_pin_screen.dart:445`, and it is already `showConfirmDialog(context:, title: 'Start fresh?', body: …, confirmLabel: 'Start fresh', confirmIcon: Icons.warning_amber_rounded, destructive: true)` inside `_lostIt()` — routed in `335b5d5`. The screen is also frozen (key/backup/restore). Nothing to do; nothing touched. |
| 7 | T1 `WarmPopTokens.cardShadow` | **done (4) + 3 skipped** | Converted: `chat_screen` in-search bar (12/4 → 8/2), `pinned_message_banner` (10/3 → 8/2), `message_input` floating panel (14/4 → 8/2), `starred_messages` card (8/2 → **identical**). Kept: `chat/widgets/expiry_badge.dart:87` `ChatBubbleGeometry.shadow` (chat-bubble frame spec piece — "chat bubbles keep theirs"), `message_input:727` (a *button glow* whose colour is `backgroundColor@24%`, not a card layer and not `t.shadow` — the audit never listed it), `backup_pin_screen:1107` (frozen key screen). |
| 8 | T2 `colorScheme.` → `context.t.*` | **done (12 sites) + 2 skips** | Mechanical, exact-value mapping (`onSurface`→`t.ink`, `surfaceContainerHighest`→`t.surface2`, `surface`→`t.surface`) across `message_body_text` ×1, `message_bubble` ×2, `voice_message_bubble` ×1, `document_message_bubble` ×2, `starred_messages` ×6 — `colorScheme` is an alias built from `ColorTokens`, so these are the *same* colours. Plus the one raw overlay with a real token: `reaction_bar`'s other-side chip tint `Colors.white@12%`/`Colors.black@7%` → `t.ink` at the same alphas. |
| 8 | D4 skip | **skipped (logged)** | `lib/features/auth/screens/backup_pin_screen.dart` (recovery-key setup / change / restore — the whole key backup-restore flow) is listed as an explicit exception **inside the new T2 gate**. It has **0** `colorScheme.` uses today anyway; its remaining raw colour constants (`WarmPopTokens.ink` ×2, `inkSoftDark` ×1, `shadowDark`) are untouched. |
| 8 | raw media scrims | **skipped — no matching token** | `video_message_bubble` ×2 (`Colors.black@.55` / `@.45` duration chrome), `media_docs` ×2 (play disc + duration chip), `chat/widgets/expiry_badge` ×2 (timestamp pill `black@.55`, overlay text `white@.66`), plus their white glyphs. These sit **on top of a photo/video**, where the token set has no equivalent: `t.bg` is near-white in light and pure black in AMOLED, `t.ink` inverts with the theme — swapping either would flip the scrim or kill the contrast. The audit's own "one line" fix only gives a mapping for `colorScheme.*`, so these stay neutral by design. |
| 9 | `PhotoPickerBadge` + R21 | **done (4 sites + registry row)** | New `lib/core/widgets/photo_picker_badge.dart`; used at `google_onboarding_screen`, `edit_profile_screen`, `create_group_screen`, `group_settings_screen`. Disc, ring and glyph are the existing 32 / 2px `t.bg` / 16px camera — **each call site keeps its own `Positioned`** (`right:0,bottom:0` on the two profile pages, `right:2,bottom:2` on the two group pages) and its own outer `Semantics`/`GestureDetector`, so position and disabled states are unchanged. `onTap` is required and nullable, wired to the same conditional the outer wrapper already used (`_busy ? null : _pickAvatar`, `_pickImage`, `_creating ? null : _pickIcon`, `photoLive ? _pickPhoto : null`). Row **R21** added to `docs/design/10-registry.md`. |
| 10 | R8 Home pill note | **done (registry only)** | No code change. One row added directly under R8. |
| 11 | gate title rename | **done (1 line, title only)** | `test/grep_gates_test.dart` Gate 10: `media docs screen + expiry badge carry no raw grey/alpha-white chrome` → `media docs screen carries no raw grey/alpha-white chrome`. The scan target list was already correct (wave A removed the deleted file); body untouched. |

**Frozen areas — verified untouched** (`git diff --stat` contains none of them):
`lib/infrastructure/`, `lib/services/`, `lib/features/chat/providers/`, the outbox
(`lib/infrastructure/offline/outbox*`), `lib/features/auth/screens/backup_pin_screen.dart`
and every key/backup/restore path. No `ref` added to any `dispose()` (existing gate 7 still
green). No copy, navigation or behaviour changed beyond the visible restyles in §4.
`pubspec.yaml` untouched.

---

## 2. New grep gates — RED → GREEN

Five gates appended to `main()` in `test/grep_gates_test.dart`. Each was proved **RED on the
pre-wave tree** by snapshotting `lib/` to `/tmp`, `git checkout -- lib` (back to `78d121e`),
running the *same* test file, then restoring the snapshot byte-for-byte (`diff -rq` verified
both ways) and running again.

### RED — `flutter test test/grep_gates_test.dart --reporter expanded` on `78d121e`

```
00:00 +28 -1: R5: no ScaffoldMessenger…showSnackBar in lib outside app_toast.dart [E]
  Expected: empty
    Actual: [
              'lib/features/home/screens/home_screen.dart: ScaffoldMessenger…showSnackBar',
              'lib/features/chat/screens/chat_screen.dart: ScaffoldMessenger…showSnackBar',
              'lib/features/chat/widgets/message_input.dart: ScaffoldMessenger…showSnackBar'
            ]
  every snackbar goes through R5 showToast(): [lib/features/home/screens/home_screen.dart: ScaffoldMessenger…showSnackBar, lib/features/chat/screens/chat_screen.dart: ScaffoldMessenger…showSnackBar, lib/features/chat/widgets/message_input.dart: ScaffoldMessenger…showSnackBar]

00:00 +28 -2: R11: no Shimmer.fromColors in lib outside skeleton.dart [E]
  Expected: empty
    Actual: [
              'lib/features/chat/widgets/document_message_bubble.dart',
              'lib/features/chat/widgets/image_message_bubble.dart',
              'lib/features/chat/widgets/message_bubble.dart',
              'lib/features/chat/widgets/video_message_bubble.dart',
              'lib/features/media/screens/media_docs_screen.dart'
            ]

00:00 +28 -3: R1/R1a: no CircleAvatar( in lib/features (avatars go through AppAvatar) [E]
  Expected: empty
    Actual: [
              'lib/features/chat/screens/chat_screen.dart',
              'lib/features/chat/widgets/message_bubble.dart',
              'lib/features/media/screens/media_docs_screen.dart',
              'lib/features/groups/screens/create_group_screen.dart'
            ]

00:00 +28 -4: R14: no AppBar( in lib/features except lib/features/home/ [E]
  Expected: empty
    Actual: [
              'lib/features/starred_messages/screens/starred_messages_screen.dart',
              'lib/features/friend_requests/screens/friend_requests_screen.dart',
              'lib/features/media/screens/media_docs_screen.dart',
              'lib/features/groups/screens/create_group_screen.dart',
              'lib/features/groups/screens/group_settings_screen.dart'
            ]

00:00 +28 -5: T2: no colorScheme. in lib/features outside the D4-skipped files [E]
  Expected: empty
    Actual: [
              'lib/features/chat/widgets/document_message_bubble.dart',
              'lib/features/chat/widgets/message_body_text.dart',
              'lib/features/chat/widgets/message_bubble.dart',
              'lib/features/chat/widgets/voice_message_bubble.dart',
              'lib/features/starred_messages/screens/starred_messages_screen.dart'
            ]

00:00 +28 -5: Some tests failed.

Failing tests:
  …grep_gates_test.dart: R1/R1a: no CircleAvatar( in lib/features (avatars go through AppAvatar)
  …grep_gates_test.dart: R11: no Shimmer.fromColors in lib outside skeleton.dart
  …grep_gates_test.dart: R14: no AppBar( in lib/features except lib/features/home/
  …grep_gates_test.dart: R5: no ScaffoldMessenger…showSnackBar in lib outside app_toast.dart
  …grep_gates_test.dart: T2: no colorScheme. in lib/features outside the D4-skipped files
```

All **28 pre-existing** gates were still green on that same run (`+28` before the first
failure), so the RED is caused by the unrouted `lib/` only.

### GREEN — same file on the routed tree

```
00:00 +28: bug wave 2: no raw exception reaches the screen; media reloads
00:00 +29: R5: no ScaffoldMessenger…showSnackBar in lib outside app_toast.dart
00:00 +30: R11: no Shimmer.fromColors in lib outside skeleton.dart
00:00 +31: R1/R1a: no CircleAvatar( in lib/features (avatars go through AppAvatar)
00:00 +32: R14: no AppBar( in lib/features except lib/features/home/
00:00 +33: T2: no colorScheme. in lib/features outside the D4-skipped files
00:00 +33: All tests passed!
```

The D4 exceptions are listed **inside** the T2 gate:

```dart
// Decision D4: the key backup/restore flow keeps its own colours.
const d4Exceptions = <String>[
  'lib/features/auth/screens/backup_pin_screen.dart',
];
```

---

## 3. Judgement calls (for the grader)

### 3.1 `BusySpinner` gained an optional `color` slot

The item says the per-row *tinted* rings become `BusySpinner()`. `BusySpinner` renders
`CircularProgressIndicator` with no colour, which resolves to `colorScheme.primary` = `t.accent`
(`app_theme.dart:35`). Two of the eight sites are tinted **`t.onAccent` on an accent-filled
disc** (`message_input` send button, ×2): routing them literally would have painted an accent
ring on an accent disc — an invisible spinner, i.e. a behaviour regression the item didn't ask
for. So `color` was added (default `null` = the accent default, so every default caller is
unchanged) and each site passes the tint it had. The slot is recorded on the R3a registry row.
This also keeps the item's "keep each site's size" rule: `size:` is passed everywhere (13 / 16 /
18 / 20 / 30) instead of collapsing to 18.

### 3.2 `Skeleton.fill` paints through `Shimmer.fromColors` — and why it must

`test/chat/media_link_widgets_test.dart` asserts `find.byType(Shimmer)` **findsOneWidget** with
animations on and **findsNothing** under reduced motion, for the image, video and voice loading
paths — i.e. for exactly the sites item 4 routes through `Skeleton`. That test may not be
edited, so `Skeleton.fill` builds a real `Shimmer.fromColors(baseColor: t.surface2,
highlightColor: t.line)` when motion is on and drops out of the tree entirely when it is off.
This is also why the new gate carves `skeleton.dart` out of its own ban.

The **default** `Skeleton` was left byte-identical (its own ticker, `Color.lerp(surface2→line)`
pulse) — `test/widgets_batch2_test.dart` pins that controller's restart/park behaviour
(`hasRunningAnimations` on a `duration:` change), and nothing in the item asks for the
existing loading blocks (Home, Profile, Requests, Groups, About, reaction bar) to change their
motion. So the file now holds two shapes with one palette: the pulsing fixed block and the
sweeping fill.

### 3.3 Other calls

1. **Item 6 skipped as stale, not as frozen** — the confirm it names already routes through
   R20 (commit `335b5d5`). It is *also* inside the frozen key screen, but the stale reading is
   the primary reason there is nothing to do.
2. **`CircleAvatar` icon discs** (`media_docs` voice/doc rows): "leave non-avatar circles
   alone" vs the unqualified gate `no CircleAvatar( in lib/features`. Resolved by moving the
   *disc* to an identical `Container` circle — the circle is not turned into an avatar, and the
   gate goes green. Pixel-identical, logged as no visible change.
3. **`chat_tile._initials` kept** (see item 1) — different algorithm, not an audit site.
4. **`pageAppBar` extended with `leading` / `bottom`** — without them two of the five bars
   physically cannot move onto R14. Both are optional pass-throughs; every existing caller is
   unaffected (`leading: null` / `bottom: null` are the defaults). Recorded on the R14 row.
5. **Registry amendments** made alongside R21 and the R8 note, because the wave changed shared
   pieces and the registry is the source of truth: R3a (`color?`), R11 (`Skeleton.fill`), R14
   (`leading`, `bottom`). No other rows or files in `docs/` changed.
6. **`chat_screen` header avatar** — R1 computes its foreground with
   `_readableAccentForeground(accentSoft)` (contrast-picked) and its size as `radius × 0.75`,
   so the two hand-built header avatars change letter colour and move 14px → 13.5px. That is
   the cost of item 1's "every hand-built CircleAvatar that is an avatar → AppAvatar";
   it also fixes the old amber-on-pale-amber contrast. Logged in §4.
7. **`Hold to record` toast** — the old snackbar carried `duration: 1s`; `showToast` is
   always 3s and exposes no duration. Message text kept exactly; only the lifetime changed.
8. **`shimmer:` stays in `pubspec.yaml`** — `Skeleton.fill` still depends on it, so it is not
   dead. `pubspec.yaml` was out of scope anyway.

---

## 4. Visible changes (check each on the phone, light / dark / AMOLED)

| Screen | What looks different |
|---|---|
| **Home** | Pin / mark-read / "Chat is not ready yet…" messages now arrive as the Warm Pop floating toast — rounded, 1px line border, 3s, and failures get a red stripe + ⓘ icon — instead of the default Material snackbar; a new toast now **clears** the previous one instead of stacking. Profile-button initials: an *empty* display name shows **K** instead of **?** (every other input is unchanged). |
| **Chat** | Header avatar (1:1 and group): letter is now R1's contrast-picked colour on accent-soft (dark ink in light, cream in dark) instead of amber accent, and 13.5px instead of 14px; a failed avatar image now falls back to initials instead of an empty disc. In-chat search bar shadow softens: blur 12 → 8, y-offset 4 → 2. "Finding message…" and the two "Message not found in this chat" messages take the toast chrome (the failures also gain the red error stripe). |
| **Chat — group bubbles** | Sender-initial disc is now an R1 `AppAvatar`: letter 11px → 10.5px (radius 14 × 0.75); same `surface2` disc, same exclusion from semantics. |
| **Chat — sending / upload rows** | The per-row rings keep their exact size and colour (30px + 18px upload, 20px doc download, 16px voice play, 13px delivery tick, 16px composer voice, 18px composer send) but now **park as a static surface2 ring under reduced motion** instead of spinning. |
| **Chat — optimistic upload bar** | The little progress bar beside the upload ring went from **accent-tinted** (accent @16%/30%) to the neutral **surface2 ↔ line** shimmer. |
| **Chat — image / video / document placeholders** | Same colours, same size, square corners preserved. The shimmer sweep now runs at **1200 ms** (R11's duration) instead of the package default 1500 ms, and the document placeholder sweeps surface2 → line instead of line → surface2. Under reduced motion there is no shimmer widget in the tree at all — same as before. |
| **Chat — reaction chips** | Other-side chip tint is now `t.ink` @7% (light) / @12% (dark) instead of raw black/white at the same alphas — effectively identical. |
| **Chat — message text** | `colorScheme.onSurface` → `t.ink` — identical values by construction, **no visible change**. |
| **Pinned banner** | Shadow tightens: blur 10 → 8, y-offset 3 → 2. |
| **Composer** | Attach / preview floating panel shadow softens: blur 14 → 8, y-offset 4 → 2. The mic/send accent glow is untouched. |
| **Requests** | App bar title line-height 1.4 → 1.3 (R14's 20/26 w700 ink); the bar was already on `t.bg`, so that is the only delta. |
| **Group Info** | Camera badge glyph is now `Icons.camera_alt_outlined` (matches the other three screens; it was `Icons.camera_alt`). Bar and member-list rings unchanged — the bar already matched R14 exactly and the member row already used `BusySpinner`. |
| **New group** | No visible change: bar chrome is identical through R14, badge identical, and the file-image avatar renders the same 48px accent-soft disc via `AppAvatar(image:)`. |
| **Starred messages** | App bar is now R14: **page-coloured** bar (was Material's default `t.surface` band) with a 20/26 w700 ink title (was the theme's default AppBar title style). Card surface and shadow are identical (8/2 either way). Empty-state icon and captions now read `t.ink` at the same alphas — same values. |
| **Media & Docs** | App bar is now R14: **page-coloured** bar with a 20/26 w700 ink title (was a default Material bar); the TabBar row is unchanged. Voice/Doc row leading discs are plain 40px circles — pixel-identical. Thumbnail shimmer 1500 ms → 1200 ms, base/highlight normalised to surface2 → line. |
| **Google onboarding / Edit profile** | No visible change — the badge is pixel-identical (32px accent disc, 2px `t.bg` ring, 16px outlined camera) and sits where it did. |
| **Every screen, reduced-motion on** | Loading rings and media shimmer blocks now park instead of animating (R3a / R11). |

---

## 5. Gates run by this wave (output verbatim)

- **`flutter test`** → `00:32 +746: All tests passed!` — **746/746 = 741 + the 5 new
  gates**. No existing test was edited except the single Gate-10 title rename in item 11
  (`git diff --numstat -- test/` → `85 1  test/grep_gates_test.dart`: 1 removed line = that
  title, 85 added = new gates).
- **`flutter analyze`** → `82 issues found. (ran in 2.5s)`, **0 errors, 0 warnings introduced**.
  Composition is `64 info + 18 warning` = 82, matching the wave-A baseline count. Swept every
  file in `git diff --name-only` against the report: the only hits are the pre-existing
  `create_group_screen.dart` deprecation/`use_build_context_synchronously` infos and two
  `unnecessary_non_null_assertion` warnings on `createdConversationId!` (lines 343/349 —
  outside every hunk of this wave; only line numbers shifted). All 18 warnings are in
  `lib/infrastructure/repositories/*` and `create_group_screen.dart`, all pre-existing.
- **`git diff --check`** → `exit=0`, clean (one `new blank line at EOF` in `request_card.dart`
  was caught by this gate and fixed before the final run).
- **`git diff --stat`** → 26 files, +320 / −444:

```
 docs/design/10-registry.md                         |  8 +-
 lib/core/widgets/busy_spinner.dart                 | 15 +++-
 lib/core/widgets/page_app_bar.dart                 |  8 ++
 lib/core/widgets/skeleton.dart                     | 72 +++++++++++++++---
 .../auth/screens/google_onboarding_screen.dart     | 13 +---
 lib/features/chat/screens/chat_screen.dart         | 63 ++++------------
 lib/features/chat/widgets/delivery_tick.dart       |  6 +-
 .../chat/widgets/document_message_bubble.dart      | 31 +++-----
 .../chat/widgets/image_message_bubble.dart         | 23 ++----
 lib/features/chat/widgets/message_body_text.dart   |  2 +-
 .../chat/widgets/message_bubble.dart               | 74 +++----------------
 .../chat/widgets/message_context_menu.dart         |  9 +--
 .../chat/widgets/message_input.dart                | 62 ++++------------
 .../chat/widgets/pinned_message_banner.dart        |  8 +-
 .../chat/widgets/video_message_bubble.dart         |  9 +--
 .../chat/widgets/voice_message_bubble.dart         | 17 ++---
 .../screens/friend_requests_screen.dart            | 20 +----
 .../friend_requests/widgets/group_invite_card.dart |  7 +-
 .../friend_requests/widgets/request_card.dart      |  7 +-
 .../groups/screens/create_group_screen.dart        | 65 ++++------------
 .../groups/screens/group_settings_screen.dart      | 49 +++---------
 lib/features/home/screens/home_screen.dart         | 32 ++------
 lib/features/media/screens/media_docs_screen.dart  | 33 +++++++---
 .../profile/screens/edit_profile_screen.dart       | 13 +---
 .../screens/starred_messages_screen.dart           | 32 ++++++------
 test/grep_gates_test.dart                          | 86 +++++++++++++++++++++-
 26 files changed, 320 insertions(+), 444 deletions(-)
```

Plus one **new** file (untracked, so it does not appear in `git diff --stat`):
`lib/core/widgets/photo_picker_badge.dart`.

Every file above maps to an item in §1: registry → items 9/10 (+ the §3.5 amendments),
`busy_spinner`/`skeleton`/`page_app_bar` → items 2/4/5, the 21 feature files → items 1/2/3/4/5/7/8/9,
`grep_gates_test.dart` → item 11 + the new gates. **No frozen path is present.**

Nothing was committed.

## 6. Follow-up after the user's device check (Claude, 2026-10-31)

User reported three things on the device. All three were older than wave B; fixed here and checked
on the M52 (debug run + adb taps), not yet re-checked by the user.

| Report | Cause | Fix |
|---|---|---|
| Group sender disc stuck to the screen edge | The disc sat outside the bubble's own 12dp near margin (x = 0), then an 8dp gap + the bubble's 12dp margin | `message_bubble.dart`: disc slot padded `left: nearMargin, bottom: verticalMargin`; the extra 8dp gap removed (the bubble's margin is the gap). Test `test/chat/group_sender_disc_test.dart`: disc x = 12, RED at x = 0 without the pad |
| Tapping the mic shows nothing | The mic had no tap handler (hold only); the hint fired only on a hold released under 1s. A toast would also cover the composer and the mic | `message_input.dart`: `_ComposerAction.tapHint` → the mic's Tooltip says "Hold to record" on a tap (above the button), plus a semantics hint. Tests `test/chat/mic_hint_test.dart` (2), RED without the hint |
| Search: hard to tell the current match; lands above/below the screen | (1) Bodies were read with `ref.read(messageBodyProvider(id).future)` on an auto-disposed provider with no listener: an uncached body's provider was dropped and its future never completed, so the scan stalled (Avium "hi" = 0/0). (2) The up arrow called `_prevMatch`, which goes NEWER (matches are newest-first) and wraps to the oldest. (3) Off-screen targets: a 400ms estimate scroll, then `ensureVisible` on the next frame, before the target was built, so it stopped at the estimate. (4) Current match tint 8% vs 4% | `chat_screen.dart`: `_resolveSearchBody` holds the provider with `listenManual` while waiting, 2s cap per body; up = older, down = newer, tooltips "Older match" / "Newer match"; one `_scrollToFlatIndex` (estimate jump, then step a screen at a time until the target is built, then centre; reduced motion = no animation), used by search and reply/star/pin jumps; the flash runs after the scroll lands; current match 20%, others 5%. Device: Avium "hi" = 1/17, up → 2/17 → 3/17, each centred with the strong band. No widget test for the screen's search (no ChatScreen harness); covered by the device run |

Gates: `flutter test` 749/749 (746 + 3), `flutter analyze` 0 errors, `git diff --check` clean. `trail check`:
backlog.md:240 and 10-registry.md:32, both word matches (albums; app bar vs progress bar).
