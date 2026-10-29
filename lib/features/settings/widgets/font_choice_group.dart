import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/settings_tile.dart';
import '../providers/font_provider.dart';
import 'theme_mode_group.dart';

/// Registry R18: System default / Plus Jakarta Sans, each title drawn in
/// its own font (the row is its preview). Settings and the restore wait.
class FontChoiceGroup extends ConsumerWidget {
  const FontChoiceGroup({super.key});

  Future<void> _setFont(
      BuildContext context, WidgetRef ref, AppFont font) async {
    try {
      await ref.read(fontControllerProvider).setFont(font);
    } catch (e) {
      debugPrint('[Settings] setFont failed: $e');
      if (context.mounted) {
        showToast(context, "Couldn't change the font. Try again.",
            error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(fontFamilyProvider).valueOrNull ?? AppFont.system;
    // The platform's own family, so "System default" previews correctly
    // while the app runs in Jakarta.
    final systemFamily =
        Typography.material2021(platform: Theme.of(context).platform)
            .black
            .bodyMedium
            ?.fontFamily;
    return SettingsGroup(children: [
      for (final font in AppFont.values)
        Semantics(
          selected: font == current,
          inMutuallyExclusiveGroup: true,
          child: DefaultTextStyle.merge(
            style: TextStyle(fontFamily: font.fontFamily ?? systemFamily),
            child: SettingsTile(
              icon: Icons.text_fields,
              title: font.label,
              trailing: CheckDisc(selected: font == current),
              onTap: () => _setFont(context, ref, font),
            ),
          ),
        ),
    ]);
  }
}
