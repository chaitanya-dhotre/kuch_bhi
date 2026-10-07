# Offline Phase 0 — custom-id verification (Plan A gate)

Date: 2026-10-07 · Task 1 of the offline-first plan (spec §16).
Server: `https://kuch-bhi.duckdns.org` (PocketBase, reported 0.37.5).
Auth: normal user login only (`shreysaw76@gmail.com` test account).
**Superuser: never used, never attempted** (standing security rule).

## Verdict

**PLAN_A_PASS (functional)** — client-supplied custom ids flow through the
SDK, the server accepts them, enforces uniqueness with a typed error, and
ownership fields round-trip. Caveat: the literal schema read in (b) is
denied to normal users (403); the "no id restriction" question was closed
behaviorally by (c) instead. See (b).

---

## (a) Client passes `id` through create — opaque JSON

**Result: PASS (SDK source, pocketbase 0.21.0).**

`pubspec.lock:1410` → `version: "0.21.0"` (hosted pub.dev,
sha256 `807a82d0…c658`).

Chain, with citations from
`~/.pub-cache/hosted/pub.dev/pocketbase-0.21.0/`:

1. `lib/src/services/base_crud_service.dart:160-176` —
   `create({Map<String, dynamic> body = const {}})` forwards `body: body`
   verbatim to `client.send(...)` (POST). No key filtering, no `id` strip.
2. `lib/src/client.dart:214-340` — `send()` builds the request via
   `_jsonRequest`:
   - `client.dart:313` — `request.body = jsonEncode(body);` — the create
     body is serialized opaquely; every caller key (including `id`)
     reaches the wire.
   - `client.dart:338` (multipart path) — `request.fields["@jsonPayload"] =
     [jsonEncode(body)]` — same: whole body JSON-wrapped, nothing dropped.
   - `client.dart:122` — doc comment: "everything else is converted to a
     string using `jsonEncode()`".
3. `grep -rn 'remove("id"…|remove('"'"'id'"'"'…|body[…id…]'` over
   `pocketbase-0.21.0/lib/src/` → **no matches**: the SDK never mutates or
   strips a caller-supplied `id`.

## (b) Collection schema read (`createRule` + field-level id restriction)

**Result: BLOCKED-as-literally-specified (403 for normal user) — no
superuser attempted; intent closed by (c).**

Request (normal user token from `users/auth-with-password`):

```
GET /api/collections/messages
Authorization: <user JWT>
→ HTTP 403
{"data":{},"message":"The authorized record is not allowed to perform this action.","status":403}
```

The collections-management API is superuser-gated server-side, so the
`createRule` string cannot be pasted with normal-user auth (would require
elevated rights → not attempted per the absolute constraint).

Field-level-id-restriction question, closed behaviorally instead: if the
schema carried an id pattern / length / format restriction, the (c)
create with a custom 15-char `[a-z0-9]` id would have failed validation.
It returned HTTP 200 (below). Likewise, if `createRule` rejected
client-supplied ids, create #1 would have been 403. It was not. Server-side
uniqueness on `id` is proven by the typed duplicate error in (c).

## (c) Authenticated create / duplicate / fetch-by-id

**Result: PASS (3/3, normal user auth only).**

Test id: `chq0ct7x0char01` (15 chars, `[a-z0-9]`).
Conversation: `s0wewbc1u0oscea` (test account is an `admin` member).
Sender: `teb3elavw531hwx` (the test account).

1. **Create with custom id** —
   `POST /api/collections/messages/records`
   body: `{"id":"chq0ct7x0char01","conversation_id":"s0wewbc1u0oscea",
   "sender_id":"teb3elavw531hwx","type":"text","encrypted_body":…,"iv":…,
   "reply_to_id":"","reply_preview":"","is_deleted_for_everyone":false}`
   → **HTTP 200**; response echoes `"id":"chq0ct7x0char01"`,
   `sender_id:"teb3elavw531hwx"`, `conversation_id:"s0wewbc1u0oscea"`.

2. **Same id again (duplicate)** — identical create with `id` reused →
   **HTTP 400** with the exact error shape:

   ```json
   {"data":{"id":{"code":"validation_not_unique",
                  "message":"Value must be unique."}},
    "message":"Failed to create record.","status":400}
   ```

   (Duplicate detection is keyed on the `id` field — `validation_not_unique`.
   This is the shape later tasks' offline id-collision handling must match.)

3. **Fetch by id (ownership round-trip)** —
   `GET /api/collections/messages/records/chq0ct7x0char01`
   → **HTTP 200**; `id`, `sender_id` (= test account),
   `conversation_id`, `encrypted_body`, `iv` all match the create payload.

### Cleanup

- `DELETE …/records/chq0ct7x0char01` → **HTTP 403** (deleteRule denies the
  sender) — hard delete not available to normal users.
- `PATCH` with `{"is_deleted_for_everyone":true}` → **HTTP 200**; re-read
  confirms `"is_deleted_for_everyone":true`. The row is therefore filtered
  out of every app read path (`watchMessages` DAO and the fetch pipeline
  both exclude it). Soft-deleted throwaway remains on the server as
  tombstone evidence.

---

## Gate ruling

- (a) PASS, (c) PASS 3/3 → Plan A's mechanism works end-to-end with normal
  user auth.
- (b) literal schema paste impossible without superuser (403; not
  attempted); its intent — "no field-level id restriction" — is proven by
  (c) create #1 succeeding and the duplicate failing with a typed id error.
- Per the brief's stop rule this doc is the report artifact: the caller
  must decide acceptance of (b)'s evidence substitution before Task 2.
