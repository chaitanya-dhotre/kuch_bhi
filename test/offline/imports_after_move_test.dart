// Task 10 (offline-first): screen-side HTTP/PocketBase calls move behind
// lib/infrastructure/services (spec §12 import-gate precursor; same
// read-source assertion shape as Task 1's path checks).
//
// RED first: every file below still carries its import while the logic
// lives in the widget/screen — all six tests must fail before the move.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('edit_profile_screen.dart carries no package:http / Dio', () {
    final src = File('lib/features/profile/screens/edit_profile_screen.dart')
        .readAsStringSync();
    expect(src.contains('package:http'), isFalse,
        reason: 'edit_profile_screen: http must live behind a service');
    expect(src.contains('Dio'), isFalse,
        reason: 'edit_profile_screen: Dio must live behind a service');
  });

  test('create_group_screen.dart carries no package:http / Dio', () {
    final src = File('lib/features/groups/screens/create_group_screen.dart')
        .readAsStringSync();
    expect(src.contains('package:http'), isFalse,
        reason: 'create_group_screen: http must live behind a service');
    expect(src.contains('Dio'), isFalse,
        reason: 'create_group_screen: Dio must live behind a service');
  });

  test('google_onboarding_screen.dart carries no package:http / Dio', () {
    final src = File('lib/features/auth/screens/google_onboarding_screen.dart')
        .readAsStringSync();
    expect(src.contains('package:http'), isFalse,
        reason: 'google_onboarding_screen: http must live behind a service');
    expect(src.contains('Dio'), isFalse,
        reason: 'google_onboarding_screen: Dio must live behind a service');
  });

  test('link_preview_card.dart carries no package:http / Dio', () {
    final src = File('lib/features/chat/widgets/link_preview_card.dart')
        .readAsStringSync();
    expect(src.contains('package:http'), isFalse,
        reason: 'link_preview_card: http must live behind a service');
    expect(src.contains('Dio'), isFalse,
        reason: 'link_preview_card: Dio fetch must live behind a service');
  });

  test('friends_provider.dart carries no package:pocketbase/', () {
    final src = File('lib/features/home/providers/friends_provider.dart')
        .readAsStringSync();
    expect(src.contains('package:pocketbase/'), isFalse,
        reason: 'friends_provider: PB client access must go through a service');
  });

  test('media_docs_screen.dart carries no package:pocketbase/', () {
    final src = File('lib/features/media/screens/media_docs_screen.dart')
        .readAsStringSync();
    expect(src.contains('package:pocketbase/'), isFalse,
        reason: 'media_docs_screen: PB list query must go through a service');
  });
}
