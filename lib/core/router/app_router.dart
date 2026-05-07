import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_screen.dart';

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

// Single global key — never recreated.
final _rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: false,
    // Route guard: only blocks unauthenticated access to protected routes.
    // All success-path navigation is handled imperatively via ref.listen
    // in the individual screens. This avoids stale-read race conditions.
    redirect: (context, state) {
      final authState = ref.read(authProvider).valueOrNull;
      final location  = state.matchedLocation;

      final isProtected = location == AppRoutes.home;

      // Block unauthenticated users from protected routes.
      if (isProtected && authState is! AuthAuthenticated) {
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
        builder: (_, __) => const _PlaceholderScreen(title: 'Home 🏠'),
      ),
    ],
  );
});

class _SplashScreen extends ConsumerWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Navigate as soon as auth state resolves — no redirect needed.
    ref.listen(authProvider, (_, next) {
      if (next.isLoading) return;
      next.whenData((state) {
        if (state is AuthAuthenticated) {
          context.go(AppRoutes.home);
        } else {
          context.go(AppRoutes.login);
        }
      });
    });

    // Also handle the case where state is already resolved
    // (e.g. hot restart with cached session).
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

class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
    );
  }
}
