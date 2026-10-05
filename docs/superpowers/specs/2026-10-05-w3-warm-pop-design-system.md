# W3 — Warm Pop Design System & UI Overhaul (Spec)

Date: 2026-10-05. Direction approved live on the concept board
(`127.0.0.1:8791/concept-board.html` during the session; board source in job
tmp + reference art in `docs/Capybara.png`, `docs/Bear to Capybara Design Comparison.png`).

## Locked decisions

- **Design language:** Pop-forward structure, Warm Pop execution — bright warm
  surfaces, vivid accent used generously, soft sticker radii, springy-but-
  restrained motion. Daily-use calm over loudness (user choice after A/B).
- **Mascot:** Capybara ("chill guardian"), 2D flat vector, side-profile loaf
  with dark snout block. Art approved in three iterations (see references).
- **Accent:** Marigold `#EFA00B`. No violet, no purple, no gradients on
  chrome (explicit user veto). Gradients allowed ON the mascot only.
- **Motion:** native Flutter rig (no Rive/Lottie/3D) — Tier 1 idle (breathe +
  blink) ships with W3; Tier 2 state performers; Tier 3 scripted scenes later.
- **Typography:** system font default (P11); Plus Jakarta Sans bundled as the
  optional user-selectable font. Jakarta is also the web/board voice.
- **Quality bar:** taste-skill installed at `.claude/skills/taste` —
  anti-default discipline (no AI-purple, no Inter-by-default, no template
  layouts). Micro-stutters/frame drops folded into W3 (user decision).

## Extensibility rules (the meta-requirement)

Every future plan must land without redesign. Enforced invariants:

1. **Tokens are the single source of truth.** One Dart file
   (`lib/core/theme/tokens.dart`) defines color/type/space/radius/motion/
   elevation; components read ONLY tokens. A `tool/export_tokens.dart` emits
   `design_tokens.json` + `design_tokens.css` so the future website/privacy
   pages inherit the palette automatically.
2. **Consistency by construction.** Pages compose a fixed component set
   (`lib/core/widgets/`). A screen may not hardcode color/radius/spacing —
   lint-level rule, checked in review.
3. **Slots, not decisions.** `EmptyState(mascot:, title:, action:)` and
   `StatusBanner(...)` take content via slots → mascot/onboarding/illustrations
   drop in later. Settings = data-driven sections → hidden dev panel is one
   section, not a special screen.
4. **UI reads only domain providers** (already true; regression-checked) →
   offline-first swap underneath never touches UI.
5. **Absorption table:**

| Future plan | Lands as |
|---|---|
| Offline-first | data-layer swap; UI unchanged (rule 4) |
| Mascot expansion | new poses in the existing rig + new EmptyState/status slots |
| Website / GitHub pages / privacy policy | token JSON/CSS export + shared palette |
| Hidden dev options | one Settings section + in-app log buffer (D5 below) |
| Edit/forward/mentions/polls (post-W3 features) | compose existing components; one new menu item each |

## Token system (initial values)

**Color — light:** bg `#FAF7F1`, surface `#FFFFFF`, surface-2 `#F1ECE3`,
ink `#2A2520`, ink-soft `#6E655A`, ink-faint `#9C9284`, line `#E4DDD1`,
accent `#EFA00B`, accent-pressed `#D98F08`, accent-soft `#FFF3DC`,
on-accent `#2A2520`, success `#0E9F6E`, error `#E5484D`, info `#4A6FA5`.

**Color — dark:** bg `#171512`, surface `#211E1A`, surface-2 `#2B2823`,
ink `#F3EDE3`, ink-soft `#9C9284`, line `#3B362F`, accent `#EFA00B`
(unchanged), accent-soft `#3A2E14`, on-accent `#21260F`.

**Mascot palette (constant in both themes):** body `#C6894F`, shade
`#B27A42`, snout `#8B5E3E`, nostril `#5C3B28`, face `#3A2E22`,
key-gold `#E8A21D`.

