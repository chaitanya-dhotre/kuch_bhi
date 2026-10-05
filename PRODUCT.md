# Product

<!-- impeccable:product-schema 1 -->

## Platform
android

## Stack
Flutter/Dart client; PocketBase backend; Drift (SQLite) local cache;
Riverpod state; E2E encryption (X25519 + AES-GCM, group keys per conv).
Release build is the perf baseline (debug is 2-5x slower).

## Users
- Founder-operated app; users are personal friends the founder invites.
- Test fleet: Samsung, Redmi S2 (oldest supported device, Snapdragon 625),
  Pixel emulator.
- [OPEN] Wider audience persona: design-conscious personal-use messaging
  users — not enterprise. (From session brief; not yet validated.)

## Product Purpose
Private, fast, lively everyday messaging — E2E by default, no ads, no
tracking. Success = messages arrive live without reopening the app, and the
app feels intentional rather than templated.

## Positioning
Privacy-first chat that is also a pleasure to use. Competes on polish +
trust, not on feature count.

## Operating Context
Android phones only (Redmi S2 is the performance floor). Offline-first
architecture is planned but lands only after the app is robust and
production-ready (founder's sequencing decision).

## Capabilities and Constraints
- 1:1 + group chat, E2E encrypted, media, invites, disappearing messages.
- System font default; optional bundled font.
- Design must absorb later: mascot expansion, website/GitHub pages,
  privacy policy, hidden dev-options panel.
- Constrained by the W3 spec extensibility rules (tokens as single source).

## Brand Commitments
- Direction: Warm Pop (warm surfaces, vivid single accent, soft radii).
- Accent: Marigold #EFA00B. No violet/purple/gradients in chrome.
- Mascot: Capybara, art approved and locked (docs/Capybara.png).

## Evidence on Hand
- docs/superpowers/specs/2026-10-05-w3-warm-pop-design-system.md
- docs/Capybara.png, docs/Bear to Capybara Design Comparison.png
- Prior specs: W1 reliability, W2 group invites (same repo).

## Product Principles
[OPEN] Founder's values observed in session: consistency over novelty;
intentionality (Apple reference); liveliness via mascot/motion, not clutter.
To be confirmed as written principles in a later init pass.

## Accessibility & Inclusion
- Contrast-checked color pairs (onAccent on accent, light+dark) are part of
  the token contract.
- Reduced-motion: animations park (W3 spec).
- [OPEN] No explicit a11y standard adopted yet.
