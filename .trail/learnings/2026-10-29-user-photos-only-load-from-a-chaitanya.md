---
title: "User photos only load from a public file field, and every uploaded photo must be re-encoded to drop its GPS data"
author: Chaitanya
date: 2026-10-29
branch: main
cost: { minutes: 38, tokens: 223916 }
id: l-e02776b8
scope: repo
status: active
src: agent
touches:
  - docs/design/10-registry.md
  - docs/design/pages/profile-handoff.md
  - docs/design/pages/profile-work-log.md
  - docs/design/pages/profile.html
  - docs/design/pages/profile.md
  - lib/core/router/app_router.dart
  - lib/core/widgets/app_avatar.dart
  - lib/core/widgets/app_field.dart
  - lib/domain/repositories/auth_repository.dart
  - lib/features/auth/providers/auth_provider.dart
---

## Decided
The users avatar file field is public, like the group icon field. A protected PocketBase file field returns 404 for a plain file URL unless the request carries a short-lived file token, and the app builds plain URLs and caches them in Drift. So until 2026-10-29 no user avatar had ever loaded anywhere in the app; it looked like an upload bug.
Every photo upload re-encodes to JPEG with EXIF dropped (flutter_image_compress, keepExif false) and never falls back to the original bytes. image_picker's maxWidth/maxHeight resize keeps the original EXIF, GPS included; a device test upload carried the phone's coordinates.

## Tried and ruled out
Keeping the field protected and fetching file tokens in the client: every avatar call site would need token refresh and a token-free cache key. Dropped as more code for little privacy gain, since file names already carry a random suffix and group icons were already public.
A native crop library for the avatar crop step: its Android crop activity can't use Warm Pop tokens and adds native build setup, so the crop step is a small Flutter screen instead.

## Watch out
An avatar widget that hides the initials whenever a URL is set shows an empty disc on any failed load. AppAvatar now paints the photo as foregroundImage over the initials.
Live schema changes are done without the superuser password: write a migrate() file locally, scp it to the server, sudo mv it into pb_migrations, restart pocketbase, then check the _migrations table. Back up data.db first.

In the code:
- lib/infrastructure/repositories/auth_repository_impl.dart _avatarJpegWithoutExif (profile uploads)
- lib/core/widgets/app_avatar.dart (foregroundImage over initials)
- lib/features/profile/screens/crop_photo_screen.dart (cropRectInImage)
- Server: /opt/pocketbase/pb_migrations/1793269388_updated_users_avatar_public.js; backup /home/ubuntu/pb_backups/data.db.20261029-avatar-unprotect-pre
- Other upload paths (group photo, onboarding avatar, chat images): branch claude/exciting-bardeen-3ac765, not merged as of 2026-10-29
