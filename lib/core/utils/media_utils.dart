/// Shared helpers for media expiry display.
library;

import 'dart:math' as math;

import '../constants/app_constants.dart';

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

/// True when a [type] message sent at [createdAt] is older than the longest
/// the server keeps that type (any quality, plus a day of slack): its copy is
/// purged for sure, so there is nothing to download. The store cannot tell
/// this itself: a purged record answers 404, which it files as "not landed
/// yet" (queued), so the bubble would wait and offer a retry forever.
bool isPastRetention(String type, DateTime? createdAt) {
  if (createdAt == null) return false;
  final days = switch (type) {
    'image' => math.max(
      AppConstants.retentionPhotoNormalDays,
      AppConstants.retentionPhotoHighDays,
    ),
    'video' => math.max(
      AppConstants.retentionVideoNormalDays,
      AppConstants.retentionVideoHighDays,
    ),
    _ => AppConstants.retentionVoiceDays, // voice notes and documents
  };
  return createdAt.add(Duration(days: days + 1)).isBefore(DateTime.now());
}
