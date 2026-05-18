/// Shared helpers for media expiry display.

/// Returns null if [expiresAt] is null or more than 7 days away.
/// Returns "Expires today" if < 24 hours remain.
/// Returns "Expires in Xd" for 1–7 days remain.
String? expiryBadgeText(DateTime? expiresAt) {
  if (expiresAt == null) return null;
  final now  = DateTime.now();
  final diff = expiresAt.difference(now);
  if (diff.isNegative) return null; // already expired — handled separately
  if (diff.inHours < 24)  return 'Expires today';
  final days = diff.inDays;
  if (days <= 7) return 'Expires in ${days}d';
  return null;
}

/// Returns true if [expiresAt] is in the past.
bool isExpired(DateTime? expiresAt) {
  if (expiresAt == null) return false;
  return expiresAt.isBefore(DateTime.now());
}
