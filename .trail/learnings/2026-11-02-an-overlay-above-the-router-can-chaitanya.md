---
title: "An overlay above the router can't stop Android back with a pop scope; it has to hand back to the system while it is showing"
author: Chaitanya
date: 2026-11-02
branch: main
cost: { minutes: 6, tokens: 203233 }
id: l-018afa2a
scope: repo
status: active
src: agent
touches:
  - lib/services/encryption_service.dart
  - test/offline/check_backup_secret_test.dart
  - docs/design/pages/app-lock-work-log.md
  - lib/app.dart
  - lib/features/app_lock/app_lock_controller.dart
---

## Decided
While the app lock overlay is up, it swallows the navigator's "can I handle back" notifications and tells Android the app does not handle back, so Android itself sends the app to the background. On unlock it restores the last value the navigator reported. A binding observer's didPopRoute (added before the router's own) is kept as the fallback for a plain back-button press.

## Tried and ruled out
WillPopScope (or PopScope) around the overlay in MaterialApp.router's builder: the builder sits above every route, there is no ModalRoute there, so it never runs and back pops the hidden route.
didPopRoute alone: Flutter's default Android page transition is the predictive-back one, and a back *gesture* calls navigator.pop() on the current route directly from the gesture observer, never reaching didPopRoute.

## Watch out
Any future full-screen layer that hides the app without being a route (cover, lock, onboarding overlay) has the same problem. Handing back to the system also means back on an inner step of the overlay backgrounds the app instead of going one step back; use a visible Back button for that.

In the code: lib/features/app_lock/lock_overlay.dart (_onNavigation, _syncSystemBack, didPopRoute); SystemNavigator.setFrameworkHandlesBack; flutter/lib/src/material/predictive_back_page_transitions_builder.dart handleStartBackGesture; widgets/routes.dart _handleDragEnd -> navigator?.pop(). Manifest has enableOnBackInvokedCallback="true".
