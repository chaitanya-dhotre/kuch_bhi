---
name: brand-design-md
description: Structured design analyses of famous product brands (Apple, Airbnb, Uber, Spotify, Linear, Notion) — exact colors, type scales, radii, spacing, component specs. Use when designing UI and needing reference-grade specs or when the user names one of these brands as a direction. Source: github.com/VoltAgent/awesome-design-md.
---

# Brand Design Analyses

Reference corpus: `design-md/<brand>/DESIGN.md` — each is a structured
analysis with verbatim tokens: color palettes (hex), typography scale
(px/weights/line-heights), radii, spacing, component patterns, voice.

## Brands present

- `airbnb` — warm consumer marketplace; Rausch `#ff385c`, pill search,
  ~14px card radius, Cereal VF at 500/600 (not heavy bold). Our Warm Pop
  direction borrows this family's traits.
- `apple` — SF discipline, intentional hierarchy, restrained motion.
  Reference for the "everything intentional" feel the user admires.
- `uber` — operational clarity, semantic-only color, dense information
  rhythm. Reference for the Confident Utility direction.
- `spotify`, `linear.app`, `notion` — supporting references.

## How to use

1. Identify the brand closest to the design question.
2. Read `design-md/<brand>/DESIGN.md` fully before advising — quote its
   tokens (colors/px/weights) rather than inventing numbers.
3. Never copy a brand's identity into the app (trademarked palettes/marks);
   extract *patterns* (radii, scale structure, density) and re-derive them
   through the project's own tokens (`lib/core/theme/tokens.dart`).

## Adding brands

The full corpus (147 brands) lives in github.com/VoltAgent/awesome-design-md
— clone and copy a folder in when a new brand becomes relevant (e.g.
headspace when mascot/onboarding work starts).
