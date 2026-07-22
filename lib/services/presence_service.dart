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

  DateTime? _lastTypingPatch;

  Future<void> onTyping(String conversationId) async {
    final uid = await _uid(); if (uid == null) return;
    final now = DateTime.now();
    // Patch on first keystroke, then RENEW every 4s while typing continues.
    // Recipients expire the indicator locally 6s after the last renewal, so
    // a killed app can never leave a permanent "Typing..." on other devices.
    final needsPatch = !_isTyping ||
        _lastTypingPatch == null ||
        now.difference(_lastTypingPatch!).inSeconds >= 4;
    if (needsPatch) {
      _isTyping = true;
      _lastTypingPatch = now;
      await _patch(uid, {'typing_in': conversationId});
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () async {
      _isTyping = false;
      _lastTypingPatch = null;
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
    Timer? typingExpiry;
    OtherUserPresence? last;

    void emit(OtherUserPresence p) {
      if (ctrl.isClosed) return;
      last = p;
      ctrl.add(p);

      // The sender renews typing_in every ≤2s while actively typing. If the
      // app is killed mid-typing the clear never reaches the server, so we
      // expire typing locally when no renewal arrives within 6s.
      typingExpiry?.cancel();
      if (p.isTyping) {
        typingExpiry = Timer(const Duration(seconds: 6), () {
          if (ctrl.isClosed || last == null) return;
          ctrl.add(OtherUserPresence(
            isOnline: last!.isOnline,
            isTyping: false,
            isInChat: last!.isInChat,
            lastSeen: last!.lastSeen,
          ));
        });
      }
    }

    // Emit initial state.
    _pb.collection('users').getOne(otherUserId).then((r) {
      emit(_toPresence(r, conversationId));
    }).catchError((e) {
      debugPrint('[Presence] initial fetch: $e');
      return null;
    });

    // Subscribe to live updates.
    _pb.collection('users').subscribe(otherUserId, (event) {
      if (event.record == null || ctrl.isClosed) return;
      emit(_toPresence(event.record!, conversationId));
    }).catchError((e) {
      debugPrint('[Presence] subscribe: $e');
      return () async {};
    });

    ctrl.onCancel = () {
      typingExpiry?.cancel();
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
