import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/decrypt/body_cache.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/local/database/app_database.dart';
import '../../../domain/entities/conversation.dart';
import '../../../domain/entities/message.dart';
import '../../../infrastructure/repositories/message_repository_impl.dart';
import '../../../services/presence_service.dart';
import '../../../services/fcm_service.dart';
import '../../../infrastructure/offline/connectivity_signal.dart';
import '../providers/chat_provider.dart';
import '../providers/message_body_provider.dart';
import '../chat_run_grouping.dart';
import '../message_offline_policy.dart';
import 'album_screen.dart';
import '../widgets/disappearing_dialog.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_context_menu.dart';
import '../widgets/message_input.dart';
import '../widgets/pinned_message_banner.dart';
import '../widgets/selection_bar.dart';
import '../../media/screens/media_docs_screen.dart';
import '../../groups/screens/group_settings_screen.dart';
import '../../starred_messages/screens/starred_messages_screen.dart';
import '../../profile/screens/view_profile_screen.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/skeleton.dart';
import '../../mascot/capybara.dart';

/// Who may send in [conv]: the composer and the share picker (12.1 D6) both
/// ask here, so the rule lives in one place.
bool canSendIn(
  Conversation conv, {
  required String? myRole,
  required bool keyReady,
}) => !conv.isGroup
    ? true
    : (myRole == 'left' || !keyReady
          ? false
          : (!conv.onlyAdminsCanMessage || myRole == 'admin'));

// ── Sealed list item ──────────────────────────────────────────────────────

sealed class _ChatItem {}

class _MsgItem extends _ChatItem {
  _MsgItem(
    this.msg,
    this.key, {
    required this.runStart,
    required this.runEnd,
    this.album,
  });

  /// For an album, its earliest row (place and time).
  final Message msg;
  final GlobalKey key;
  final bool runStart;
  final bool runEnd;

  /// 12.5: the album's rows in order; null for a single message.
  final List<Message>? album;

  Iterable<Message> get rows => album ?? [msg];
}

/// 12.8 B3: tags a selectable row for the drag hit-test.
class _RowTag {
  const _RowTag(this.id);
  final String id;
}

class _DateItem extends _ChatItem {
  _DateItem(this.date);
  final DateTime date;
}

class _HistoryEndItem extends _ChatItem {
  _HistoryEndItem();
}

// ── In-conversation search (Task 9: spec §5.1/§19.1) ─────────────────────
//
// Decrypt-on-query with a 200ms debounce and a per-keystroke cancel token:
// typing a new character bumps the generation, so any in-flight scan aborts
// at its next checkpoint and only the LAST query's results ever land.
// Bodies resolve through the caller-supplied [resolveBody] (production wires
// `messageBodyProvider(id).future` — the provider's own reads); match sets
// live ONLY in this controller (ephemeral) — never in the DB, never written
// back to the shared body cache (search must not rebuild a plaintext store).

typedef ConversationBodyResolver = Future<String?> Function(String messageId);

class ConversationSearchController {
  ConversationSearchController({
    required this.resolveBody,
    this.debounce = const Duration(milliseconds: 200),
  });

  /// Provider read seam — production: `(id) => ref.read(messageBodyProvider(id).future)`.
  final ConversationBodyResolver resolveBody;

  /// Brief-pinned debounce between keystroke and scan start.
  final Duration debounce;

  /// Called on the main isolate with the matching flat-list indices
  /// (chat screen maps them to `_matchItemIndices`).
  void Function(List<int> matchIndices)? onResults;

  /// Instrumented cancel token (brief test 4): incremented every time an
  /// in-flight scan observes that a newer keystroke superseded it.
  @visibleForTesting
  int cancelCount = 0;

  /// Last COMPLETED query's matches — only ever the newest generation's.
  List<int> lastMatches = const [];

  int _generation = 0;
  Timer? _debounceTimer;

  /// Schedules a scan of [candidates] (`(flatIndex, messageId)` pairs)
  /// for [query]. ANY new keystroke bumps the generation first — an
  /// in-flight scan observes the mismatch at its next checkpoint and
  /// aborts (incrementing [cancelCount]) without applying; only the
  /// newest generation ever calls [onResults].
  void setQuery(String query, {required List<(int, String)> candidates}) {
    final generation = ++_generation; // cancel token: supersede in-flight
    _debounceTimer?.cancel();
    if (query.isEmpty) {
      lastMatches = const [];
      _debounceTimer = null;
      onResults?.call(const []);
      return;
    }
    _debounceTimer = Timer(debounce, () {
      _debounceTimer = null;
      unawaited(_scan(query, candidates, generation));
    });
  }

  Future<void> _scan(
    String query,
    List<(int, String)> candidates,
    int generation,
  ) async {
    final needle = query.toLowerCase();
    final matches = <int>[];
    for (final (index, messageId) in candidates) {
      if (generation != _generation) {
        cancelCount++; // instrumented abort (brief test 4)
        return;
      }
      final body = await resolveBody(messageId);
      if (generation != _generation) {
        cancelCount++; // superseded while awaiting the body
        return;
      }
      if (body != null && body.toLowerCase().contains(needle)) {
        matches.add(index);
      }
    }
    if (generation != _generation) {
      cancelCount++;
      return;
    }
    lastMatches = matches;
    onResults?.call(matches); // ephemeral — nothing persisted anywhere
  }

  void dispose() {
    _generation++;
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }
}

