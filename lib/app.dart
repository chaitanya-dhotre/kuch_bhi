import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_colors.dart';
import 'core/router/app_router.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/settings/providers/theme_provider.dart';
import 'infrastructure/repositories/message_repository_impl.dart';
import 'services/presence_service.dart';

class KuchBhiApp extends ConsumerStatefulWidget {
  const KuchBhiApp({super.key});

  @override
  ConsumerState<KuchBhiApp> createState() => _KuchBhiAppState();
}

class _KuchBhiAppState extends ConsumerState<KuchBhiApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(presenceServiceProvider).goOnline();
      // Cold start: the lifecycle `resumed` event does NOT fire when the
      // app is launched from killed — without this, messages received while
      // the app was closed are never fetched on open, so the home badge
      // stays stale (item-4 fail). Deltas are cursor-cheap; this is the
      // cold-start twin of the resumed handler below.
      ref.read(messageRepositoryProvider).resyncOnResume();
      ref.read(authProvider.notifier).refreshSessionThrottled();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Best-effort offline update — the server-side cron (every 5 min)
    // handles cases where this call doesn't complete before the OS kills
    // the process (e.g. swipe-away from recents).
    ref.read(presenceServiceProvider).goOffline();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final presence = ref.read(presenceServiceProvider);
    switch (state) {
      case AppLifecycleState.resumed:
        // App foregrounded — re-establish online status.
        // The active ChatScreen (if any) will call enterChat() itself
        // via its own WidgetsBindingObserver.
        presence.goOnline();
        // Android suspends the SSE socket while backgrounded and events in
        // that window are silently lost. Reconnect + backfill everything.
        ref.read(messageRepositoryProvider).resyncOnResume();
        // Resume-only throttled token/session refresh (never on navigation).
        ref.read(authProvider.notifier).refreshSessionThrottled();
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        // App backgrounded or about to be killed.
        // goOffline() also clears current_chat and typing_in.
        presence.goOffline();
      case AppLifecycleState.detached:
        presence.goOffline();
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider).valueOrNull ??
        AppThemeMode.system;

    // AMOLED is a dark variant selected via darkTheme + forced dark mode.
    final darkTheme = themeMode == AppThemeMode.amoled
        ? AppColors.amoledTheme()
        : AppColors.darkTheme();

    final flutterThemeMode = switch (themeMode) {
      AppThemeMode.system => ThemeMode.system,
      AppThemeMode.light  => ThemeMode.light,
      AppThemeMode.dark   => ThemeMode.dark,
      AppThemeMode.amoled => ThemeMode.dark,
    };

    return MaterialApp.router(
      title:                     'Kuch Bhi',
      debugShowCheckedModeBanner: false,
      theme:       AppColors.lightTheme(),
      darkTheme:   darkTheme,
      themeMode:   flutterThemeMode,
      routerConfig: router,
    );
  }
}
