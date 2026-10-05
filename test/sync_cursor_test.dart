import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/utils/sync_cursor.dart';

void main() {
  test('null cursor (cold cache) → no incremental filter', () {
    expect(incrementalFetchFilter(null), isNull);
  });

  test('cursor → strictly-newer server filter, UTC ISO verbatim', () {
    final c = DateTime.utc(2026, 10, 4, 17, 58, 30, 177);
    expect(incrementalFetchFilter(c),
        'created > "2026-10-04 17:58:30.177Z"');
  });

  test('server-timestamp strings pass through unmodified (no clock skew)', () {
    // Cursor parsed FROM a server 'created' string must re-serialize to the
    // same instant — devices never contribute their own clock here.
    final server = DateTime.tryParse('2026-10-04 17:58:30.177Z')!;
    expect(incrementalFetchFilter(server.toUtc()),
        'created > "2026-10-04 17:58:30.177Z"');
  });

  test('full page means maybe more delta → fetch next page', () {
    expect(shouldFetchNextPage(pageItems: 40, perPage: 40), isTrue);
    expect(shouldFetchNextPage(pageItems: 12, perPage: 40), isFalse);
  });
}