// ── Chat screen ───────────────────────────────────────────────────────────

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.conversation});
  final Conversation conversation;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver {
  final _scrollCtrl = ScrollController();
  final _searchCtrl = TextEditingController();
  bool _loadingMore = false;
  int _offset = 40;
  bool _searchActive = false;
  bool _historyExhausted = false;
  bool _historyLoadFailed = false;
  bool _showScrollToLatest = false;
  final Set<String> _selectedMessageIds = <String>{};

  /// 12.8 A2: its own flag, so selection stays open at 0 selected.
  bool _selectionMode = false;

  // B3/B4 drag range: the start row, its new state, the selection before
  // the drag, the finger, and the autoscroll tick.
  final _listKey = GlobalKey();
  String? _dragAnchor;
  bool _dragOn = true;
  Set<String> _dragBase = const {};
  Offset? _dragPointer;
  Timer? _autoScroll;

  // Match navigation
  List<int> _matchItemIndices = []; // indices into _items (the flat list)
  int _matchIndex = 0;
  bool _searchPending = false;

  // Keys per message for scroll-to
  final Map<String, GlobalKey> _msgKeys = {};
  String? _flashMessageId;
  int _flashGeneration = 0;
  Timer? _flashTimer;

  // Cached items list so scroll helpers can access it
  List<_ChatItem> _items = [];

  final Map<String, String> _senderNameCache = {};

  ProviderSubscription<AsyncValue<List<Message>>>? _markReadSub;

  /// T9 in-conversation search: 200ms debounce + per-keystroke cancel;
  /// bodies resolve through the provider (its own reads only).
  late final ConversationSearchController _search;

  // Collapses the rapid messages-stream burst (rowCount 1→N during a backfill,
  // plus the per-message re-emits) into a SINGLE server round-trip. Without
  // this, every emit called `markConversationRead` — which writes a `read_at`
  // receipt for each message → fired the receipts subscription → which
  // re-ran reconcile → receipts flood. The open chat kept "running" forever.
  Timer? _markReadDebounce;

  // Read once in initState: `ref` is unusable in dispose, which must leave.
  late final PresenceService _pres;
  String get _cid => widget.conversation.id;

  /// The body provider is auto-disposed: a bare `ref.read(...future)` lets
  /// it be dropped before an uncached body resolves, and that future never
  /// completes, which stalled the whole search at 0/0. Hold it while
  /// waiting, and cap each wait so one stuck body can't stall the rest.
  Future<String?> _resolveSearchBody(String id) async {
    final keepAlive = ref.listenManual(messageBodyProvider(id), (_, __) {});
    try {
      return await ref
          .read(messageBodyProvider(id).future)
          .timeout(const Duration(seconds: 2), onTimeout: () => null);
    } finally {
      keepAlive.close();
    }
  }

  @override
  void initState() {
    super.initState();
    _pres = ref.read(presenceServiceProvider);
    _search = ConversationSearchController(
      resolveBody: _resolveSearchBody,
    );
    _search.onResults = (matches) {
      if (!mounted) return;
      setState(() {
        _matchItemIndices = matches;
        _matchIndex = 0;
        _searchPending = false;
      });
      if (matches.isNotEmpty) _scrollToMatch(0);
    };
    FcmService.activeConversationId = _cid;
    WidgetsBinding.instance.addObserver(this);
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _enter();
      if (!mounted) return;
      _markReadSub = ref.listenManual(messagesProvider(_cid), (_, next) {
        if (!mounted) return;
        if (!next.hasValue || next.value!.isEmpty) return;
        // Debounce: reset the clock on every emit; only the LAST emit (after
        // ~1.5s of quiet) actually marks read. This collapses an initial
        // 30-message backfill from ~30 server round-trips into 1.
        _markReadDebounce?.cancel();
        _markReadDebounce = Timer(const Duration(milliseconds: 1500), () {
          if (mounted) {
            ref.read(messageRepositoryProvider).markConversationRead(_cid);
          }
        });
      });
    });
  }

  @override
  void dispose() {
    if (FcmService.activeConversationId == _cid) {
      FcmService.activeConversationId = null;
    }
    _search.dispose();
    _flashTimer?.cancel();
    _autoScroll?.cancel();
    _markReadSub?.close();
    _markReadDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    _pres.leaveChat(_cid);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      FcmService.activeConversationId = _cid;
      _enter();
    }
    if (s == AppLifecycleState.paused || s == AppLifecycleState.inactive) {
      FcmService.activeConversationId = null;
      _pres.leaveChat(_cid);
    }
  }

  Future<void> _enter() async {
    await ref.read(messageRepositoryProvider).markConversationRead(_cid);
    await _pres.enterChat(_cid);
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final position = _scrollCtrl.position;
    final awayFromLatest = position.pixels > position.viewportDimension;
    if (awayFromLatest != _showScrollToLatest && mounted) {
      setState(() => _showScrollToLatest = awayFromLatest);
    }
    // A failed page waits for Retry instead of refetching on every scroll tick.
    if (position.pixels >= position.maxScrollExtent - 200 &&
        !_historyExhausted &&
        !_historyLoadFailed) {
      final loadedCount = _items.whereType<_MsgItem>().fold<int>(
        0,
        (n, m) => n + m.rows.length,
      );
      if (loadedCount < _offset) {
        if (mounted) setState(() => _historyExhausted = true);
        return;
      }
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() {
      _loadingMore = true;
      _historyLoadFailed = false;
    });
    try {
      await ref.read(messageRepositoryProvider).loadMoreMessages(_cid, _offset);
      _offset += 40;
    } catch (_) {
      // Offset stays put so Retry refetches the same page (bug §1.3).
      _historyLoadFailed = true;
    }
    if (mounted) setState(() => _loadingMore = false);
  }

  // ── Build flat item list with date separators ─────────────────────────

  List<_ChatItem> _buildItems(List<Message> all) {
    final items = <_ChatItem>[];
    // 12.5 A2/A5: an album is one entry, placed and timed by its earliest
    // row; run flags see it as one message.
    final units = groupChatUnits(all);
    final messages = [for (final u in units) u.anchor];
    final runFlags = computeChatRunFlags(messages);
    for (int i = 0; i < messages.length; i++) {
      final msg = messages[i];
      final key = _msgKeys.putIfAbsent(msg.localId, () => GlobalKey());
      items.add(
        _MsgItem(
          msg,
          key,
          runStart: runFlags[i].runStart,
          runEnd: runFlags[i].runEnd,
          album: units[i].isAlbum ? units[i].rows : null,
        ),
      );

      final next = i + 1 < messages.length ? messages[i + 1] : null;
      if (next == null || !_sameDay(msg.createdAt, next.createdAt)) {
        items.add(_DateItem(msg.createdAt));
      }
    }
    if (_historyExhausted) items.add(_HistoryEndItem());
    _items = items;
    return items;
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // ── Search helpers ────────────────────────────────────────────────────

  void _onSearchChanged(String q, List<Message> messages) {
    setState(() {
      _matchIndex = 0;
      _searchPending = q.trim().isNotEmpty;
      if (!_searchPending) _matchItemIndices = [];
    });
    // T9: debounced, cancellable decrypt-on-query over RESOLVED bodies —
    // results arrive via the controller's onResults (ephemeral index list).
    final candidates = <(int, String)>[
      for (var i = 0; i < _items.length; i++)
        if (_items[i] is _MsgItem) (i, (_items[i] as _MsgItem).msg.localId),
    ];
    _search.setQuery(q, candidates: candidates);
  }

  void _scrollToMatch(int index) {
    if (_matchItemIndices.isEmpty ||
        index < 0 ||
        index >= _matchItemIndices.length) {
      return;
    }
    setState(() => _matchIndex = index);
    final flatIndex = _matchItemIndices[index];
    final item = _items[flatIndex];
    unawaited(_scrollToFlatIndex(flatIndex).then((_) {
      if (mounted && item is _MsgItem) _flashMessage(item.msg.localId);
    }));
  }

  void _nextMatch() => _scrollToMatch(
    (_matchIndex + 1) %
        (_matchItemIndices.isEmpty ? 1 : _matchItemIndices.length),
  );

  void _prevMatch() => _scrollToMatch(
    (_matchIndex -
            1 +
            (_matchItemIndices.isEmpty ? 1 : _matchItemIndices.length)) %
        (_matchItemIndices.isEmpty ? 1 : _matchItemIndices.length),
  );

  /// Scrolls to [msg] whether it is currently rendered or not.
  /// Fast path: widget in tree → ensureVisible.
  /// Slow path: estimate offset by item index, then retry ensureVisible
  /// once the ListView has rebuilt with the target item rendered.
  int _findFlatIndex(Message msg) {
    for (int i = 0; i < _items.length; i++) {
      final item = _items[i];
      if (item is _MsgItem && unitHolds(item.rows, msg)) return i;
    }
    return -1;
  }

  /// Centres the item at [flatIndex] in the reversed list (index 0 = bottom,
  /// offset 0). An off-screen item isn't built, so this jumps near it, then
  /// steps a screen at a time toward it until it is built, and only then
  /// centres it — an estimate alone stops short when bubble heights vary.
  Future<void> _scrollToFlatIndex(int flatIndex) async {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 300);
    for (var attempt = 0; attempt < 30; attempt++) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      if (flatIndex >= _items.length) return;
      final target = _items[flatIndex];
      final ctx = target is _MsgItem ? target.key.currentContext : null;
      if (ctx != null && ctx.mounted) {
        await Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration: duration,
          curve: Curves.easeInOut,
        );
        return;
      }
      final pos = _scrollCtrl.position;
      final built = [
        for (var i = 0; i < _items.length; i++)
          if (_items[i] case final _MsgItem m
              when m.key.currentContext != null)
            i,
      ];
      final double next;
      if (attempt == 0 || built.isEmpty) {
        next = flatIndex / _items.length.clamp(1, _items.length) *
            pos.maxScrollExtent;
      } else {
        final older = flatIndex > built.last;
        next = pos.pixels +
            (older ? 1 : -1) * pos.viewportDimension * 0.8;
      }
      _scrollCtrl.jumpTo(next.clamp(0.0, pos.maxScrollExtent));
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  /// Unified jump for search/star/reply/pin. If the target is not in the
  /// loaded window, fetch it from the server, wait for the stream to emit
  /// it, then scroll precisely. Never bails silently (B3).
  Future<void> _jumpToMessage(Message msg) async {
    var flatIndex = _findFlatIndex(msg);
    if (flatIndex < 0 && msg.serverId != null) {
      final findingTimer = Timer(const Duration(seconds: 1), () {
        if (!mounted) return;
        showToast(context, 'Finding message…');
      });
      try {
        await ref
            .read(messageRepositoryProvider)
            .fetchAndCacheSingleMessage(msg.serverId!, _cid);
      } catch (e) {
        findingTimer.cancel();
        if (mounted) {
          showToast(context, 'Message not found in this chat', error: true);
        }
        return;
      }
      findingTimer.cancel();
      for (var i = 0; i < 20 && flatIndex < 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (!mounted) return;
        flatIndex = _findFlatIndex(msg);
      }
    }
    if (flatIndex < 0) {
      if (mounted) {
        showToast(context, 'Message not found in this chat', error: true);
      }
      return;
    }
    await _scrollToFlatIndex(flatIndex);
    if (mounted) _flashMessage(msg.localId);
  }

  void _flashMessage(String localId) {
    _flashTimer?.cancel();
    setState(() {
      _flashMessageId = localId;
      _flashGeneration++;
    });
    _flashTimer = Timer(const Duration(milliseconds: 450), () {
      if (!mounted || _flashMessageId != localId) return;
      setState(() => _flashMessageId = null);
    });
  }

  // ── Selection (12.8) ──────────────────────────────────────────────────

  bool _isSelected(_MsgItem item) =>
      item.rows.any((r) => _selectedMessageIds.contains(r.localId));

  /// E1: an album selects as one unit.
  void _mark(Set<String> into, _MsgItem item, bool on) {
    final ids = item.rows.map((r) => r.localId);
    on ? into.addAll(ids) : into.removeAll(ids);
  }

  void _enterSelection(_MsgItem item) {
    setState(() {
      _selectionMode = true;
      _mark(_selectedMessageIds, item, true);
    });
    // A1: keyboard down, draft kept. After the frame, because the menu's
    // pop hands focus back to the composer.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => FocusManager.instance.primaryFocus?.unfocus(),
    );
  }

  void _toggle(_MsgItem item) =>
      setState(() => _mark(_selectedMessageIds, item, !_isSelected(item)));

  void _exitSelection() {
    _endDrag();
    setState(() {
      _selectionMode = false;
      _selectedMessageIds.clear();
    });
  }

  /// B3: the selectable row under [global], found by hit-testing the list
  /// for the [MetaData] each message row carries.
  String? _rowAt(Offset global) {
    final box = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final result = BoxHitTestResult();
    box.hitTest(result, position: box.globalToLocal(global));
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderMetaData && target.metaData is _RowTag) {
        return (target.metaData as _RowTag).id;
      }
    }
    return null;
  }

  int _indexOf(String id) => _items.indexWhere(
    (it) => it is _MsgItem && it.msg.localId == id,
  );

  void _tapRow(TapUpDetails d) {
    final id = _rowAt(d.globalPosition);
    final i = id == null ? -1 : _indexOf(id);
    if (i >= 0) _toggle(_items[i] as _MsgItem);
  }

  /// B2: a long-press while selecting toggles its row and starts a range
  /// that takes the row's new state.
  void _startDrag(LongPressStartDetails d) {
    final id = _rowAt(d.globalPosition);
    final i = id == null ? -1 : _indexOf(id);
    if (i < 0) return;
    HapticFeedback.selectionClick();
    _autoScroll?.cancel();
    _dragAnchor = id;
    _dragBase = {..._selectedMessageIds};
    _dragOn = !_isSelected(_items[i] as _MsgItem);
    _dragPointer = d.globalPosition;
    _applyRange(id!);
    _autoScroll = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _autoScrollTick(),
    );
  }

  void _moveDrag(Offset global) {
    if (_dragAnchor == null) return;
    _dragPointer = global;
    // A finger past the list's edge still follows the edge row (B4).
    final box = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final local = box.globalToLocal(global);
    final id = _rowAt(
      box.localToGlobal(
        Offset(local.dx, local.dy.clamp(1.0, box.size.height - 1)),
      ),
    );
    // Over a date row: the range stays where it was.
    if (id != null) _applyRange(id);
  }

  /// Rows between the start and [toId] take the drag's state; every other
  /// row is what it was before the drag.
  void _applyRange(String toId) {
    final from = _indexOf(_dragAnchor!);
    if (from < 0) return _endDrag(); // F6: the start row expired
    final to = _indexOf(toId);
    if (to < 0) return;
    final next = {..._dragBase};
    for (var i = math.min(from, to); i <= math.max(from, to); i++) {
      final item = _items[i];
      if (item is _MsgItem && item.msg.type != 'system') {
        _mark(next, item, _dragOn);
      }
    }
    setState(
      () => _selectedMessageIds
        ..clear()
        ..addAll(next),
    );
  }

  /// B4: a finger in the list's top or bottom 64dp scrolls that way, from
  /// 0 at the band's inner edge to 1600 dp/s at the list's edge.
  void _autoScrollTick() {
    final box = _listKey.currentContext?.findRenderObject() as RenderBox?;
    final pointer = _dragPointer;
    if (box == null || pointer == null || !_scrollCtrl.hasClients) return;
    const band = 64.0;
    const maxSpeed = 1600.0;
    final y = box.globalToLocal(pointer).dy;
    final h = box.size.height;
    // Reversed list: older history (up the screen) is +pixels.
    final speed = y < band
        ? (band - y).clamp(0.0, band) / band * maxSpeed
        : y > h - band
        ? -(y - (h - band)).clamp(0.0, band) / band * maxSpeed
        : 0.0;
    if (speed == 0) return;
    final pos = _scrollCtrl.position;
    final next = (pos.pixels + speed * 0.016).clamp(
      pos.minScrollExtent,
      pos.maxScrollExtent,
    );
    if (next == pos.pixels) return;
    _scrollCtrl.jumpTo(next);
    _moveDrag(pointer);
  }

  void _endDrag() {
    _autoScroll?.cancel();
    _autoScroll = null;
    _dragAnchor = null;
    _dragPointer = null;
  }

  /// D7: the selection resolved against the current list, oldest first; an
  /// album brings every row it has now.
  List<Message> _selectedRows() {
    final messages = ref.read(messagesProvider(_cid)).valueOrNull ?? [];
    final albums = {
      for (final m in messages)
        if (m.albumId != null && _selectedMessageIds.contains(m.localId))
          m.albumId,
    };
    return [
      for (final m in messages.reversed)
        if (_selectedMessageIds.contains(m.localId) ||
            albums.contains(m.albumId))
          m,
    ];
  }

  /// D2: a text whose body is on the phone (not deleted, not undecryptable).
  static bool _copyable(Message m) =>
      m.type == 'text' &&
      !m.isDeletedForEveryone &&
      m.decryptState != 'key_missing' &&
      m.decryptState != 'failed';

  Future<void> _copySelected() async {
    final rows = _selectedRows();
    final texts = <String>[];
    for (final m in rows.where(_copyable)) {
      final body = bodyCache.get(m.localId) ?? await _resolveSearchBody(m.localId);
      if (body != null && body.isNotEmpty) texts.add(body);
    }
    if (!mounted || texts.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: texts.join('\n\n')));
    if (!mounted) return;
    final n = texts.length;
    showToast(
      context,
      n < rows.length
          ? 'Copied $n of ${rows.length}. Only text is copied.'
          : n == 1
          ? 'Copied'
          : 'Copied $n messages',
    );
    _exitSelection();
  }

  Future<void> _starSelected() async {
    final starrable = [
      for (final m in _selectedRows())
        if (!m.isDeletedForEveryone) m,
    ];
    if (starrable.isEmpty) return _exitSelection();
    final unstar = starrable.every((m) => m.isStarred);
    final ids = [
      for (final m in starrable)
        if (unstar || !m.isStarred) m.localId,
    ];
    await ref.read(messageRepositoryProvider).setStarred(ids, !unstar);
    if (!mounted) return;
    final n = ids.length;
    final verb = unstar ? 'Unstarred' : 'Starred';
    showToast(context, n == 1 ? verb : '$verb $n messages');
    _exitSelection();
  }

  Future<void> _deleteSelected({
    required String myId,
    required bool isLeft,
  }) async {
    final rows = _selectedRows();
    if (rows.isEmpty) return _exitSelection();
    final deleted = await deleteSelectedMessages(
      context,
      ref,
      rows,
      // D5: per row as it is when the delete is confirmed.
      current: _selectedRows,
      // D4 / decision 10: all yours and still a member.
      canDeleteForEveryone: !isLeft && rows.every((m) => m.senderId == myId),
    );
    if (deleted && mounted) _exitSelection();
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final convAsync = ref.watch(conversationStreamProvider(_cid));
    final conv = convAsync.asData?.value ?? widget.conversation;
    final messagesAsync = ref.watch(messagesProvider(_cid));
    final otherUserId = conv.otherUser?.id;
    final presence = otherUserId != null
        ? ref
              .watch(_presenceProvider((userId: otherUserId, convId: _cid)))
              .asData
              ?.value
        : null;

    final myId = ref.watch(currentUserIdProvider).asData?.value ?? '';
    final isSending = ref.watch(sendMessageProvider);
    final activeReply = ref.watch(replyProvider(_cid));
    final isOnline = ref.watch(isOnlineProvider).value ?? true;
    final messages = messagesAsync.asData?.value ?? [];
    final items = _buildItems(messages);

    // ── Group-specific reactive state ─────────────────────────
    final membersAsync = ref.watch(groupMembersProvider(_cid));
    final members = membersAsync.asData?.value ?? [];
    final myMember = members.where((m) => m.id == myId).firstOrNull;
    final isLeft = myMember?.groupRole == 'left';
    final memberCount = conv.isGroup
        ? members.where((m) => m.groupRole != 'left').length
        : 0;

    // Group-key readiness: a just-joined member holds no key until an admin
    // device rotates. Keyless -> composer off + explanatory banner (spec D3).
    final keyReady = !conv.isGroup
        ? true
        : (ref.watch(groupKeyReadyProvider(_cid)).asData?.value ?? false);

    final canSend = canSendIn(
      conv,
      myRole: myMember?.groupRole,
      keyReady: keyReady,
    );

    final restrictionMessage = isLeft
        ? "You can't send messages to this group because you're no longer a member."
        : (!keyReady
              ? 'Waiting for a group admin to come online and share the group key…'
              : null);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_selectionMode) return _exitSelection();
        _pres.leaveChat(_cid).then((_) {
          if (context.mounted) Navigator.of(context).pop();
        });
      },
      child: Scaffold(
        backgroundColor: context.t.bg,
        resizeToAvoidBottomInset: true,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                child: AnimatedSwitcher(
                  // A5: reduced motion → no fade.
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : WarmPopTokens.motionFast,
                  transitionBuilder: (child, animation) =>
                      FadeTransition(opacity: animation, child: child),
                  child: KeyedSubtree(
                    key: ValueKey((_selectionMode, _searchActive)),
                    child: _selectionMode
                        ? _selectionBar(myId: myId, isLeft: isLeft)
                        : _searchActive
                        ? _searchBar(context, messages)
                        : _mainBar(context, conv, presence, memberCount),
                  ),
                ),
              ),
            ),

            if (_loadingMore)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(WarmPopTokens.radiusSm),
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    color: context.t.accent,
                    backgroundColor: context.t.surface2,
                  ),
                ),
              ),

            if (_historyLoadFailed && !_loadingMore)
              HistoryLoadFailedRow(online: isOnline, onRetry: _loadMore),

            if (!isOnline)
              _OfflineStrip(
                onRetry: () => ref.invalidate(messagesProvider(_cid)),
              ),

            if (!_searchActive)
              PinnedMessageBanner(
                conversationId: _cid,
                onTap: (m) => unawaited(_jumpToMessage(m)),
              ),

            Expanded(
              child: Stack(
                children: [
                  messagesAsync.when(
                    loading: () => const _ChatLoadingState(),
                    error: (e, _) => ChatLoadError(
                      onRetry: () => ref.invalidate(messagesProvider(_cid)),
                    ),
                    data: (_) => items.isEmpty
                        ? _ChatEmptyState(
                            displayName: conv.displayName,
                            hidden: ref
                                .watch(undecryptableCountProvider(_cid))
                                .value,
                          )
                        : _searchActive &&
                              _searchCtrl.text.trim().isNotEmpty &&
                              !_searchPending &&
                              _matchItemIndices.isEmpty
                        ? _SearchEmptyState(query: _searchCtrl.text.trim())
                        : _selectionGestures(ListView.builder(
                            key: _listKey,
                            controller: _scrollCtrl,
                            reverse: true,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: items.length,
                            itemBuilder: (_, i) {
                              final item = items[i];

                              if (item is _DateItem) {
                                return _DateSeparator(date: item.date);
                              }
                              if (item is _HistoryEndItem) {
                                return const _HistoryEndMarker();
                              }

                              final msgItem = item as _MsgItem;
                              final msg = msgItem.msg;
                              final isMine = msg.senderId == myId;

                              if (conv.isGroup &&
                                  !isMine &&
                                  !_senderNameCache.containsKey(msg.senderId)) {
                                ref
                                    .read(appDatabaseProvider)
                                    .usersDao
                                    .getUserById(msg.senderId)
                                    .then((u) {
                                      if (u != null && mounted) {
                                        setState(
                                          () => _senderNameCache[msg.senderId] =
                                              u.displayName,
                                        );
                                      }
                                    });
                              }

                              final isMatch = _matchItemIndices.contains(i);
                              final isCurrent =
                                  _matchItemIndices.isNotEmpty &&
                                  _matchIndex < _matchItemIndices.length &&
                                  _items[_matchItemIndices[_matchIndex]] ==
                                      item;

                              final row = KeyedSubtree(
                                key: msgItem.key,
                                child: _HighlightWrapper(
                                  active: isMatch,
                                  current: isCurrent,
                                  flash: msgItem.rows.any(
                                    (r) => r.localId == _flashMessageId,
                                  ),
                                  flashToken: _flashGeneration,
                                  child: MessageBubble(
                                    message: msg,
                                    isMine: isMine,
                                    isGroup: conv.isGroup,
                                    runStart: msgItem.runStart,
                                    runEnd: msgItem.runEnd,
                                    searchQuery:
                                        _searchActive &&
                                            _searchCtrl.text.trim().isNotEmpty
                                        ? _searchCtrl.text
                                        : null,
                                    searchCurrent: isCurrent,
                                    album: msgItem.album,
                                    onOpenAlbum: (tile) {
                                      final album = msgItem.album;
                                      if (album == null || album.isEmpty) {
                                        return;
                                      }
                                      final page = AlbumScreen(
                                            conversationId: _cid,
                                            albumId: album.first.albumId!,
                                            senderName: conv.isGroup
                                                ? (_senderNameCache[
                                                          msg.senderId] ??
                                                      'Unknown')
                                                : (conv.otherUser
                                                          ?.displayName ??
                                                      'Unknown'),
                                            timestamp: msg.createdAt,
                                            initialIndex: tile,
                                          );
                                      // G1: reduced motion → no route animation.
                                      Navigator.of(context).push(
                                        MediaQuery.disableAnimationsOf(context)
                                            ? PageRouteBuilder<void>(
                                                transitionDuration:
                                                    Duration.zero,
                                                reverseTransitionDuration:
                                                    Duration.zero,
                                                pageBuilder: (_, _, _) => page,
                                              )
                                            : MaterialPageRoute<void>(
                                                builder: (_) => page,
                                              ),
                                      );
                                    },
                                    selected: _isSelected(msgItem),
                                    selecting: _selectionMode,
                                    // F1: an album selects as one unit.
                                    onSelect: _selectionMode
                                        ? () => _toggle(msgItem)
                                        : () => _enterSelection(msgItem),
                                    senderName: conv.isGroup
                                        ? (_senderNameCache[msg.senderId] ??
                                              'Unknown')
                                        : (conv.otherUser?.displayName ??
                                              'Unknown'),
                                    onReply: () =>
                                        ref.read(replyProvider(_cid).notifier).state =
                                            msg,
                                    onReplyTap: msg.replyToId != null
                                        ? () {
                                            final orig = messages
                                                .where(
                                                  (m) =>
                                                      m.serverId ==
                                                      msg.replyToId,
                                                )
                                                .firstOrNull;
                                            if (orig != null) {
                                              unawaited(_jumpToMessage(orig));
                                            }
                                          }
                                        : null,
                                  ),
                                ),
                              );
                              // B5: system rows carry no tag, so taps and
                              // ranges skip them.
                              return msg.type == 'system'
                                  ? row
                                  : MetaData(
                                      metaData: _RowTag(msg.localId),
                                      behavior: HitTestBehavior.opaque,
                                      child: row,
                                    );
                            },
                          )),
                  ),
                  if (!_searchActive && _showScrollToLatest)
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: _ScrollLatestButton(
                        unreadCount: conv.unreadCount,
                        onPressed: () {
                          _scrollCtrl.animateTo(
                            0,
                            duration: WarmPopTokens.motionBase,
                            curve: Curves.easeOut,
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),

            if (!_searchActive)
              MessageInput(
                conversationId: _cid,
                isLoading: isSending,
                canSendMessages: canSend,
                restrictionMessage: restrictionMessage,
                replySenderName: activeReply == null
                    ? null
                    : activeReply.senderId == myId
                    ? 'You'
                    : (conv.isGroup
                          ? (_senderNameCache[activeReply.senderId] ?? 'them')
                          : conv.displayName),
                onTyping: () => _pres.onTyping(_cid),
                onSend: (text) {
                  final reply = ref.read(replyProvider(_cid));
                  // P7 (spec §3): the reply PREVIEW is no longer computed
                  // here and never reaches the repository — the quote
                  // derives from the parent row at render time and the
                  // drain derives the server-bound copy from the same row.
                  return ref
                      .read(sendMessageProvider.notifier)
                      .send(
                        conversationId: _cid,
                        text: text,
                        replyToLocalId: reply?.localId,
                      );
                },
              ),
          ],
        ),
      ),
    );
  }

  // ── App bars ──────────────────────────────────────────────────────────

  Widget _mainBar(
    BuildContext context,
    Conversation conv,
    OtherUserPresence? presence,
    int memberCount,
  ) {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          BackButton(
            color: context.t.ink,
            onPressed: () => _pres.leaveChat(_cid).then((_) {
              if (context.mounted) Navigator.of(context).pop();
            }),
          ),
          Expanded(
            child: Semantics(
              button: true,
              label: conv.isGroup ? 'Open group info' : 'Open profile',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _openConversationInfo(conv),
                child: Row(
                  children: [
                    if (!conv.isGroup)
                      AppAvatar(
                        radius: 18,
                        accentSoft: true,
                        url: conv.avatarUrl,
                        initials: initialsOf(conv.displayName),
                      )
                    else
                      Stack(
                        children: [
                          AppAvatar(
                            radius: 18,
                            accentSoft: true,
                            url: conv.iconUrl,
                            initials: initialsOf(conv.displayName),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(1.5),
                              decoration: BoxDecoration(
                                color: context.t.bg,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.group,
                                size: 10,
                                color: context.t.accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            conv.displayName,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: context.t.ink,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (conv.isGroup)
                            Text(
                              '$memberCount member${memberCount == 1 ? '' : 's'}',
                              style: TextStyle(
                                fontSize: 12,
                                color: context.t.inkSoft,
                              ),
                            )
                          else if (presence != null)
                            _PresenceSubtitle(presence: presence),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Search messages',
            color: context.t.inkSoft,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const Icon(Icons.search),
            onPressed: () => setState(() => _searchActive = true),
          ),
          IconButton(
            tooltip: 'Chat actions',
            color: context.t.inkSoft,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const Icon(Icons.more_vert),
            onPressed: () => _showChatMenu(context, conv),
          ),
        ],
      ),
    );
  }

  Widget _selectionBar({required String myId, required bool isLeft}) {
    final rows = _selectedRows();
    final starrable = [
      for (final m in rows)
        if (!m.isDeletedForEveryone) m,
    ];
    return SelectionBar(
      count: rows.length,
      onExit: _exitSelection,
      onCopy: _copySelected,
      canCopy: rows.any(_copyable),
      starState: starrable.isNotEmpty && starrable.every((m) => m.isStarred),
      onStar: _starSelected,
      canStar: starrable.isNotEmpty,
      onDelete: () => _deleteSelected(myId: myId, isLeft: isLeft),
    );
  }

  /// B1–B3: while selecting, a tap toggles the row under it (the whole row
  /// width) and a long-press toggles and drags a range.
  Widget _selectionGestures(Widget list) => GestureDetector(
    excludeFromSemantics: true, // each row is its own button (G1)
    onTapUp: _selectionMode ? _tapRow : null,
    onLongPressStart: _selectionMode ? _startDrag : null,
    onLongPressMoveUpdate: _selectionMode
        ? (d) => _moveDrag(d.globalPosition)
        : null,
    onLongPressEnd: _selectionMode ? (_) => _endDrag() : null,
    // A cancelled touch (app backgrounded) never sends an end.
    onLongPressCancel: _selectionMode ? _endDrag : null,
    child: list,
  );

  Future<void> _showChatMenu(BuildContext context, Conversation conv) async {
    final row = await ref
        .read(appDatabaseProvider)
        .conversationsDao
        .getConversationById(_cid);
    if (!context.mounted) return;
    final disappearingDuration = row?.disappearingDuration ?? 0;
    // F1: C4a, no header (decision 10); each callback is today's.
    showActionSheet(
      context: context,
      haptic: false,
      actions: [
        ConversationMenuAction(
          label: 'Media and docs',
          icon: Icons.perm_media_outlined,
          callback: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MediaDocsScreen(conversationId: _cid),
              ),
            );
          },
        ),
        ConversationMenuAction(
          label: 'Starred messages',
          icon: Icons.star_outline,
          callback: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => StarredMessagesScreen(
                  conversationId: _cid,
                  onJump: (m) => unawaited(_jumpToMessage(m)),
                ),
              ),
            );
          },
        ),
        if (conv.isGroup)
          ConversationMenuAction(
            label: 'Group info',
            icon: Icons.group_outlined,
            callback: () {
              _openConversationInfo(conv);
            },
          ),
        ConversationMenuAction(
          label: 'Disappearing messages',
          icon: Icons.timer_outlined,
          trailing: disappearingDurationLabel(disappearingDuration),
          callback: () {
            unawaited(showDisappearingDialog(context, ref, _cid));
          },
        ),
      ],
    );
  }

  void _openConversationInfo(Conversation conv) {
    if (conv.isGroup) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GroupSettingsScreen(conversation: conv),
        ),
      );
    } else if (conv.otherUser != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ViewProfileScreen(user: conv.otherUser!),
        ),
      );
    }
  }

  Widget _searchBar(BuildContext context, List<Message> messages) {
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: context.t.surface,
        border: Border.all(color: context.t.line),
        borderRadius: BorderRadius.circular(WarmPopTokens.radiusXl),
        boxShadow: WarmPopTokens.cardShadow(context.t.shadow),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Close search',
            color: context.t.inkSoft,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const Icon(Icons.arrow_back),
            onPressed: _closeSearch,
          ),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              cursorColor: context.t.accent,
              style: TextStyle(color: context.t.ink),
              decoration: InputDecoration(
                hintText: 'Search in conversation…',
                hintStyle: TextStyle(color: context.t.inkFaint),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onChanged: (q) => _onSearchChanged(q, messages),
              onSubmitted: (_) => _nextMatch(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              '${_matchItemIndices.isEmpty ? 0 : _matchIndex + 1}/${_matchItemIndices.length}',
              style: TextStyle(fontSize: 13, color: context.t.inkSoft),
            ),
          ),
          IconButton(
            // Matches run newest-first (index 0 = bottom), so "next" is the
            // older one above: up steps back in time, down forward.
            tooltip: 'Older match',
            color: context.t.inkSoft,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const Icon(Icons.keyboard_arrow_up),
            onPressed: _matchItemIndices.isNotEmpty ? _nextMatch : null,
          ),
          IconButton(
            tooltip: 'Newer match',
            color: context.t.inkSoft,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: _matchItemIndices.isNotEmpty ? _prevMatch : null,
          ),
          IconButton(
            tooltip: 'Close search',
            color: context.t.inkSoft,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const Icon(Icons.close),
            onPressed: _closeSearch,
          ),
        ],
      ),
    );
  }

  void _closeSearch() {
    setState(() {
      _searchActive = false;
      _matchItemIndices = [];
      _matchIndex = 0;
      _searchPending = false;
      _searchCtrl.clear();
    });
  }

}

