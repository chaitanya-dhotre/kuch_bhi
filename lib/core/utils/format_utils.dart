/// Shared text formatters (dead-code audit §3.3, §3.4). One `m:ss` and one
/// byte-size formatter instead of per-file copies.
library;

/// `m:ss` from a count of seconds — recorder timers, media rows, players.
/// Durations pass `d.inSeconds`; inputs are always ≥ 0.
String formatMmSs(int seconds) =>
    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

/// Byte-size label for a raw (int or numeric-string) size. The KB/MB lines
/// agree everywhere; the sub-1KB unit is the one deliberate variant:
/// document bubbles print `123 B`, the docs screen prints `123B`.
String formatFileSize(dynamic raw, {required bool bytesUnitSpaced}) {
  final bytes = raw is int ? raw : int.tryParse(raw?.toString() ?? '') ?? 0;
  if (bytes <= 0) return '';
  if (bytes < 1024) return bytesUnitSpaced ? '$bytes B' : '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
