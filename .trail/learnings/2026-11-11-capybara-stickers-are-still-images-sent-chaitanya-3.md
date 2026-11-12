---
title: "Capybara stickers are still images sent as a sticker-type message whose encrypted text names the sticker, and a raised paw is a short leg that grows out of the…"
author: Chaitanya
date: 2026-11-11
branch: main
cost: { minutes: 9, tokens: 29509 }
id: l-6d7919ea
scope: repo
status: active
replaces: l-242d5418
src: agent
touches:
  - docs/design/pages/mascot.md
---

(Proposed in the Page 10 phase 4 spec, mascot §J, 2026-11-11, awaiting the user's PASS.)

## Decided
- A sticker is a normal messages row with type `sticker`. The sticker id goes INSIDE the encrypted body as the plain line `Sticker: <id>` (ids like `on-my-way`). The server learns only "a sticker", never which one. The format and ids are permanent once shipped.
- Builds up to e4ad70e render a message type they don't know as a plain text bubble with its decrypted body, so on them a sticker reads "Sticker: hi" and the chat list "New message". That readable body is the old-version fallback, and why the id is spelled out in plain words rather than hidden.
- The send reuses the text outbox kind `text_send` (queue, cancel before ack, burst-order lift and the offline bath count stay one path). Only the create's `type` and the text-only gates change, through one `{'text','sticker'}` set.
- Stickers are still WebP images in the APK, not Rive: a chat can show 20, and more than two animated capybaras drop the Redmi frame rate. ~96 KB for ten.
- Sticker art is rendered from the rig, not drawn separately: one patched rig copy per sticker, rendered on white and on black, and the alpha recovered from the difference (the CLI's captures are opaque). A white die-cut edge is added because the dark outline nearly vanishes on the dark chat background.

## Tried and ruled out
- The rig's built-in wave and celebrate one-shots as sticker poses: the arm lines stay inside the body outline and don't read at sticker size.
- Long raised arms drawn behind the body (first sticker draft): the user rejected them as monkey arms growing from the back. A capybara's front limbs are short and shaped like its legs.
- A fat stub sitting wholly inside the body outline: its rounded ink end showed on the chest and it read as stuck on. The user picked a medium stub (22 thick, 13 body-colour core) that starts just inside the body's side edge so the paw breaks the outline, drawn in front of the body like the feet, with a body-colour joint covering the ink end at the base.

## Watch out
- If live `messages.type` is a select, a sticker create is refused until `sticker` is added, so the field change goes live before any phone can send stickers. Ask before reading the server.
- The push can carry a `preview` from the server hook, which the app shows as the notification body. If the hook labels types, stickers need a label there too.
- Chat search decrypts every row and would match "hi" against a sticker's body; its prefilter must skip type `sticker`.
- `retryMessage` routes any non-text row to the media upload; stickers must be in the text-like set there.

In the code: docs/design/mascot/stickers/{apply_stickers.py,render.sh,matte.py}; message_repository_impl.dart _sendTextOp ('type': 'text'), retryMessage, searchMessages; message_bubble.dart (unknown types fall through to _TextBubble); fcm_service.dart notificationText.
