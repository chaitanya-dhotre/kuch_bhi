import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Registry R21: the camera disc that marks an avatar as pickable.
///
/// One 32px accent disc with a 2px page-colour ring and a 16px camera glyph.
/// The four call sites (Google onboarding, Edit profile, New group, Group
/// info) used to hand-build this; the glyph now agrees everywhere — Group
/// info used `Icons.camera_alt`, the other three `camera_alt_outlined`
/// (registry decision D3: promote, one badge).
///
/// The badge is only the disc: each caller keeps its own `Positioned` and
/// its own outer `Semantics`/`GestureDetector`, so size, ring and position
/// stay where the page put them.
class PhotoPickerBadge extends StatelessWidget {
  const PhotoPickerBadge({super.key, required this.onTap});

  /// What the disc does when tapped. `null` leaves it inert — the page
  /// uses that for the busy / read-only states.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: t.accent,
          shape: BoxShape.circle,
          border: Border.all(color: t.bg, width: 2),
        ),
        child: Icon(Icons.camera_alt_outlined, size: 16, color: t.onAccent),
      ),
    );
  }
}
