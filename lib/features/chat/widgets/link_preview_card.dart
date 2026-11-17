import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/tokens.dart';
import 'expiry_badge.dart';

/// Shows a URL card below message text: the domain only. F13: the phone
/// never fetches the page, so a sender can't learn a reader's IP address
/// or make their phone send requests into its own network.
class LinkPreviewCard extends StatelessWidget {
  const LinkPreviewCard({super.key, required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(url);
    final domain = uri?.host.isNotEmpty == true ? uri!.host : url;

    return Semantics(
      container: true,
      button: true,
      label: 'Open link $domain',
      child: GestureDetector(
        onTap: () => launchUrl(
          uri ?? Uri.parse(url),
          mode: LaunchMode.externalApplication,
        ),
        // E6: one surface2 tile, width A2, no second border.
        child: Container(
          key: const ValueKey('link-preview-card'),
          margin: const EdgeInsets.only(top: 8),
          width: ChatBubbleGeometry.attachmentWidthOf(context),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: context.t.surface2,
            borderRadius: BorderRadius.circular(WarmPopTokens.radiusSm),
          ),
          child: Row(
            children: [
              Icon(Icons.link, color: context.t.inkSoft, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      domain,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.t.ink,
                        fontSize: 15,
                        height: 22 / 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      domain,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.t.inkSoft,
                        fontSize: 13,
                        height: 18 / 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
