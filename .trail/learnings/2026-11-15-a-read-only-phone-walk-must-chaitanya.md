---
title: "A read-only phone walk must check it is still inside the app before every tap, and must find Home by the new-chat button, not the app name"
author: Chaitanya
date: 2026-11-15
branch: main
cost: { minutes: 25, tokens: 213197 }
id: l-085895f8
scope: repo
status: active
src: agent
touches:
  - docs/design/pages/calm-rest.md
  - docs/design/pages/calm-rest.html
---

## Decided
For screenshot walks over adb (calm-rest spec, 2026-11-15, M52), every tap and back press first checks that kuch_bhi has window focus, and "at Home" is detected by the `New chat` content description in a uiautomator dump.

## Tried and ruled out
- Fixed back-press counts to return Home: one extra back leaves the app, and the next taps land in whatever app is behind it (they hit WhatsApp's tab bar; nothing was sent, but it could have been).
- Detecting Home by the `Kuch Bhi` title: the About page shows the same text, so the walk thought it was Home and shot the wrong screens.

## Watch out
- The user's phone may be on AMOLED; light and dark shots need the in-app theme switched, which is a setting change: ask first and set it back after.
- Auth screens cannot be shot on a signed-in phone without signing out, which clears the phone's chats; spec them from code or use a spare phone.
- Real chat names can be offensive or private; boards draw placeholder names and only link the local screenshots.

In the code: walk helpers lived in the session scratchpad (`inapp`, `gohome`, `rowy`, `walk`); focus check = `adb shell dumpsys window | grep mCurrentFocus | grep com.chai.kuch_bhi`.
