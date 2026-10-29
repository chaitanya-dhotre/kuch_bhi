import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/settings_tile.dart';
import '../providers/notification_status_provider.dart';

/// Registry R17: the Notifications status row in its own R10b group
/// (Settings, restore wait). Re-reads the status on resume.
class NotificationsStatusRow extends ConsumerStatefulWidget {
  const NotificationsStatusRow({super.key});

  @override
  ConsumerState<NotificationsStatusRow> createState() =>
      _NotificationsStatusRowState();
}

class _NotificationsStatusRowState
    extends ConsumerState<NotificationsStatusRow> {
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
    final status = ref.watch(notificationsEnabledProvider);
    // D2: a failed re-read shows no subtitle, never the stale previous value.
    final enabled = status.hasError ? null : status.valueOrNull;
    return SettingsGroup(children: [
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
    ]);
  }
}
