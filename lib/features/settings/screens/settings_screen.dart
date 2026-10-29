import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/page_app_bar.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/settings_tile.dart';
import '../widgets/font_choice_group.dart';
import '../widgets/notifications_status_row.dart';
import '../widgets/theme_mode_group.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
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
