# Viewer follow-ups work log — 2026-10-31

No commit created. No files under `docs/design/pages/` were edited for this task.

| Backlog item | Cause | Change | Files |
|---|---|---|---|
| 13.5 — video controls remain over playback | The viewer kept `_chrome` true throughout playback; no playback timer existed. | Start/reset a 3-second timer on autoplay and when chrome is brought back by a tap. It hides the shared top bar, centre disc and strip together. Pause/end restores chrome; accessible navigation skips scheduling; reduced motion uses the existing zero-duration opacity; dispose cancels the timer. | `lib/features/media/screens/media_viewer_screen.dart`; `test/media/media_viewer_video_test.dart` (added regression) |
| 13.9 — photo pans into black margins | `InteractiveViewer` received a screen-filling `Stack`, so its pan bounds were the viewport. | Size its child to the image metadata’s aspect ratio fitted within the viewport, then center the child. Existing scale and gesture handling remain in place. | `lib/features/media/screens/media_viewer_screen.dart`; `test/media/media_viewer_screen_test.dart` (added regression) |
| 13.10 — expired reply quote stays on decrypting skeleton | `_originalMessageProvider` completing with `null` means the parent row is absent (expired, deleted, or not cached). The quote previously passed that missing ID into `messageBodyProvider`, whose null result intentionally shows the loading placeholder. | Key the fallback on `originalAsync.hasValue && original == null`; render **Message expired** in `inkSoft`. While the lookup is still loading, retain the existing provider skeleton. | `lib/features/chat/widgets/reply_quote.dart`; `test/chat/reply_quote_expired_test.dart` (added regression) |

## RED → GREEN proof

Ran the new regressions with the original production files restored from `HEAD` (tests unchanged). They failed on the expected old behavior:

```text
RED — video chrome: expected AnimatedOpacity.opacity 0 after 3 seconds; actual 1.0
RED — fitted photo child: expected 400×200; original child filled the 400×300 viewport
RED — missing quote parent: “Message expired” not found
```

Restored the fixes and reran the focused viewer/video/quote test files:

```text
00:02 +39: All tests passed!
```

The focused run included the new cases and the existing Page 9 viewer tests unchanged.

## Requested gates

```text
flutter test --reporter compact
00:33 +781 -1
Failed: test/media/media_retry_test.dart
  a blob the store marked failed is final: no retry offered
  Expected “No longer available”; found 0 matching text widgets.
Exit code: 1
```

This shared checkout contains other uncommitted media-send work. The one failing test is outside the files changed for these follow-ups.

```text
flutter analyze
81 issues found. (ran in 2.5s)
Exit code: 1
No errors or warnings in the files changed for these follow-ups; the reported issues are elsewhere in the shared checkout.
```

```text
git diff --check
clean
```

Scoped `git diff --stat` (tracked files; the new quote test is untracked):

```text
lib/features/chat/widgets/reply_quote.dart         |  8 +++-
lib/features/media/screens/media_viewer_screen.dart | 49 +++++++++++++++++++++-
test/media/media_viewer_screen_test.dart            | 13 ++++++
test/media/media_viewer_video_test.dart             | 20 +++++++++
4 files changed, 87 insertions(+), 3 deletions(-)
New test: test/chat/reply_quote_expired_test.dart
```

## Device checks for the user

- Play a video: confirm the centre disc, strip and top bar hide after about 3 seconds; tap to bring them back, then pause and confirm they stay visible. Check replay at the end.
- Turn on TalkBack/accessibility navigation and repeat; chrome should stay visible. With Reduce motion enabled, show/hide should jump without a fade.
- Open portrait and landscape photos: pinch to 4×, double-tap at different points, and pan to each photo edge. Confirm the black margin does not move into view. At 1×, verify swipe-down dismissal still follows the existing threshold.
- Reply to a message, then test after its disappearance timer, after deletion, and when the quoted parent is still loading. The first two should show **Message expired** with no shimmer; loading should retain the skeleton.

## Claude follow-up after the user's device check (2026-11-01)

User: 13.9 not fixed. The photo sat at the very top and zoom still reached the black.

Cause: `InteractiveViewer(constrained: false)` lays its child out at the top-left; `alignment` only sets
the scale origin. A child sized to the photo also doesn't clamp panning to the photo once zoomed. The
original test only asserted `constrained == false` and a SizedBox size, so it passed on the bug.

Fix (`media_viewer_screen.dart`): the zoom layer is full-screen again (default `constrained`), with the
photo drawn contain-centred in it. A `LayoutBuilder` records the viewport and the photo's fitted rect
(from the file's width/height). `_clampZoom` runs on every controller change (pinch, pan, double-tap
tween): per axis, while the scaled photo is smaller than the screen it stays centred, and once bigger
its edges can't move inside the screen's. If the size is unknown, there's no clamp (old behaviour).

Test: replaced Mimo's 13.9 test with `zoom stays inside the photo; centred at 1x`. It asserts that the
zoom content fills the screen and that, after a double-tap in the black band and hard drags down and up,
the photo's top edge stays ≤ 0 and its bottom edge ≥ the screen bottom. RED on Mimo's version (content
400×200 at the top); GREEN now.

Gates: `flutter test` 810/810, `flutter analyze` 0 errors, `git diff --check` clean, frozen areas empty.
Not yet re-checked on a device.
