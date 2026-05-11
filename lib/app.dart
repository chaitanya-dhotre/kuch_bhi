import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/constants/app_colors.dart';
import 'core/router/app_router.dart';
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
    return MaterialApp.router(
      title:                     'Kuch Bhi',
      debugShowCheckedModeBanner: false,
      theme:       AppColors.lightTheme(),
      darkTheme:   AppColors.darkTheme(),
      themeMode:   ThemeMode.system,
      routerConfig: router,
    );
  }
}
