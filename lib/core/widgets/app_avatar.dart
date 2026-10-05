import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/theme/tokens.dart';

class AppAvatar extends StatelessWidget {
  const AppAvatar({super.key, this.url, required this.initials, this.radius = 20});
  final String? url;
  final String initials;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return CircleAvatar(
      radius: radius,
      backgroundColor: t.surface2,
      backgroundImage: url != null ? CachedNetworkImageProvider(url!) : null,
      child: url != null
          ? null
          : Text(
              initials,
              style: TextStyle(
                color: t.inkSoft,
                fontWeight: FontWeight.w700,
                fontSize: radius * 0.75,
              ),
            ),
    );
  }
}
