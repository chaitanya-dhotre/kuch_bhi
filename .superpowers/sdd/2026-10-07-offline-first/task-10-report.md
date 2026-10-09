# Task 10 report — Screen HTTP behind services

**Status:** DONE — LIGHT tier, guard-5 verbatim moves ×6, gates all green.
**Commit:** `fb2a245` `[Offline P5] Screen HTTP behind services — profile/group/onboarding/link-preview`
(13 files, +407/−148; BASE `8019079` verified HEAD+clean at start; trailer present).
**Device captures:** DEFERRED per ledgered ruling → P5 batch checkpoint (avatar upload / group create / link preview unverified on device; this task's gate = tests).

## File table

| Path | Change |
|---|---|
| `lib/infrastructure/services/profile_update_service.dart` | NEW — PB `users.update` + multipart avatar (from edit_profile_screen) |
| `lib/infrastructure/services/group_create_service.dart` | NEW — conversation/members/users/group_keys/messages writes + baseUrl (from create_group_screen) |
| `lib/infrastructure/services/auth_onboarding_service.dart` | NEW — onboarding avatar multipart push (from google_onboarding_screen) |
| `lib/infrastructure/services/link_preview_service.dart` | NEW — Dio fetch + meta parse + `LinkPreview` + family provider (from link_preview_card) |
| `lib/infrastructure/services/friend_query_service.dart` | NEW — friendships/friend_requests SSE subscribe + dispose registration (from friends_provider) |
| `lib/infrastructure/services/media_gallery_service.dart` | NEW — message_media getList + `mediaPageProvider` + `MediaRecord` typedef (from media_docs_screen) |
| `lib/features/profile/screens/edit_profile_screen.dart` | MOD — calls `profileUpdateServiceProvider`; `package:http` + pocketbaseClient imports deleted |
| `lib/features/groups/screens/create_group_screen.dart` | MOD — calls `groupCreateServiceProvider` at 8 sites; `package:http`, `package:pocketbase`, pocketbaseClient imports deleted |
| `lib/features/auth/screens/google_onboarding_screen.dart` | MOD — calls `authOnboardingServiceProvider`; `package:http` + pocketbaseClient imports deleted |
| `lib/features/chat/widgets/link_preview_card.dart` | MOD — watches `linkPreviewServiceProvider(url)`; Dio import + inline provider + `_LinkMeta` deleted |
| `lib/features/home/providers/friends_provider.dart` | MOD — `friendQueryServiceProvider`; `package:pocketbase/` + pocketbaseClient imports deleted |
| `lib/features/media/screens/media_docs_screen.dart` | MOD — watches `mediaPageProvider`; `package:pocketbase/` + pocketbaseClient imports + inline `_mediaPageProvider` deleted |
| `test/offline/imports_after_move_test.dart` | NEW — 6 source-assertion tests (TDD RED first) |

`git show --stat fb2a245` = exactly these 13 (6 modified + 6 created + 1 test). Char tests byte-identical (`git diff --name-only -- test/` empty; new test is the only test/ addition).

## AS-BUILT — service constructors / providers

All providers registered at the bottom of their service file (same pattern as
`friendRepositoryProvider` / `presenceServiceProvider`); all instance services
take the `PocketBaseClient` wrapper via `ref.watch(pocketbaseClientProvider)`.

```dart
// profile_update_service.dart
ProfileUpdateService(PocketBaseClient _client)
Future<void> updateProfile({required String userId, required Map<String,dynamic> body, File? avatarFile})
final profileUpdateServiceProvider = Provider<ProfileUpdateService>

// group_create_service.dart
GroupCreateService(PocketBaseClient _client)
String get baseUrl
Future<RecordModel> createConversation({required Map<String,dynamic> convBody, File? iconFile})
Future<RecordModel> createMemberRecord(Map<String,dynamic> body)
Future<List<RecordModel>> addMembers({required String conversationId, required List<String> memberIds})
Future<RecordModel> getUserRecord(String userId)
Future<RecordModel> createGroupKey(Map<String,dynamic> body)
Future<RecordModel> createMessage(Map<String,dynamic> body)
final groupCreateServiceProvider = Provider<GroupCreateService>

// auth_onboarding_service.dart
AuthOnboardingService(PocketBaseClient _client)
Future<void> uploadAvatar({required String userId, required File image})
final authOnboardingServiceProvider = Provider<AuthOnboardingService>

// link_preview_service.dart
class LinkPreview { final String title; final String? description; final String url; }  // public, brief-pinned name
LinkPreviewService()   // no deps — Dio() constructed per fetch, verbatim
Future<LinkPreview?> fetch(String url)
final linkPreviewServiceProvider = FutureProvider.family<LinkPreview?, String>  // brief interface: (url) → Future<LinkPreview?>
final _linkPreviewServiceInstanceProvider = Provider<LinkPreviewService>        // private seam

// friend_query_service.dart
FriendQueryService(PocketBaseClient _client)
Future<void> subscribeToFriendChanges(void Function() onChange, void Function(void Function()) registerDispose)
final friendQueryServiceProvider = Provider<FriendQueryService>

// media_gallery_service.dart
typedef MediaRecord = RecordModel
MediaGalleryService(PocketBaseClient _client)
Future<List<RecordModel>> fetchMediaPage(({String conversationId, String mediaType}) args)
final mediaGalleryServiceProvider = Provider<MediaGalleryService>
final mediaPageProvider = FutureProvider.autoDispose.family<List<RecordModel>, ({String conversationId, String mediaType})>  // moved from screen (_mediaPageProvider)
```

## Guard-5 deviation list (verbatim vs seamed)

**Verbatim (byte-preserved modulo identifier renames):** if/else avatar branch
(edit_profile), multipart construction ×3, Dio fetch + Options + both RegExps +
null-title bail + swallow-all catch (link_preview), conversation create
if/else with icon multipart, both member-map literals, group_keys map,
system-message map, filter/sort/perPage triple (media), both SSE subscribe
calls + unsubscribe closure + **vacuous `if (pb != null)` guard kept including
onDispose registration inside it** (friends), body map literals at call sites.

**Deviations (each: seam, file → reason):**

1. `ref.read(pocketbaseClientProvider).pb` → `Ctor(PocketBaseClient _client)` + `final pb = _client.pb` — every service. T5 precedent: injected seam at construction; moved bodies unchanged.
2. edit_profile: `user.id`→`userId`, `_pickedImage`→`avatarFile` params; `body` map stays in screen (data, not network). Call order body→update→invalidate identical.
3. google_onboarding: try/catch + `ref.invalidate(authProvider)` stay in screen (needs WidgetRef); moved body = pb+multipart only. Order update→invalidate identical.
4. link_preview: `_LinkMeta`→`LinkPreview` (brief pins `Future<LinkPreview?>`; private type can't cross files); `_linkPreviewProvider`→`linkPreviewServiceProvider` (brief-pinned name). `Dio()` still constructed per fetch (NOT a shared instance — verbatim).
5. create_group: `RecordModel conv;` → `late RecordModel conv` + `return` inside service (wrap for transport); two member-create sites → `createMemberRecord` (admin: map literal verbatim at call site) + `addMembers` (loop moved; `f.friend.id`→`memberId` param; ids materialized via `.map().toList()` BEFORE the loop — `selectedFriends` is a local, never mutated mid-await → same sequential requests, same order); `pb.baseUrl`→`groupService.baseUrl` getter (screen `${pb.baseUrl}` no longer names pb); `RecordModel` type names dropped to inference (`final conv = …`) so `package:pocketbase/` could leave the screen. Drift/encryption/storage/navigation/bodyCache blocks untouched, interleaving order preserved.
6. friends: `(_) => refresh()` → `(_) => onChange()` (identifier rename; service invokes `onChange()`); `ref.onDispose({…})` → `registerDispose({…})` with tear-offs `refresh` + `ref.onDispose` — the ENTIRE original guarded block (2 subs + dispose registration inside guard) moved as one unit, so even the dead branch still gates dispose registration. Notifier: `final pb = …` → `final queries = ref.read(friendQueryServiceProvider)` (both plain reads, non-rebuilding — same semantics).
7. media: `_mediaPageProvider` (private, screen) → `mediaPageProvider` (public, service file) — rename forced: the provider's type args name `RecordModel`, which the screen may no longer import; family body delegates to service, args record passed through unchanged (filter string byte-identical). `_expiresAt(RecordModel r)` → `_expiresAt(MediaRecord r)` — typedef (transparent: identical static type, zero runtime change) chosen over `dynamic` to keep static checking.

## TDD evidence

**RED (captured before any move):**
```
00:00 +0 -3: google_onboarding_screen.dart carries no package:http / Dio [E]
  Expected: false  Actual: <true>
  google_onboarding_screen: http must live behind a service
00:00 +0 -4: link_preview_card.dart carries no package:http / Dio [E]
  link_preview_card: Dio fetch must live behind a service
00:00 +0 -5: friends_provider.dart carries no package:pocketbase/ [E]
  friends_provider: PB client access must go through a service
00:00 +0 -6: media_docs_screen.dart carries no package:pocketbase/ [E]
  media_docs_screen: PB list query must go through a service
00:00 +0 -6: Some tests failed.
```
(edit_profile + create_group failed first, counts 1–2 truncated by tail; final `+0 -6` = all 6 files RED.)

**GREEN:**
```
00:00 +4: link_preview_card.dart carries no package:http / Dio
00:00 +5: friends_provider.dart carries no package:pocketbase/
00:00 +6: media_docs_screen.dart carries no package:pocketbase/
00:00 +6: All tests passed!
```
Right-reason: each RED = `Actual: <true>` on the banned string that the move deletes; GREEN only after the move (banned-string grep across all 6 files = zero hits).

**Gates:**
- Full suite: `00:11 +130: All tests passed!` — 130 = 124 baseline + 6 new (counted honestly; no baseline test edited).
- `flutter analyze`: **0 errors**, **86 issues** (baseline 88, Δ−2, all explainable, zero new issues in touched files):
  1. **−1** `unused_import` — `package:pocketbase/` warning in friends_provider deleted with the sanctioned import (service imports pocketbase legitimately; warning cannot "move", only disappear).
  2. **−1** `deprecated_member_use baseUrl` — 2 screen sites (`${pb.baseUrl}`) became `groupService.baseUrl`; the underlying deprecated `.pb.baseUrl` access now exists once (service getter) → 2 infos → 1 info.
  - Net-neutral movers: `unnecessary_null_comparison` friends_provider → friend_query_service (verbatim `if (pb != null)`), 2× `created` deprecation stay in create_group screen (`.created` parsed in screen), `use_build_context_synchronously` + `unnecessary_import foundation` stay.
- Char tests byte-identical (git diff on test/ empty).
- Bonus: T11 gate-13 regex pre-check over `lib/features/` → **NONE** (was: the 6 files).
- Tracked tree clean post-commit.

## Corrections (brief vs code / reality rule)

1. Brief create-list says friend_query_service = "PB **list queries** moved from friends_provider" — friends_provider contains no list query (`getFriendships` already lives in `friendRepositoryProvider`, untouched); its only pb usage is the SSE subscribe block. Smallest spec-satisfying choice: moved the pb usage per the brief's modify-line ("direct `pocketbaseClientProvider.pb` usage → providers over the new services; delete `package:pocketbase/` imports").
2. Brief Step 1 pins absence of `package:http`/`Dio` only for the 4 widget files — implemented exactly; create_group/media additionally dropped `package:pocketbase/` (beyond the test's letter) because gate 13 (T11) bans it in `lib/features/` and its own pre-check says "After Task 10 this should compile GREEN immediately". Kept screens' `RecordModel` typing via inference + `MediaRecord` typedef (no behavior/type drift).
3. Test granularity: 6 tests (one per file) instead of 2 grouped tests — makes the gate line "RED fails on all 6 files" directly observable in output.

## Self-review

- Diff read line-by-line pre-commit: every moved body matches its origin modulo the ledgered identifier seams; all request payloads, await ordering, and interleaving (PB ↔ Drift ↔ encryption ↔ navigation) preserved; no changes outside the 13 committed files; no schema, no push, no deferred-minor fixes smuggled; no `package:http`/`Dio`/`package:pocketbase/` strings remain in `lib/features/`.
- Provider pattern matches codebase precedent (bottom-of-file `Provider<T>` + `ref.watch(pocketbaseClientProvider)`); `linkPreviewServiceProvider(url)` and `mediaPageProvider(args)` keep exact prior family signatures so call sites/AsyncValue shapes are unchanged.
- Gates re-run post-commit on identical content: imports 6/6, analyze 86/0-error, tree clean.

## Concerns

1. Device captures (avatar upload, group create, link preview) not executed — ledgered deferral to P5 batch checkpoint; regressions in these flows would surface there, not here.
2. `create_group_screen` still holds local `users.getOne` **field parsing** (`r.created` deprecations) — by design (only network I/O moved); T11 gate bans imports, not record parsing, and screen has no pocketbase import.
3. `friend_query_service` keeps the vacuous `if (pb != null)` (carries 1 analyzer warning with it) — deliberate guard-5 choice; if a future cleanup wants it gone, ledger as its own edit.
4. `_expiresAt(MediaRecord r)` relies on the typedef trick; if gate 13 ever evolves to scan `typedef … = RecordModel` patterns it would flag the service file (sanctioned path today — no action).
