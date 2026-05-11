import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbase/pocketbase.dart';

import '../core/network/pocketbase_client.dart';
import '../data/local/database/app_database.dart';
import '../data/local/database/tables/app_settings_table.dart';

class OtherUserPresence {
  const OtherUserPresence({
    this.isOnline  = false,
    this.isTyping  = false,
    this.isInChat  = false,
    this.lastSeen,
  });

  final bool      isOnline;
  final bool      isTyping;
  final bool      isInChat;
  final DateTime? lastSeen;

  /// Typing ALWAYS takes priority over in-chat.
  String get statusLabel {
    if (isTyping)  return 'Typing...';
    if (isInChat)  return 'In chat';
    if (isOnline)  return 'Online';
    if (lastSeen != null) return 'Last seen ${_fmt(lastSeen!)}';
    return 'Offline';
  }

  bool get showDot => isOnline || isInChat || isTyping;

  static String _fmt(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1)  return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours   < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}

class PresenceService {
  PresenceService({required this.pbClient, required this.db});

  final PocketBaseClient pbClient;
  final AppDatabase      db;

  PocketBase get _pb => pbClient.pb;
  Timer? _typingTimer;
  Timer? _heartbeatTimer;
  bool   _isTyping = false;

  // ── Online heartbeat ──────────────────────────────────────────

  Future<void> goOnline() async {
    _heartbeatTimer?.cancel();
    final uid = await _uid(); if (uid == null) return;
    await _patch(uid, {
      'is_online': true,
      'last_seen': DateTime.now().toIso8601String(),
    });
    // Heartbeat every 90s so server-side cron doesn't mark offline.
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 90), (_) async {
      final id = await _uid(); if (id == null) return;
      await _patch(id, {
        'is_online': true,
        'last_seen': DateTime.now().toIso8601String(),
      });
    });
  }

  Future<void> goOffline() async {
    _heartbeatTimer?.cancel();
    _typingTimer?.cancel();
    final uid = await _uid(); if (uid == null) return;
    await _patch(uid, {
      'is_online':    false,
      'last_seen':    DateTime.now().toIso8601String(),
      'typing_in':    '',
      'current_chat': '',
    });
  }

  // ── Chat presence ─────────────────────────────────────────────

  Future<void> enterChat(String conversationId) async {
    final uid = await _uid(); if (uid == null) return;
    await _patch(uid, {'current_chat': conversationId});
  }

  Future<void> leaveChat(String conversationId) async {
    _typingTimer?.cancel();
    _isTyping = false;
    final uid = await _uid(); if (uid == null) return;
    await _patch(uid, {'current_chat': '', 'typing_in': ''});
  }

  // ── Typing ────────────────────────────────────────────────────

  Future<void> onTyping(String conversationId) async {
    final uid = await _uid(); if (uid == null) return;
    if (!_isTyping) {
      _isTyping = true;
      await _patch(uid, {'typing_in': conversationId});
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () async {
      _isTyping = false;
      final id = await _uid(); if (id == null) return;
      await _patch(id, {'typing_in': ''});
    });
  }

  // ── Watch other user ──────────────────────────────────────────

  Stream<OtherUserPresence> watchPresence(
    String otherUserId,
    String conversationId,
  ) {
    final ctrl = StreamController<OtherUserPresence>.broadcast();

    // Emit initial state.
    _pb.collection('users').getOne(otherUserId).then((r) {
      if (!ctrl.isClosed) ctrl.add(_toPresence(r, conversationId));
    }).catchError((e) => debugPrint('[Presence] initial fetch: $e'));

    // Subscribe to live updates.
    _pb.collection('users').subscribe(otherUserId, (event) {
      if (event.record == null || ctrl.isClosed) return;
      ctrl.add(_toPresence(event.record!, conversationId));
    }).catchError((e) => debugPrint('[Presence] subscribe: $e'));

    ctrl.onCancel = () {
      _pb.collection('users').unsubscribe(otherUserId)
          .catchError((_) {});
    };

    return ctrl.stream;
  }

  // ── Helpers ───────────────────────────────────────────────────

  OtherUserPresence _toPresence(RecordModel r, String convId) {
    final typing     = r.getStringValue('typing_in');
    final chat       = r.getStringValue('current_chat');
    final lastSeenStr = r.getStringValue('last_seen');
    return OtherUserPresence(
      isOnline:  r.getBoolValue('is_online'),
      isTyping:  typing.isNotEmpty && typing == convId,
      isInChat:  chat.isNotEmpty   && chat   == convId,
      lastSeen:  lastSeenStr.isEmpty
          ? null
          : DateTime.tryParse(lastSeenStr),
    );
  }

  Future<void> _patch(String uid, Map<String, dynamic> body) async {
    try {
      await _pb.collection('users').update(uid, body: body);
    } catch (e) {
      debugPrint('[Presence] patch error: $e');
    }
  }

  Future<String?> _uid() =>
      db.settingsDao.getSetting(AppSettingsKeys.currentUserId);

  void dispose() {
    _heartbeatTimer?.cancel();
    _typingTimer?.cancel();
  }
}

final presenceServiceProvider = Provider<PresenceService>((ref) {
  final svc = PresenceService(
    pbClient: ref.read(pocketbaseClientProvider),
    db:       ref.read(appDatabaseProvider),
  );
  ref.onDispose(svc.dispose);
  return svc;
});
