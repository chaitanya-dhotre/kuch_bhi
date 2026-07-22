/// Pure Dart domain entity. No Flutter, no PocketBase, no Drift dependencies.
/// This is what the rest of the app works with.
class User {
  const User({
    required this.id,
    required this.displayName,
    required this.username,
    required this.email,
    required this.friendCode,
    this.avatarUrl,
    this.about,
    this.publicKey,
    this.isOnline = false,
    this.lastSeen,
    required this.createdAt,
    this.groupRole,
  });

  final String id;
  final String displayName;
  final String username;
  final String email;
  final String friendCode;
  final String? avatarUrl;
  final String? about;
  final String? publicKey;
  final bool isOnline;
  final DateTime? lastSeen;
  final DateTime createdAt;
  final String? groupRole;

  User copyWith({
    String? displayName,
    String? username,
    String? avatarUrl,
    String? about,
    String? publicKey,
    bool? isOnline,
    DateTime? lastSeen,
    String? groupRole,
  }) {
    return User(
      id: id,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      email: email,
      friendCode: friendCode,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      about: about ?? this.about,
      publicKey: publicKey ?? this.publicKey,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      createdAt: createdAt,
      groupRole: groupRole ?? this.groupRole,
    );
  }

  @override
  String toString() => 'User(id: $id, displayName: $displayName, '
      'friendCode: $friendCode, groupRole: $groupRole)';
}
