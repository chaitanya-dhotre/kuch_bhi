import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../core/constants/app_constants.dart';
import '../../data/local/secure_storage/secure_storage_service.dart';

class PocketBaseClient {
  PocketBaseClient._(this._pb);

  final PocketBase _pb;

  PocketBase get pb => _pb;
  bool get isAuthenticated => _pb.authStore.isValid;

  static Future<PocketBaseClient> create(
    SecureStorageService storage,
  ) async {
    final pb = PocketBase(AppConstants.baseUrl);

    // Restore token from SecureStorage.
    // Even if this fails, getCurrentUser() will handle the fallback.
    try {
      final token = await storage.getAuthToken();
      if (token != null && token.isNotEmpty) {
        pb.authStore.save(token, null);
        debugPrint('[PB] Token restored from SecureStorage. '
            'isValid: ${pb.authStore.isValid}');
      }
    } catch (e) {
      debugPrint('[PB] SecureStorage restore failed: $e');
    }

    final client = PocketBaseClient._(pb);

    // Keep SecureStorage in sync.
    pb.authStore.onChange.listen((event) async {
      try {
        if (event.token.isEmpty) {
          await storage.deleteAuthToken();
        } else {
          await storage.saveAuthToken(event.token);
        }
      } catch (e) {
        debugPrint('[PB] Token sync error: $e');
      }
    });

    return client;
  }

  void clearAuth() => _pb.authStore.clear();
}

// Plain Provider — must be overridden in main() before runApp.
// Using Provider (not FutureProvider) eliminates the loading state
// that caused AuthNotifier to run against _LoadingAuthRepository.
final pocketbaseClientProvider = Provider<PocketBaseClient>((ref) {
  throw StateError(
    'pocketbaseClientProvider must be overridden in main(). '
    'Call overrideWithValue(pbClient) inside ProviderScope.',
  );
});
