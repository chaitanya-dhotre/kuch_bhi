---
title: "Reading an auto-disposed provider's future with nothing listening can wait forever, which froze in-chat search"
author: Chaitanya
date: 2026-10-31
branch: main
cost: { minutes: 10, tokens: 129869 }
id: l-c03a0fa1
scope: repo
status: active
src: agent
touches:
  - docs/audits/dead-code-wave-a-work-log.md
  - lib/app.dart
  - lib/core/constants/app_constants.dart
  - lib/core/constants/app_strings.dart
  - lib/core/utils/format_utils.dart
  - lib/core/utils/media_utils.dart
  - lib/core/utils/username_rules.dart
  - lib/domain/repositories/auth_repository.dart
  - lib/features/auth/providers/auth_provider.dart
  - lib/features/auth/screens/register_screen.dart
---

## Decided
- Never `await ref.read(someAutoDisposeProvider(x).future)` without a listener. If the value isn't ready at once, the provider is disposed at the end of the frame and that future never completes. In-chat search did this for every message body, so one uncached body (media, older messages) froze the whole scan at 0/0, and only "sometimes", depending on what was cached.
- Hold the provider with `ref.listenManual(...)` while awaiting, close it after, and cap each wait (search uses 2s per body) so one stuck item can't stall a loop.
- Search matches run newest-first (index 0 = bottom of the reversed list), so the "next" match is the older one ABOVE. The up arrow steps to older, down to newer.
- Scrolling to an off-screen message: jump to an estimate, then step a screen at a time until the target is built, and only then `ensureVisible`. An estimate plus one post-frame `ensureVisible` stops short, because the target isn't built yet.

## Tried and ruled out
- An animated estimate scroll followed by `ensureVisible` on the next frame: the item was still unbuilt, so it silently stayed at the estimate ("lands slightly above or below").

## Watch out
- Unit tests for the search controller passed the whole time; they inject `resolveBody`, so the provider lifecycle bug only shows on a device.

In the code: `_resolveSearchBody`, `_scrollToFlatIndex`, and the search bar arrows in chat_screen.dart; messageBodyProvider is FutureProvider.autoDispose.family.
