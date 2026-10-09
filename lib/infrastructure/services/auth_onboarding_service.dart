import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/network/pocketbase_client.dart';

/// Google-onboarding avatar push (best-effort at the call site).
///
/// Logic moved verbatim from `google_onboarding_screen._uploadAvatarIfPicked`
/// (Task 10, guard 5: structure move, no behavior edits).
class AuthOnboardingService {
  AuthOnboardingService(this._client);

  final PocketBaseClient _client;

  Future<void> uploadAvatar({
    required String userId,
    required File image,
  }) async {
    final pb = _client.pb;
    await pb.collection('users').update(
      userId,
      files: [
        http.MultipartFile.fromBytes(
          'avatar',
          await image.readAsBytes(),
          filename: image.path.split('/').last,
        ),
      ],
    );
  }
}

final authOnboardingServiceProvider = Provider<AuthOnboardingService>((ref) {
  return AuthOnboardingService(ref.watch(pocketbaseClientProvider));
});
