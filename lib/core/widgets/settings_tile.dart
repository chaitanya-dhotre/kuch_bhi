import 'package:flutter/material.dart';
import '../../core/theme/tokens.dart';

class SettingsTile extends StatelessWidget {
  const SettingsTile(
      {super.key,
      required this.icon,
      required this.title,
      this.subtitle,
      this.onTap,
      this.trailing});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: t.surface2,
                  borderRadius: BorderRadius.circular(WarmPopTokens.radiusSm),
                ),
                child: Icon(icon, size: 19, color: t.ink),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    if (subtitle != null)
                      Text(subtitle!,
                          style: TextStyle(fontSize: 12.5, color: t.inkSoft)),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}
