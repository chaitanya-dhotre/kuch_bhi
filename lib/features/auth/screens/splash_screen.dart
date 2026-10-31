import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_logo_tile.dart';
import '../../../core/widgets/busy_spinner.dart';
import '../providers/auth_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  /// B3: a spinner only when the splash outlasts 1s.
  Timer? _slowTimer;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    _slowTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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

    final t = context.t;
    return Scaffold(
      backgroundColor: t.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppLogoTile(),
            const SizedBox(height: 16),
            Text(
              AppConstants.appName,
              style: TextStyle(
                fontSize: 24,
                height: 30 / 24,
                fontWeight: FontWeight.w700,
                color: t.ink,
              ),
            ),
            const SizedBox(height: 24),
            AnimatedOpacity(
              opacity: _slow ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: _slow ? const BusySpinner() : const SizedBox(height: 18),
            ),
          ],
        ),
      ),
    );
  }
}
