import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/app_haptic.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/page_app_bar.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/settings_tile.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../domain/entities/user.dart';
import '../../../features/auth/providers/auth_provider.dart';

/// K1: "K B 7 Q 2 X" so a screen reader says the code digit by digit.
String spacedCode(String code) => code.split('').join(' ');

/// Copies [code] with a haptic and the shared toast (C2).
void copyFriendCode(BuildContext context, String code) {
  Clipboard.setData(ClipboardData(text: code));
  appHaptic(HapticsType.selection);
  showToast(context, 'Friend code copied');
}

/// Avatar + name + @username + about, shared by Profile and View Profile.
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({super.key, required this.user, this.onAvatarTap});

  final User user;
  final VoidCallback? onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final name = user.displayName.trim().isEmpty ? 'Unknown' : user.displayName;
    final about = (user.about ?? '').trim();
    final avatar = AppAvatar(
      url: user.avatarUrl,
      initials: initialsOf(user.displayName),
      radius: 48,
    );
    return Column(
      children: [
        if (onAvatarTap == null)
          ExcludeSemantics(child: avatar)
        else
          Semantics(
            button: true,
            label: 'Edit profile',
            excludeSemantics: true,
            child: GestureDetector(onTap: onAvatarTap, child: avatar),
          ),
        const SizedBox(height: 16),
        Semantics(
          header: true,
          label: '$name, @${user.username}${about.isEmpty ? '' : ', $about'}',
          excludeSemantics: true,
          child: Column(
            children: [
              Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: pageTitleStyle(context),
              ),
              Text(
                '@${user.username}',
                style: TextStyle(fontSize: 15, height: 22 / 15, color: t.inkSoft),
              ),
              if (about.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  about,
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, height: 22 / 15, color: t.ink),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final ok = await showConfirmDialog(
      context: context,
      title: 'Sign out?',
      body:
          'This clears your chats from this phone. You can sign back in any time.',
      confirmLabel: 'Sign out',
      confirmIcon: Icons.logout,
      destructive: true,
    );
    if (ok == true) await ref.read(authProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final authState = ref.watch(authProvider).valueOrNull;
    final user = authState is AuthAuthenticated ? authState.user : null;

    return Scaffold(
      backgroundColor: t.bg,
      appBar: pageAppBar(context, 'Profile', actions: [
        IconButton(
          tooltip: 'Settings',
          icon: Icon(Icons.settings_outlined, color: t.ink),
          onPressed: () => context.push(AppRoutes.settings),
        ),
      ]),
      body: user == null ? const _ProfileSkeleton() : _body(context, ref, user),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, User user) {
    final t = context.t;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 16),
          ProfileHeader(
            user: user,
            onAvatarTap: () => context.push(AppRoutes.editProfile),
          ),
          const SizedBox(height: 16),
          AppButton(
            variant: AppButtonVariant.secondary,
            onPressed: () => context.push(AppRoutes.editProfile),
            child: const Text('Edit profile'),
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(WarmPopTokens.radiusLg),
              boxShadow: WarmPopTokens.cardShadow(t.shadow),
            ),
            child: Column(
              children: [
                Text(
                  'YOUR FRIEND CODE',
                  style: TextStyle(
                    fontSize: 11,
                    height: 14 / 11,
                    fontWeight: FontWeight.w600,
                    color: t.inkSoft,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Semantics(
                      label: 'Friend code ${spacedCode(user.friendCode)}',
                      excludeSemantics: true,
                      child: Text(
                        user.friendCode,
                        style: TextStyle(
                          fontSize: 28,
                          height: 34 / 28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 4,
                          color: t.ink,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _CopyCodeButton(code: user.friendCode),
                  ],
                ),
                const SizedBox(height: 16),
                // Fixed white in both themes so the code scans (fixed tokens,
                // never theme-flipped ink on white).
                Semantics(
                  label: 'QR code for your friend code',
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: WarmPopTokens.surface,
                      borderRadius:
                          BorderRadius.circular(WarmPopTokens.radiusMd),
                    ),
                    child: Column(
                      children: [
                        ExcludeSemantics(
                          child: QrImageView(
                            data: 'kuchbhi://add/${user.friendCode}',
                            version: QrVersions.auto,
                            size: 200,
                            eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                              color: WarmPopTokens.ink,
                            ),
                            dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: WarmPopTokens.ink,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Scan to add me on Kuch Bhi',
                          style: TextStyle(
                            fontSize: 13,
                            height: 18 / 13,
                            color: WarmPopTokens.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SectionHeader('Account'),
          SettingsGroup(children: [
            SettingsTile(
              icon: Icons.lock_reset_outlined,
              title: 'Recovery key',
              trailing: Icon(Icons.chevron_right, color: t.inkFaint),
              onTap: () => context.push(AppRoutes.backupPinChange),
            ),
          ]),
          const SizedBox(height: 12),
          SettingsGroup(children: [
            SettingsTile(
              icon: Icons.logout,
              title: 'Sign out',
              destructive: true,
              onTap: () => _confirmSignOut(context, ref),
            ),
          ]),
        ],
      ),
    );
  }
}

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    // A7: one SkeletonGroup, so every block breathes on one clock.
    return const SkeletonGroup(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          children: [
            SizedBox(height: 16),
            Skeleton(height: 96, width: 96, radius: 48),
            SizedBox(height: 16),
            Skeleton(height: 20, width: 160),
            SizedBox(height: 8),
            Skeleton(height: 16, width: 100),
            SizedBox(height: 32),
            Skeleton(height: 180, radius: WarmPopTokens.radiusLg),
          ],
        ),
      ),
    );
  }
}

/// C3: the copy icon turns into a tick for 1.5 s after a copy.
class _CopyCodeButton extends StatefulWidget {
  const _CopyCodeButton({required this.code});
  final String code;

  @override
  State<_CopyCodeButton> createState() => _CopyCodeButtonState();
}

class _CopyCodeButtonState extends State<_CopyCodeButton> {
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  void _copy() {
    copyFriendCode(context, widget.code);
    _reset?.cancel();
    setState(() {
      _reset = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _reset = null);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final copied = _reset != null;
    return IconButton(
      tooltip: 'Copy friend code',
      onPressed: _copy,
      icon: AnimatedSwitcher(
        duration: motionOf(context, WarmPopTokens.motionFast),
        child: Icon(
          copied ? Icons.check : Icons.copy_outlined,
          key: ValueKey(copied),
          color: context.t.ink,
        ),
      ),
    );
  }
}
