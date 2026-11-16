# Calm for the rest of the app (spec, rev 1)

Status: **spec PASS 2026-11-16, all defaults (CR-1 A, CR-2 A, CR-3 A, CR-4 A, CR-5 A, CR-6 A, CR-7 A, CR-8 A).** Carries Chat calm
(`858cd5a`, `chat-calm.md`) and the motion pass (`c5c6c7a`, `motion.md`) to
every screen that is not the chat: Home, Requests, Group info and New group,
Profile and Edit profile, Settings (with About and App lock), Auth, sheets
and dialogs, Starred messages, Media & docs.
Board: `docs/design/pages/calm-rest.html` (before and after, light and dark).
Amends: foundation §2 (C5 list, AMOLED `surface2`), §3 (weights), registry
R1, R3, R11 usage, R21. Builds on Chat calm and the motion pass; does not
change the chat screen.

The spec is split into four parts. **Part 1 goes first** (it holds the
shared pieces); parts 2, 3 and 4 then ship alone, in any order, each with its
own device PASS and commit.

| Part | Screens | Size |
|---|---|---|
| 1 | Shared pieces + Home | 1 day |
| 2 | Settings, Profile, Edit profile, About, App lock | half a day |
| 3 | Requests, Group info, New group, Add a friend sheet | 1 day |
| 4 | Starred, Media & docs, Auth, sheets and dialogs | 1 day |

## What was said

The designer and friends: the chat now looks calm but the rest of the app
does not match; marigold is still everywhere outside the chat; the designer
points to **Ahead**, where the primary colour is kept for what matters.
Round 2 notes (`feedback-2026-11-plan.md`): on Home the new-chat button covers
the last visible row's unread badge; group avatars are dark on dark.

## How it was checked

- **Device walk**, Samsung M52 (411 dp), 2026-11-15, read-only (nothing sent,
  accepted or declined). The app was on AMOLED; with the user's OK it was
  switched to Light, then Dark, and set back to AMOLED. 16 screens per theme
  in `docs/Inspiration/calm-rest/current/` (`*-light.png`, `*-dark.png`,
  `*-amoled.png`). Auth screens were **not** shot: that needs a sign-out,
  which clears the phone's chats. Auth is specced from code.
- **Code count** (§ Counts): every `t.accent`, raw `Duration`, `Curves.*`,
  off-scale `fontSize`, radius and padding in the screens above.
- **References**, Mobbin (iOS only: the Mobbin tools search iOS and web, no
  Android), saved in `docs/Inspiration/calm-rest/<topic>/`.

## References (Mobbin, iOS)

