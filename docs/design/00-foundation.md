# Design Foundation — Page-0 (shared vocabulary for all page specs)

Date: 2026-10-17. Status: **binding** — every per-page design spec and every
Astra implementation plan argues from this file. Authority chain:
PRODUCT.md brand commitments → W3 spec (`docs/superpowers/specs/2026-10-05-w3-warm-pop-design-system.md`)
→ this file → per-page spec. Conflicts resolve upward.

Purpose: one page per day (~10 days) covering every surface; this file exists
so page 3 cannot drift from page 1. Pages REFERENCE these tokens and laws;
they never redefine them.

## 1. Design read

Reading this as: **Operate** surface (messaging app UI, daily-use) for
design-conscious personal-use users, Warm Pop language (pop-forward
structure, warm execution), leaning toward the existing Warm Pop token
system. Daily-use calm over loudness. `DESIGN_VARIANCE` moderate (identity
in soft radii + marigold + mascot, not in layout gymnastics); `MOTION`
restrained (150/250/400ms, emphasized cubic enters, spring only for mascot
and reactions); `DENSITY` medium (airy cards, chat list scannable).

## 2. Color tokens (verbatim — single source `lib/core/theme/tokens.dart`)

| Token | Light | Dark | Role |
|---|---|---|---|
| bg | `#FAF7F1` | `#171512` | app background |
| surface | `#FFFFFF` | `#211E1A` | cards, bubbles (them), sheets |
| surface2 | `#F1ECE3` | `#2B2823` | skeletons, avatar fills, wells |
| ink | `#2A2520` | `#F3EDE3` | primary text |
| inkSoft | `#6E655A` | `#9C9284` | secondary text |
| inkFaint | `#9C9284` | `#9C9284` | placeholder/meta |
| line | `#E4DDD1` | `#3B362F` | borders/dividers |
| accent | `#EFA00B` | `#EFA00B` (same) | Marigold — the ONLY chrome accent |
| accentPressed | `#D98F08` | `#D98F08` | pressed accent |
| accentSoft | `#FFF3DC` | `#3A2E14` | accent-tinted surfaces/banners |
| onAccent | `#2A2520` | `#21260F` | text on accent |
| success | `#0E9F6E` | same | positive status |
| error | `#E5484D` | same | errors/destructive |
| info | `#4A6FA5` | same | informational |

Mascot palette (constant both themes): body `#C6894F`, shade `#B27A42`,
snout `#8B5E3E`, nostril `#5C3B28`, face `#3A2E22`, key-gold `#E8A21D`.

**Color laws**
- C1: No violet, no purple, no gradients on chrome (user veto, standing).
  Gradients allowed ON the mascot only.
- C2: One accent (Marigold). Semantic colors (success/error/info) are
  status-only, never decorative.
- C3: Screens/components NEVER hardcode color — `context.t.*` tokens only
  (grep gate). Web/spec mockups use the CSS custom properties above.
- C4: Contrast pairs are part of the token contract: `onAccent` on `accent`,
  `ink` on `bg`/`surface`, both themes. Body ≥4.5:1, large text ≥3:1.

## 3. Type scale

System font in the app; Plus Jakarta Sans only labels boards/mockups.

| Role | Size/Line | Weight | Use |
|---|---|---|---|
| display | 28/34 | 700 | hero/empty-state titles |
| h1 | 24/30 | 700 | screen titles |
| h2 | 20/26 | 700 | section heads |
| title | 16/22 | 600 | tile titles, app bar names |
| body | 15/22 | 400 | message text, body copy |
| caption | 13/18 | 400/600 | meta, timestamps, previews |
| micro | 11/14 | 600 | badges, labels, uppercase kickers |

Laws: headings 700, titles/actions 600, body 400 — never other weights.
Message bubbles = body scale. No font-size invention per screen; extended
sizes need a foundation amendment.

## 4. Space / radius / elevation

- Space (4-base): 4, 8, 12, 16, 20, 24, 32, 40, 48.
- Radius: sm 10, md 16, lg 20, xl 24, pill 999.
  Chat bubble 18 with **6px tail corner** (board-approved): them =
  bottom-left 6, me = bottom-right 6.
