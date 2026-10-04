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