class _ChatLoadingState extends StatelessWidget {
  const _ChatLoadingState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      children: [
        Align(child: const Skeleton(width: 72, height: 18, radius: 999)),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: const _ChatSkeletonBubble(width: 220),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: const _ChatSkeletonBubble(width: 164),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: const _ChatSkeletonBubble(width: 260),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: const _ChatSkeletonBubble(width: 196, height: 76),
        ),
      ],
    );
  }
}

class _ChatSkeletonBubble extends StatelessWidget {
  const _ChatSkeletonBubble({required this.width, this.height = 34});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Skeleton(
        width: width,
        height: height,
        radius: WarmPopTokens.radiusBubble,
      ),
    );
  }
}

class ChatLoadError extends StatelessWidget {
  const ChatLoadError({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: context.t.error.withValues(alpha: 0.08),
          border: Border.all(color: context.t.error.withValues(alpha: 0.40)),
          borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(
                child: Capybara(
                  mood: CapyMood.neutral,
                  showKey: true,
                  size: Size(72, 65),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: context.t.error,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      "Couldn't load this chat.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.t.ink, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.center,
                child: TextButton(
                  onPressed: onRetry,
                  child: const Text('Retry'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An older history page failed to load. Retry refetches the same page;
/// offline it dims (38%) with the shared hint instead of firing a doomed call.
class HistoryLoadFailedRow extends StatelessWidget {
  const HistoryLoadFailedRow({
    super.key,
    required this.online,
    required this.onRetry,
  });

  final bool online;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final caption = TextStyle(color: context.t.inkSoft, fontSize: 12);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          Text("Couldn't load older messages.", style: caption),
          Opacity(
            opacity: online ? 1 : .38,
            child: TextButton(
              onPressed: online ? onRetry : null,
              child: const Text('Retry'),
            ),
          ),
          if (!online) Text(kOfflineActionHint, style: caption),
        ],
      ),
    );
  }
}

/// Empty chat, or history this device can no longer decrypt.
///
/// An empty list used to render "Say hello" unconditionally, which is wrong for
/// a conversation whose rows are all `pending`/`key_missing` (backlog §170):
/// those rows are hidden by design — ciphertext must never reach a bubble — so
/// a group with 75 unrecoverable rows looked brand-new. [hidden] > 0 means
/// "history exists but cannot be decrypted", which is the honest copy.
class _ChatEmptyState extends StatelessWidget {
  const _ChatEmptyState({required this.displayName, this.hidden});

  final String displayName;
  final int? hidden;

  @override
  Widget build(BuildContext context) {
    if (chatEmptyKind(hidden) == ChatEmptyKind.undecryptable) {
      return EmptyState(
        title: 'Older messages unavailable',
        subtitle:
            'These messages were encrypted with a key this device no longer '
            'has. Ask a group admin to re-share them.',
        mood: CapyMood.sleepy,
        mascot: const Capybara(mood: CapyMood.sleepy, size: Size(64, 58)),
      );
    }
    return EmptyState(
      title: 'Say hello to $displayName',
      subtitle:
          'Messages here are end-to-end encrypted. Nobody else can read them.',
      mascot: const Capybara(size: Size(108, 97)),
    );
  }
}

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      title: 'Nothing found',
      subtitle: 'No messages match “$query”.',
      mascot: const Capybara(mood: CapyMood.sleepy, size: Size(64, 58)),
    );
  }
}

