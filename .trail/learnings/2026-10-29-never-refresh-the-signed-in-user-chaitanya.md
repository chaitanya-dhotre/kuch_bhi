---
title: Never refresh the signed-in user by invalidating the auth provider; write the saved record into the cache and set the state
author: Chaitanya
date: 2026-10-29
branch: main
cost: { minutes: 16, tokens: 224763 }
id: l-cfc7361e
scope: repo
status: active
src: agent
touches:
  - docs/design/pages/profile.md
  - docs/design/pages/profile.html
  - lib/infrastructure/repositories/auth_repository_impl.dart
  - lib/features/profile/screens/edit_profile_screen.dart
  - docs/design/00-foundation.md
  - docs/design/10-registry.md
  - docs/design/pages/group-info.md
  - lib/features/profile/screens/profile_screen.dart
  - lib/features/profile/screens/view_profile_screen.dart
---

## Decided
After a profile save, the new user record goes into the local Drift users row and the auth notifier's state is set from it directly. Re-running the auth provider's build is not a refresh: build returns the CACHED Drift user, so a server write that skipped the cache comes back stale until a resume refresh.

## Tried and ruled out
`ref.invalidate(authProvider)` after the PB write (what the edit screen did): the old name and photo reappear, and the rebuild re-enters getCurrentUser's reinstall-detection branch, which can generate and upload a new key pair. A profile save must never reach key code.

## Watch out
Any feature that changes the current user on the server (profile, avatar, future settings) has the same trap. Also, before the Page 5 fix nothing pushed the edit-profile route, so that screen could not be reached at all.

In the code:
- lib/infrastructure/repositories/auth_repository_impl.dart getCurrentUser: cached user read ~L257, reinstall key branch ~L266-270; helpers _recordToUser and _cacheUserLocally (~L436)
- lib/features/profile/screens/edit_profile_screen.dart:70 (the invalidate)
- Spec: docs/design/pages/profile.md G1-G3 (AuthRepository.updateProfile -> _recordToUser -> _cacheUserLocally -> AsyncData(AuthAuthenticated(user)))
