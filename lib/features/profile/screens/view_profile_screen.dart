import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/settings_tile.dart';
import '../../../domain/entities/user.dart';
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
      appBar: profileAppBar(context, 'Profile'),
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
      appBar: profileAppBar(context, 'Profile'),
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
