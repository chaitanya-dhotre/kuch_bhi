# Dead-code wave A — work log

Audit: `docs/audits/2026-10-30-dead-code.md` §1 and §3 only (§2 registry items are wave B — untouched). Base commit under audit: `a4b6f25`; work done on `70fd5ae` (current `main`, no commits made by this wave). Every audit claim was re-checked against today's tree (`trail callers`, plain `grep -rn -w` over `lib/` + `test/`, `flutter analyze`) before touching; anything that no longer matched would have been skipped (none found — all items still live as described, except where noted).

**Nothing user-visible changed.** Every migrated string is carried character-for-character (same punctuation, same em dashes, same quotes); formatter math proven identical for every reachable input (§3.3 note below). No layout, import-graph or behaviour changes. **PASS/grade is left to Claude; not claimed here. Not committed (per instructions).**

| Audit item | Status | Detail |
|---|---|---|
| §1.1 Google-prefill chain | **done** | Deleted as one unit: `getGooglePrefill` + `fetchGoogleProfile` (+doc comments) from `auth_repository.dart` interface, both impls (`auth_repository_impl.dart`, −34 lines), the provider wrapper `fetchGoogleProfile` (`auth_provider.dart`, −15 lines incl. doc), and the `GooglePrefill` class. Pre-verified: `trail callers` → "no indexed callers" for all three symbols; `grep -rn -w getGooglePrefill\|fetchGoogleProfile\|GooglePrefill lib/ test/` → only definition sites, zero test hits. `GoogleSignIn` import stays (live `signInWithGoogle`); `AuthAction.google` stays (live arms). |
| §1.2 video_player_screen.dart | **skipped (already done)** | File was deleted in an earlier commit (per prompt; confirmed absent from the tree — nothing to do). |
| §1.3 interface/impl methods with no callers | **skipped (kept per trail ruling)** | `trail ask "interface methods with no callers"` + the cited learning `.trail/learnings/2026-10-29-blocking-account-deletion-app-lock-mute-chaitanya.md` (id `l-2561fc62`): block/unblock/list and delete-account are ruled-out *unshipped features*, each "its own task" pending a server cascade/blocking verification — Methods are deliberate feature stubs, same family as the prompt's DO-NOT keeps (`local_auth`, `muteUntil`). Re-verified today: `deleteAccount` (auth_repository.dart:54 / impl:396), `setNickname` (friend_repository.dart:33 / impl:239), `blockUser` (:36/:245), `unblockUser` (:39/:257), `getBlockedUserIds` (:42/:273) — zero callers in lib+test (`grep -rn -w`); the only non-declaration mention is the banned-call regex at `test/grep_gates_test.dart:419`. Kept all five. |
| §1.4 media expiry_badge.dart | **done** | Deleted `lib/features/media/widgets/expiry_badge.dart` (71 lines: `ExpiryBadge`, `ExpiredMediaPlaceholder`) and the `expiryBadgeText` helper from `lib/core/utils/media_utils.dart` (−14 incl. doc). `isExpired`/`isPastRetention` kept — live (4 bubbles + media screens; `l-bcb4d29c` owns `isPastRetention`). The four media bubbles / message_bubble / media_viewer all import the **chat** copy (`features/chat/widgets/expiry_badge.dart`), which is untouched (live `ExpiryBadge`/`MediaDisc`/`ExpiredPlaceholder`). `test/chat/expiry_badge_test.dart` confirmed to bind the chat file — unaffected. |
| §1.4 — single test edit | **done (1 file, 1 line)** | `test/grep_gates_test.dart` Gate 10: removed the one scan target `'lib/features/media/widgets/expiry_badge.dart'` from the files list (the deleted file no longer exists — `File.readAsStringSync` would throw and fail the gate). This is the **only** test edit of the wave; the gate's test title/artwork text was left untouched (minimal edit). |
| §1.5 dead AppConstants members | **done** | Deleted from `lib/core/constants/app_constants.dart`: `apiUrl`, `appId`, `githubReleasesUrl`, `friendCodeLength`, `maxGroupMembers`, `maxFileSizeMb`, `connectTimeoutSeconds`, `receiveTimeoutSeconds`, `messagesPageSize`, `conversationsPageSize`, `onlineThresholdMinutes`. Alive members kept: `baseUrl`, `appName` (now referenced ×5 — §3.6, so it is no longer dead), `maxPinnedMessages`, `maxVoiceMessageSeconds`, the five `retention*Days`, and `kMediaCache*`. Re-verified zero `AppConstants.<name>` refs before deleting (grep). **`friendCodeLength` choice: deleted, not wired** — the `'6'` appears as a TextField `maxLength` and two `length` checks (`friend_request_provider.dart`, `add_friend_screen.dart`), but other occurrences are human copy ("Friend code must be exactly 6 characters.") that must not become a template; wiring two of three sites while leaving the copy hardcoded buys a false sense of one-source. The literal-6 sites stay exactly as they read today (deletion chosen, so no wiring). |
| §1.6 other no-caller bits | **skipped (kept per prompt)** | `local_auth` dependency and `muteUntil` column kept (app lock on backlog). `FcmDebugHelper` live via `main.dart:66`. pubspec.yaml and drift tables untouched. |
| §1.7 false positives | **n/a** | List-only; no action. |
| §3.1 offline strip | **done** | One exported **pair** (variants kept): `kOfflineActionsCopy` ("…actions are available…") ×4 sites (edit_profile, friend_requests, group_settings, create_group — all dropped their private `_offlineCopy`/inline const) and `kOfflineSendCopy` ("…messages will send…") ×3 sites (home ×2, chat) in `lib/core/constants/app_strings.dart`. |
| §3.2 username rules | **done** | Regex + `validateUsername` moved to `lib/core/utils/username_rules.dart` (copy verbatim). `register_screen.dart` imports it and **re-exports** `validateUsername`, so `test/auth/register_screen_test.dart` (which imports register_screen for it) compiles unchanged — no test edits. `google_onboarding_screen.dart` unchanged (resolves via its existing register_screen import). `edit_profile_screen.dart` drops its private `_usernamePattern` + re-typed three branches and now calls `validateUsername` + `kUsernameTakenCopy` (already exported by `auth_provider.dart`, already imported). |
| §3.3 m:ss formatter | **done** | `formatMmSs(int seconds)` in `lib/core/utils/format_utils.dart`. Six copies removed: `message_input.dart` `_formatDuration(int)`, `_fmt(int)`, `_fmt(Duration)`; `voice_message_bubble.dart` `_fmtDur`; `video_message_bubble.dart` `_durationText`; `media_docs_screen.dart` `_fmt(Duration)` (its `_formatDuration(dynamic)` keeps only its JSON-parse pre-step, delegating to `formatMmSs`). `formatMmSs` reproduces the *int* path exactly (`~/ 60`, `% 60`); Duration callers pass `d.inSeconds` — identical for every reachable input (all player totals are voice notes ≤300s, minutes < 60) and consistent with the int path for larger values. `_durationTextToSeconds` (inverse parse) untouched. |
| §3.4 byte formatter | **done** | `formatFileSize(raw, {required bool bytesUnitSpaced})` in format_utils; both B-unit variants preserved: document bubble `123 B` (`bytesUnitSpaced: true`), docs screen `123B` (`false`); KB/MB lines identical (original used 1048576 vs 1024×1024 — equal integers). |
| §3.5 media-type labels | **done (exact-duplicate form, variants kept)** | Plain labels single-sourced as `kMediaRowPhotoLabel`/`kMediaRowVideoLabel`/`kMediaRowVoiceLabel`/`kMediaRowDocumentLabel` (~20 sites: message_bubble switch, reply_quote, image/video/voice/doc bubbles' `what` + previews, starred rows, media docs, media viewer `_isVideo ? … : …`, attach_sheets row). Emoji glyph labels single-sourced as `kPreviewPhotoLabel`/`kPreviewVideoLabel`/`kPreviewVoiceLabel`/`kPreviewDocumentLabel`, consumed by the C9 owner `conversationPreviewLabel`, the pinned-banner fallbacks, the repo's `_deriveReplyPreview`, and reply_quote's 🎤 arm. **Not** converted to the audit's "derive all labels from C9 wholesale" idea — that would put emoji where plain labels render (visible change). Interpolated banner rows (`'🎬 Video · $body'`, `'🎤 Voice message · $body'`, `'📎 $body'`) are non-exact variants, left as raw code per "keep both variants". |
| §3.6 app name | **done** | `AppConstants.appName` now referenced ×5: `app.dart` (title), `splash_screen.dart`, `home_screen.dart` (title), `about_screen.dart` ×2 (title + `applicationName:`). The `'Kuch Bhi'` literal now lives only in app_constants. (Compound copy like "Join Kuch Bhi" / "Scan to add me on Kuch Bhi" is not the standalone name const — untouched.) |
| §3.7 failure copy | **done (4 families)** | `kUpdateFailedCopy` ×4 (group_settings dropped `const _updateFailed`; friend_requests ×2 toasts; disappearing_dialog). `kSaveFailedCopy` ×3 (media_viewer ×2, edit_profile). `kLoadFriendsFailedCopy` ×2 (create_group, group_settings). `kConnectionRetryCopy` 'Check your connection and try again.' ×4 (home, starred, friend_requests, create_group empty-state subtitles). The LONGER variant strings ("Can't reach the server. Check your connection and try again.", "Couldn't start fresh. …", "Couldn't save your backup. …", "Couldn't create the group. …") are distinct copy — untouched. |
| §3.8 `Voice message · $dur` | **done** | `voiceMessageRowCopy(String dur)` → referenced at reply_quote, starred row, media_docs sheet title (all three feed an `m:ss` dur). Plain `'Voice message'` inside the same guards now `kMediaRowVoiceLabel`. |
| §3.9 admin copy | **done** | `adminPromotedCopy(name)` / `adminDemotedCopy(name)` in app_strings; consumed by the moderation toasts (group_settings ×2) and the mirrored system-message bodies (message_repository_impl ×2) so toast and persisted system row can't drift. |
| §3.10 media hero tag | **done** | `mediaHeroTag(String serverId) => 'media_$serverId'` in `media_retry.dart` (already imported by both bubbles); the 4 string literals in image/video bubbles now call it. `media_docs_…` tags are a different family — untouched. |
| §3.11 misc CTA/empty-state | **done** | `kAddFriendCtaLabel` ×3 (home button, friend_requests button, create_group button — `const` preserved via `const Text(kAddFriendCtaLabel)`), `kNoPendingRequestsCopy` ×2 (home label, friend_requests title), `kSystemDefaultLabel` ×2 (theme_provider, font_provider label switches). |
| §2 registry consolidation | **skipped (wave B)** | Not touched: AppAvatar/initialsOf, BusySpinner, showToast raw sites, pageAppBar, SearchField, shimmer, shadow layers. |
| Frozen areas | **skipped (verified untouched)** | Diff touches none of: `lib/infrastructure/media/`, `lib/services/encryption_service.dart`, key/backup/restore code (`backup_pin_screen.dart` unchanged), the upload path in `lib/services/media_upload_service.dart`, `lib/infrastructure/offline/outbox*`. `message_repository_impl.dart` is NOT frozen; only its admin system-message bodies, reply-preview glyph labels and imports changed. |

## Files touched (git diff HEAD --stat)

```
 lib/app.dart                                       |  3 +-
 lib/core/constants/app_constants.dart              | 20 ------
 lib/core/constants/app_strings.dart                | 48 +++++++++++++++   (NEW)
 lib/core/utils/format_utils.dart                   | 19 ++++++            (NEW)
 lib/core/utils/media_utils.dart                    | 14 -----
 lib/core/utils/username_rules.dart                 | 13 ++++              (NEW)
 lib/domain/repositories/auth_repository.dart       | 22 -------
 lib/features/auth/providers/auth_provider.dart     | 15 -----
 lib/features/auth/screens/register_screen.dart     | 14 ++---
 lib/features/auth/screens/splash_screen.dart       |  3 +-
 lib/features/chat/screens/chat_screen.dart         |  3 +-
 lib/features/chat/widgets/attach_sheets.dart       |  3 +-
 lib/features/chat/widgets/disappearing_dialog.dart |  3 +-
 .../chat/widgets/document_message_bubble.dart      | 15 ++---
 .../chat/widgets/image_message_bubble.dart         |  9 +--
 lib/features/chat/widgets/media_retry.dart         |  5 ++
 lib/features/chat/widgets/message_body_text.dart   |  9 +--
 lib/features/chat/widgets/message_bubble.dart      |  9 +--
 lib/features/chat/widgets/message_input.dart       | 21 ++-----
 .../chat/widgets/pinned_message_banner.dart        | 11 ++--
 lib/features/chat/widgets/reply_quote.dart         | 22 ++++---
 .../chat/widgets/video_message_bubble.dart         | 18 +++---
 .../chat/widgets/voice_message_bubble.dart         |  9 +--
 .../screens/friend_requests_screen.dart            | 17 +++---
 .../groups/screens/create_group_screen.dart        | 15 ++---
 .../groups/screens/group_settings_screen.dart      | 24 ++++----
 lib/features/home/screens/home_screen.dart         | 15 +++--
 lib/features/media/screens/media_docs_screen.dart  | 39 +++++-------
 .../screens/media_viewer_screen.dart               |  7 ++-
 lib/features/media/widgets/expiry_badge.dart       | 71 -------------------
 .../profile/screens/edit_profile_screen.dart       | 18 +++---
 lib/features/settings/providers/font_provider.dart |  3 +-
 .../settings/providers/theme_provider.dart         |  3 +-
 lib/features/settings/screens/about_screen.dart    |  5 +-
 .../screens/starred_messages_screen.dart           | 21 ++++---
 .../repositories/auth_repository_impl.dart         | 34 -----------
 .../repositories/message_repository_impl.dart     | 13 ++--
 test/grep_gates_test.dart                          |  1 -
 38 files changed, 235 insertions(+), 359 deletions(-)
```

Net: −124 lines; the only test-file change is the single grep-gate line above.

## Gates (run by this wave, output verbatim)

- **flutter test** → `00:31 +741: All tests passed!` (741/741). Baseline check: `flutter test` on a clean `HEAD` worktree (`70fd5ae`) printed `00:41 +741: All tests passed!` — identical count, so no test was lost/added; the only test edit is the one gate target removal recorded above.
- **flutter analyze** → `82 issues found. (ran in 2.5s)`, **0 errors**. Baseline `flutter analyze` on the `HEAD` worktree: `82 issues found. (ran in 1.4s)`. Diffed rule-by-rule (file+rule sorted, line numbers stripped): info and warning sets **identical to baseline** — only pre-existing line-number shifts from the deletions (e.g. `auth_repository_impl.dart` warnings shift −34). No new warnings or infos in any touched file. (Two `dangling_library_doc_comments` infos were introduced and immediately fixed by adding `library;` to the three new core files — final count matches baseline exactly.)
- **git diff --check** → clean (exit 0, no trailing whitespace / conflict markers).
- **git diff --stat** → listed above; 38 files, all traceable to the items in this table; nothing outside `lib/` + the single `test/grep_gates_test.dart` line. (`android/build/reports/problems/problems-report.html` had a pre-session tooling modification unrelated to this wave; restored to HEAD so the diff stays scoped.)

## Judgement calls (for the grader)

1. `§1.3`: kept per the trail ruling; same posture as the prompt's DO-NOT keeps.
2. `§1.5 friendCodeLength`: deleted (option B). Reason logged above.
3. `§3.3/§3.4`: exported **functions**, not consts — the audited duplicates are formatter bodies, not literals; outputs preserved char-for-char (the byte-margin variant preserved via an explicit `bytesUnitSpaced` flag rather than unifying, which would have changed visible text).
4. `§3.5`: emoji and plain label families kept as **two variants each** (audit's C9 kept as the type→label owner; emoji consts live beside the other copy in app_strings so the repo layer (which cannot import a widget file) can reference the same strings).
5. `§3.9`: one wording per direction via small functions (name-interpolated), emitted from both the toast and the persisted system message.
6. Gate 10's test name still reads "…+ expiry badge…" while it now scans only media_docs — the title was deliberately left untouched to keep exactly one line of test diff; noted for the wave-B/MMM follow-up if desired.
7. `pubspec.yaml`, drift `.g.dart`, router: untouched (route table has no dead entries per §1.2's re-check).
