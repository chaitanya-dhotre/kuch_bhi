import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/page_app_bar.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/settings_tile.dart';
import '../../app_lock/app_lock_controller.dart';
import '../widgets/font_choice_group.dart';
import '../widgets/notifications_status_row.dart';
import '../widgets/theme_mode_group.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final appLockOn = ref.watch(appLockProvider).enabled;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: pageAppBar(context, 'Settings'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        children: [
          const SectionHeader('Appearance'),
          const ThemeModeGroup(),
          const SectionHeader('Font'),
          const FontChoiceGroup(),
          const SectionHeader('Notifications'),
          const NotificationsStatusRow(),
          const SectionHeader('Privacy'),
          SettingsGroup(children: [
            SettingsTile(
              icon: Icons.lock_outline,
              title: 'App lock',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(appLockOn ? 'On' : 'Off',
                      style: TextStyle(fontSize: 14, color: t.inkSoft)),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right, color: t.inkFaint),
                ],
              ),
              onTap: () => context.push(AppRoutes.appLock),
            ),
          ]),
          const SizedBox(height: 24),
          SettingsGroup(children: [
            SettingsTile(
              icon: Icons.info_outline,
              title: 'About',
              trailing: Icon(Icons.chevron_right, color: t.inkFaint),
              onTap: () => context.push(AppRoutes.about),
            ),
          ]),
        ],
      ),
    );
  }
}
