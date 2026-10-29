/// Typed failure for the ONE allowed edit inside `_createGroup` (E2E
/// boundary): the two `throw StateError('Member $memberId has no encryption
/// key yet.')` sites become `throw MemberKeyMissingError(memberId)` — same
/// position, same condition, only the type changes so the UI can map the id
/// back to a display NAME (a raw id must never reach user-visible text).
class MemberKeyMissingError implements Exception {
  const MemberKeyMissingError(this.memberId);

  /// The PocketBase user id that has no `public_key` yet. Never rendered
  /// as-is: the UI resolves it to the friend's display name.
  final String memberId;

  @override
  String toString() => 'MemberKeyMissingError($memberId)';
}
