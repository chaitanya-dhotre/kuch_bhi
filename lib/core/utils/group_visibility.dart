/// Group-history visibility (spec D1): a row is visible only from this
/// member's join time onward, and undecryptable non-media rows are hidden
/// entirely — ciphertext must never reach a bubble.
bool isGroupRowVisible({
  required DateTime createdAt,
  required DateTime? memberJoinedAt,
  required String? decryptedBody,
  required String type,
}) {
  if (memberJoinedAt != null && createdAt.isBefore(memberJoinedAt)) return false;
  const mediaTypes = {'image', 'video', 'voice', 'document', 'file'};
  if (!mediaTypes.contains(type) &&
      (decryptedBody == null || decryptedBody.isEmpty)) {
    return false;
  }
  return true;
}
