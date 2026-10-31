import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../core/network/pocketbase_client.dart';

/// `RecordModel` alias for feature screens: they must not import
/// `package:pocketbase/` directly (Task 11 gate 13) but keep the exact
/// static type (typedef is transparent — zero runtime change).
typedef MediaRecord = RecordModel;

/// message_media list query.
///
/// Logic moved verbatim from `media_docs_screen.dart` (Task 10, guard 5:
/// structure move, no behavior edits).
class MediaGalleryService {
  MediaGalleryService(this._client);

  final PocketBaseClient _client;

  Future<List<RecordModel>> fetchMediaPage(
    ({String conversationId, String mediaType}) args,
  ) async {
    final pb = _client.pb;
    final result = await pb.collection('message_media').getList(
      filter:  'conversation_id="${args.conversationId}"'
               '&&media_type="${args.mediaType}"',
      sort:    '-created',
      perPage: 100,
    ).timeout(const Duration(seconds: 8));
    return result.items;
  }
}

final mediaGalleryServiceProvider = Provider<MediaGalleryService>((ref) {
  return MediaGalleryService(ref.watch(pocketbaseClientProvider));
});

/// Moved from `media_docs_screen.dart` (`_mediaPageProvider` — renamed
/// public so the screen can watch it without a `package:pocketbase/` import).
final mediaPageProvider = FutureProvider.autoDispose
    .family<List<RecordModel>, ({String conversationId, String mediaType})>(
  (ref, args) async {
    return ref.read(mediaGalleryServiceProvider).fetchMediaPage(args);
  },
);
