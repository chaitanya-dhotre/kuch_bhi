import '../../domain/entities/message.dart';

/// Run flags for a message in the chat list.
///
/// The input list is newest-first, matching the reversed chat list. Therefore
/// [runStart] marks the oldest/first bubble in a visual run and [runEnd]
/// marks the newest/last bubble in that run.
class ChatRunFlags {
  const ChatRunFlags({required this.runStart, required this.runEnd});

  final bool runStart;
  final bool runEnd;
}

/// Computes sender runs without crossing date separators.
///
/// System messages intentionally never join a run. A run may contain messages
/// from the same sender only when adjacent timestamps are at most two minutes
/// apart. The function is pure so grouping remains testable independently of
/// the list widget and database stream.
List<ChatRunFlags> computeChatRunFlags(List<Message> messages) {
  return [
    for (var i = 0; i < messages.length; i++)
      ChatRunFlags(
        runStart:
            i + 1 >= messages.length || !_canJoin(messages[i], messages[i + 1]),
        runEnd: i == 0 || !_canJoin(messages[i - 1], messages[i]),
      ),
  ];
}

/// One entry of the chat list: a single message, or an album (12.5).
/// [anchor] is the album's earliest row, which sets its place and time.
class ChatUnit {
  const ChatUnit(this.anchor, this.rows);

  final Message anchor;

  /// In album order; one row = a normal bubble (A3).
  final List<Message> rows;

  bool get isAlbum => rows.length > 1;
}

/// Albums (12.5 A2–A4): rows with the same `albumId` and sender collapse
/// into one unit at the earliest row's position, so a late row joins even
/// with other messages in between. Input and output are newest-first.
List<ChatUnit> groupChatUnits(List<Message> messages) {
  final albums = <(String, String), List<Message>>{};
  for (final m in messages) {
    final a = m.albumId;
    if (a != null) (albums[(m.senderId, a)] ??= []).add(m);
  }
  return [
    for (final m in messages)
      if (m.albumId == null)
        ChatUnit(m, [m])
      // The earliest row is the last one seen newest-first.
      else if (identical(albums[(m.senderId, m.albumId!)]!.last, m))
        ChatUnit(m, albums[(m.senderId, m.albumId!)]!..sort(_albumOrder)),
  ];
}

/// A6: whether a list entry holds [target] — any row of an album counts.
/// Matches on localId OR serverId: starred-screen messages are rebuilt from
/// the server and their localId may actually be the server id.
bool unitHolds(Iterable<Message> rows, Message target) => rows.any(
  (r) =>
      r.localId == target.localId ||
      (target.serverId != null && r.serverId == target.serverId) ||
      r.serverId == target.localId,
);

/// 12.5 F3: what an album holds, for quotes, banners, previews and cards.
String albumLabel(Iterable<Message> rows) {
  final photos = rows.where((m) => m.type == 'image').length;
  final videos = rows.where((m) => m.type == 'video').length;
  String n(int c, String one) => c == 1 ? '1 $one' : '$c ${one}s';
  if (videos == 0) return n(photos, 'photo');
  if (photos == 0) return n(videos, 'video');
  return '${n(photos, 'photo')} and ${n(videos, 'video')}';
}

int _albumOrder(Message a, Message b) {
  final i = (a.albumIndex ?? 0).compareTo(b.albumIndex ?? 0);
  if (i != 0) return i;
  final t = a.createdAt.compareTo(b.createdAt);
  return t != 0 ? t : a.localId.compareTo(b.localId);
}

bool _canJoin(Message newer, Message older) {
  if (newer.type == 'system' || older.type == 'system') return false;
  if (newer.senderId != older.senderId) return false;
  if (!_sameDay(newer.createdAt, older.createdAt)) return false;
  return newer.createdAt.difference(older.createdAt).abs() <=
      const Duration(minutes: 2);
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// What the chat's empty state must say (backlog §170 fix b).
enum ChatEmptyKind { brandNew, undecryptable }

/// An empty list means one of two different things, and they read very
/// differently to the person looking at them. Pure so the widget stays a
/// renderer and the decision is testable without pumping it.
///
/// Rows whose body cannot be decrypted are hidden by design (spec D1 —
/// ciphertext must never reach a bubble), so a conversation whose history is
/// entirely unrecoverable yields the same empty list as a new one. [hidden] is
/// the count of those rows; anything above zero means history exists.
ChatEmptyKind chatEmptyKind(int? hidden) =>
    (hidden ?? 0) > 0 ? ChatEmptyKind.undecryptable : ChatEmptyKind.brandNew;
