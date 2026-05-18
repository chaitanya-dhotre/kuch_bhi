import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/emoji_utils.dart';

final _linkPreviewProvider =
  FutureProvider.family<_LinkMeta?, String>((ref, url) async {
  try {
    final resp = await Dio().get<String>(
      url,
      options: Options(
        responseType:    ResponseType.plain,
        sendTimeout:     const Duration(seconds: 5),
        receiveTimeout:  const Duration(seconds: 5),
        headers: {'User-Agent': 'Mozilla/5.0'},
      ),
    );
    final html  = resp.data ?? '';
    String? title = RegExp(
            r'<title[^>]*>([^<]+)</title>',
            caseSensitive: false)
        .firstMatch(html)
        ?.group(1)
        ?.trim();
    String? desc = RegExp(
          r'''<meta[^>]+name=["']description["'][^>]+content=["'](.*?)["']''',
            caseSensitive: false)
        .firstMatch(html)
        ?.group(1)
        ?.trim();
    if (title == null) return null;
    return _LinkMeta(title: title, description: desc, url: url);
  } catch (_) {
    return null;
  }
});

class _LinkMeta {
  const _LinkMeta({required this.title, this.description, required this.url});
  final String  title;
  final String? description;
  final String  url;
}

/// Shows a URL preview card below message text.
class LinkPreviewCard extends ConsumerWidget {
  const LinkPreviewCard({super.key, required this.url});
  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metaAsync = ref.watch(_linkPreviewProvider(url));

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
                left: BorderSide(color: AppColors.primary, width: 3),
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
                    color:    AppColors.primary,
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
