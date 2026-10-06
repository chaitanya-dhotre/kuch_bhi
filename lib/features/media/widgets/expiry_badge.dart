import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/utils/media_utils.dart';

/// Overlays an orange "Expires in Xd" pill badge on the top-right corner
/// of a media thumbnail. Only renders when the expiry is within 7 days
/// and not yet expired.
class ExpiryBadge extends StatelessWidget {
  const ExpiryBadge({super.key, required this.expiresAt});

  final DateTime expiresAt;

  @override
  Widget build(BuildContext context) {
    final text = expiryBadgeText(expiresAt);
    if (text == null) return const SizedBox.shrink();
    return Positioned(
      top:   6,
      right: 6,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color:        context.t.accent.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          text,
          style: TextStyle(
            color:      context.t.onAccent,
            fontSize:   10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Full expired overlay — grey rounded rectangle with icon + text.
/// Sized to fill its parent via LayoutBuilder or given explicit size.
class ExpiredMediaPlaceholder extends StatelessWidget {
  const ExpiredMediaPlaceholder({super.key, this.width, this.height});

  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width:  width,
      height: height,
      decoration: BoxDecoration(
        color:        Colors.grey.shade300,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize:      MainAxisSize.min,
        children: [
          Icon(Icons.timer_off_outlined, color: Colors.grey, size: 28),
          SizedBox(height: 6),
          Text(
            'Media expired',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
