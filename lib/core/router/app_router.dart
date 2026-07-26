import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/conversation.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/providers/encryption_sync_provider.dart';
import '../../features/auth/screens/backup_pin_screen.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/auth/screens/google_onboarding_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/chat/screens/chat_screen.dart';
import '../../features/friend_requests/screens/friend_requests_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/media/screens/media_docs_screen.dart';
import '../../features/media/screens/media_viewer_screen.dart';
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
  static const String friendRequests = '/friend-requests';
  static const String addFriend      = '/add-friend';
  static const String about          = '/about';
  static const String starredMessages = '/starred/:conversationId';
  static const String mediaViewer     = '/media-viewer';
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

final _rootNavigatorKey = GlobalKey<NavigatorState>();

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

final routerRefreshNotifierProvider = Provider<RouterRefreshNotifier>((ref) {
  return RouterRefreshNotifier(ref);
});

final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = ref.read(routerRefreshNotifierProvider);
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: AppRoutes.splash,
    refreshListenable: refreshNotifier,
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

      if (auth is AuthAuthenticated) {
        final syncStatusAsync = ref.read(encryptionSyncProvider);
        if (syncStatusAsync.isLoading) {
          // While encryption sync is loading, show splash screen
          if (state.matchedLocation != AppRoutes.splash) {
            return AppRoutes.splash;
          }
          return null;
        }

        final syncStatus = syncStatusAsync.valueOrNull;
        if (syncStatus == EncryptionSyncStatus.needsRestore) {
          if (state.matchedLocation != AppRoutes.backupPinRestore) {
            return AppRoutes.backupPinRestore;
          }
        } else if (syncStatus == EncryptionSyncStatus.needsSetup) {
          if (state.matchedLocation != AppRoutes.backupPinSetup) {
            return AppRoutes.backupPinSetup;
          }
        } else if (syncStatus == EncryptionSyncStatus.keyOk) {
          final loc = state.matchedLocation;
          if (loc == AppRoutes.splash ||
              loc == AppRoutes.login ||
              loc == AppRoutes.register ||
              loc == AppRoutes.backupPinSetup ||
              loc == AppRoutes.backupPinRestore) {
            return AppRoutes.home;
          }
        }
      }
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (_, __) => const _SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.register,
        builder: (context, state) {
          final prefill = state.extra as Map<String, String?>?;
          return RegisterScreen(
            prefilledEmail:       prefill?['email'],
            prefilledDisplayName: prefill?['displayName'],
          );
        },
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
        builder: (context, state) {
          final user = state.extra as User;
          return ViewProfileScreen(user: user);
        },
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
        path: AppRoutes.about,
        builder: (_, __) => const AboutScreen(),
      ),
      GoRoute(
        path: AppRoutes.chat,
        builder: (context, state) {
          final conv = state.extra as Conversation;
          return ChatScreen(conversation: conv);
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
        path: AppRoutes.mediaViewer,
        builder: (context, state) {
          final args = state.extra as MediaViewerArgs;
          return MediaViewerScreen(args: args);
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
          final conv = state.extra as Conversation;
          return GroupSettingsScreen(conversation: conv);
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
          final prefill = state.extra as GoogleAuthResult;
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

class _SplashScreen extends ConsumerWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(authProvider, (_, next) {
      if (next.isLoading) return;
      next.whenData((state) {
        if (!context.mounted) return;
        if (state is AuthAuthenticated) {
          context.go(AppRoutes.home);
        } else {
          context.go(AppRoutes.login);
        }
      });
    });

    final authState = ref.watch(authProvider);
    authState.whenData((state) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        if (state is AuthAuthenticated) {
          context.go(AppRoutes.home);
        } else if (state is AuthUnauthenticated || state is AuthError) {
          context.go(AppRoutes.login);
        }
      });
    });

    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
