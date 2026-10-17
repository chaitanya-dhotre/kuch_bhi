import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/decrypt/body_cache.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/settings/providers/theme_provider.dart';
import 'infrastructure/repositories/message_repository_impl.dart';
import 'services/presence_service.dart';

/// B (2026-10-14): which lifecycle signal purges the decrypted-body cache.
///
/// `paused` = HOME / Recents / screen-off — the app is genuinely in the
/// background, so spec §3 / amendment 6's intent (never show plaintext in
/// task switcher, never keep it after HOME) holds. `inactive` fires for the
/// notification shade and split-screen peek while the app is STILL VISIBLE
/// — purging there made every shade pull flash locks over live messages.
/// `detached` keeps the historical no-purge branch (process is dying).
@visibleForTesting
bool bodyCachePurgeSignal(AppLifecycleState state) =>
    state == AppLifecycleState.paused;

class KuchBhiApp extends ConsumerStatefulWidget {
  const KuchBhiApp({super.key});

  @override
  ConsumerState<KuchBhiApp> createState() => _KuchBhiAppState();
}

class _KuchBhiAppState extends ConsumerState<KuchBhiApp>
    with WidgetsBindingObserver {
  /// F2b: when focus was first lost (stamp on the FIRST non-resumed signal).
  /// Passed to resyncOnResume so a <60s return takes the light path — one
  /// aggregate delta query instead of the all-conversation backfill scan.
  DateTime? _backgroundedAt;

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
        // that window are silently lost. Reconnect + backfill — a short
        // away (<60s) takes the light delta path, null/long the full one.
        final awayFor = _backgroundedAt == null
            ? null
            : DateTime.now().difference(_backgroundedAt!);
        _backgroundedAt = null;
        ref.read(messageRepositoryProvider).resyncOnResume(awayFor: awayFor);
        // Resume-only throttled token/session refresh (never on navigation).
        ref.read(authProvider.notifier).refreshSessionThrottled();
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        // App backgrounded or about to be killed.
        // goOffline() also clears current_chat and typing_in.
        _backgroundedAt ??= DateTime.now(); // first signal wins (F2b)
        presence.goOffline();
        // Spec §3 / amendment 6: purge decrypted bodies — but only on a
        // signal that actually means background (B, 2026-10-14). The
        // notification shade / split-screen peek emit `inactive` too;
        // purging there re-decrypted every visible message on each shade
        // pull (the recurring "locks flash"). `ready` rows safely
        // re-decrypt on the next provider read (spec §8).
        if (bodyCachePurgeSignal(state)) {
          bodyCache.clear();
        }
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
        ? warmPopDark(amoled: true)
        : warmPopDark();

    final flutterThemeMode = switch (themeMode) {
      AppThemeMode.system => ThemeMode.system,
      AppThemeMode.light  => ThemeMode.light,
      AppThemeMode.dark   => ThemeMode.dark,
      AppThemeMode.amoled => ThemeMode.dark,
    };

    return MaterialApp.router(
      title:                     'Kuch Bhi',
      debugShowCheckedModeBanner: false,
      theme:       warmPopLight(),
      darkTheme:   darkTheme,
      themeMode:   flutterThemeMode,
      routerConfig: router,
    );
  }
}
