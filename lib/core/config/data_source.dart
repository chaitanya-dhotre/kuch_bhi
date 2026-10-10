/// Mock-build seam (spec §10, plan Task 12): `flutter run
/// --dart-define=USE_FAKES=true` swaps `messageRepositoryProvider` for
/// `FakeMessageRepository` in `main()` — screens read fixture data with
/// no network and no real repository on the path.
///
/// Compile-time constant (`bool.fromEnvironment` only — Gate 13: no
/// network SDK imports here), so `USE_FAKES=false` builds tree-shake the
/// fake and its import out entirely.
const bool useFakes = bool.fromEnvironment('USE_FAKES');
