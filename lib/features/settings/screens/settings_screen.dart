import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/page_app_bar.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/settings_tile.dart';
import '../providers/notification_status_provider.dart';
import '../providers/theme_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // D4: coming back from system settings shows the new status.
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(notificationsEnabledProvider),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _setTheme(AppThemeMode mode) async {
    try {
      await ref.read(themeControllerProvider).setTheme(mode);
    } catch (e) {
      debugPrint('[Settings] setTheme failed: $e');
      if (mounted) {
        showToast(context, "Couldn't change the theme. Try again.",
            error: true);
      }
    }
  }

  Future<void> _openSystemSettings() async {
    var opened = false;
    try {
      opened = await ref.read(openSystemSettingsProvider)();
    } catch (e) {
      debugPrint('[Settings] openAppSettings failed: $e');
    }
    if (!opened && mounted) {
      showToast(context, "Couldn't open system settings.", error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final current =
        ref.watch(themeModeProvider).valueOrNull ?? AppThemeMode.system;
    final status = ref.watch(notificationsEnabledProvider);
    // D2: a failed re-read shows no subtitle, never the stale previous value.
    final enabled = status.hasError ? null : status.valueOrNull;

    return Scaffold(
      backgroundColor: t.bg,
      appBar: pageAppBar(context, 'Settings'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        children: [
          const SectionHeader('Appearance'),
          SettingsGroup(children: [
            for (final mode in AppThemeMode.values)
              Semantics(
                selected: mode == current,
                inMutuallyExclusiveGroup: true,
                child: SettingsTile(
                  icon: mode.icon,
                  title: mode.label,
                  trailing: _Check(selected: mode == current),
                  onTap: () => _setTheme(mode),
                ),
              ),
          ]),
          const SectionHeader('Notifications'),
          SettingsGroup(children: [
            Semantics(
              hint: 'Opens system settings',
              child: SettingsTile(
                icon: enabled == false
                    ? Icons.notifications_off_outlined
                    : Icons.notifications_none,
                title: 'Notifications',
                subtitle: switch (enabled) {
                  true => 'On',
                  false => 'Off. Turn them on in system settings.',
                  null => null,
                },
                trailing: Icon(Icons.open_in_new, size: 20, color: t.inkSoft),
                onTap: _openSystemSettings,
              ),
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

/// C1: selected = accent fill + onAccent tick; otherwise a 2px line ring.
class _Check extends StatelessWidget {
  const _Check({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return ExcludeSemantics(
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? t.accent : null,
          border: selected ? null : Border.all(color: t.line, width: 2),
        ),
        child: selected ? Icon(Icons.check, size: 16, color: t.onAccent) : null,
      ),
    );
  }
}
