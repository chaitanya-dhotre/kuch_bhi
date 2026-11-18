---
title: "A rule dump from the live database can't tell a locked rule from an open one, and Google sign-in currently joins any account with the same email"
author: Chaitanya
date: 2026-11-18
branch: main
cost: { minutes: 6, tokens: 146564 }
id: l-8d7c750d
scope: repo
status: active
src: agent
touches:
  - docs/audits/2026-11-16-security-cloudflare-skill.md
  - docs/design/pages/google-link-and-push.md
---

## Decided
- Live checks of 2026-11-18 (audit L2–L10): live rules equal bible §7 exactly. A plain sqlite select prints a NULL rule (superusers only) and an empty-string rule (open to everyone) the same way, so every rule comparison needs a second query with `is null`. The only empty-string rule live is `users` create (open sign-up, intended).
- Google sign-in joining an unverified password account with the same email is finding F23 (medium, pre-account takeover). Fix proposed: on a Google sign-in to an unverified account, mark it verified, set a new random password, and refresh tokenKey. Spec awaiting PASS.

## Tried and ruled out
- Requiring a verified email for every password sign-in as the F23 fix: 2 of 5 live users are unverified and would be locked out, and the Google-side fix alone closes the takeover.

## Watch out
- The live Google auth hook is not in the repo, so its line numbers come from the live file.
- A hook file in pb_hooks whose name lacks `.pb.js` is never loaded. `test_b64.js` there is dead, not a live route.

In the code:
- NULL check: `sudo sqlite3 -readonly /opt/pocketbase/pb_data/data.db "select name, listRule is null, viewRule is null, createRule is null, updateRule is null, deleteRule is null from _collections where system=0"`
- Live `pb_hooks/google_auth.pb.js:25` (find by email), `:47-50` (signs in any found record), `:40` (emailVisibility true on Google sign-up)
- Spec: docs/design/pages/google-link-and-push.md; results: docs/audits/2026-11-16-security-cloudflare-skill.md §3
