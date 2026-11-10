# Mascot inventory: every place the capybara appears (Page 10, Phase 1 pre-work)

Status: DRAFT 2026-11-09. User picked S1 Sticker (round 2 = `styles/s1v2/`) and accepted D2–D8 defaults. Ideas I1–I5 (section F) wait on the user; some change rows above, marked "(if I1)".
This list becomes section A of `docs/design/pages/mascot.md` once the spec is written.
Companion page with renders: `docs/design/mascot/inventory.html`.

## Rules that still hold (W3 spec + foundation)

- Never inside a message bubble, never behind readable text, never on every screen.
- At most 1–2 animated capybaras on screen at once (Redmi S2: 6 at once drops to ~40 fps).
- Reduced motion: idles park (breathe/blink stop), one-shot moves become a single fade or the end pose.
- Mascot palette is constant in both themes. Gradients are allowed on the mascot only. No purple.
- A mascot reaction never blocks or delays a user action (see the "back must never wait" learning).

## A. Where it is today (CustomPainter, replaced in Phase 2+)

| # | Where | When | Today | Proposed role / action | View | Size (dp) |
|---|---|---|---|---|---|---|
| X1 | Login screen header | Signed out, app open | neutral, 112 | Host: wave once on first show, then idle | Sit | 112 |
| X2 | Home, no chats | Zero chats | neutral, 130 | Guide: idle, looks toward the new-chat button | Sit | 130 |
| X3 | Home, load error | Chats couldn't load | sleepy, EmptyState | Worried (spec says key mood; code has sleepy) | Sit | 120 |
| X4 | Requests, empty | No requests | neutral, 120 | Idle | Sit | 120 |
| X5 | Requests, error | Requests couldn't load | sleepy, 120 | Worried | Sit | 120 |
| X6 | Chat, empty | New chat, no messages | neutral, 108 | Wave hello; hops when the first message sends (see D2) | Sit | 108 |
| X7 | Chat, older messages unavailable | Key missing for history | sleepy, 64 | Worried, empty paws (lost key) | Sit | 72 |
| X8 | Chat search, no results | Search finds nothing | sleepy, 64 | Searching: looks left, right, shrugs | Sit | 72 |
| X9 | Chat load error card | Messages couldn't load | neutral + key, 72 | Guardian holding the key | Sit | 72 |
| X10 | `EmptyState` with no mascot given (default) | Create group: friends failed to load; create group: no friends yet; view profile: profile unavailable | default neutral, **180** | See D3 | Sit | 120 |

X10: `EmptyState` draws a 180 dp capybara unless a screen passes `withMascot: false` (starred error, share target, create-group search, group settings "Everyone's here" do). So the capybara shows in 12 places today.

## B. Planned placements

| # | Where | When | Role / action | View | Size | Phase |
|---|---|---|---|---|---|---|
| E1 | Offline banner (`StatusBanner`, Home + Chat) | Device goes offline | Dozes (head nods, "z"); wakes and perks up when back online, then the banner leaves. **(if I1)** soaks in a yuzu bath; each message queued offline floats in as a yuzu; back online, it nudges them out one by one as they send | **Head** (if I1: **Onsen**), facing the text | 40 | **2** |
| C4 | Send success | A message is sent | Happy hop. Needs a host: see D2 | Sit or Head | — | **2** |
| C5 | Failed send | A send fails for good | Worried. Never next to the bubble; only in the failed-send sheet | Head | 48 | later |
| C1 | Chat app bar buddy | Always, in chats | Tap toggles info mode (receipts, times) | Head | 28–32 | later |
| C2 | Swipe companion | Swiping a message for its time | Peeks from the edge holding a clock. See D5 | Head (peek) | 32 | later / drop |
| E4 | Cold start sync hold | Startup backup check is slow | Sits guarding the key until sync ends | Sit | 120 | later |
| K1 | Key restore success | Recovery key / PIN restore works | Celebrate: arms up, yuzu pops up and lands back | Sit | 120 | later |
| K2 | App lock screen | Lock overlay | Holds the key; eyes follow the PIN dots (lookAt); happy on unlock, worried on wrong PIN | Head | 72 | later |
| K3 | Group key rotation | A member leaves or is removed | Swaps the old key for a new one (short dance) in the group settings banner | Sit | 72 | later |
| O1 | Onboarding (after register) | First run | 3 scenes: hello, "I keep your chats locked" (key), "keep your recovery key safe" | Sit + Loaf | 160 | later |
| S1 | Settings > About | Opening About | Static, tap = squish + giggle | Sit | 96 | later |
| I1 | App icon / splash | Launcher | Static head, flattest silhouette | Head | icon | undecided |
| T1 | Typing indicator | Someone is typing | **Not proposed**: it lives in the bubble area. See D4 | — | — | no |

## C. Views (drawings) needed

A view is a separate drawing (its own artboard); moods and actions are animation inside it.

