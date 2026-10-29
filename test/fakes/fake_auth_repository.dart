import 'dart:io';

import 'package:kuch_bhi/domain/entities/user.dart';
import 'package:kuch_bhi/domain/repositories/auth_repository.dart';

/// Test double: no PocketBase, no secure storage. Anything not overridden
/// here throws via [noSuchMethod], so an unexpected call fails the test.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository(this.user);

  User user;
  int getCurrentUserCalls = 0;
  int updatePublicKeyCalls = 0;
  int signOutCalls = 0;
  int updateProfileCalls = 0;
  File? lastAvatarFile;
  bool? lastClearAvatar;

  /// Overrides the default "apply the edit and return the user" behaviour.
  Future<User> Function()? onUpdateProfile;

  @override
  Future<User?> getCurrentUser() async {
    getCurrentUserCalls++;
    return user;
  }

  @override
  Future<void> signOut() async => signOutCalls++;

  @override
  Future<void> updatePublicKey(String publicKeyBase64) async =>
      updatePublicKeyCalls++;

  @override
  Future<User> updateProfile({
    required String displayName,
    required String username,
    String? about,
    File? avatarFile,
    bool clearAvatar = false,
  }) {
    updateProfileCalls++;
    lastAvatarFile = avatarFile;
    lastClearAvatar = clearAvatar;
    if (onUpdateProfile != null) return onUpdateProfile!();
    user = user.copyWith(
      displayName: displayName,
      username: username.toLowerCase(),
      about: about,
    );
    return Future.value(user);
  }

  /// Page 7: the hook's answer for registerWithGoogle (default: [user]).
  Future<GoogleAuthResult> Function()? onRegisterWithGoogle;

  @override
  Future<GoogleAuthResult> registerWithGoogle({
    required String idToken,
    required String displayName,
    required String username,
  }) =>
      onRegisterWithGoogle?.call() ??
      Future.value(GoogleAuthResult(user: user, isNew: true));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

User fakeUser({
  String displayName = 'Avni R.',
  String username = 'avni',
  String? about,
  String? avatarUrl,
  String friendCode = 'KB7Q2X',
}) =>
    User(
      id: 'u1',
      displayName: displayName,
      username: username,
      email: 'a@b.c',
      friendCode: friendCode,
      about: about,
      avatarUrl: avatarUrl,
      createdAt: DateTime(2026),
    );
