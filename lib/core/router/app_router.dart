import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/conversation.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/providers/encryption_sync_provider.dart';
import '../../features/auth/screens/backup_pin_screen.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/auth/screens/google_onboarding_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/app_lock/app_lock_settings_screen.dart';
import '../../features/chat/screens/chat_screen.dart';
import '../../features/friend_requests/screens/friend_requests_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/media/screens/media_docs_screen.dart';
import '../../features/groups/screens/create_group_screen.dart';
import '../../features/groups/screens/group_settings_screen.dart';
import '../../features/profile/screens/edit_profile_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/profile/screens/view_profile_screen.dart';
import '../../features/settings/screens/about_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/starred_messages/screens/starred_messages_screen.dart';
import '../../services/encryption_service.dart';

class AppRoutes {
  AppRoutes._();
  static const String splash         = '/';
  static const String login          = '/login';
  static const String register       = '/register';
  static const String home           = '/home';
  static const String chat           = '/chat';
  static const String profile        = '/profile';
  static const String settings       = '/settings';
  static const String appLock        = '/settings/app-lock';
  static const String friendRequests = '/friend-requests';
  static const String addFriend      = '/add-friend';
  static const String about          = '/about';
  static const String starredMessages = '/starred/:conversationId';
  static const String mediaDocs       = '/media-docs/:conversationId';
  static const String createGroup     = '/create-group';
  static const String groupSettings   = '/group-settings';
  static const String backupPinSetup    = '/backup-pin/setup';
  static const String backupPinRestore  = '/backup-pin/restore';
  static const String backupPinChange   = '/backup-pin/change';
  static const String forgotPassword    = '/forgot-password';
  static const String editProfile       = '/edit-profile';
  static const String viewProfile       = '/view-profile';
  static const String googleOnboarding  = '/google-onboarding';
}

/// Root navigator key — public so non-widget code (FcmService notification
/// tap routing) can navigate via `rootNavigatorKey.currentContext`.
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// A refresh rebuilds a pushed stack from go_router's encoded copy, and without
/// a codec every `extra` comes back null. This one encodes a token and decodes
/// the same object, so a page keeps its data and its state. The stack holds the
/// object strongly while the page is open; the weak link lets it go afterwards.
/// shortcut: class instances only (Expando throws on a String or num extra),
/// wrap one in a class if a route ever needs that.
class _LiveExtraCodec extends Codec<Object?, Object?> {
  final _tokens = Expando<int>();
  final _live = <int, WeakReference<Object>>{};
  int _nextToken = 0;

  Object? _encode(Object? extra) {
    if (extra == null) return null;
    final known = _tokens[extra];
    if (known != null) return known;
    _live.removeWhere((_, object) => object.target == null);
    _live[_nextToken] = WeakReference(extra);
    return _tokens[extra] = _nextToken++;
  }

  @override
  late final encoder = _Converted(_encode);

  @override
  late final decoder = _Converted((token) => _live[token]?.target);
}

class _Converted extends Converter<Object?, Object?> {
  const _Converted(this._convert);
  final Object? Function(Object?) _convert;

  @override
  Object? convert(Object? input) => _convert(input);
}

/// A page that lost its `extra` can't draw, so it leaves instead of going grey.
/// Not a route redirect: go_router ignores one to the stack's base location,
/// which for a page pushed over Home is Home itself.
Widget _backToHome(BuildContext context) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (context.mounted) context.go(AppRoutes.home);
  });
  return const Scaffold();
}

class RouterRefreshNotifier extends ChangeNotifier {
  RouterRefreshNotifier(Ref ref) {
    ref.listen(authProvider, (previous, next) {
      debugPrint('[RouterRefresh] authProvider changed: $previous -> $next');
      notifyListeners();
    });
    ref.listen(encryptionSyncProvider, (previous, next) {
      debugPrint('[RouterRefresh] encryptionSyncProvider changed: $previous -> $next');
      notifyListeners();
    });
  }
}

/// Where the key-sync route sends a signed-in user. Remembers the user it
/// last answered keyOk for, so a reload for that same user (an auth
/// re-publish such as a profile save) leaves them where they are instead of
/// bouncing through the splash. Any other reload still waits on the splash.
class SyncRouteGate {
  String? _keyOkFor;

  String? redirect(
      String loc, AuthState? auth, AsyncValue<EncryptionSyncStatus> sync) {
    if (auth is! AuthAuthenticated) {
      _keyOkFor = null;
      return null;
    }
    if (sync.isLoading) {
      if (_keyOkFor == auth.user.id) return null;
      return loc == AppRoutes.splash ? null : AppRoutes.splash;
    }

    final syncStatus = sync.valueOrNull;
    _keyOkFor = syncStatus == EncryptionSyncStatus.keyOk ? auth.user.id : null;
    if (syncStatus == EncryptionSyncStatus.needsRestore) {
      if (loc != AppRoutes.backupPinRestore) return AppRoutes.backupPinRestore;
    } else if (syncStatus == EncryptionSyncStatus.needsSetup) {
      if (loc != AppRoutes.backupPinSetup) return AppRoutes.backupPinSetup;
    } else if (syncStatus == EncryptionSyncStatus.keyOk) {
      if (loc == AppRoutes.splash ||
          loc == AppRoutes.login ||
          loc == AppRoutes.register ||
          loc == AppRoutes.backupPinSetup ||
          loc == AppRoutes.backupPinRestore) {
        return AppRoutes.home;
      }
    }
    return null;
  }
}

