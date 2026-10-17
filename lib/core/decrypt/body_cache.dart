/// In-memory decrypted-body memcache (spec §8) — LRU by message id,
/// bounded, cleared on backgrounding and logout (§3/§11).
///
/// Plaintext lives ONLY here (plus transient provider state) — never at
/// rest: DecryptPass puts decrypted bodies here and never writes them
/// back to Drift (the `decrypted_body` column is dropped in Task 9).
/// A cleared cache is safe: `ready` rows re-decrypt on the next provider
/// read (spec §8).
class BodyCache {
  BodyCache({this.maxEntries = 500});

  /// Spec §8: bounded LRU (500 messages).
  final int maxEntries;

  /// Insertion-ordered map: first key = least-recently used.
  final _entries = <String, String>{};

  /// Cache hit → re-inserts at the tail (most-recently used) and returns
  /// the body; miss → null.
  String? get(String id) {
    final body = _entries.remove(id);
    if (body != null) _entries[id] = body;
    return body;
  }

  void put(String id, String body) {
    _entries.remove(id);
    _entries[id] = body;
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first); // evict least-recently used
    }
  }

  /// B/C3 (review #72): bumped on every clear(). DecryptPass captures it
  /// at schedule time and refuses to put when it moved — an in-flight
  /// decrypt completing after a paused purge must not repopulate the
  /// cache the purge emptied (§3: nothing decrypted survives
  /// backgrounding).
  int _generation = 0;
  int get generation => _generation;

  void clear() {
    _entries.clear();
    _generation++;
  }

  int get length => _entries.length;
}

/// App-wide cache — shared across providers; cleared from `app.dart`
/// (backgrounding) and the repo's session-epoch path (logout wipe).
final bodyCache = BodyCache();
