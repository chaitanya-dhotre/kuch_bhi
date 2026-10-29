# Settings + About — acceptance checklist (Page 6)

Date: 2026-10-29. Visual ground truth: **`docs/design/pages/settings.html`** (sections S1–S11,
numbered; S9 = what Settings holds, S11 = full diff vs current code). Authority:
`docs/design/00-foundation.md` (tokens/laws) → `docs/design/10-registry.md` (shared pieces) → this
checklist. Page letters A–G are page-local. Line refs: `ss` = `settings_screen.dart`,
`ab` = `about_screen.dart`, `tp` = `theme_provider.dart`, `ps` = `profile_screen.dart`, as of
`81a6502`.

**Starting point.** Both screens exist and were audited 2026-10-29 (80 + 93 lines, plus the 61-line
theme provider). Only entry point: Profile's gear (`ps:172`); About is reached only from Settings
(`ss:74`). Neither has a widget test; the only coverage is the colour gate in
`test/grep_gates_test.dart:18`. Every item below changes existing code (S11) unless marked NEW.

**Routing.** Claude end to end (spec, implementation, grading). No Astra/Mimo brief. The grading
pass is a fresh-context reviewer (subagent or `/code-review`), never the implementer.

**Pass criteria (page complete when):** all MUSTs ✓ · `flutter analyze` 0 errors · `flutter test`
green (baseline **405/405**, plus the new tests, with no existing test edited to pass) · test-gate
files below green · `git diff --check` clean · forbidden-pattern grep over `lib/features/settings/`
empty · fresh-context review with no open BLOCK · device captures light + dark (+ one AMOLED) of:
Settings, Settings with notifications Off, About · user device PASS (no commit without it).

**Spec status: user PASS 2026-10-29. Every deferred decision = its default.** Implementation: code-level PASS after an independent review, device PASS 2026-10-29 (see `settings-work-log.md`). Deferred decisions at the bottom; each had a
recommended default.

**Pre-implementation gate:** none on the server. This page writes nothing to PocketBase.

**Status key:** `[x]` implemented AND verified by code/tests or recorded device evidence;
`[ ]` pending, partial, or blocked.

---

## ⛔ Key boundary (read first: a breach here is an automatic FAIL)

Settings and About do **not** edit, call or import: secure storage, key generation / rotation /
re-wrap, `signOut`, `deleteAccount`, `updatePublicKey`, the Backup PIN screens, `lib/core/decrypt/`, or the
encryption / key services. The grep gate enforces the imports. Read for context only, do not re-solve:

- `.trail/learnings/2026-10-28-group-key-rotation-keeps-history-only-chaitanya.md`
- `.trail/learnings/2026-10-28-group-key-re-wrap-recovers-rows-chaitanya.md`
- `.trail/learnings/2026-10-29-one-device-rotates-a-group-s-chaitanya.md`
- `.trail/learnings/2026-10-29-never-refresh-the-signed-in-user-chaitanya.md`

## A. Shell, laws, grep-gated hygiene (S1, S3)

- [x] **A1 MUST** Both screens use **R14 `pageAppBar(context, title)`** (NEW
  `lib/core/widgets/page_app_bar.dart`) and `Scaffold(backgroundColor: t.bg)`. R14 = Profile's
  `profileAppBar` moved as is (bg + tint `t.bg`, elevation 0, scrolledUnder 0, title 20/26 w700 ink)
  plus `Semantics(header: true)` on the title. Profile's 6 call sites switch to it;
  `profileAppBar` and `profileTitleStyle` are removed from `ps` (move the title style with it if
  anything else uses it). No third copy.
- [x] **A2 MUST** C3: colours only via `context.t.*`; radii only via `WarmPopTokens` (`ab:30`
  `circular(22)` → `radiusXl`); no `colorScheme`, no `withValues(alpha` (`ab:46-50, 60-64`).
- [x] **A3 MUST** C4: no accent- or error-coloured `Text` on either screen. Accent appears only as a
  fill (check disc, logo tile).
- [x] **A4 MUST** Type scale only (foundation §3): no 12.5 / 14.5 sizes in page code (`ss:31, 51`).
  R10's own subtitle size is the registry's, not this page's (out of scope).
- [x] **A5 MUST** No `$e` / `e.toString()` in user-visible text; detail goes to `debugPrint` only.
- [x] **A6 MUST** `lib/features/settings/` imports no `pocketbase`, `dio`, `http`,
  `connectivity_plus`, secure storage or crypto code, and never calls `invalidate(authProvider)`.