**Type (app):** scale — display 28/34, h1 24/30, h2 20/26, title 16/22,
body 15/22, caption 13/18, micro 11/14. Weights: 700 headings, 600 titles/
actions, 400 body. System font; optional Jakarta ships with matching scale.

**Space:** 4-base grid — 4, 8, 12, 16, 20, 24, 32, 40, 48.

**Radius:** sm 10, md 16, lg 20, xl 24, pill 999; chat bubble 18 with
6px tail corner (approved on board).

**Motion:** fast 150ms, base 250ms, slow 400ms; emphasized easing
(Curves.emphasizedCubic) for enters, spring (damping ~0.8) for mascot/reacts.
Reduced-motion: animations collapse to opacity or stop (mascot idles park).

**Elevation:** warm-tinted soft shadows (`rgba(52,42,28,.10)` light /
black `.35` dark) — max 2 shadow layers; no blur effects/backdrop filters
(frame budget).

## Component set (fixed, small)

Buttons (primary/secondary/text/icon), Chip, ChatTile, MessageBubble
(text/media/system variants), Composer, Banner (status, mascot slot),
Badge, Avatar, Sheet, Dialog, Toast, EmptyState (mascot slot), Skeleton
(loader), NavBar, SettingsTile, SectionHeader, ProfileCard, InviteCard,
SearchField, SegmentedControl. Each ships light + dark + pressed/focus +
disabled states from tokens. New features compose these; adding a component
requires a spec amendment.

## Mascot system

- **Source of truth:** the approved SVG paths, transcribed into a
  `CustomPainter` (zero new deps) with parameters: `blink` (0-1), `breathe`
  (0-1), `mood` (neutral/happy/sleepy/key), `keyVisible`.
- **Tier 1 (W3):** idle breathe (3.4s) + blink (4.6s loop) as on the board;
  squash-on-tap, success bounce. Used in: EmptyState, onboarding, splash,
  status banners, profile header.
- **Tier 2:** state performers — typing, offline-sleepy, key-rotation dance,
  PIN-restore celebration, sync-hold. (Spec'd here, built on demand.)
- **Tier 3 (later):** scripted onboarding scenes.
- **Never:** inside message bubbles, behind readable text, on every screen.

## Screens (scope of the redesign)

Onboarding/login/register, Home (chat list + requests badge), Chat
(thread + composer + menus), Requests (friend/group cards), Group info
(members + invites), Profile + edit profile, Settings (incl. profile/photo
pickers) — each with light/dark, loading (skeleton), empty (mascot), and
error states. Character reference for each = the approved board language;
**before wiring each screen batch, HTML mockups (concept-board style) are
shown and approved by the user** (mockup-first gate, same as the board).

## Frame-drop work (user-reported stutters)

- Profile chat-list builds (no per-tile async work on build; avatar cache
  hits only), image decode off main isolate for thumbnails, limit shadow
  layers (elevation rule), all implicit animations ≤ base 250ms.
- Measure on the Redmi S2 (slowest device): frame times via DevTools during
  home scroll, chat scroll with media, app switch. Target: no >16ms spikes
  during steady scroll on S2, with recorded before/after numbers.

## D5 — developer options (user's plan #5)

Settings → tap version number ×7 → hidden Dev panel (section, per rule 3):
export logs, toggle verbose logging, clear image caches, show overlay
perf HUD (debug only), copy diagnostics. Requires a small in-app ring
buffer logger (wraps `debugPrint`, 2000-line cap) — scoped as its own
task in the plan.

## Verification / gates

1. Mockup approval per screen batch (user).
2. `flutter analyze` 0 errors, `flutter test` green after every task.
3. On-device visual pass on all 3 devices: light + dark, reduced-motion
   toggle, empty/loading/error states exercised.
4. Stutter before/after numbers recorded (Redmi S2).
5. Standing rule: no commit until user PASS.

## Out of scope (queued after W3)

Edit/forward/mentions/polls, link invites, block/report, key-archive,
release keystore, website build (token export lands in W3; site itself
later), Rive/Lottie adoption (revisit at Tier 3).
