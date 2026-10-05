import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/utils/chunk_ids.dart';
import 'package:kuch_bhi/core/utils/sync_cursor.dart';

void main() {
  test('cursor boundary is inclusive — same-millisecond row not skipped',
      () {
    final c = DateTime.utc(2026, 10, 5, 12, 0, 0, 177);
    expect(incrementalFetchFilter(c),
        'created >= "2026-10-05 12:00:00.177Z"');
  });

  test('cursor only advances when the full delta was fetched', () {
    // Page-offset shifts during multi-page catch-up must not write a cursor
    // past rows that were skipped.
    expect(shouldAdvanceCursor(fetched: 40, totalAtStart: 40), isTrue);
    expect(shouldAdvanceCursor(fetched: 40, totalAtStart: 95), isFalse);
    expect(shouldAdvanceCursor(fetched: 12, totalAtStart: 12), isTrue);
  });

  test('chunkIds splits large id lists under the SQLite bind limit', () {
    expect(chunkIds([], 500), isEmpty);
    expect(chunkIds(['a'], 500), [['a']]);
    final ids = [for (var i = 0; i < 1001; i++) 'id$i'];
    final chunks = chunkIds(ids, 500);
    expect(chunks.length, 3);
    expect(chunks.first.length, 500);
    expect(chunks.last.length, 1);
    expect(chunks.expand((c) => c).length, 1001); // no id lost
  });
}
