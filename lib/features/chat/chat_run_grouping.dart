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

bool _canJoin(Message newer, Message older) {
  if (newer.type == 'system' || older.type == 'system') return false;
  if (newer.senderId != older.senderId) return false;
  if (!_sameDay(newer.createdAt, older.createdAt)) return false;
  return newer.createdAt.difference(older.createdAt).abs() <=
      const Duration(minutes: 2);
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
