import 'dart:math' as math;
import 'dart:ui';

/// 12.5 E2: the collage's layout, pure and deterministic.
///
/// Walked in pick order over each item's aspect (width / height):
/// * landscape (aspect >= 1.2): its own full-width row, height = width /
///   aspect, cropped to at most 2:1;
/// * portrait or square: paired with the next item when that one is also
///   portrait or square, side by side, widths in proportion to their
///   aspects, one shared height;
/// * a lone portrait: full width, cropped to at most 4:5.
///
/// Unknown or unusable sizes are treated as 1.0. [gap] separates every row
/// and the two tiles of a pair. The returned rectangles are in index order,
/// top-to-bottom and left-to-right, and never overlap.
List<Rect> albumLayout(
  List<double> aspects,
  double width, {
  double gap = 2,
}) {
  final out = <Rect>[];
  var y = 0.0;
  var i = 0;
  while (i < aspects.length) {
    final a = _aspect(aspects[i]);
    if (a >= 1.2) {
      final h = width / math.min(a, 2.0);
      out.add(Rect.fromLTWH(0, y, width, h));
      y += h + gap;
      i++;
      continue;
    }
    final next = i + 1 < aspects.length ? _aspect(aspects[i + 1]) : null;
    if (next != null && next < 1.2) {
      final h = (width - gap) / (a + next);
      final first = h * a;
      out.add(Rect.fromLTWH(0, y, first, h));
      out.add(Rect.fromLTWH(first + gap, y, width - first - gap, h));
      y += h + gap;
      i += 2;
      continue;
    }
    // A lone portrait/square: at most 4:5 (aspect >= 0.8).
    final h = width / math.max(a, 0.8);
    out.add(Rect.fromLTWH(0, y, width, h));
    y += h + gap;
    i++;
  }
  return out;
}

double _aspect(double value) =>
    value.isFinite && value > 0 ? value : 1.0;