final routerRefreshNotifierProvider = Provider<RouterRefreshNotifier>((ref) {
  return RouterRefreshNotifier(ref);
});

final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = ref.read(routerRefreshNotifierProvider);
  final syncGate = SyncRouteGate();
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.splash,
    refreshListenable: refreshNotifier,
    extraCodec: _LiveExtraCodec(),
    redirect: (context, state) {
      final auth = ref.read(authProvider).valueOrNull;
      final syncStatusAsync = ref.read(encryptionSyncProvider);
      debugPrint('[RouterRedirect] location: ${state.matchedLocation}, auth: $auth, syncLoading: ${syncStatusAsync.isLoading}, syncValue: ${syncStatusAsync.valueOrNull}');
      final protected = [
        AppRoutes.home, AppRoutes.profile,
        AppRoutes.friendRequests, AppRoutes.chat,
        AppRoutes.createGroup, AppRoutes.groupSettings,
        AppRoutes.settings, AppRoutes.about,
        '/starred'
      ];
      if (protected.any((p) => state.matchedLocation.startsWith(p)) &&
          auth is! AuthAuthenticated) {
        return AppRoutes.login;
      }

      return syncGate.redirect(state.matchedLocation, auth, syncStatusAsync);
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.register,
        builder: (_, __) => const RegisterScreen(),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (_, __) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (_, __) => const HomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.profile,
        builder: (_, __) => const ProfileScreen(),
      ),
      GoRoute(
        path: AppRoutes.editProfile,
        builder: (_, __) => const EditProfileScreen(),
      ),
      GoRoute(
        path: AppRoutes.viewProfile,
        builder: (context, state) => viewProfileFromExtra(state.extra),
      ),
      GoRoute(
        path: AppRoutes.friendRequests,
        builder: (_, __) => const FriendRequestsScreen(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (_, __) => const SettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.appLock,
        builder: (_, __) => const AppLockSettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.about,
        builder: (_, __) => const AboutScreen(),
      ),
      GoRoute(
        path: AppRoutes.chat,
        builder: (context, state) {
          final conv = state.extra;
          return conv is Conversation
              ? ChatScreen(conversation: conv)
              : _backToHome(context);
        },
      ),
      GoRoute(
        path: AppRoutes.starredMessages,
        builder: (context, state) {
          final convId = state.pathParameters['conversationId']!;
          return StarredMessagesScreen(conversationId: convId);
        },
      ),
      GoRoute(
        path: AppRoutes.mediaDocs,
        builder: (context, state) {
          final convId = state.pathParameters['conversationId']!;
          return MediaDocsScreen(conversationId: convId);
        },
      ),
      GoRoute(
        path: AppRoutes.createGroup,
        builder: (_, __) => const CreateGroupScreen(),
      ),
      GoRoute(
        path: AppRoutes.groupSettings,
        builder: (context, state) {
          final conv = state.extra;
          return conv is Conversation
              ? GroupSettingsScreen(conversation: conv)
              : _backToHome(context);
        },
      ),
      GoRoute(
        path: AppRoutes.backupPinSetup,
        builder: (context, state) {
          return FutureBuilder<bool>(
            future: ref.read(encryptionServiceProvider).hasLocalPrivateKey(),
            builder: (context, snapshot) {
              final hasLocal = snapshot.data ?? true;
              return BackupPinScreen(
                mode: BackupPinMode.setup,
                isOptionalSetup: !hasLocal,
              );
            },
          );
        },
      ),
      GoRoute(
        path: AppRoutes.backupPinRestore,
        builder: (_, __) => const BackupPinScreen(mode: BackupPinMode.restore),
      ),
      GoRoute(
        path: AppRoutes.backupPinChange,
        builder: (_, __) => const BackupPinScreen(mode: BackupPinMode.change),
      ),
      GoRoute(
        path: AppRoutes.googleOnboarding,
        builder: (context, state) {
          // H2: no prefill (process death) falls back to Login.
          final prefill = state.extra;
          if (prefill is! GoogleAuthResult) return const LoginScreen();
          return GoogleOnboardingScreen(
            email: prefill.email ?? '',
            displayName: prefill.displayName ?? '',
            idToken: prefill.idToken ?? '',
          );
        },
      ),
    ],
  );
});
