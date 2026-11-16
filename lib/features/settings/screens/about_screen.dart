import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/page_app_bar.dart';
import '../../../core/widgets/settings_tile.dart';
import '../../../core/widgets/skeleton.dart';
import '../../mascot/capy.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  // E2: created once, not on every build.
  late final Future<PackageInfo> _info = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: pageAppBar(context, 'About'),
      body: FutureBuilder<PackageInfo>(
        future: _info,
        builder: (context, snapshot) {
          final info = snapshot.data;
          final version =
              info == null ? null : '${info.version} (${info.buildNumber})';
          final valueStyle = TextStyle(fontSize: 15, color: t.inkSoft);
          final Widget versionValue = snapshot.hasError
              ? Text('Unknown', style: valueStyle)
              : version == null
                  ? const SkeletonGroup(child: Skeleton(width: 64, height: 14))
                  : Text(version,
                      style: valueStyle, textAlign: TextAlign.end);

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 20, 12, 24),
            children: [
              // K4 S1: still; a tap pets it (squish, blush, light haptic).
              const Center(child: Capy(view: CapyView.sit, size: 96)),
              const SizedBox(height: 16),
              Text(
                AppConstants.appName,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  height: 30 / 24,
                  fontWeight: FontWeight.w700,
                  color: t.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Private, end-to-end encrypted messaging',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, height: 22 / 15, color: t.inkSoft),
              ),
              const SizedBox(height: 20),
              SettingsGroup(children: [
                SettingsTile(
                  icon: Icons.tag,
                  title: 'Version',
                  // G3: flexible, so 200% text wraps instead of overflowing;
                  // Align pins it to the row end (a bare Flexible sat mid-row).
                  trailing: Flexible(
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: versionValue,
                    ),
                  ),
                ),
                SettingsTile(
                  icon: Icons.description_outlined,
                  title: 'Open-source licences',
                  trailing: Icon(Icons.chevron_right, color: t.inkFaint),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: AppConstants.appName,
                    applicationVersion: version,
                  ),
                ),
              ]),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                child: Text(
                  'Your messages are encrypted end-to-end. '
                  'Only you and the people you talk to can read them.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13, height: 18 / 13, color: t.inkSoft),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
