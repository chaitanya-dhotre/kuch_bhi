---
title: "Auth timeouts go on the network call only, and the sign-up photo must upload before the user is marked signed in"
author: Chaitanya
date: 2026-10-29
branch: main
cost: { minutes: 1, tokens: 0 }
id: l-e493242b
scope: repo
status: active
src: agent
---

## Decided
- Bound auth calls (sign in, register, Google hook, password reset) at 8s on the network request itself, before the session is saved. Never wrap the whole sign-in in a timeout.
- The Google onboarding photo uploads inside the register step, before the auth state turns signed-in, and goes through the profile-save path (which strips EXIF).

## Tried and ruled out
- A UI-level `.timeout()` around the whole sign-in, the way Profile's save does it: a timeout stops the wait, not the work. The timed-out attempt keeps running key setup, and the user's retry starts a second key setup on the same device at the same time.
- Uploading the photo from the screen after the user is marked signed in: the router redirect replaces the onboarding screen as soon as auth turns signed-in, so a "still mounted?" check skips the upload.

## Watch out
- Every auth screen listens to the same auth state. With Register pushed above Login, both show every error unless each one tracks the action it started.
- The Google picker is never signed out by app sign-out, so Android silently picks the last account again.

In the code:
- signInWithEmailPassword → _saveSession → _initEncryptionKeys in auth_repository_impl.dart; EXIF strip in _avatarJpegWithoutExif.
- Spec: docs/design/pages/auth.md, items G3, G4, F5, F6, F7.
