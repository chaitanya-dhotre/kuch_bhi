import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_provider.dart';

class AppRoutes {
  AppRoutes._();
  static const String splash    = '/';
  static const String login     = '/login';
  static const String register  = '/register';
  static const String home      = '/home';
  static const String chat      = '/chat/:conversationId';
  static const String profile   = '/profile';
  static const String settings  = '/settings';
  static const String friendRequests = '/friend-requests';
  static const String addFriend = '/add-friend';
  static const String mediaViewer = '/media-viewer';
  static const String starredMessages = '/starred';
  static const String groupCreate = '/group/create';
  static const String groupInfo = '/group/:groupId/info';
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final isOnSplash = state.matchedLocation == AppRoutes.splash;
      final isOnAuth   = state.matchedLocation == AppRoutes.login ||
                         state.matchedLocation == AppRoutes.register;

      return authState.when(
        loading: () => isOnSplash ? null : AppRoutes.splash,
        error: (_, __) => AppRoutes.login,
        data: (authData) => switch (authData) {
          AuthLoading()        => isOnSplash ? null : AppRoutes.splash,
          AuthAuthenticated()  => isOnAuth || isOnSplash
                                    ? AppRoutes.home
                                    : null,
          AuthUnauthenticated() => isOnAuth ? null : AppRoutes.login,
          AuthError()          => isOnAuth ? null : AppRoutes.login,
        },
      );
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (_, __) => const _SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (_, __) => const _PlaceholderScreen(title: 'Login'),
      ),
      GoRoute(
        path: AppRoutes.register,
        builder: (_, __) => const _PlaceholderScreen(title: 'Register'),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (_, __) => const _PlaceholderScreen(title: 'Home'),
      ),
    ],
  );
});

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
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
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
    );
  }
}
