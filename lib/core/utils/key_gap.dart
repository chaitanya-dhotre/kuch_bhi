/// User ids whose latest group_keys version is behind the conversation's
/// current version (null or 0 = no row at all).
Set<String> membersMissingCurrentKey({
  required Map<String, int?> memberToMaxVersion,
  required int currentVersion,
}) {
  return memberToMaxVersion.entries
      .where((e) => (e.value ?? 0) < currentVersion)
      .map((e) => e.key)
      .toSet();
}

/// User ids holding a group_keys row at [currentVersion] who are not in
/// [memberIds]: someone who left (or a removal whose rotation failed) and
/// can still read new messages.
Set<String> keyHoldersNotMembers({
  required Iterable<({String userId, int version})> keyRows,
  required Set<String> memberIds,
  required int currentVersion,
}) {
  if (currentVersion <= 0) return {};
  return {
    for (final k in keyRows)
      if (k.version == currentVersion && !memberIds.contains(k.userId))
        k.userId,
  };
}