| View | Used by | Needed for Phase 2? |
|---|---|---|
| **Sit** (three-quarter, full body, sitting) | X1–X10, C4 (D2 default), E4, K1, K3, O1, S1 | Yes |
| **Front** (sitting, facing you, paws free) | holding things: key (X9, K2), stickers (I2), celebrate (K1) | Yes (round 2 added it) |
| **Head** (profile bust + yuzu) | C1, C2 (clipped as a peek), C5, K2, I1 | Yes |
| **Onsen** (Head soaking in a pool, floating yuzus) | E1 (if I1) | Yes, if I1 |
| Loaf (side, lying down) | O1 "chill" scene, optional big sleepy | No (D6) |

Round 2 (user: "looks like a brown seal"): the capybara read comes from a long blunt box-ended snout with the dark patch at its tip, the eye small and high and set back, a flat head top, small round ears at the back, no neck, a bean body and toe ticks. The Sit and Head views use a profile head; it faces left as drawn and flips for free (scaleX −1), so in the banner it faces the text.

Side and three-quarter alone were not enough: at 40 dp a full-body capybara leaves the face about 10 dp tall, so every slot under ~56 dp uses the Head view (face about 25 dp).

## D. Actions (animations) per view

| Action | Sit | Head | Used by |
|---|---|---|---|
| Idle: breathe + blink | ✓ | ✓ | all animated placements |
| Look at a point (eyes, head tilt) | ✓ | ✓ | X2, K2 |
| Tap: squish + giggle | ✓ | ✓ | any tappable placement |
| Happy hop | ✓ | ✓ | C4, K2 unlock |
| Celebrate (arms up, yuzu pops) | ✓ | — | K1 |
| Wave hello (one paw) | ✓ | — | X1, X6 |
| Doze / wake | ✓ | ✓ | E1 |
| Worried (brows up, ears back, sweat drop) | ✓ | ✓ | X3, X5, X7, C5, K2 |
| Searching (look left/right, shrug) | ✓ | — | X8 |
| Hold key / swap key | ✓ | ✓ (hold) | X9, E4, K2, K3 |

Moods (one at a time): neutral, happy, sleepy, worried. Props: key (gold `#E8A21D`), clock (C2 only).
Rig and view-model inputs (mood, tap, success, sleep, reducedMotion, lookAt) are step 5, after the pick.

## E. Decisions for the user (defaults in bold)

- **D1 Style.** **S1 Sticker** (outline, flat, dot eyes; matches the inspiration folder) / S2 Flat bold (Duolingo-like) / C as first drawn (soft gradients).
- **D2 Where C4 hops.** **The empty-chat capybara (X6) hops when the first message of a chat sends, then fades out.** Alt: a header buddy (C1) that hops on every send. Every-send hops get noisy and cost frames while typing fast.
- **D3 The 12 places it shows today.** **Keep them; the 3 default ones drop from 180 to 120 dp. Each shows its mood's still pose; only the placements marked animated in the spec play idles, and only one per screen.** Alt: drop it from error states that are not about connection.
- **D4 Typing indicator capybara.** **No** (bubble area rule).
- **D5 C2 swipe companion.** **Drop**: it would animate during a scroll/swipe gesture, the costliest moment on the Redmi, for a hidden feature.
- **D6 Loaf view.** **Later** (only onboarding wants it).
- **D7 App icon.** **Decide after Phase 2**, from the Head view.
- **D8 Prop count.** **Key only for now**; the clock comes only if C2 comes back.

## F. Ideas (round 2, may break earlier rules)

| # | Idea | What people get | Breaks | Cost | My call |
|---|---|---|---|---|---|
| I1 | **Yuzu bath offline banner.** Real capybaras soak in yuzu baths in Japanese zoos every winter, which is why ours wears one. Offline = it takes a soak. Each message written offline floats in as a small yuzu (3 + "+n"); back online it nudges them out one per real send. | An answer to "did my message go?" that is also the cutest moment in the app. Gives the yuzu a story. | E1 "sleepy" mood; C4 gets a host (each yuzu leaving = a send) | One more drawing (done: Onsen). Data: a global count over the outbox table (already a drift stream). | **Phase 2, replaces sleepy E1** |
| I2 | **Capybara stickers.** 8–12 stickers from the same drawings (hi, lol, sorry, love, thanks, sleepy, on my way, chill, guarding, celebrate). Sent as a tiny "sticker" message holding only an id; the art ships in the app, so nothing is uploaded, it works offline, and encryption is unchanged. Still images, so chat scrolling stays smooth. | The thing friends would actually use every day. | "Never in bubbles" (an exception for content the user chooses to send) | New message type: live PocketBase field/rule + a fallback "Sticker" line for old app versions. Own spec. | **Own feature after Phase 2** |
| I3 | **Pet it.** Tap any capybara: eyes close, blush deepens, a small purr haptic (`appHaptic`). Hold: it melts into a loaf. | A reason to touch it; costs nothing on screens that already show one. | Nothing | One "pet" animation per view + the haptic call | **Phase 2** |
| I4 | **Night and festival looks.** After 11 pm the capybara wears a nightcap; Diwali diya, Holi colour dabs (no purple), New Year party hat, swapped by date on the phone. | Small surprises through the year. | Nothing | A few accessory shapes, one view-model enum | Later |
| I5 | **Give it a name.** People bond with named mascots. Used in copy only where it reads naturally ("Kuchu's guarding your key"). | Personality in copy. | Nothing | Copy only | Your pick of name, or skip |