- Elevation: warm-tinted soft shadow `rgba(52,42,28,.10)` light /
  `rgba(0,0,0,.35)` dark; **max 2 shadow layers**; no blur/backdrop filters
  (frame budget, W3).

## 5. Motion

| Token | Value | Use |
|---|---|---|
| fast | 150ms | pressed states, small fades |
| base | 250ms | sheets, switches, implicit anims (ceiling) |
| slow | 400ms | large enters, highlight fades |
| emphasized | `Curves.emphasizedCubic` | enters |
| spring | damping ≈0.8 | mascot + reaction pop only |

Laws: all implicit animations ≤250ms (frame-drop rule). Reduced-motion:
animations collapse to opacity or stop; mascot idles park. Jump-to-message
highlight = accent-tinted flash decaying over `slow` (400ms) — spec'd per
page but timed from these tokens.

## 6. Shared state vocabulary (same meaning on every page)

| State | Language | Rule |
|---|---|---|
| loading | shape-matching **skeleton** (`Skeleton`, shimmer ≤1.4s) | skeleton mirrors final layout; never a lone circular spinner for content that has a shape |
| empty | `EmptyState(mascot:, title:, action:)` | mascot + title + subtitle + one primary action; mascot never inside bubbles/behind text |
| error | `StatusBanner` / inline error + retry | contextual, not toast-only for loadable content |
| terminal decrypt | lock icon + "Can't decrypt" | NEVER skeleton bars for `key_missing`/`failed` (loading-UX law, a70f020) |
| offline | `StatusBanner` accentSoft + mascot where slotted | holding-messages phrasing, not alarm-red |
| pressed | accentPressed / surface2 shift + ≤150ms | tactile, no layout shift |

## 7. Fixed component set (W3)

Buttons (primary/secondary/text/icon), Chip, **ChatTile**, MessageBubble
(text/media/system variants), Composer, Banner (status + mascot slot),
Badge, Avatar, Sheet, Dialog, Toast, **EmptyState** (mascot slot),
**Skeleton**, **StatusBanner**, NavBar, SettingsTile, **SectionHeader**,
ProfileCard, InviteCard, SearchField, SegmentedControl.

Laws:
- L1: Each ships light + dark + pressed/focus + disabled from tokens.
- L2: New feature = compose this set. Adding a component = spec amendment
  (add it to this list in the same PR).
- L3: Shared interactions (long-press menu, search field, sheets) are
  defined ONCE in the registry with their widget path; pages import, never
  reimplement.
- L4: UI reads only domain providers (offline-first swap stays invisible).

## 8. Page inventory (spec order)

| # | Page | Notes |
|---|---|---|
| 1 | **Chat screen** | first; forces most shared components into the registry |
| 2 | Home / conversation list | floating title, tiles, FAB, banner |
| 3 | Requests (friend + group) | cards, badges |
| 4 | Group info / create group | members, invites |
| 5 | Profile + edit profile | avatar picker |
| 6 | Settings (+ hidden dev section later) | data-driven sections |
| 7 | Auth (login/register/onboarding) | |
| 8 | Sheets & overlays | new-chat, add-friend, attach, context menu (components, but spec'd once) |
| 9 | Media fullscreen (image viewer / video) | |
| 10 | Mascot placements pass | last: poses slot into pages built above |

Reorder allowed by user; Page-0 laws are not.

## 9. Review contract (per page)

1. Deliverable = expanded HTML spec (`docs/design/pages/<page>.html`, light
   + dark panels) + acceptance checklist (`docs/design/pages/<page>.md`).
2. Astra implements against the checklist; improvising allowed only
   **within tokens/laws** ("surpass" = better inside the system; a beautiful
   deviation that breaks C1-C4/L1-L4 = revise list, not a pass).
3. My review = checklist verdict + device screenshots + suite green
   (`flutter test` baseline 213/213, `flutter analyze` 0 errors) — same
   change-list format as the loading-UX attempt-2 review.
4. Behaviors in §6 and the loading-UX/tap-down laws are constraints, not
   suggestions — redesign changes looks, not these contracts.

## 10. Pipeline

While Astra implements page N, spec N+1 is written. 1 page/day sustained.
Backlog §2 order (Home → Chat → …) is superseded by §8 order (Chat first —
user ruling 2026-10-17) for the spec pass.
