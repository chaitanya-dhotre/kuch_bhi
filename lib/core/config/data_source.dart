/// Mock-build seam (spec §10, plan Task 12): `flutter run
/// --dart-define=USE_FAKES=true` swaps `messageRepositoryProvider` for
/// `FakeMessageRepository` in `main()` — screens read fixture data with
/// no network and no real repository on the path.
///
/// Compile-time constant (`bool.fromEnvironment` only — Gate 13: no
/// network SDK imports here), so `USE_FAKES=false` builds tree-shake the
/// fake and its import out entirely.
const bool useFakes = bool.fromEnvironment('USE_FAKES');

/// Release fail-loud guard for the [useFakes] mock-build seam (P3, spec §10).
///
/// A release binary must NEVER run with `USE_FAKES=true`. `main()` calls
/// this as its FIRST statement — before any init and before ProviderScope
/// mounts — so a mis-built release artifact dies with [StateError] instead
/// of serving fixture data.
///
/// Test seam: `kReleaseMode` is a compile-time const pinned by the
/// framework (flutter_test always runs kDebugMode=true), so tests cannot
/// simulate a release context by pumping widgets. The pure
/// `release`/`useFakes` parameters are the honest injection point;
/// `test/offline/use_fakes_release_guard_test.dart` pins both branches and
/// pins the main.dart wiring.
void assertFakesAllowed({required bool release, required bool useFakes}) {
  if (release && useFakes) {
    throw StateError(
      'USE_FAKES must never be enabled in a release build. '
      'Rebuild without --dart-define=USE_FAKES=true.',
    );
  }
}
