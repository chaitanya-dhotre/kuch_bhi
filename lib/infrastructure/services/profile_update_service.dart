import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/network/pocketbase_client.dart';

/// Profile display-name/about update + multipart avatar push.
///
/// Logic moved verbatim from `edit_profile_screen._save` (Task 10,
/// guard 5: structure move, no behavior edits).
class ProfileUpdateService {
  ProfileUpdateService(this._client);

  final PocketBaseClient _client;

  Future<void> updateProfile({
    required String userId,
    required Map<String, dynamic> body,
    File? avatarFile,
  }) async {
    final pb = _client.pb;

    if (avatarFile != null) {
      await pb.collection('users').update(
        userId,
        body: body,
        files: [
          http.MultipartFile.fromBytes(
            'avatar',
            await avatarFile.readAsBytes(),
            filename: avatarFile.path.split('/').last,
          ),
        ],
      );
    } else {
      await pb.collection('users').update(userId, body: body);
    }
  }
}

final profileUpdateServiceProvider = Provider<ProfileUpdateService>((ref) {
  return ProfileUpdateService(ref.watch(pocketbaseClientProvider));
});
