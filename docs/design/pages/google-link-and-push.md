# Google link takeover, public emails, shared push tokens (audit F23–F25)

Status: **PASS 2026-11-18, all defaults.** Build files: `docs/server/hooks/google_auth.pb.js` (live copy +
D-1/D-3), `docs/server/hooks/fcm_token_unique.pb.js` (D-4), `docs/server/migrations/1794830000_users_email_private.js`
(D-3), dry run `docs/server/tests/glink_dry_run.sh` + `glink_check.py` + `glink_stub.pb.js`.
**Dry run 15/15 PASS** on a DB copy (Google tokeninfo stubbed; the first run's 3 F25 fails were the
test hitting PocketBase's auth rate limit, now retried). **LIVE 2026-11-18** via `glink_go_live.sh`:
backups `pb_backups/data.db.20261118-google-link-pre` and `pb_hooks.20261118-google-link-pre`,
migration applied, 0 public emails, `test_b64.js` removed, no errors after restart. **Device check (5) PASS 2026-11-18.** Source: the live read of 2026-11-18, recorded in
`docs/audits/2026-11-16-security-cloudflare-skill.md` §3 under "Results of the live read".

All three fixes are server-only (hooks plus one data change). No app change and no new build.
Every live change needs its own yes, a backup first (`pb_backups/*.20261118-google-link-pre`), and a
dry run on a DB copy (the pattern in memory `server-topology`). Flat hooks only; nothing is deployed
via ssh heredoc.

## F23 — Google sign-in joins an unverified password account (medium)

Live `google_auth.pb.js:25` finds the account by the Google email, and `:47-50` signs in whatever it
finds. A stranger who signed up first with the victim's Gmail keeps the password and their session.

**D-1. What the Google hook does with an existing account that is not verified**
- **(A, default)** Treat Google as proof of the email: set `verified = true`, set a new random
  password, refresh `tokenKey` (signs out every other session), then sign in.
- (B) Refuse with "Verify this email first, or use Forgot password". The victim is stuck until they
  reset the password.
- (C) Leave it as it is.

A real owner who signed up by email and never verified keeps all their data under (A); their old
password stops working, and Forgot password still works.

**D-2. Also require a verified email for password sign-in (`users` authRule `verified = true`)**
- **(No, default)** D-1 closes the takeover. 2 of 5 live users are unverified and would be locked
  out until they verify.
- (Yes) Stricter, but needs a verify-your-email screen in the app first.

## F24 — Google sign-ups get a public email (low)

Live `google_auth.pb.js:40` creates the account with `emailVisibility: true`. Any signed-in user can
list `users`, and sign-up is open.

**D-3.**
- **(default)** Remove `emailVisibility: true` from the hook, and set it to false on the 1 live row
  (one guarded one-off migration). The app never shows another user's email.
- (B) Leave it.

## F25 — A push token can sit on two accounts (low)

Nothing keeps `fcm_token` unique. If sign-out's best-effort clear fails, the next account on that
phone keeps getting the old account's pushes, with sender names shown.

**D-4.**
- **(default)** A new after-update hook on `users`: when `fcm_token` changes to a non-empty value,
  clear that same token on every other row (direct SQL, no broadcast; the field is hidden).
- (B) Add `recipient_id` to the push data, and have the phone drop pushes for another user (server
  plus app change, and old builds stay exposed).
- (C) Leave it (low).

## D-5. Leftovers (hardening)

- **(default)** Delete the dead `pb_hooks/test_b64.js` (never loaded, since it is not `.pb.js`). Leave
  the FCM relay's fallback secret (`fcm_webhook.py:31`, reachable only from the VM).
- (B) Also remove the fallback, so the relay refuses to start without `HOOK_SECRET`.

## Checks after it goes live

1. Throwaway A signs up by password and stays unverified. A Google sign-in for that email (dry run:
   stub the tokeninfo answer on a DB copy) gives `verified = true`, A's old token gets 401, and A's
   old password fails.
2. A verified account signs in by Google with no change to its password or tokenKey.
3. A new Google sign-up has `emailVisibility = false`, and a second user's list call shows no email.
4. B saves A's push token: A's row has `fcm_token = ''`, and B's row has the token.
5. Device: a normal Google sign-in on M52 and Redmi still works, and pushes still arrive.
