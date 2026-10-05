/// PB filter for the incremental message fetch: only rows strictly newer
/// than [cursor]. Null cursor (cold/empty cache) → null (caller fetches the
/// latest page only, like the old behaviour).
///
/// [cursor] always originates from a server `created` string — never from
/// the device clock — so skew between devices cannot skip messages.
String? incrementalFetchFilter(DateTime? cursor) {
  if (cursor == null) return null;
  final t = cursor.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  final stamp =
      '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.'
      '${t.millisecond.toString().padLeft(3, '0')}Z';
  return 'created > "$stamp"';
}

/// A full page means there may be more delta rows on the next page.
bool shouldFetchNextPage({required int pageItems, required int perPage}) =>
    pageItems >= perPage;
