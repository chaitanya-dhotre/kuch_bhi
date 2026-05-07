import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../core/constants/app_constants.dart';
import '../../data/local/secure_storage/secure_storage_service.dart';

/// Singleton PocketBase client for the entire app.
///
/// Responsibilities:
/// - Maintains the authenticated PocketBase instance
/// - Persists and restores auth state across app restarts
/// - Provides the raw PocketBase client to repositories
///
/// Never use this directly in UI. Always go through a Repository.
class PocketBaseClient {
  PocketBaseClient._(this._pb);

  final PocketBase _pb;

  /// The raw PocketBase client. Repositories use this.
  PocketBase get pb => _pb;

  /// Whether the client currently has a valid auth token.
  bool get isAuthenticated => _pb.authStore.isValid;

  /// The current auth token string.
  String? get token => _pb.authStore.token;

  /// Factory: creates and initializes the client.
  /// Call once at app startup via the Riverpod provider.
  static Future<PocketBaseClient> create(
    SecureStorageService storage,
  ) async {
    final pb = PocketBase(AppConstants.baseUrl);

    // Attempt to restore previous auth session from secure storage.
    final storedAuthJson = await storage.getPbAuthStore();
    if (storedAuthJson != null) {
      try {
        final data = jsonDecode(storedAuthJson) as Map<String, dynamic>;
        final token = data['token'] as String? ?? '';
        final model = data['model'];

        if (token.isNotEmpty) {
          pb.authStore.save(token, model);
        }
      } catch (_) {
        // Corrupted store — clear it and start fresh.
        await storage.deletePbAuthStore();
      }
    }

    final client = PocketBaseClient._(pb);

    // Listen for auth changes and persist them.
    pb.authStore.onChange.listen((event) async {
      if (event.token.isEmpty) {
        await storage.deletePbAuthStore();
      } else {
        final json = jsonEncode({
          'token': event.token,
          'model': event.model,
        });
        await storage.savePbAuthStore(json);
        if (event.model != null) {
          final modelMap = event.model as Map<String, dynamic>?;
          final userId = modelMap?['id'] as String?;
          if (userId != null) {
            await storage.saveCurrentUserId(userId);
          }
        }
      }
    });

    return client;
  }

  /// Clear auth state. Called on logout.
  void clearAuth() => _pb.authStore.clear();
}

/// Async provider — initialized once at startup.
/// The app waits on this before rendering anything.
final pocketbaseClientProvider =
    FutureProvider<PocketBaseClient>((ref) async {
  final storage = ref.read(secureStorageProvider);
  return PocketBaseClient.create(storage);
});
