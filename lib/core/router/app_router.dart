import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/friend_requests/screens/friend_requests_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/profile/screens/profile_screen.dart';

class AppRoutes {
  AppRoutes._();
  static const String splash          = '/';
  static const String login           = '/login';
  static const String register        = '/register';
  static const String home            = '/home';
  static const String chat            = '/chat/:conversationId';
  static const String profile         = '/profile';
  static const String settings        = '/settings';
  static const String friendRequests  = '/friend-requests';
  static const String addFriend       = '/add-friend';
  static const String mediaViewer     = '/media-viewer';
  static const String starredMessages = '/starred';
  static const String groupCreate     = '/group/create';
  static const String groupInfo       = '/group/:groupId/info';
}

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final authState = ref.read(authProvider).valueOrNull;
      final protected = [AppRoutes.home, AppRoutes.profile,
                         AppRoutes.friendRequests];
      if (protected.contains(state.matchedLocation) &&
          authState is! AuthAuthenticated) {
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

    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
