import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/settings_tile.dart';
import '../providers/theme_provider.dart';

/// Registry R16: the four theme rows (Settings, restore wait). The R9
/// header stays with the caller.
class ThemeModeGroup extends ConsumerWidget {
  const ThemeModeGroup({super.key});

  Future<void> _setTheme(
      BuildContext context, WidgetRef ref, AppThemeMode mode) async {
    try {
      await ref.read(themeControllerProvider).setTheme(mode);
    } catch (e) {
      debugPrint('[Settings] setTheme failed: $e');
      if (context.mounted) {
        showToast(context, "Couldn't change the theme. Try again.",
            error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current =
        ref.watch(themeModeProvider).valueOrNull ?? AppThemeMode.system;
    return SettingsGroup(children: [
      for (final mode in AppThemeMode.values)
        Semantics(
          selected: mode == current,
          inMutuallyExclusiveGroup: true,
          child: SettingsTile(
            icon: mode.icon,
            title: mode.label,
            trailing: CheckDisc(selected: mode == current),
            onTap: () => _setTheme(context, ref, mode),
          ),
        ),
    ]);
  }
}

/// C1: selected = accent fill + onAccent tick; otherwise a 2px line ring.
class CheckDisc extends StatelessWidget {
  const CheckDisc({super.key, required this.selected});
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
