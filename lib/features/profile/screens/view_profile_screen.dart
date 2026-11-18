import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/page_app_bar.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/settings_tile.dart';
import '../../../domain/entities/user.dart';
import '../../security/key_change_providers.dart';
import '../../security/security_code_screen.dart';
import 'profile_screen.dart';

/// H5: the `/view-profile` route body. A restored route or a bad deep link
/// has no [User] in `extra`; show the unavailable state instead of crashing.
Widget viewProfileFromExtra(Object? extra) =>
    extra is User ? ViewProfileScreen(user: extra) : const ProfileUnavailableScreen();

class ViewProfileScreen extends StatelessWidget {
  const ViewProfileScreen({super.key, required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: pageAppBar(context, 'Profile'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 16),
            ProfileHeader(user: user),
            const SizedBox(height: 32),
            Material(
              color: t.surface,
              clipBehavior: Clip.antiAlias,
              borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd),
              // K1: one node that reads the code digit by digit; the whole
              // row copies, so the trailing icon needs no node of its own.
              child: Semantics(
                button: true,
                label: 'Friend code ${spacedCode(user.friendCode)}',
                hint: 'Copy friend code',
                excludeSemantics: true,
                child: SettingsTile(
                  icon: Icons.tag,
                  title: 'Friend code',
                  subtitle: user.friendCode,
                  onTap: () => copyFriendCode(context, user.friendCode),
                  trailing: IconButton(
                    tooltip: 'Copy friend code',
                    onPressed: () => copyFriendCode(context, user.friendCode),
                    icon: Icon(Icons.copy_outlined, color: t.ink),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // F3 D7: the contact's security code and whether it is checked.
            Consumer(
              builder: (context, ref, _) {
                final pin = ref.watch(contactKeyProvider(user.id)).asData?.value;
                if (pin == null) return const SizedBox.shrink();
                return Material(
                  color: t.surface,
                  clipBehavior: Clip.antiAlias,
                  borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd),
                  child: SettingsTile(
                    key: const ValueKey('profile-security-code'),
                    icon: Icons.shield_outlined,
                    title: 'Security code',
                    subtitle: pin.isPending
                        ? 'Changed, check it'
                        : (pin.verified ? 'Verified' : 'Not verified'),
                    onTap: () => openSecurityCode(
                      context,
                      userId: user.id,
                      name: user.displayName,
                      avatarUrl: user.avatarUrl,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class ProfileUnavailableScreen extends StatelessWidget {
  const ProfileUnavailableScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: pageAppBar(context, 'Profile'),
      body: EmptyState(
        title: 'Profile unavailable',
        action: AppButton(
          variant: AppButtonVariant.secondary,
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(AppRoutes.home),
          child: const Text('Go back'),
        ),
      ),
    );
  }
}
