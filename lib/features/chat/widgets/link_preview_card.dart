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
      loading: () => const SizedBox(height: 4),
      error:   (_, __) => const SizedBox.shrink(),
      data: (meta) {
        if (meta == null) return const SizedBox.shrink();
        return GestureDetector(
          onTap: () => launchUrl(Uri.parse(url),
              mode: LaunchMode.externalApplication),
          child: Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border(
                left: BorderSide(color: context.t.accent, width: 3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meta.title,
                  maxLines:  2,
                  overflow:  TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize:   13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (meta.description != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    meta.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  Uri.parse(url).host,
                  style: TextStyle(
                    fontSize: 10,
                    color:    context.t.accent,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
