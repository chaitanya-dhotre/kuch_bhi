import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/settings_tile.dart';
import '../providers/theme_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(themeModeProvider).valueOrNull ??
        AppThemeMode.system;
    final t = context.t;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // Marigold uppercase header per approved Batch 2 mockup (core
          // SectionHeader renders inkFaint, which Home relies on).
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 10),
            child: Text(
              'APPEARANCE',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: .08,
                color: t.accent,
              ),
            ),
          ),
          for (final mode in AppThemeMode.values) ...[
            RadioListTile<AppThemeMode>(
              value: mode,
              groupValue: current,
              onChanged: (v) {
                if (v != null) {
                  ref.read(themeControllerProvider).setTheme(v);
                }
              },
              secondary: Icon(mode.icon, color: t.inkSoft, size: 20),
              controlAffinity: ListTileControlAffinity.trailing,
              title: Text(mode.label,
                  style: const TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w600)),
              activeColor: t.accent,
              tileColor: t.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
          SettingsTile(
            icon: Icons.lock_outline,
            title: 'Backup PIN',
            subtitle: 'Change your key-backup PIN',
            trailing: Icon(Icons.chevron_right, color: t.inkFaint),
            onTap: () => context.push(AppRoutes.backupPinChange),
          ),
          SettingsTile(
            icon: Icons.info_outline,
            title: 'About',
            trailing: Icon(Icons.chevron_right, color: t.inkFaint),
            onTap: () => context.push(AppRoutes.about),
          ),
        ],
      ),
    );
  }
}
