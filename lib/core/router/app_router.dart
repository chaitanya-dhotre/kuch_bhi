import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/conversation.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/chat/screens/chat_screen.dart';
import '../../features/friend_requests/screens/friend_requests_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/media/screens/media_docs_screen.dart';
import '../../features/media/screens/media_viewer_screen.dart';
import '../../features/groups/screens/create_group_screen.dart';
import '../../features/groups/screens/group_settings_screen.dart';
import '../../features/profile/screens/profile_screen.dart';

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
  static const String starredMessages = '/starred/:conversationId';
  static const String mediaViewer     = '/media-viewer';
  static const String mediaDocs       = '/media-docs/:conversationId';
  static const String createGroup     = '/create-group';
  static const String groupSettings   = '/group-settings';
}

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: AppRoutes.splash,
    redirect: (context, state) {
      final auth = ref.read(authProvider).valueOrNull;
      final protected = [AppRoutes.home, AppRoutes.profile,
                         AppRoutes.friendRequests, AppRoutes.chat,
                         AppRoutes.createGroup, AppRoutes.groupSettings,
                         '/starred'];
      if (protected.any((p) => state.matchedLocation.startsWith(p)) &&
          auth is! AuthAuthenticated) {
        return AppRoutes.login;
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
        builder: (_, __) => const RegisterScreen(),
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
        path: AppRoutes.friendRequests,
        builder: (_, __) => const FriendRequestsScreen(),
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
