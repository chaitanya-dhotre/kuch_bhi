---
title: "Google sign-in trusts only what Google's tokeninfo returns, and a taken username on Google register is a 400 field error"
author: Chaitanya
date: 2026-10-29
branch: main
cost: { minutes: 5, tokens: 77917 }
id: l-ced3f1cd
scope: repo
status: active
src: agent
touches:
  - android/app/google-services.json
---

## Decided
The server's Google auth hook sends every idToken to Google's tokeninfo endpoint and trusts only that reply: HTTP 200, `aud` exactly one of the app's OAuth client ids, `iss` accounts.google.com, `email_verified` "true", not expired. The email comes from Google's reply, never from the token payload. Before this, the hook base64-decoded the JWT and checked only exp/aud, so a hand-made token with any email signed in as that user (a forged probe got past every check to "User not found").
On register, a taken username answers 400 with `data.username.code = validation_not_unique` (plus a top-level message), so the client can show it as a field error. The old hook computed a free candidate name, then saved the original one and crashed on the unique index with a 500.

## Tried and ruled out
Checking `aud` with a substring of the project number: any client id in the project would pass. Exact ids instead.
Verifying the signature in the hook with JWKS: needs RSA in the JS VM; tokeninfo is one HTTP call and Google does the crypto.

## Watch out
Adding a new OAuth client (iOS app, a new signing key / SHA, a web client) means adding its id to the hook's allow-list, or every Google sign-in from it gets 401 "aud mismatch".
If the server can't reach Google, the hook answers 503, not 401.
The hook only logs successes; the status of each call is in PocketBase's request log (`_logs` in auxiliary.db).

In the code: live server `/opt/pocketbase/pb_hooks/google_auth.pb.js` (AUDS list at the top; ids from `android/app/google-services.json`). Backup of the old hook: `/home/ubuntu/pb_backups/google_auth.pb.js.20261029-k2-pre`. Spec: `docs/design/pages/auth.md` section K (K2, K4) and decision 18.
