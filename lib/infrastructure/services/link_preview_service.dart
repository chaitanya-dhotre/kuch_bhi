import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Link preview metadata parsed from a page's `<title>` /
/// `<meta name="description">`.
class LinkPreview {
  const LinkPreview({required this.title, this.description, required this.url});
  final String title;
  final String? description;
  final String url;
}

/// Dio fetch + HTML meta parse.
///
/// Logic moved verbatim from `link_preview_card.dart` (Task 10, guard 5:
/// structure move, no behavior edits).
class LinkPreviewService {
  Future<LinkPreview?> fetch(String url) async {
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
      return LinkPreview(title: title, description: desc, url: url);
    } catch (_) {
      return null;
    }
  }
}

/// Brief interface: `linkPreviewServiceProvider(url) → Future<LinkPreview?>`.
final linkPreviewServiceProvider =
    FutureProvider.family<LinkPreview?, String>((ref, url) async {
  return ref.watch(_linkPreviewServiceInstanceProvider).fetch(url);
});

final _linkPreviewServiceInstanceProvider =
    Provider<LinkPreviewService>((ref) => LinkPreviewService());
