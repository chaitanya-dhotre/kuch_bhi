/// Central location for all app-wide constants.
/// Never hardcode these values anywhere else.
class AppConstants {
  AppConstants._();

  // --- Server ---
  static const String baseUrl = 'https://kuch-bhi.duckdns.org';
  static const String apiUrl = '$baseUrl/api';

  // --- App ---
  static const String appName = 'Kuch Bhi';
  static const String appId = 'com.chai.kuch_bhi';
  static const String githubReleasesUrl =
      'https://api.github.com/repos/YOUR_GITHUB_USERNAME/kuch_bhi/releases/latest';

  // --- Friend Code ---
  static const int friendCodeLength = 6;

  // --- Groups ---
  static const int maxGroupMembers = 15;
  static const int maxPinnedMessages = 3;

  // --- Media Limits ---
  static const int maxVoiceMessageSeconds = 300; // 5 minutes
  static const int maxFileSizeMb = 100;

  // --- Media Retention (days) ---
  static const int retentionVoiceDays = 60;
  static const int retentionPhotoNormalDays = 60;
  static const int retentionPhotoHighDays = 30;
  static const int retentionVideoNormalDays = 30;
  static const int retentionVideoHighDays = 15;

  // --- Timeouts ---
  static const int connectTimeoutSeconds = 15;
  static const int receiveTimeoutSeconds = 30;

  // --- Pagination ---
  static const int messagesPageSize = 40;
  static const int conversationsPageSize = 30;

  // --- Online Status ---
  static const int onlineThresholdMinutes = 5;
}
