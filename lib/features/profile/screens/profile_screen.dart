import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/tokens.dart';
import '../../../features/auth/providers/auth_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider).valueOrNull;
    final user =
        authState is AuthAuthenticated ? authState.user : null;

    if (user == null) return const SizedBox.shrink();

    final qrData = 'kuchbhi://add/${user.friendCode}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push(AppRoutes.settings),
          ),
          TextButton(
            onPressed: () =>
                ref.read(authProvider.notifier).signOut(),
            child: Text(
              'Sign Out',
              style: TextStyle(color: context.t.error),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 16),

            // Avatar.
            CircleAvatar(
              radius: 48,
              backgroundColor: context.t.accentSoft,
              child: Text(
                user.displayName.substring(0, 1).toUpperCase(),
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                  color: context.t.accent,
                ),
              ),
            ),
            const SizedBox(height: 16),

            Text(
              user.displayName,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              '@${user.username}',
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 32),

            // Friend code card.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: context.t.accentSoft,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Text(
                    'Your Friend Code',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: context.t.accent,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        user.friendCode,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 6,
                          color: context.t.accent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: user.friendCode),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Friend code copied!'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        icon: Icon(
                          Icons.copy_outlined,
                          color: context.t.accent,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Tonal secondary per approved Batch 2 mockup (AppButton
            // .secondary is an outline style; tonal variant deferred).
            ElevatedButton.icon(
              onPressed: () => context.push(AppRoutes.backupPinChange),
              icon: const Icon(Icons.lock_reset_outlined),
              label: const Text('Change Backup PIN'),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.t.accentSoft,
                foregroundColor: context.t.accent,
                elevation: 0,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // QR code.
            // QR card stays white in both themes so the code scans and the
            // caption reads: fixed tokens, never theme-flipped ink on white.
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: WarmPopTokens.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: context.t.shadow,
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  QrImageView(
                    data: qrData,
                    version: QrVersions.auto,
                    size: 200,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: WarmPopTokens.accent,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: WarmPopTokens.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Share this QR code to add friends',
                    style: TextStyle(
                      fontSize: 12,
                      color: WarmPopTokens.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
