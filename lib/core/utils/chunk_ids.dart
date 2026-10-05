/// Splits [ids] into batches of at most [size] for SQL `IN (...)` clauses —
/// older Android SQLite caps bound variables at 999, and a long-offline
/// catch-up can exceed that (review I3: one oversized query = permanent
/// fetch failure for that conversation).
List<List<String>> chunkIds(List<String> ids, int size) {
  final out = <List<String>>[];
  for (var i = 0; i < ids.length; i += size) {
    out.add(ids.sublist(i, i + size > ids.length ? ids.length : i + size));
  }
  return out;
}