class _PresenceSubtitle extends StatelessWidget {
  const _PresenceSubtitle({required this.presence});

  final OtherUserPresence presence;

  @override
  Widget build(BuildContext context) {
    if (presence.isTyping) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TypingDots(color: context.t.info),
          const SizedBox(width: 4),
          Text(
            'typing…',
            style: TextStyle(fontSize: 12, color: context.t.info),
          ),
        ],
      );
    }
    if (presence.isOnline) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: context.t.success,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            'Online',
            style: TextStyle(fontSize: 12, color: context.t.success),
          ),
        ],
      );
    }
    return Text(
      presence.statusLabel,
      style: TextStyle(fontSize: 12, color: context.t.inkSoft),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots({required this.color});

  final Color color;

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Opacity(
                opacity:
                    0.35 +
                    0.65 * ((1 + math.sin((_controller.value * 6.28) - i)) / 2),
                child: Container(
                  width: 3,
                  height: 3,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OfflineStrip extends StatelessWidget {
  const _OfflineStrip({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: context.t.accentSoft,
        border: Border.all(color: context.t.accent.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd),
      ),
      child: Row(
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 16,
            color: context.t.accentPressed,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              kOfflineSendCopy,
              style: TextStyle(color: context.t.ink, fontSize: 12),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _ScrollLatestButton extends StatelessWidget {
  const _ScrollLatestButton({
    required this.unreadCount,
    required this.onPressed,
  });

  final int unreadCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Semantics(
          button: true,
          label: 'Scroll to latest messages',
          child: IconButton.filled(
            onPressed: onPressed,
            tooltip: 'Scroll to latest',
            style: IconButton.styleFrom(
              backgroundColor: context.t.surface2,
              foregroundColor: context.t.inkSoft,
              side: BorderSide(color: context.t.accent),
            ),
            icon: const Icon(Icons.keyboard_arrow_down),
          ),
        ),
        if (unreadCount > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: context.t.accent,
                shape: BoxShape.circle,
                border: Border.all(color: context.t.bg, width: 2),
              ),
              child: Text(
                unreadCount > 99 ? '99+' : '$unreadCount',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.t.onAccent,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _HistoryEndMarker extends StatelessWidget {
  const _HistoryEndMarker();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: context.t.surface2,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          'This is the beginning of your chat…',
          style: TextStyle(color: context.t.inkSoft, fontSize: 11),
        ),
      ),
    );
  }
}

// ── Date separator ────────────────────────────────────────────────────────

class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.date});
  final DateTime date;

  String _label() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);
    if (d == today) return 'Today';
    if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return date.year == today.year
        ? DateFormat('d MMMM').format(date)
        : DateFormat('d MMMM y').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: context.t.surface2,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          _label(),
          style: TextStyle(fontSize: 11, color: context.t.inkSoft),
        ),
      ),
    );
  }
}

