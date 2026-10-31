/// Central location for all app-wide constants.
/// Never hardcode these values anywhere else.
class AppConstants {
  AppConstants._();

  // --- Server ---
  static const String baseUrl = 'https://kuch-bhi.duckdns.org';

  // --- App ---
  static const String appName = 'Kuch Bhi';

  // --- Groups ---
  static const int maxPinnedMessages = 3;

  // --- Media Limits ---
  static const int maxVoiceMessageSeconds = 300; // 5 minutes

  // --- Media Retention (days) ---
  static const int retentionVoiceDays = 60;
  static const int retentionPhotoNormalDays = 60;
  static const int retentionPhotoHighDays = 30;
  static const int retentionVideoNormalDays = 30;
  static const int retentionVideoHighDays = 15;
}

/// Media blob cache hard cap (spec §9) — eviction target: `evictIfNeeded`
/// shrinks the `ready` total back under this figure, LRU-first, skipping
/// the derived-protected set. Tunable via this ONE constant.
const int kMediaCacheMaxBytes = 300 * 1024 * 1024;

/// Watermark (spec §9): once the `ready` total crosses 85% of
/// [kMediaCacheMaxBytes], a DEFERRED (never write-path-awaited)
/// `evictIfNeeded()` is scheduled after the blob write completes.
const double kMediaCacheWatermark = 0.85;
