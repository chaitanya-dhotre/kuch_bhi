// Task 12 — brief's file map path for FakeMessageRepository.
//
// The class itself lives at package:kuch_bhi/core/config/fake_message_
// repository.dart because lib/ code (main.dart's USE_FAKES override) must
// import it: package:/relative URIs inside lib/ cannot address test/
// (analyzer: "Target of URI doesn't exist"). This barrel keeps the brief's
// test-side import path working: ../fakes/fake_message_repository.dart.
export 'package:kuch_bhi/core/config/fake_message_repository.dart';
