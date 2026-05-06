import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Route name constants
class AppRoutes {
  AppRoutes._();
  static const String splash = '/';
  static const String login = '/login';
  static const String register = '/register';
  static const String home = '/home';
  static const String chat = '/chat/:conversationId';
  static const String profile = '/profile';
  static const String settings = '/settings';
  static const String friendRequests = '/friend-requests';
  static const String addFriend = '/add-friend';
  static const String mediaViewer = '/media-viewer';
  static const String starredMessages = '/starred';
  static const String groupCreate = '/group/create';
  static const String groupInfo = '/group/:groupId/info';
}

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: true,
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const _PlaceholderScreen(title: 'Splash'),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const _PlaceholderScreen(title: 'Login'),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const _PlaceholderScreen(title: 'Home'),
      ),
    ],
  );
});

/// Temporary placeholder — replaced screen by screen during development.
class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text(
          'Phase 1 — $title\nReady for implementation.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    );
  }
}
