/// Albums 12.5 E2: the collage layout, pure and deterministic — landscape
/// full rows (≤2:1), portrait/square pairs, a lone portrait ≤4:5, with a
/// gap between every row and the tiles of a pair.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/features/media/album_layout.dart';

void main() {
  test('two landscapes: full-width rows, height from aspect, capped 2:1',
      () {
    final out = albumLayout([2.0, 1.5], 300);
    expect(out.length, 2);
    // 300 / min(2.0, 2.0) = 150; then the 1.5 row is 300 / 1.5 = 200.
    expect(out[0], const Rect.fromLTWH(0, 0, 300, 150));
    expect(out[1], const Rect.fromLTWH(0, 152, 300, 200));
    expect(out[1].bottom, 352);
  });

  test('a 3:1 landscape is cropped to at most 2:1', () {
    final out = albumLayout([3.0], 300);
    expect(out.single.height, 150, reason: '300 / min(3, 2)');
    expect(out.single.width, 300);
  });

  test('portrait pair: side by side, widths in proportion to aspect', () {
    final out = albumLayout([0.5, 1.0], 100);
    expect(out, hasLength(2));
    final h = (100 - 2) / (0.5 + 1.0); // 65.33…
    expect(out[0].top, 0);
    expect(out[0].height, closeTo(h, 1e-6));
    expect(out[0].width, closeTo(h * 0.5, 1e-6));
    expect(out[1].left, closeTo(out[0].width + 2, 1e-6));
    expect(out[1].width, closeTo(100 - out[0].width - 2, 1e-6));
    expect(out[1].height, closeTo(h, 1e-6));
  });

  test('a lone portrait is at most 4:5', () {
    final out = albumLayout([0.4], 100);
    expect(out.single.height, closeTo(100 / 0.8, 1e-6),
        reason: 'width / max(0.4, 0.8)');
  });

  test('a lone square fills the row', () {
    final out = albumLayout([1.0], 100);
    expect(out.single, const Rect.fromLTWH(0, 0, 100, 100));
  });

  test('unknown / zero / NaN / infinite aspects are treated as 1.0', () {
    final out = albumLayout([0, double.nan, double.infinity], 100);
    expect(out, hasLength(3));
    // All three are 1.0 → first and second pair up, the third goes alone.
    expect(out[0].width, closeTo(49, 1e-6));
    expect(out[1].width, closeTo(49, 1e-6));
    expect(out[2].width, 100);
    expect(out[2].height, 100);
    expect(out[2].top, closeTo(out[0].height + 2, 1e-6),
        reason: 'pair row + gap, then the lone row');
  });

  test('rows never overlap and never leave the width; order is pick order',
      () {
    final aspects = [2.0, 0.75, 0.5, 1.0, 1.5, 0.9, 0.4];
    final out = albumLayout(aspects, 240, gap: 2);
    expect(out, hasLength(aspects.length));
    for (final r in out) {
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.right, lessThanOrEqualTo(240 + 1e-6));
    }
    // Same-row pairs share the same top/bottom; consecutive items may be in the
    // same row. Check that no item overlaps any other by verifying all rects
    // are non-overlapping pairwise.
    for (var i = 0; i < out.length; i++) {
      for (var j = i + 1; j < out.length; j++) {
        expect(out[i].overlaps(out[j]), isFalse,
            reason: 'items $i and $j must not overlap');
      }
    }
  });

  test('empty input → empty output', () {
    expect(albumLayout([], 300), isEmpty);
  });

  test('a mixed list lays out top-to-bottom in index order', () {
    final out = albumLayout([1.5, 0.5, 0.5], 300);
    expect(out.length, 3);
    // Row 0: landscape 300 × 200; row 1+2: the portrait pair underneath.
    expect(out[0].height, 200);
    expect(out[1].top, out[0].bottom + 2);
    expect(out[2].top, out[1].top);
  });
}