## B. Settings — sections (S2)

- [x] **B1 MUST** Order: **Appearance** (R9 `SectionHeader('Appearance')` + one R10b group of 4
  rows) → **Notifications** (R9 + one R10b group of 1 row) → 24 gap → one R10b group with **About**
  (R10, chevron, pushes `AppRoutes.about`). No other rows.
- [x] **B2 MUST** The amber `APPEARANCE` text (`ss:26-36`) is gone; headers are R9 (inkFaint).
- [x] **B3 MUST** (decision 3) No Backup PIN row on Settings (`ss:63-69` removed). Profile's
  **Change Backup PIN** row (`ps:290`) is untouched and still works.
- [x] **B4 MUST** `ListView` padding 0 top / 24 bottom; groups inset 12 left/right like Profile.

## C. Appearance — theme (S4)

- [x] **C1 MUST** Each mode is an R10 `SettingsTile`: `mode.icon` in the well, `mode.label` as the
  title, trailing check disc 24: selected = accent fill + onAccent tick (`Icons.check` 16), not
  selected = 2px `t.line` ring. No `RadioListTile`, no accent ring.
- [x] **C2 MUST** Selection follows `themeModeProvider` (`valueOrNull ?? system`, as today). The tick
  moves only when the Drift stream emits.
- [x] **C3 MUST** Tap = `await ref.read(themeControllerProvider).setTheme(mode)` inside
  `try/catch`. On a throw: R5 `showToast(context, "Couldn't change the theme. Try again.", error:
  true)` (only if still mounted), `debugPrint` the detail, tick unchanged.
- [x] **C4 MUST** `theme_provider.dart` keeps its public API (`AppThemeMode`, `themeModeProvider`,
  `themeControllerProvider`, labels, icons) so `app.dart:108-120` is unchanged.

## D. Notifications row (S5) — NEW, decision 2

- [x] **D1 MUST** NEW `notificationsEnabledProvider` (`FutureProvider.autoDispose<bool>` in
  `lib/features/settings/providers/notification_status_provider.dart`) =
  `(await Permission.notification.status).isGranted`. NEW `openSystemSettingsProvider`
  (`Provider<Future<bool> Function()>`, default `openAppSettings`). Both exist so tests override
  them; no platform channel in tests.
- [x] **D2 MUST** Row: R10, title **Notifications**. `data(true)` → subtitle **On**, icon
  `Icons.notifications_none`. `data(false)` → **Off. Turn them on in system settings.**, icon
  `Icons.notifications_off_outlined`. Loading or error → no subtitle, `notifications_none` icon.
  Trailing `Icons.open_in_new` 20 in inkSoft (not a chevron).
- [x] **D3 MUST** Tap → `await ref.read(openSystemSettingsProvider)()`; `false` or a throw → R5
  **Couldn't open system settings.** (error variant).
- [x] **D4 MUST** On app resume (`AppLifecycleListener(onResume:)`, disposed with the screen)
  `ref.invalidate(notificationsEnabledProvider)`, so the row updates after a trip to system
  settings.
- [x] **D5 MUST** Never an in-app on/off switch and never per-type toggles (the server keeps no
  preference: S9 row 2).

## E. About (S6)

- [x] **E1 MUST** Top-aligned `ListView` (not a centred column). Hero: logo tile 88, `radiusXl`,
  `t.accent` fill, `Icons.lock_outline` 44 in `t.onAccent` · **Kuch Bhi** 24/30 w700 ink (not
  `headlineSmall`) · tagline 15/22 inkSoft. Then one R10b group, then the footnote 13/18 inkSoft
  centred. All copy unchanged.
- [x] **E2 MUST** **Version** row: R10, no tap, trailing `version (buildNumber)` 15 inkSoft. While
  pending: R11 `Skeleton(width: 64, height: 14)` in the trailing slot. On error: **Unknown**.
  `_InfoRow` deleted. The `PackageInfo` future is created once (in `initState` or a provider), not
  in `build`.
- [x] **E3 MUST** **Open-source licences** row: R10 + chevron → `showLicensePage(context: context,
  applicationName: 'Kuch Bhi', applicationVersion: <version or null>)`. No new dependency; the
  framework page is not restyled.

## F. Offline (S8)

