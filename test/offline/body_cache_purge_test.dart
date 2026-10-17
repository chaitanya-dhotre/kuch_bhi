import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kuch_bhi/app.dart';

/// B (2026-10-14): purge decrypted bodies ONLY on a signal that means the
/// app is truly backgrounded. The notification shade (and split-screen
/// peek) emit `inactive` while the app is still on screen — purging on it
/// re-decrypted every visible message on each shade pull, which is the
/// recurring "locks flash when I pull the shade" complaint (recording
/// chat2.png). HOME / Recents / screen-off emit `paused` — those MUST
/// still purge, keeping spec §3 / amendment 6's intent (no plaintext in
/// the task switcher).
void main() {
  test('B: shade (inactive) does NOT purge; HOME/Recents (paused) does',
      () {
    expect(
      bodyCachePurgeSignal(AppLifecycleState.inactive),
      isFalse,
      reason: 'notification shade / split-screen peek keep the cache — '
          'this is the lock-flash regression pin',
    );
    expect(
      bodyCachePurgeSignal(AppLifecycleState.paused),
      isTrue,
      reason: 'HOME / Recents / screen-off must still purge (spec §3 / '
          'amendment 6)',
    );
    // Signals that never carried a purge keep their behavior.
    expect(bodyCachePurgeSignal(AppLifecycleState.resumed), isFalse);
    expect(bodyCachePurgeSignal(AppLifecycleState.detached), isFalse);
  });
}
