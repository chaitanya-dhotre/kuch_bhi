import 'dart:async';

import 'package:kuch_bhi/core/utils/op_id.dart';
import 'package:kuch_bhi/domain/entities/conversation.dart';
import 'package:kuch_bhi/domain/entities/group_invite.dart';
import 'package:kuch_bhi/domain/entities/message.dart';
import 'package:kuch_bhi/domain/entities/user.dart';
import 'package:kuch_bhi/domain/repositories/message_repository.dart';
import 'package:kuch_bhi/features/stickers/stickers.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart'
    show ReactionGroup;

/// Map-backed fake for mock-build screen development (spec §10).
/// Screen-facing reads are implemented; the rest fail LOUD on purpose —
/// extend when the consuming screen needs them.
///
/// Seeding: [seedConversation] / [seedMessage] before the widget pumps, or
/// [sendMessage] at runtime (local echo). No network, no Drift — the ONLY
/// read source when `main.dart` overrides `messageRepositoryProvider`
/// under `--dart-define=USE_FAKES=true`.
class FakeMessageRepository implements MessageRepository {
  FakeMessageRepository(); // explicit: the .demo() factory below would
  // otherwise suppress the implicit default constructor.

  final _conversations = <String, Conversation>{};
  final _messages = <String, List<Message>>{}; // conversationId → rows

  /// Per-conversation invalidation ping — watchers re-read their own map
  /// entry (a shared `List<Message>` broadcast would cross-talk between
  /// conversations; each `watchMessages` filters by its own id).
  final _messagesChanged = StreamController<void>.broadcast();
  final _conversationsChanged = StreamController<void>.broadcast();

  // ── Seeding (tests / dev fixtures) ─────────────────────────────

  void seedConversation(Conversation conversation) {
    _conversations[conversation.id] = conversation;
    _conversationsChanged.add(null);
  }

  void seedMessage(Message message) {
    (_messages[message.conversationId] ??= []).add(message);
    _messagesChanged.add(null);
  }

  List<Conversation> get seededConversations =>
      List.unmodifiable(_conversations.values);
  List<Message> messagesIn(String conversationId) =>
      List.unmodifiable(_messages[conversationId] ?? const <Message>[]);

  /// Mock-build fixture set (spec §10): what `main()` mounts under
  /// `USE_FAKES=true` so the home screen renders rows with no network,
  /// no auth session, and no real repository.
  factory FakeMessageRepository.demo() {
    final repo = FakeMessageRepository();
    final now = DateTime.now();
    repo.seedConversation(Conversation(
      id: 'demo-conv-group',
      type: 'group',
      name: 'Offline Demo Group',
      lastMessageAt: now,
      unreadCount: 2,
      memberCount: 3,
    ));
    repo.seedConversation(Conversation(
      id: 'demo-conv-dm',
      type: 'direct',
      lastMessageAt: now.subtract(const Duration(minutes: 12)),
      otherUser: User(
        id: 'demo-peer',
        displayName: 'Demo Peer',
        username: 'demo_peer',
        email: 'demo@example.com',
        friendCode: 'DEMO000000',
        createdAt: now.subtract(const Duration(days: 30)),
      ),
    ));
    return repo;
  }

  // ── Screen-facing reads (first fake-backed screens) ────────────

  @override
  Stream<List<Conversation>> watchConversations() async* {
    yield List.unmodifiable(_conversations.values);
    await for (final _ in _conversationsChanged.stream) {
      yield List.unmodifiable(_conversations.values);
    }
  }

  @override
  Stream<List<Message>> watchMessages(String conversationId) async* {
    yield List.unmodifiable(_messages[conversationId] ?? const <Message>[]);
    await for (final _ in _messagesChanged.stream) {
      yield List.unmodifiable(_messages[conversationId] ?? const <Message>[]);
    }
  }

  @override
  Future<void> sendMessage({
    required String conversationId,
    required String plaintext,
    String? replyToLocalId,
  }) => _send(conversationId, plaintext, replyToLocalId, 'text');

  @override
  Future<void> sendSticker({
    required String conversationId,
    required String stickerId,
    String? replyToLocalId,
  }) => _send(conversationId, stickerBody(stickerId), replyToLocalId, 'sticker');

  Future<void> _send(
    String conversationId,
    String plaintext,
    String? replyToLocalId,
    String type,
  ) async {
    final message = Message(
      localId: generateOpId(),
      conversationId: conversationId,
      senderId: 'me',
      type: type,
      decryptedBody: plaintext,
      replyToId: replyToLocalId,
      status: 'sent',
      createdAt: DateTime.now(),
    );
    (_messages[conversationId] ??= []).add(message);
    final conv = _conversations[conversationId];
    if (conv != null) {
      // P7 (spec §3): no preview string on the entity anymore — the tile
      // derives it from the message rows.
      _conversations[conversationId] = conv.copyWith(
        lastMessageAt: message.createdAt,
      );
      _conversationsChanged.add(null);
    }
    _messagesChanged.add(null);
  }

  @override
  Future<void> markConversationRead(String conversationId) async {
    final conv = _conversations[conversationId];
    if (conv == null) return;
    if (conv.unreadCount == 0) return;
    _conversations[conversationId] = conv.copyWith(unreadCount: 0);
    _conversationsChanged.add(null);
  }

  @override
  Stream<List<Message>> watchPinnedMessages(String conversationId) async* {
    yield (_messages[conversationId] ?? const <Message>[])
        .where((m) => m.isPinned)
        .toList(growable: false);
  }

  @override
  Future<List<Message>> getStarredMessages(String conversationId) async =>
      (_messages[conversationId] ?? const <Message>[])
          .where((m) => m.isStarred)
          .toList(growable: false);

  @override
  Future<bool> hasUsableKey(String conversationId) async => true;

  @override
  Future<void> predecryptConversation(
    String conversationId, {
    int limit = 30,
  }) async {}

  @override
  Future<List<Message>> searchMessages(
    String conversationId,
    String query,
  ) async {
    final q = query.toLowerCase();
    return (_messages[conversationId] ?? const <Message>[])
        .where((m) => (m.decryptedBody ?? '').toLowerCase().contains(q))
        .toList(growable: false);
  }

  @override
  Future<void> resyncOnResume({Duration? awayFor}) async {
    // app.dart calls this on every cold start / resume. The real impl
    // reconnects SSE sockets + refetches; the fake owns no sockets, so a
    // no-op IS the correct behaviour (loud failure would only add boot
    // noise — extend for real work when a fake-backed screen needs it).
  }

  @override
  Future<List<GroupInvite>> getIncomingGroupInvites() async =>
      const <GroupInvite>[];

  // Reactions: no local store here, so "watch" replays the server-shaped
  // getReactions + reactionsChanges pair that test subclasses override.
  @override
  Stream<List<ReactionGroup>> watchReactions(String messageServerId) async* {
    yield await getReactions(messageServerId);
    await for (final _
        in reactionsChanges.where((id) => id == messageServerId)) {
      yield await getReactions(messageServerId);
    }
  }

  @override
  Future<void> refreshReactions(String messageServerId) async {}

  /// Callers pass only the rows that change, so a toggle each is a set.
  @override
  Future<void> setStarred(List<String> localIds, bool starred) async {
    for (final id in localIds) {
      await toggleStar(id);
    }
  }

  // Everything else: LOUD failure with the member name — extend when a
  // consuming screen actually needs it (never a silent wrong answer).
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'FakeMessageRepository: ${invocation.memberName} — '
      'extend as screens need it');
}