- [x] **F1 MUST** No offline dim and no `kOfflineActionHint` on either screen: every control works
  offline. (A6's import gate keeps this true.)

## G. A11y & motion (S10)

- [x] **G1 MUST** Theme rows: `Semantics(selected: <bool>, inMutuallyExclusiveGroup: true)`; the
  tick glyph is excluded from semantics.
- [x] **G2 MUST** Notifications row has the hint **Opens system settings**.
- [x] **G3 MUST** No fixed heights on text; About scrolls at 200% text size without overflow.
- [x] **G4 MUST** No custom animation; R11 parks under reduced motion (registry contract).

## Registry amendments (same commit, L2)

| ID | Amendment |
|---|---|
| R14 | `pageAppBar(BuildContext context, String title, {List<Widget>? actions})` in NEW `lib/core/widgets/page_app_bar.dart`: Profile's `profileAppBar` moved (page-colour bar, 20/26 w700 ink title) + `Semantics(header: true)`. Used by Profile (6 sites), Settings, About. Moving Group Info's inline copy (`group_settings_screen.dart:419`) onto it is a SHOULD. |
| R10b | `SettingsGroup({required List<Widget> children})` in `lib/core/widgets/settings_tile.dart`: Profile's private `_Group` moved (surface, `radiusMd`, `Clip.antiAlias`, 1px `t.line` dividers). Profile and Settings use it. |

## Test gates (mandatory; there are NO settings tests today)

- [x] NEW `test/settings/settings_screen_test.dart` (in-memory `AppDatabase` or an overridden
  `themeModeProvider` / `themeControllerProvider`; no platform channels): sections in order
  Appearance → Notifications → About · the selected mode has the tick and `selected` semantics,
  the others not · tapping **Dark** calls `setTheme(AppThemeMode.dark)` once · a throwing
  `setTheme` shows **Couldn't change the theme. Try again.** and no exception escapes ·
  notifications `true` → **On**, `false` → **Off. Turn them on in system settings.** · tapping the
  row calls the opener once; opener `false` → **Couldn't open system settings.** · **About** pushes
  `/about` · no **Backup PIN** text · no `Text` styled with `t.accent` or `t.error`.
- [x] NEW `test/settings/about_screen_test.dart` (`PackageInfo.setMockInitialValues`): shows
  **1.0.0 (1)** for version `1.0.0` build `1` · **Open-source licences** opens a `LicensePage` ·
  tagline and footnote text present · no accent/error `Text`.
- [x] `test/grep_gates_test.dart`: NEW test **inside `main()`** for `lib/features/settings/`:
  no `colorScheme`, `withValues(alpha`, `CircularProgressIndicator`, `RadioListTile`,
  `(Border|Radius).circular(<digit>`, `e.toString()` / `$e` except on `debugPrint(` lines,
  `invalidate(authProvider)`, `kOfflineActionHint`, and no import of `pocketbase`, `dio`,
  `package:http`, `connectivity_plus`, `secure_storage` or `crypto`. Verify it runs: break it once
  locally (RED), then restore.
- [x] Count: the work log records **405 + N = total**, N = the tests added, and the suite total
  matches. No existing test edited to pass (Profile tests may change only for the R14/R10b move,
  and only in imports or names; each such edit is listed in the work log).
- [x] Full suite green · analyze 0 errors · `git diff --check` clean.

## Device check list (phase 2, M52 if connected, else Redmi S2)

Theme: each of the 4 modes re-themes the whole app immediately, and survives an app restart ·
Notifications: shows **On**; turn notifications off in Android settings → back → **Off…** without
reopening the screen; turn on → **On** · the row opens the app's system page · About: version is
the installed build, licences page opens and scrolls · Profile still shows its page-colour bar and
**Change Backup PIN** still opens the PIN flow · airplane mode: every row on both screens still
works, nothing dimmed.

## Out of scope (do NOT build on this page)

Every row S9 leaves out (privacy toggles, blocked users, storage, app lock, delete account, sign out
here, default disappearing timer) · the key boundary above · Backup PIN screens · auth screens
(page 7) · the hidden dev section · restyling `LicensePage` · the About mascot (page 10) · R10's
subtitle size · L4 for `theme_provider.dart` · removing the unused `local_auth` dependency.

---

## Diff vs current implementation

| # | Area | Today (file:line) | Spec | Checklist |
|---|---|---|---|---|
| 1 | App bar | Default `AppBar` `ss:20`, `ab:12` | R14 `pageAppBar` (promoted from `ps:28`) | A1 |
| 2 | Section header | Accent text 12.5 w700 (2.02:1) `ss:26-36` | R9 `SectionHeader` | A3, B2 |
| 3 | Theme rows | 4 separate `RadioListTile` cards, 8px gaps, 14.5 titles, accent radio `ss:38-61` | One R10b group of R10 rows + check disc | C1 |
| 4 | Theme write | `setTheme` not awaited, no error path `ss:44` | await + try/catch → toast | C3 |
| 5 | Theme semantics | Radio semantics only | `selected` + `inMutuallyExclusiveGroup` | G1 |
| 6 | Backup PIN | Row here `ss:63-69` and on Profile `ps:290` | Removed here (decision 3) | B3 |
| 7 | Notifications | None | NEW status row → system settings | D1–D5 |
| 8 | About row | Same list as Backup PIN `ss:70-75` | Own R10b group after 24 | B1 |
| 9 | About app bar | Default `AppBar` `ab:12` | R14 | A1 |
| 10 | Logo radius | `circular(22)` `ab:30` | `WarmPopTokens.radiusXl` | A2, E1 |
| 11 | App name | `headlineSmall` `ab:38` | 24/30 w700 ink | E1 |
| 12 | C3 colour | `colorScheme.onSurface.withValues(.6/.5)` `ab:46-50, 60-64` | `t.inkSoft`; grep gate | A2, E1 |
| 13 | Version load | **…** while pending and forever on error `ab:13-18` | R11 skeleton · **Unknown** | E2 |
| 14 | Version row | Centred "Version: x" `_InfoRow` `ab:54, 77-93` | R10 row, trailing value; `_InfoRow` deleted | E2 |
| 15 | Licences | None | NEW row → `showLicensePage` | E3 |
| 16 | About layout | Centred column `ab:19` | Top-aligned `ListView` | E1, G3 |
| 17 | L4 | `tp:37-48` reads Drift directly | Kept (device-local preference) | — |
| 18 | Shared pieces | `profileAppBar`, `_Group` private to Profile `ps:28, 313` | Promoted: R14, R10b; Profile uses them | A1, Registry |
| 19 | Tests | None; only the colour gate `grep_gates_test.dart:18` | 2 widget-test files + a page gate inside `main()` | Test gates |

---

### Deferred decisions (user decides at spec review; default = recommended)

Every candidate row was checked against what the app and PocketBase support today (evidence in
`settings.html` S9).

1. **Theme stays inline as four rows.** Alternative: one **Theme** row that opens a picker sheet.
2. **Notifications = a status row that opens Android's app settings.** `permission_handler` is
   already a dependency and the manifest declares `POST_NOTIFICATIONS`. An in-app switch or
   per-type toggles are **not offered**: the PB hook `fcm_notify.pb.js` pushes every message and
   keeps no per-user preference, so a switch would not stop pushes. Alternative: leave the row out.
3. **Backup PIN leaves Settings.** Profile → Account has had **Change Backup PIN** since Page 5;
   two entry points to one flow is one too many. Alternatives: keep it in both, or move it to a
   Settings "Security" section and drop it from Profile.
4. **Privacy toggles (read receipts, typing, last seen): left out.** `presence_service.dart:61-118`
   writes `last_seen` / `typing_in` on every call, receipts are always written, and nothing reads a
   preference on either side. Its own task.
5. **Blocked users: left out.** `blockUser` / `unblockUser` / `getBlockedUserIds`
   (`friend_repository_impl.dart:245-284`) have zero callers and nothing filters a blocked user.
   The live `blocked_users` collection was **not verified**: the read-only server query was
   declined this session. A list screen would promise blocking that does not happen. Its own task.
6. **Storage / clear cache: left out.** No storage accounting exists, and the cache is the
   offline-first store, so clearing it is data-loss-adjacent. Its own task.
7. **App lock: left out.** `local_auth` is in `pubspec.yaml` with zero uses in `lib/`. Its own
   security task.
8. **Delete account: left out.** `deleteAccount()` (`auth_repository_impl.dart:377`) has no caller
   and deletes only the `users` row, orphaning memberships, group keys and messages. Needs a server
   cascade; inside the key boundary.
9. **About = version + Open-source licences** (Flutter's built-in page, no dependency).
   Alternative: version only.
10. **Sign out and a default disappearing timer: not on Settings.** Sign out lives on Profile with
    a confirm; disappearing is per conversation (C11) and has no default concept.
