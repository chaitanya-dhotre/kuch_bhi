import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/settings_tile.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../domain/entities/user.dart';
import '../../../features/auth/providers/auth_provider.dart';

/// A1: shared app-bar title style (20/26 w700).
TextStyle profileTitleStyle(BuildContext context) => TextStyle(
      fontSize: 20,
      height: 26 / 20,
      fontWeight: FontWeight.w700,
      color: context.t.ink,
    );

/// A1: app bar on the page colour, never a separate surface band (the Page 4
/// Group Info bar; device finding 2026-10-29).
AppBar profileAppBar(
  BuildContext context,
  String title, {
  List<Widget>? actions,
}) {
  final t = context.t;
  return AppBar(
    backgroundColor: t.bg,
    surfaceTintColor: t.bg,
    elevation: 0,
    scrolledUnderElevation: 0,
    title: Text(title, style: profileTitleStyle(context)),
    actions: actions,
  );
}

/// K1: "K B 7 Q 2 X" so a screen reader says the code digit by digit.
String spacedCode(String code) => code.split('').join(' ');

/// Copies [code] with a haptic and the shared toast (C2).
void copyFriendCode(BuildContext context, String code) {
  Clipboard.setData(ClipboardData(text: code));
  HapticFeedback.selectionClick();
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
      accentSoft: true,
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
                style: profileTitleStyle(context),
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
    final t = context.t;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WarmPopTokens.radiusXl),
        ),
        title: Text('Sign out?', style: profileTitleStyle(ctx)),
        content: Text(
          'This clears your chats from this phone. You can sign back in any time.',
          style: TextStyle(fontSize: 15, height: 22 / 15, color: t.ink),
        ),
        actions: [
          AppButton(
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          AppButton(
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.logout, size: 18, color: t.error),
                const SizedBox(width: 8),
                const Text('Sign out'),
              ],
            ),
          ),
        ],
      ),
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
      appBar: profileAppBar(context, 'Profile', actions: [
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
                    IconButton(
                      tooltip: 'Copy friend code',
                      onPressed: () => copyFriendCode(context, user.friendCode),
                      icon: Icon(Icons.copy_outlined, color: t.ink),
                    ),
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
          _Group(children: [
            SettingsTile(
              icon: Icons.lock_reset_outlined,
              title: 'Change Backup PIN',
              trailing: Icon(Icons.chevron_right, color: t.inkFaint),
              onTap: () => context.push(AppRoutes.backupPinChange),
            ),
          ]),
          const SizedBox(height: 12),
          _Group(children: [
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

/// Grouped rows: surface, radiusMd, 1px line dividers.
class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Material(
      color: t.surface,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: t.line),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
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
    );
  }
}
