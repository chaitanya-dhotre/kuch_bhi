import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/tokens.dart';
import '../../../infrastructure/services/link_preview_service.dart';

/// Shows a URL preview card below message text.
class LinkPreviewCard extends ConsumerWidget {
  const LinkPreviewCard({super.key, required this.url});
  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metaAsync = ref.watch(linkPreviewServiceProvider(url));

    return metaAsync.when(
      loading: () => _buildCard(context, null),
      error: (_, __) => _buildCard(context, null),
      data: (meta) => _buildCard(context, meta),
    );
  }

  Widget _buildCard(BuildContext context, LinkPreview? meta) {
    final uri = Uri.tryParse(url);
    final domain = uri?.host.isNotEmpty == true ? uri!.host : url;
    final title = meta?.title.trim().isNotEmpty == true ? meta!.title : domain;

    return Semantics(
      container: true,
      button: true,
      label: 'Open link $domain',
      child: GestureDetector(
        onTap: () => launchUrl(
          uri ?? Uri.parse(url),
          mode: LaunchMode.externalApplication,
        ),
        child: Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: context.t.surface,
            border: Border.all(color: context.t.line),
            borderRadius: BorderRadius.circular(WarmPopTokens.radiusSm),
          ),
          child: Row(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: context.t.surface2,
                  borderRadius: BorderRadius.circular(WarmPopTokens.radiusSm),
                ),
                child: Icon(Icons.link, color: context.t.inkFaint, size: 24),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.t.ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      domain,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.t.info,
                        fontSize: 10.5,
                        decoration: TextDecoration.underline,
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
