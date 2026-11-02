// Share into the app (12.1 C1–C7): what was shared, how it is split, and the
// one-line summary. Pure: no channel, no files.
import '../../core/constants/app_constants.dart';

enum SharedKind { photo, video, document }

/// One shared item as `takeShare` reports it: a link, never a copy.
class SharedItem {
  const SharedItem({
    required this.uri,
    required this.mime,
    required this.name,
    this.size = -1,
  });

  factory SharedItem.fromMap(Map<Object?, Object?> m) => SharedItem(
    uri: m['uri'] as String,
    mime: (m['mime'] as String?) ?? 'application/octet-stream',
    name: (m['name'] as String?) ?? 'shared',
    size: (m['size'] as num?)?.toInt() ?? -1,
  );

  final String uri;
  final String mime;
  final String name;

  /// Bytes, or -1 when the sharing app didn't say.
  final int size;

  SharedKind get kind => sharedKindOf(mime, name);
}

class ShareInPayload {
  const ShareInPayload({this.items = const [], this.text});

  final List<SharedItem> items;
  final String? text;

  bool get hasText => text != null && text!.trim().isNotEmpty;
}

/// A share after the 20 cap and the known-size check (C2, C3).
class SharePlan {
  const SharePlan({
    required this.items,
    required this.text,
    this.overCap = false,
    this.tooBig = 0,
  });

  final List<SharedItem> items;
  final String? text;
  final bool overCap;
  final int tooBig;

  bool get isEmpty => items.isEmpty && (text == null || text!.trim().isEmpty);
}

/// A share copied into `share_in/` and handed to one chat (D10).
class ReadyShare {
  const ReadyShare({required this.chatName, this.files = const [], this.text});

  /// For the documents confirm, **Send to Asha?** (E3).
  final String chatName;
  final List<({String path, SharedKind kind, String mime})> files;
  final String? text;
}

const _videoExts = {
  'mp4', 'mov', 'm4v', 'avi', 'mkv', 'webm', '3gp', 'mpeg', 'mpg', //
};
const _photoExts = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif'};

/// C1: photos and videos by MIME, then by extension; everything else
/// (SVG, PDF, audio, archives, contacts) goes as a document (decision 20).
SharedKind sharedKindOf(String mime, String name) {
  final m = mime.toLowerCase();
  if (m == 'image/svg+xml') return SharedKind.document;
  if (m.startsWith('image/')) return SharedKind.photo;
  if (m.startsWith('video/')) return SharedKind.video;
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  final known = m.isNotEmpty && m != 'application/octet-stream' && m != '*/*';
  if (known) return SharedKind.document;
  if (_videoExts.contains(ext)) return SharedKind.video;
  if (_photoExts.contains(ext)) return SharedKind.photo;
  return SharedKind.document;
}

int get shareMaxBytes => AppConstants.maxFileSizeMb * 1024 * 1024;

/// C2 then C3: the first 20 in shared order, then known sizes over 100 MB
/// out. An unknown size is left to the copy's byte limit.
SharePlan planShare(ShareInPayload share) {
  final capped = share.items.take(AppConstants.maxAlbumItems).toList();
  final kept = [
    for (final i in capped)
      if (i.size <= shareMaxBytes) i,
  ];
  return SharePlan(
    items: kept,
    text: share.text,
    overCap: share.items.length > AppConstants.maxAlbumItems,
    tooBig: capped.length - kept.length,
  );
}

/// C3 / D8 wording for items left out.
String tooBigLeftOut(int n) => n == 1
    ? '1 item is over 100 MB and was left out.'
    : '$n items are over 100 MB and were left out.';

String unreadableLeftOut(int n) => n == 1
    ? "1 item couldn't be opened and was left out."
    : "$n items couldn't be opened and were left out.";

const kShareUnreadable = "Couldn't open what was shared.";

/// C7: the picker's summary line. Text alongside items is not counted.
String shareSummary(List<SharedItem> items, String? text) {
  if (items.isEmpty) {
    final t = text?.trim() ?? '';
    return RegExp(r'^https?://\S+$').hasMatch(t) ? 'Link' : 'Text';
  }
  String n(int c, String one) => c == 1 ? '1 $one' : '$c ${one}s';
  final photos = items.where((i) => i.kind == SharedKind.photo).length;
  final videos = items.where((i) => i.kind == SharedKind.video).length;
  final docs = items.length - photos - videos;
  if (docs == items.length) return n(docs, 'file');
  if (docs > 0) return n(items.length, 'item');
  // Same counting as albumLabel (chat_run_grouping.dart).
  if (videos == 0) return n(photos, 'photo');
  if (photos == 0) return n(videos, 'video');
  return '${n(photos, 'photo')} and ${n(videos, 'video')}';
}
