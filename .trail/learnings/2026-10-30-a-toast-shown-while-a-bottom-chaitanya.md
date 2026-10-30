---
title: A toast shown while a bottom sheet stays open lands under the sheet
author: Chaitanya
date: 2026-10-30
branch: main
cost: { minutes: 14, tokens: 192140 }
id: l-9f279214
scope: repo
status: active
src: agent
---

## Decided
R5 `showToast` uses the root ScaffoldMessenger, whose SnackBar is painted on the root Scaffold, below
any modal bottom sheet. A sheet that toasts while it stays open (the Add a friend QR tab: "No QR code
in that photo.") wraps that content in its own `ScaffoldMessenger` + a transparent `Scaffold` inside
`IgnorePointer` in a `Stack`, so the toast shows inside the sheet and taps still reach the rows.

## Tried and ruled out
Doing it for every sheet in `showAppSheet`. Copy (message menu) and group invites pop their sheet and
then toast with the sheet's context. A sheet-local messenger dies with the sheet, so those toasts
would vanish.

In the code: `add_friend_screen.dart` (the `_QrScanTab` slot in `TabBarView`).