| Screen | What we take |
|---|---|
| [Ahead, home](https://mobbin.com/screens/16c5628d-f890-4c07-b647-83d9a8c04093) · `ahead/ahead-home-learnings-white.webp` | off-white page, plain white cards; the brand colour is only on the profile button and the nav pill |
| [Ahead, sheet](https://mobbin.com/screens/fbea16ed-bd17-40a1-add2-a793bc9b2fcb) · `ahead/ahead-techniques-bottom-sheet.webp` | a sheet with a mascot and two plain buttons, no accent fill at all |
| [Ahead, question](https://mobbin.com/screens/ccf1b06f-ef31-490a-9b8b-6e88935fcb22) · `ahead/ahead-pain-question-cream.webp` | selected row = accent outline; one filled primary per screen |
| [Lapse, chat list dark](https://mobbin.com/screens/4b185b2e-45d4-4848-bfdf-14784e506526) · `home/lapse-chat-list-dark.webp` | black list, grey text, one small dot for unread |
| [Feeld, chat list](https://mobbin.com/screens/7fee67b3-dc9e-4505-aef5-12536129329f) · `home/feeld-chat-list.webp` | grey avatars, grey times; the unread mark is the only colour on a row |
| [Jomo, settings](https://mobbin.com/screens/b2fe6142-36de-491e-af1f-6cdedb605107) · `settings/jomo-interface-rows.webp` | grey icon wells, monochrome icons; colour only on a switch that is on |
| [Coursera, settings dark](https://mobbin.com/screens/5b8224c9-c186-4720-96ab-0782480d3f2e) · `settings/coursera-dark-toggles.webp` | appearance picker with a check, colour only on the check and switches |
| [XChat, group info](https://mobbin.com/screens/71a8edc5-15cc-48ca-8958-f95d3f46b704) · `groups/xchat-group-info-admin.webp` | round grey action buttons, grey **Admin** pill, grouped white rows |
| [Beside, group info](https://mobbin.com/screens/6390fb0a-18e8-406b-b74c-ef92aad3a370) · `groups/beside-group-info.webp` | red **Leave group** is the only strong colour |
| [Discord, new group](https://mobbin.com/screens/7e569bd7-61b8-4688-a776-7e3ea370e3fb) · `groups/discord-create-group-checks.webp` | chosen people as chips above the list; colour only on ticked checks |
| [Genie, pending friends](https://mobbin.com/screens/8712785a-0200-4bfd-8612-52f1d9be0e92) · `requests/genie-pending-friends.webp` | grey **Decline** text + one quiet filled **Accept** per row |
| [Swarm, requests](https://mobbin.com/screens/efa44766-3426-4bdc-a84a-c70403a705ba) · `requests/swarm-requests-inbox.webp` | Accept filled, Decline outlined, rest neutral |
| [XChat, own profile](https://mobbin.com/screens/a03eadb9-1dec-4f2d-8e48-510e7d47cf58) · `profile/xchat-own-profile.webp` | avatar, name, handle, grey round buttons, one card of rows |
| [Manus, favourites](https://mobbin.com/screens/76d9ee48-69e4-4bb2-b7da-f7a0f01795fb) · `lists/manus-favorites-grey-list.webp` | grey icons; one small gold star is the only colour |
| [ChatGPT, sources](https://mobbin.com/screens/6f4ae0f6-7186-4539-b3c6-f60a0a396a14) · `lists/chatgpt-project-sources-rows.webp` | document rows with small type icons, no filled buttons |
| [XChat, message sheet](https://mobbin.com/screens/bc8a4ddd-5ea3-4d38-9c93-e21017815296) · `sheets/xchat-message-actions-sheet.webp` | grouped rows, red only on destructive rows |
| [Yuka, welcome](https://mobbin.com/screens/9e8f5f21-20bf-4f95-bc42-8d623c54b691) · `auth/yuka-welcome-carrot-single-green-button.webp` | small mascot, one button, no gradient |
| [Partiful, empty dark](https://mobbin.com/screens/ab64dcb9-cd6e-48bb-94e9-f1620dcaba00) · `empty/partiful-new-message-mascot-dark.webp` | the mascot is the only colour in an empty state |

All 59 picks, with links, are in `docs/Inspiration/calm-rest/refs.md`.
Ahead has no dark screen on Mobbin.

## Counts (code, 2026-11-15, `main` at `f3321fe`)

"Solid" = `t.accent` used as a fill, text, icon or border. "Keep" = on the
C5 list (primary action, badge, play disc, progress, focus ring, cursor) or
on the new C5b list (§A1). Type is off-scale when not 28/24/20/16/15/13/11.
Spacing is off-scale when not 4/8/12/16/20/24/32/40/48 (inner padding of
micro pills excepted). Raw motion = a literal `Duration` or `Curves.*` in UI
code (timers and timeouts are not counted).

| Screen | Solid accent today → after | Soft accent avatar | Off-scale type | Off-scale space / radius | Raw motion |
|---|---|---|---|---|---|
| Home (`home_screen.dart`, `chat_tile.dart`, `home_search_bar.dart`) | 7 → 4 (unread time, avatar press ring, warning icon go) | 1 (`home_screen.dart:662`) | 21, 10, 12, 13.5 ×3 | 18 (10 ×6, 7 ×2, 5 ×2, 9, 2, 1) | 4 × `1400 ms` skeleton, `Curves.easeOut` (`home_search_bar.dart:174`), local `_homeMotionDuration` (`:1202`) |
| Requests (`friend_requests_screen.dart`, `request_card.dart`, `group_invite_card.dart`) | 3 + 1 per card → 1 + 0 (Accept per card goes tonal; warning icon, offline icon, invite badge go) | 2 | 12 ×2 | 8 (14 ×6, 6 ×2) | `1400 ms` skeleton (`:421`), local `_motionDuration` (`:493`) |
| Group info (`group_settings_screen.dart`) | 4 → 2 (switch, picker check stay) | 1 + Add pill + Admin pill | 12 ×2 | 11 (14 ×5, 2 ×4, 6 ×2) | `1400 ms` skeleton (`:1484`), local `_motionDuration` (`:51`) |
| New group (`create_group_screen.dart`) | 4 → 2 (check disc, focus ring stay) | 2 | 12 ×2 | 6 (6 ×3, 14, 10, 2) | none; skeleton without a group |
| Profile + Edit (`profile_screen.dart`, `edit_profile_screen.dart`) | 2 → 0 (photo badge, offline icon) | 2 | 12 | 0 | none |
| Settings + About + App lock | 4 → 4 (check discs, 3 switches: all on C5b) | 0 | 14 (`settings_screen.dart`), 12.5 (`settings_tile.dart:57`) | 1 (14) | none |
| Add a friend sheet (`add_friend_screen.dart`) | 3 → 1 (search button stays; gallery button, 3 dp tab bar go) | 1 | none off-scale | 2 (14, 72) | none |
| Starred (`starred_messages_screen.dart`) | 2 → 0 (star icon → `accentText`, **You** label → inkSoft) | 0 | 12 | 2 + radii 14, 12, 12 | none |
| Media & docs (`media_docs_screen.dart`) | 8 → 2 (player disc, progress stay) + default `TabBar` accent label and bar | 0 | 12 ×4, 9 | 7 (6 ×4, 2 ×3) + radius 4 | none |
| Auth (`login`, `register`, `forgot_password`, `google_onboarding`, `backup_pin`, `splash`) | 2 → 2 (one primary button per screen, restore progress) | 1 + forgot-password icon disc | 17, 19, 12 (`backup_pin_screen.dart`) | 0 | splash `150 ms` ×2, backup PIN `450 ms` + `easeInOutCubic`, `200`, `250` |
| Sheets and dialogs (`app_sheet.dart`, `app_dialog.dart`, `message_context_menu.dart`) | 0 → 0 | 2 (`message_context_menu.dart:208,412`) | 0 | 0 | none (motion pass B4 done) |
| Shared (`app_button.dart`, `app_field.dart`, `app_toast.dart`, `photo_picker_badge.dart`, `status_banner.dart`) | photo badge disc, banner border | — | button label **w700** (law: actions 600), field 12, toast 14 | — | busy ring uses the theme default colour (accent on an accent button) |

Device count, Home at rest (M52, AMOLED shot `home-amoled.png`): 9 marigold
spots on one screen (new-chat button, 4 unread badges, 4 unread times). After
part 1: 5 (button + 4 badges), and no row has more than one.

## A. Shared rules (part 1)

### A1 Colour roles (foundation C5 amendment)

- **C5 (unchanged)** solid accent: send and mic, new-chat button, primary
  button, unread badge, voice play disc, playback and download progress,
  focus ring and text cursor.
- **C5b (new)** solid accent for **state controls that are on**: a switch's
  track, a ticked check disc (theme, font, member picker, poll). They are
  small and their colour means "on". See decision CR-5.
- **Never marigold**: list icons, row icon wells, info and warning icons in
  banners (they take `accentText`), labels such as **You**, tab labels,
  avatar placeholders, secondary buttons, small pills (Admin, Add).
- **Marigold text** is always `accentText` (primary/800 light,
  primary/300 dark), never `accent` (2.0 : 1 on light surfaces, the
  2026-10-28 learning).
- **One solid primary per screen.** Where an action repeats on each row
  (Accept on every request, Add on a member list) it uses the new **tonal**
  button (A3), not solid marigold.

### A2 Avatar placeholder (registry R1 amendment)

One look on every screen: `surface2` fill, 1 dp `line` ring, initials in
`inkSoft` 600. The `accentSoft: true` flag is removed and its 12 callers
(listed in the diff) drop it. Photos keep no ring. Same as Chat calm C9.

### A3 Buttons (registry R3 amendment)

| Variant | Fill | Label | Use |
|---|---|---|---|
| primary | `accent` | `onAccent` | the one main action of a screen or sheet |
| **tonal (new)** | `bubbleMine` (primary/100 light, primary/900 dark) | `ink` | a main action that repeats per row or card |
| secondary | `surface` + 1.5 dp `line` | `ink` | everything else that is a button |
| text | none | `ink` | Cancel, Forgot password, links |

All labels **15/22 w600** (today w700, against the weight law). The busy
ring is `BusySpinner` (R3a) in the label's colour, never the theme accent on
an accent fill. Small (36 dp) tonal and secondary buttons exist for in-row
use (Group info **Add**); they keep a 48 dp tap area.

### A4 Photo badge (registry R21 amendment, decision CR-6)

32 dp disc, `surface2` fill, 2 dp `bg` ring, 16 dp camera icon in `ink`.
Used by Edit profile, New group, Group info, Google onboarding.

### A5 AMOLED

`surface2` on AMOLED becomes `#171512` (the Dark theme's `bg`, an existing
token) instead of `#0D0D0D`. Today it sits on a `#0A0908` surface and every
avatar disc, icon well and skeleton is invisible (`app_theme.dart:18`). With
A2's ring the discs read on black. Light and Dark are unchanged.

### A6 Tabs

Selected label `ink` 15/22 600, others `inkSoft`; indicator 2 dp `accent`
under the label, full tab width. One `tabBarTheme` in `app_theme.dart`, so
Media & docs (today the Material default: marigold label and bar) and Add a
friend (`add_friend_screen.dart:79`, 3 dp) match. Decision CR-7.

### A7 Loading

Every loading layout sits in **one** `SkeletonGroup` (R11) and passes no
duration. Today Home, Requests and Group info pass `1400 ms` per block and
none of the six screens with placeholders (Home, Requests, Group info, New
group, Profile, About) wraps them in a group, so each block breathes on its
own clock.

### A8 Motion helper

One `motionOf(context, duration)` in `lib/core/theme/tokens.dart` (returns
zero under reduced motion) replaces the three local copies
(`home_screen.dart:1202`, `friend_requests_screen.dart:493`,
`group_settings_screen.dart:51`) and the inline ones
(`home_search_bar.dart:172`, `splash_screen.dart:82`). The L8 grep gate from
the motion pass is widened to `lib/features/{home,friend_requests,groups,profile,settings,auth,starred_messages,media/screens/media_docs_screen.dart}` and `lib/core/widgets`, with an allow-list for timers,
timeouts and the restore envelope's mascot timings.

### A9 Type and spacing fixes (mechanical)

| Today | After | Where |
|---|---|---|
| 21 | 20/26 700 (`pageTitleStyle`) | Home title `home_screen.dart:188` |
| 10 | 11/14 600 | Home section count `:811` |
| 12 | 13/18 | Home `:835`, request and invite cards, group info, new group, edit profile, starred, share target, media & docs ×4, `app_field.dart` helper |
| 12.5 | 13/18 | `settings_tile.dart:57` subtitle |
| 13.5 | 13/18 (height 44, like R8) | `home_search_bar.dart` ×3 |
| 14 | 13/18 (settings), 15/22 (toast) | `settings_screen.dart`, `app_toast.dart` |
| 9 | 11/14 600 | media grid duration chip `media_docs_screen.dart:251` |
| 17, 19 | 16/22, 20/26 | `backup_pin_screen.dart` |
| padding 14 | 16 | request and invite cards, group info rows, starred card, add friend, `settings_tile.dart` |
| padding 10 (Home list sides, banner) | 12 | `home_screen.dart:227,698,856,…` |
| padding 6 / 2 / 7 / 5 / 9 | 8 / 4 / 8 / 4 / 8 | group info, new group, media & docs, Home |
| radius 14 / 12 | 16 / 10 | starred card / thumbnails |
| radius 4 | pill | media grid duration chip |

## B. Home (part 1)

- **B1** Row time is `inkSoft` always; an unread row shows it in `ink` 600.
  The badge is the only marigold on a row (CR-1). Sender prefix stays
  `inkSoft` 600 (Chat calm D3).
- **B2** The new-chat button hides while the list scrolls down and comes
  back on any scroll up or at the top (CR-2): slide 16 dp down + fade,
  `motionPress` out, `motionFast` in with `curveEnter`; the list's bottom
  padding becomes 88 (56 button + 16 + 16) so the last row's badge is clear
  at the end of the list.
- **B3** Rows stay cards (`surface`, radius 16) with an 8 dp gap (CR-3).
- **B4** Avatars per A2; the group badge disc stays `bg` with an `inkSoft`
  glyph and gets the A2 ring colour on its border.
- **B5** The profile button's pressed ring is `line`, not marigold
  (`home_screen.dart:654`). The load-error banner icon is `accentText`
  (`:747`).
- **B6** Placeholders per A7. The requests icon in the app bar pops its count
  with `springSoft` when a request arrives (`PopOnChange`).

## C. Settings, Profile, Edit profile, About, App lock (part 2)

- **C1** Settings keeps its groups (R10b). Icon wells `surface2` (AMOLED per
  A5), icons `ink`. Check discs and switches per C5b.
- **C2** Theme change cross-fades the whole app: `MaterialApp`
  `themeAnimationDuration: motionBase`, `themeAnimationCurve: curveMove`
  (today the Flutter default, 200 ms linear). Ticking a check disc
  cross-fades its fill over `motionFast`.
- **C3** Profile: avatar per A2 (photo when set); **Edit profile** is a
  secondary button; the friend-code card keeps `surface`; the copy icon
  swaps to a tick for 1.5 s with a `motionFast` cross-fade.
- **C4** Edit profile: photo badge per A4; offline icon `inkSoft`;
  **Save** stays a text action in the app bar (ink, 600).
- **C5** About keeps the logo tile (R15, the brand mark is allowed
  marigold); placeholders per A7.
- **C6** App lock: switches per C5b; nothing else changes.

## D. Requests, Group info, New group, Add a friend (part 3)

- **D1 Request and invite cards.** Avatar per A2. **Accept** = tonal,
  **Decline** = secondary (CR-4). The invite card's group glyph disc is the
  Home group badge (`bg`, `inkSoft` glyph), not a 20 dp marigold disc
  (`group_invite_card.dart:161`). Card padding 16.
- **D2** When a card is accepted or declined it leaves: fade + height closes
  over `motionExit` (190 ms) with `curveExit`; the cards below move up with
  it (motion L4 exception, as chat C10). Under reduced motion it is removed
  at once.
- **D3** Load-error banner icon `accentText`; offline strip icon `inkSoft`
  (`friend_requests_screen.dart:121,398`). The empty state keeps its one
  primary **Add a Friend**.
- **D4 Group info.** Group photo placeholder per A2 (48 radius); photo
  badge per A4. **Add** = small tonal button (`group_settings_screen.dart:732`).
  **Admin** pill = `surface2` fill, `inkSoft` 11/14 600 (`:833`). **Leave
  group** keeps the R10a destructive row (error icon, ink label). The
  only-admins switch per C5b.
- **D5** A member removed while the screen is open leaves like D2; a member
  added fades in over `motionEnter` (only rows added after the screen
  opened, motion C3).
- **D6 New group.** Rows: avatar per A2, check disc per C5b. Chosen people
  also show as chips in a row above the list (36 dp, R4 unselected look with
  a ✕), which pop in with `springSoft` from scale 0.6 and leave in
  `motionPress`. Name field focus ring stays marigold (C5). **Next** in the
  app bar is `ink` 600, disabled `inkFaint`.
- **D7 Add a friend sheet.** Tabs per A6. The search button stays solid (the
  sheet's one primary). **Pick from gallery** on the QR tab becomes a
  secondary button (`add_friend_screen.dart:455`). The found-person avatar
  per A2.

## E. Starred, Media & docs, Auth, sheets and dialogs (part 4)

- **E1 Starred.** Card radius 16, thumbnail radius 10. The row's star icon
  is `accentText` (it means "starred"); **You** / sender name is `inkSoft`
  13/18 600 (today `accent` text, 2.0 : 1 on white,
  `starred_messages_screen.dart:235`). An unstarred row leaves like D2.
- **E2 Media & docs.** Tabs per A6. Voice and document rows: 40 dp icon tile
  `ink` at 8 % with an `ink` icon (Chat calm E4), title 15/22 600, meta
  13/18 `inkSoft`; the trailing play and download icons are `inkSoft`
  (`media_docs_screen.dart:449-456,740-747`). The mini player keeps its
  solid play disc and progress (C5). Grid duration chip per A9.
- **E3 Auth.** Already one primary per screen. Changes: button weight (A3),
  avatar per A2 on Google onboarding, the forgot-password "sent" disc is
  `surface2` with an `ink` icon (`forgot_password_screen.dart:129`), restore
  progress keeps marigold (progress). Splash and restore use tokens: splash
  fades `motionFast`; the restore progress bar moves with `motionSlow` and
  `curveMove` (today 450 ms `easeInOutCubic`); the envelope and mascot timers
  are allow-listed.
- **E4 Sheets and dialogs.** Already calm (R19, R20, motion B4). The Home
  long-press sheet's header avatar per A2 (`message_context_menu.dart:208,412`).
  Destructive rows stay error icon + ink label. Nothing else changes.

## Decisions (defaults in bold)

| # | Question | Options |
|---|---|---|
| CR-1 | Unread row time on Home | **A: `ink` 600, the badge is the row's only marigold** · B: `accentText` (today) |
| CR-2 | New-chat button over the last row's badge | **A: hides on scroll down, back on scroll up (B2)** · B: move it into the app bar as an icon, no floating button · C: keep, padding only (does not help mid-list) |
| CR-3 | Home rows | **A: keep cards, 8 dp gap** · B: flat rows on the page, no card (Lapse, Apple) |
| CR-4 | An action that repeats per row (Accept, Add) | **A: tonal (primary/100 light, primary/900 dark, ink label)** · B: solid marigold (today) · C: ink fill (Genie, Swarm) |
| CR-5 | A switch that is on, a ticked check disc | **A: solid marigold (C5b)** · B: ink |
| CR-6 | Photo badge on avatars | **A: `surface2` disc, ink icon** · B: keep the marigold disc |
| CR-7 | Tabs | **A: ink label, 2 dp marigold bar** · B: `accentText` label + bar |
| CR-8 | Avatar placeholder | **A: `surface2` + 1 dp ring everywhere** · B: warm `accentSoft` everywhere (adds a marigold tint to every list) |

## Must not undo

- Chat calm and the motion pass stay as built (`858cd5a`, `c5c6c7a`); this
  spec does not touch the chat screen.
- Foundation C4: error red is never text on light; destructive rows are an
  error icon + ink label (R10a, C4b).
- Accent ink on a faint accent shell is unreadable in dark (2026-10-30
  learning): text on `bubbleMine` (tonal buttons) is `ink`.
- A settings row's trailing value stays flexible and end-aligned
  (2026-10-29 learning); A9's 13/18 subtitle must not overflow at 200 % text
  on 360 dp.
- A sheet that disables an online-only action watches the connection while
  open (2026-11-02 learning).
- Back never waits for a server write; D2/D5 exits never delay a pop.
- A screen never uses `ref` in `dispose`; exit animations dispose their
  controllers without it.
- Profile saves write the record into the cache, never invalidate auth
  (2026-10-29 learning).
- Remove and leave rotate group keys: D5's exit is drawn from the stream,
  never by retrying a remove.
- Grep gates: no hard-coded colours in screens; one `showModalBottomSheet`
  (R19); `CircularProgressIndicator` only via `BusySpinner` in features.

## Test gates

Per part, in its own test file under `test/design/calm_rest_*_test.dart`.

1. (P1) Avatar: an initials avatar has fill `surface2` and a 1 dp `line`
   border in light, dark and AMOLED; no caller passes `accentSoft`.
2. (P1) AMOLED `surface2` ≠ `surface`, and the initials pass 4.5 : 1 on it.
3. (P1) `AppButton` tonal: fill `bubbleMine`, label `ink`, both themes;
   every variant's label weight is 600; busy ring is a `BusySpinner`.
4. (P1) Home: an unread row has exactly one widget painted `t.accent` (the
   badge); its time is `ink`.
5. (P1) Home: scrolling down hides the new-chat button; scrolling up shows
   it; reduced motion = no animation, same end states.
6. (P1) Every loading layout in scope has one `SkeletonGroup` ancestor
   (`SkeletonGroup.debugLiveControllers == 1` per screen) and no
   `Skeleton(duration:)`.
7. (P1) L8 grep gate over the widened paths, allow-list as A8.
8. (P2) Theme change: `MaterialApp.themeAnimationDuration == motionBase`.
9. (P2) Settings rows at 200 % text on 360 dp: no overflow.
10. (P3) Request card: Accept is tonal, Decline secondary; accepting removes
    the card after `motionExit`; under reduced motion at once.
11. (P3) Group info: Add is tonal, Admin pill has no accent; New group chips
    appear for each ticked person and leave on untick.
12. (P4) Starred: no `t.accent` text; Media & docs: only the player disc and
    progress use `t.accent`; tab theme per A6.
13. (each) Full `flutter test` green against the baseline taken at build
    start; `flutter analyze` 0 errors.

## Device check list (M52 and Redmi, Light, Dark, AMOLED)

Part 1
1. Home at rest: each unread row has one marigold spot (the badge); read
   rows have none; times are grey.
2. Scroll down: the new-chat button slides away; scroll up: it returns. At
   the end of the list the last row's badge is clear.
3. AMOLED: initials discs and the group badge are visible on black.
4. Pull to refresh and a cold start on slow data: placeholders breathe
   together, nothing jumps.

Part 2
5. Settings: switch Light → Dark → AMOLED: the app cross-fades, no flash.
6. Profile and Edit profile: grey avatar disc, grey photo badge, Save works.
7. Large text (200 %): no Settings row overflows.

Part 3
8. Requests with 2+ requests (use test accounts): Accept is a soft marigold,
   not solid; accepting slides the card away; the rest move up.
9. Group info: Add and Admin are quiet; Leave group is the only red.
10. New group: tick three people, chips appear above the list; untick one.
11. Add a friend: the tab bar matches Media & docs.

Part 4
12. Starred: names are grey and easy to read in Light.
13. Media & docs: voice and doc rows are grey icons; playing a voice note
    shows the marigold disc and progress only.
14. Auth (on a test account, after sign-out on a spare phone): one marigold
    button per screen; restore progress moves smoothly.
15. Reduced motion on: every new motion above is instant.

## Out of scope

The chat screen, composer and media viewer; new mascot poses; onboarding
flow changes; copy changes; Home search filters; empty-state illustrations
beyond the existing mascot.

## Diff vs current (files a build touches)

Part 1: `lib/core/theme/tokens.dart` (`motionOf`), `lib/core/theme/app_theme.dart`
(AMOLED `surface2`, `tabBarTheme`), `lib/core/widgets/app_avatar.dart`,
`app_button.dart`, `photo_picker_badge.dart`, `chat_tile.dart`,
`lib/features/home/screens/home_screen.dart`,
`lib/features/home/widgets/home_search_bar.dart`,
`test/core/motion_tokens_test.dart` (wider gate),
`docs/design/00-foundation.md` (C5b, AMOLED row, weights),
`docs/design/10-registry.md` (R1, R3, R21).
Callers dropping `accentSoft: true` (A2): `google_onboarding_screen.dart:231`,
`add_friend_screen.dart:228`, `home_screen.dart:662`,
`message_context_menu.dart:208,412`, `profile_screen.dart:47`,
`edit_profile_screen.dart:268`, `request_card.dart:59`,
`group_invite_card.dart:153`, `create_group_screen.dart:685,690`,
`group_settings_screen.dart:505`. These are one-line removals and ship with
part 1 so every screen gets the same disc at once.

Part 2: `lib/app.dart:157` (`MaterialApp.router` theme animation),
`lib/features/settings/screens/settings_screen.dart`, `about_screen.dart`,
`lib/features/settings/widgets/theme_mode_group.dart`,
`lib/core/widgets/settings_tile.dart`,
`lib/features/profile/screens/profile_screen.dart`,
`edit_profile_screen.dart`, `lib/features/app_lock/app_lock_settings_screen.dart`.

Part 3: `lib/features/friend_requests/screens/friend_requests_screen.dart`,
`widgets/request_card.dart`, `widgets/group_invite_card.dart`,
`lib/features/groups/screens/group_settings_screen.dart`,
`create_group_screen.dart`, `lib/features/home/screens/add_friend_screen.dart`.

Part 4: `lib/features/starred_messages/screens/starred_messages_screen.dart`,
`lib/features/media/screens/media_docs_screen.dart`,
`lib/features/auth/screens/*.dart` (splash, backup PIN, forgot password),
`lib/core/widgets/app_field.dart`, `app_toast.dart`,
`lib/features/share/share_target_screen.dart` (type only).