// ── Search highlight wrapper ───────────────────────────────────────────────

class _HighlightWrapper extends StatefulWidget {
  const _HighlightWrapper({
    required this.child,
    required this.active,
    required this.current,
    required this.flash,
    required this.flashToken,
  });
  final Widget child;
  final bool active;
  final bool current;
  final bool flash;
  final int flashToken;

  @override
  State<_HighlightWrapper> createState() => _HighlightWrapperState();
}

class _HighlightWrapperState extends State<_HighlightWrapper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flashController = AnimationController(
    vsync: this,
    duration: WarmPopTokens.motionSlow,
    value: 0,
  );

  @override
  void didUpdateWidget(covariant _HighlightWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.flash && widget.flashToken != oldWidget.flashToken) {
      final reduceMotion =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      _flashController
        ..duration = reduceMotion
            ? const Duration(milliseconds: 200)
            : WarmPopTokens.motionSlow
        ..value = 1
        ..animateTo(0, curve: Curves.easeOut);
    }
  }

  @override
  void dispose() {
    _flashController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final persistent = widget.active
        ? context.t.accent.withValues(alpha: widget.current ? 0.20 : 0.05)
        : context.t.bg.withValues(alpha: 0);
    return AnimatedBuilder(
      animation: _flashController,
      builder: (_, child) => ColoredBox(
        color: Color.alphaBlend(
          context.t.accent.withValues(alpha: 0.26 * _flashController.value),
          persistent,
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}

// ── Presence stream provider ──────────────────────────────────────────────

final _presenceProvider = StreamProvider.autoDispose
    .family<OtherUserPresence, ({String userId, String convId})>((ref, args) {
      return ref
          .read(presenceServiceProvider)
          .watchPresence(args.userId, args.convId);
    });
