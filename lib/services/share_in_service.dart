// Share into the app (12.1 B1–B7, F3): takes a share from MainActivity's
// `kuch_bhi/share` channel, holds it until the app can send, then opens the
// Send to picker. Nothing is copied here.
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/router/app_router.dart';
import '../core/widgets/app_toast.dart';
import '../domain/entities/conversation.dart';
import '../features/auth/providers/auth_provider.dart';
import '../features/auth/providers/encryption_sync_provider.dart';
import '../features/chat/message_offline_policy.dart' show kUploadTooBig;
import '../features/share/share_payload.dart';
import '../features/share/share_target_screen.dart';

const shareChannel = MethodChannel('kuch_bhi/share');

/// The share waiting for a chat (B1); a newer one replaces it (B6).
final pendingShareProvider = StateProvider<ShareInPayload?>((_) => null);

/// A copied share handed to one chat's composer (D10). Not autoDispose: the
/// picker writes it before the chat is built.
final chatShareProvider = StateProvider.family<ReadyShare?, String>(
  (_, _) => null,
);

final shareInServiceProvider = Provider<ShareInService>((ref) {
  final service = ShareInService(ref);
  ref.listen(authProvider, (_, next) => service._onAuth(next.valueOrNull));
  ref.listen(encryptionSyncProvider, (_, _) => service._check());
  ref.listen(pendingShareProvider, (_, _) => service._check());
  return service;
});

/// Wipes `cache/share_in/` (F3). Best effort: no channel in tests.
Future<void> clearSharedFiles() async {
  try {
    await shareChannel.invokeMethod<void>('clearShared');
  } catch (e) {
    debugPrint('[Share] clear failed: $e');
  }
}

// Screens a share waits behind: sign-in, key restore or setup (B4, B5).
const _waitRoutes = {
  AppRoutes.splash,
  AppRoutes.login,
  AppRoutes.register,
  AppRoutes.forgotPassword,
  AppRoutes.googleOnboarding,
  AppRoutes.backupPinSetup,
  AppRoutes.backupPinRestore,
};

class ShareInService {
  ShareInService(this._ref);

  final Ref _ref;
  bool _started = false;
  bool _pickerOpen = false;
  bool _checkQueued = false;
  bool _signedIn = false;
  ShareInPayload? _toastedFor;

  GoRouter get _router => _ref.read(appRouterProvider);

  /// App start: clear what an earlier run left, then take the share that
  /// started the app, if any. Safe to call twice (hot restart).
  Future<void> start() async {
    // setMethodCallHandler replaces: a hot restart never doubles it (K3).
    shareChannel.setMethodCallHandler((call) async {
      if (call.method == 'shareArrived') await _take();
    });
    if (_started) return;
    _started = true;
    _signedIn = _ref.read(authProvider).valueOrNull is AuthAuthenticated;
    _router.routerDelegate.addListener(_check);
    await clearSharedFiles(); // no share can be in flight yet
    await _take();
  }

  Future<void> _take() async {
    try {
      final raw = await shareChannel.invokeMapMethod<Object?, Object?>(
        'takeShare',
      );
      if (raw == null) return;
      final items = [
        for (final m in (raw['items'] as List<Object?>? ?? const []))
          SharedItem.fromMap(m! as Map<Object?, Object?>),
      ];
      _ref.read(pendingShareProvider.notifier).state = ShareInPayload(
        items: items,
        text: raw['text'] as String?,
      );
    } catch (e) {
      debugPrint('[Share] take failed: $e');
    }
  }

  void _onAuth(AuthState? auth) {
    if (auth is AuthAuthenticated) {
      _signedIn = true;
    } else if (auth is AuthUnauthenticated) {
      // Logout drops a waiting share (B4); a share from before sign-in stays.
      if (_signedIn) {
        _ref.read(pendingShareProvider.notifier).state = null;
        _ref.invalidate(chatShareProvider);
      }
      _signedIn = false;
    }
    _check();
  }

  String? _location() {
    try {
      return _router.state.matchedLocation;
    } catch (_) {
      return null; // router not built yet; its first notify re-checks
    }
  }

  // Navigation from a router or provider callback waits for the frame.
  void _check() {
    if (!_started || _checkQueued) return;
    _checkQueued = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _checkQueued = false;
      _checkNow();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _checkNow() {
    final share = _ref.read(pendingShareProvider);
    if (share == null || _pickerOpen) return; // an open picker follows B6
    final location = _location();
    final ctx = rootNavigatorKey.currentContext;
    if (location == null || ctx == null || !ctx.mounted) return;

    if (_ref.read(authProvider).valueOrNull is! AuthAuthenticated) {
      if (location == AppRoutes.login && !identical(_toastedFor, share)) {
        _toastedFor = share;
        showToast(ctx, 'Sign in to share.');
      }
      return;
    }
    final sync = _ref.read(encryptionSyncProvider);
    if (sync.isLoading || sync.valueOrNull != EncryptionSyncStatus.keyOk) {
      return;
    }
    if (_waitRoutes.contains(location)) return;
    _open(share);
  }

  Future<void> _open(ShareInPayload share) async {
    final plan = planShare(share);
    final ctx = rootNavigatorKey.currentContext!;
    if (plan.isEmpty) {
      _ref.read(pendingShareProvider.notifier).state = null;
      showToast(
        ctx,
        plan.tooBig > 0 ? kUploadTooBig : kShareUnreadable,
        error: true,
      );
      return;
    }

    _pickerOpen = true;
    final Conversation? conv;
    try {
      conv = await Navigator.of(ctx).push<Conversation>(shareTargetRoute(ctx));
    } finally {
      _pickerOpen = false;
    }
    if (conv == null) {
      // ✕, back or swipe (D11): drop it, delete any copies.
      _ref.read(pendingShareProvider.notifier).state = null;
      await clearSharedFiles();
      return;
    }
    // D9: the chat takes the picker's place; already under it → just popped.
    final top = _router.state;
    final under = top.extra;
    if (top.matchedLocation == AppRoutes.chat &&
        under is Conversation &&
        under.id == conv.id) {
      return;
    }
    _router.push(AppRoutes.chat, extra: conv);
  }
}
