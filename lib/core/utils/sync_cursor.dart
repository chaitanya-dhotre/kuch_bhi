/// PB filter for the incremental message fetch: rows at-or-newer than
/// [cursor]. Null cursor (cold/empty cache) → null (caller fetches the
/// latest page only, like the old behaviour).
///
/// INCLUSIVE (>=, review I2): a row inserted in the same millisecond as the
/// cursor must be re-fetched, not skipped forever — upserts are idempotent,
/// so re-fetching the boundary row is free. [cursor] always originates from
/// a server `created` string — never from the device clock — so skew
/// between devices cannot skip messages.
String? incrementalFetchFilter(DateTime? cursor) {
  if (cursor == null) return null;
  final t = cursor.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  final stamp =
      '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.'
      '${t.millisecond.toString().padLeft(3, '0')}Z';
  return 'created >= "$stamp"';
}

/// A full page means there may be more delta rows on the next page.
bool shouldFetchNextPage({required int pageItems, required int perPage}) =>
    pageItems >= perPage;

/// Advance the cursor only when the ENTIRE delta present at fetch start was
/// fetched. Multi-page catch-up uses offsets; rows inserted between page
/// requests shift those offsets, so a partial catch-up must leave the
/// cursor alone (review I2) — the next fetch retries the same window.
bool shouldAdvanceCursor({required int fetched, required int totalAtStart}) =>
    fetched >= totalAtStart;
