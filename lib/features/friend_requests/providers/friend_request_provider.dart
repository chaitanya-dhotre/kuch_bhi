import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/pocketbase_client.dart';
import '../../../core/network/realtime_subscribe.dart';
import '../../../data/local/database/app_database.dart';
import '../../../data/local/database/tables/app_settings_table.dart';
import '../../../domain/entities/friend_request.dart';
import '../../../domain/entities/group_invite.dart';
import '../../../domain/entities/user.dart';
import '../../../infrastructure/repositories/friend_repository_impl.dart';
import '../../../infrastructure/offline/connectivity_signal.dart';
import '../../../infrastructure/repositories/message_repository_impl.dart';
import '../../auth/providers/auth_provider.dart';
import '../../home/providers/friends_provider.dart';
import 'request_snapshot_cache.dart';

/// Cold-start offline cache for the Requests page (checklist H3).
final requestSnapshotCacheProvider = Provider<RequestSnapshotCache>((ref) {
  return RequestSnapshotCache(
    SettingsSnapshotStore(ref.read(appDatabaseProvider).settingsDao),
  );
});

/// Re-subscribe when the device comes back online.
///
/// A cold start with no network never completes the realtime handshake, and
/// PocketBase's client does not retry a subscribe on its own — so without
/// this the source would stay deaf for the rest of the session. The
/// connectivity signal is the trigger: going offline→online rebuilds the
/// source, which re-subscribes and re-fetches.
///
/// [generation] is the calling build's generation: only the CURRENT build
/// may rebuild, or a stale build would resurrect a disposed provider.
void watchReconnect(Ref ref, int generation, int Function() current) {
  // The connectivity signal's transition stream (not `isOnlineProvider`,
  // whose `.future` resolves only once — it cannot report a reconnect).
  //
  // Guarded: the signal needs a platform binding, which a headless test may
  // not have. A missing signal simply means no reconnect trigger — never a
  // build failure.
  Stream<bool> changes;
  try {
    changes = ref.read(connectivitySignalProvider).changes;
  } catch (_) {
    return;
  }
  final sub = changes.listen((online) {
    if (!online) return;
    if (generation != current()) return;
    ref.invalidateSelf();
  });
  ref.onDispose(sub.cancel);
}

/// How long the request fetch may take before the page falls back.
///
/// PocketBase's HTTP client has NO request timeout: a blackholed socket
/// (the "wifi up but no internet" / captive-portal case) never completes,
/// so `getIncomingRequests()` would hang forever and the page would sit on
/// its skeleton with a perfectly good snapshot on disk. Bounding the fetch
/// turns that into the offline path: the snapshot renders (H3), or — with no
/// snapshot — the error state (B3).
const _fetchTimeout = Duration(seconds: 8);

/// Session-scoping for the two request sources (H3 review finding H3-3).
///
/// These providers are NOT auto-disposed, so their state (and their realtime
/// subscription) survives a sign-out. Without this seam, a second user
/// signing in on the same process could read the FIRST user's rows straight
/// out of the notifier's in-memory state — a cross-user data disclosure.
///
/// Each notifier listens for an auth transition and rebuilds ITSELF. The
/// invalidation is deferred to a microtask because the auth transition can be
/// notified while the provider is still building, and invalidating a
/// provider from inside its own build is a circular dependency in riverpod.
///
/// The snapshot itself is namespaced per user id, so the on-disk copy is
/// isolated too.
/// Rebuilds the source under a new session and DROPS the previous
/// session's rows.
///
/// Two things are needed for a session change to be safe:
///
/// 1. The source must rebuild under the new session (otherwise the old
///    rows keep rendering).
/// 2. The previous session's rows must not SURVIVE the rebuild. Riverpod's
///    `copyWithPrevious` retains the previous value inside the new state —
///    including inside an `AsyncError` (`AsyncError.copyWithPrevious` keeps
///    `previous.valueOrNull`). So a rebuild whose fetch FAILS would produce
///    an error state that still carries the FIRST user's rows, and the
///    screen renders them (it reads `valueOrNull`).
///
/// [clearPrevious] resets the source's state to a plain, value-less
/// `AsyncLoading` before the rebuild, so nothing from the old session can
/// leak into the new one.
void watchSessionScope(
  Ref ref,
  void Function() rebuild,
  void Function() clearPrevious,
) {
  ref.listen<AsyncValue<AuthState>>(authProvider, (previous, next) {
    final prevId = _authUserId(previous);
    final nextId = _authUserId(next);
    if (prevId == nextId) return;
    scheduleMicrotask(() {
      clearPrevious();
      rebuild();
    });
  });
}

String? _authUserId(AsyncValue<AuthState>? value) {
  final state = value?.valueOrNull;
  if (state is AuthAuthenticated) return state.user.id;
  return null;
}

/// Watches incoming friend requests with proper subscription lifecycle.
class IncomingRequestsNotifier
    extends AsyncNotifier<List<FriendRequest>> {
  /// Bumped on every build AND on dispose.
  ///
  /// Riverpod REUSES a notifier instance across `invalidateSelf`, so a plain
  /// `bool _disposed` would stay `true` after the first rebuild — and the
  /// subscribe helper would then drop a listener that belongs to a LIVE
  /// provider (re-creating the R1 symptom). A generation counter gives each
  /// build its own identity: the helper only abandons a subscribe whose
  /// generation is no longer the current one.
  int _generation = 0;

  /// The session user id the current snapshot belongs to. Resolved once per
  /// load so the accept/decline eviction path never has to re-read the DB.
  String? _sessionUserId;

  /// Bumped on every accept/decline — the "action generation" fencing an
  /// in-flight load against (see [IncomingRequestsNotifier._load]).
  int _actionGeneration = 0;

  @override
  Future<List<FriendRequest>> build() async {
    final generation = ++_generation;
    // Scope this source to the current session (H3-3): a sign-out / new
    // sign-in must rebuild it rather than serve the previous user's rows.
    watchSessionScope(
      ref,
      () => ref.invalidateSelf(),
      () => state = const AsyncLoading(),
    );
    final pb = ref.read(pocketbaseClientProvider).pb;

    // The data load runs CONCURRENTLY with the realtime handshake: the
    // handshake is bounded (4s) and the load is what the page renders, so
    // awaiting the handshake first would add its full timeout to the
    // skeleton on every offline cold start.
    final load = _load();

    // R1 fix: the helper removes ONLY its own listener. The topic-less
    // `collection.unsubscribe()` maps to realtime.unsubscribeByPrefix, which
    // removes EVERY listener on `friend_requests/*` — including
    // FriendQueryService's, so one invalidateSelf (e.g. after a decline)
    // silently killed the home screen's live friend updates.
    //
    // A failed subscribe (no network at cold start) must NOT fail the page —
    // H3 requires the cached list to render offline. Live updates resume on
    // the next successful build.
    unawaited(
      subscribeWithTimeout(
        pb,
        'friend_requests',
        () => _refresh(),
        ref.onDispose,
        isAbandoned: () => generation != _generation,
      ),
    );

    // Re-establish live updates when the device comes back online: a cold
    // start with no network never completes the handshake, and without this
    // the page would stay deaf for the rest of the session (no SSE, no
    // refresh) until the user pulled to refresh or acted on a card.
    watchReconnect(ref, generation, () => _generation);

    return load;
  }

  /// Network-first, cache-fallback (H3).
  ///
  /// A successful fetch refreshes the snapshot. A failed fetch falls back to
  /// the last-good snapshot so a cold start without the network renders the
  /// last list instead of an error; when there is NO snapshot at all, the
  /// error propagates and the page shows the full-error state (B3).
  ///
  /// An EMPTY snapshot is not an error: it means the last known state was
  /// "nothing pending", so the page settles into the empty state (G1)
  /// instead of the error state.
  Future<List<FriendRequest>> _load() async {
    final actionGeneration = _actionGeneration;
    final userId = await _currentUserId();
    _sessionUserId = userId;
    final List<FriendRequest> rows;
    try {
      rows = await ref
          .read(friendRepositoryProvider)
          .getIncomingRequests()
          .timeout(_fetchTimeout);
    } catch (_) {
      // Prefer the live list over the snapshot: after a rebuild it holds the
      // last good rows, which are strictly fresher than the snapshot whose
      // own write may have failed. Only a genuinely value-less state (a cold
      // start) falls back to the snapshot — the H3 offline path.
      final live = state.valueOrNull;
      if (live != null) return live;
      final cached = await _readCache(userId);
      if (cached != null) return cached;
      rethrow;
    }
    // A payload fetched BEFORE an accept/decline must not be snapshotted —
    // the server already handled that row, so the snapshot would resurrect
    // it at the next cold start (H3-1). Publishing is fenced in _refresh.
    if (actionGeneration != _actionGeneration) return rows;
    // Refreshing the snapshot must never fail the fetch itself.
    await _writeCache(userId, rows);
    return rows;
  }

  Future<List<FriendRequest>?> _readCache(String? userId) async {
    if (userId == null || userId.isEmpty) return null;
    try {
      return await ref.read(requestSnapshotCacheProvider).readRequests(userId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(String? userId, List<FriendRequest> rows) async {
    if (userId == null || userId.isEmpty) return;
    try {
      await ref.read(requestSnapshotCacheProvider).writeRequests(userId, rows);
    } catch (_) {
      // A cache write failure is not a fetch failure.
    }
  }

  Future<String?> _currentUserId() async {
    try {
      return await ref.read(appDatabaseProvider).settingsDao.getSetting(
            AppSettingsKeys.currentUserId,
          );
    } catch (_) {
      return null;
    }
  }

  /// Realtime-triggered refresh.
  ///
  /// The SSE callback is `void Function(SseMessage)` — the returned Future is
  /// DISCARDED, so an exception here would escape into the zone as an
  /// unhandled async error (invisible to the user and to the error
  /// reporting). A failed refresh therefore keeps the last good state and
  /// reports nothing; the next event (or a pull-to-refresh) retries.
  Future<void> _refresh() async {
    // Fence against a racing accept/decline: this fetch resolves with a
    // payload captured BEFORE the action, so publishing it would resurrect
    // the just-handled row (H3-1). Discarding the whole refresh is right —
    // the action's own rebuild refetched the truthful list already.
    final actionGeneration = _actionGeneration;
    try {
      final rows = await _load();
      if (actionGeneration != _actionGeneration) return;
      state = AsyncData(rows);
    } catch (_) {
      // A realtime refresh that fails is not a page-level error — the list
      // on screen stays as it was.
    }
  }

  /// Test seam for [ _refresh ]: the SSE callback is private.
  @visibleForTesting
  Future<void> refreshForTest() => _refresh();

  Future<void> accept(String id) async {
    _actionGeneration++;
    // PocketBase's HTTP client has no request timeout: a blackholed socket
    // would hang this handler forever, and the card's busy lock is only
    // released in its finally — so the card would stay dead until the app
    // restarted. Bounding it lets the caller's catch show the failure toast.
    await ref
        .read(friendRepositoryProvider)
        .acceptRequest(id)
        .timeout(_fetchTimeout);
    // The server handled this row — drop it from the snapshot BEFORE the
    // rebuild, so a failing refetch cannot resurrect it (H3).
    await _evictFromCache(id);
    ref.invalidateSelf();
    ref.invalidate(friendshipsProvider);
  }

  Future<void> decline(String id) async {
    _actionGeneration++;
    await ref
        .read(friendRepositoryProvider)
        .declineRequest(id)
        .timeout(_fetchTimeout);
    await _evictFromCache(id);
    ref.invalidateSelf();
  }

  /// Remove a handled row from the local snapshot (best effort — a cache
  /// failure must never fail the action the user just took).
  Future<void> _evictFromCache(String requestId) async {
    final userId = _sessionUserId;
    if (userId == null || userId.isEmpty) return;
    try {
      await ref
          .read(requestSnapshotCacheProvider)
          .removeRequest(userId, requestId);
    } catch (_) {
      // Best effort.
    }
  }
}

final incomingRequestsProvider =
    AsyncNotifierProvider<IncomingRequestsNotifier, List<FriendRequest>>(
  IncomingRequestsNotifier.new,
);

/// Watches incoming group invites with proper subscription lifecycle.
///
/// subscribe('*') may also deliver events for invites in conversations the
/// user admins (their outgoing invites); `_refresh` always refetches only MY
/// pending incoming invites, so those events just cause a harmless refetch.
class IncomingGroupInvitesNotifier extends AsyncNotifier<List<GroupInvite>> {
  /// Bumped on every build — see IncomingRequestsNotifier._generation.
  int _generation = 0;

  /// The session user id the current snapshot belongs to — see
  /// IncomingRequestsNotifier._sessionUserId.
  String? _sessionUserId;

  /// Bumped on every accept/decline — see
  /// IncomingRequestsNotifier._actionGeneration.
  int _actionGeneration = 0;

  @override
  Future<List<GroupInvite>> build() async {
    final generation = ++_generation;
    // Scope this source to the current session (H3-3) — see the friend
    // requests notifier.
    watchSessionScope(
      ref,
      () => ref.invalidateSelf(),
      () => state = const AsyncLoading(),
    );
    final pb = ref.read(pocketbaseClientProvider).pb;

    // The data load runs CONCURRENTLY with the realtime handshake — see
    // IncomingRequestsNotifier.build.
    final load = _load();

    // R1 fix: scoped unsubscribe — see IncomingRequestsNotifier.build.
    unawaited(
      subscribeWithTimeout(
        pb,
        'group_invites',
        () => _refresh(),
        ref.onDispose,
        isAbandoned: () => generation != _generation,
      ),
    );

    // Re-establish live updates when the device comes back online — see
    // IncomingRequestsNotifier.build.
    watchReconnect(ref, generation, () => _generation);

    return load;
  }

  /// Network-first, cache-fallback (H3) — see IncomingRequestsNotifier._load.
  Future<List<GroupInvite>> _load() async {
    final actionGeneration = _actionGeneration;
    final userId = await _currentUserId();
    _sessionUserId = userId;
    final List<GroupInvite> rows;
    try {
      rows = await ref
          .read(messageRepositoryProvider)
          .getIncomingGroupInvites()
          .timeout(_fetchTimeout);
    } catch (_) {
      final live = state.valueOrNull;
      if (live != null) return live;
      final cached = await _readCache(userId);
      if (cached != null) return cached;
      rethrow;
    }
    if (actionGeneration != _actionGeneration) return rows;
    await _writeCache(userId, rows);
    return rows;
  }

  Future<List<GroupInvite>?> _readCache(String? userId) async {
    if (userId == null || userId.isEmpty) return null;
    try {
      return await ref.read(requestSnapshotCacheProvider).readInvites(userId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(String? userId, List<GroupInvite> rows) async {
    if (userId == null || userId.isEmpty) return;
    try {
      await ref.read(requestSnapshotCacheProvider).writeInvites(userId, rows);
    } catch (_) {
      // A cache write failure is not a fetch failure.
    }
  }

  Future<String?> _currentUserId() async {
    try {
      return await ref.read(appDatabaseProvider).settingsDao.getSetting(
            AppSettingsKeys.currentUserId,
          );
    } catch (_) {
      return null;
    }
  }

  /// Realtime-triggered refresh.
  ///
  /// The SSE callback is `void Function(SseMessage)` — the returned Future is
  /// DISCARDED, so an exception here would escape into the zone as an
  /// unhandled async error (invisible to the user and to the error
  /// reporting). A failed refresh therefore keeps the last good state and
  /// reports nothing; the next event (or a pull-to-refresh) retries.
  Future<void> _refresh() async {
    // Fence against a racing accept/decline: this fetch resolves with a
    // payload captured BEFORE the action, so publishing it would resurrect
    // the just-handled row (H3-1). Discarding the whole refresh is right —
    // the action's own rebuild refetched the truthful list already.
    final actionGeneration = _actionGeneration;
    try {
      final rows = await _load();
      if (actionGeneration != _actionGeneration) return;
      state = AsyncData(rows);
    } catch (_) {
      // A realtime refresh that fails is not a page-level error — the list
      // on screen stays as it was.
    }
  }

  /// Test seam for [ _refresh ]: the SSE callback is private.
  @visibleForTesting
  Future<void> refreshForTest() => _refresh();

  Future<void> accept(String id) async {
    _actionGeneration++;
    await ref
        .read(messageRepositoryProvider)
        .acceptGroupInvite(id)
        .timeout(_fetchTimeout);
    // The server handled this row — drop it from the snapshot BEFORE the
    // rebuild, so a failing refetch cannot resurrect it (H3).
    await _evictFromCache(id);
    ref.invalidateSelf();
  }

  Future<void> decline(String id) async {
    _actionGeneration++;
    await ref
        .read(messageRepositoryProvider)
        .declineGroupInvite(id)
        .timeout(_fetchTimeout);
    // The server handled this row — drop it from the snapshot BEFORE the
    // rebuild, so a failing refetch cannot resurrect it (H3).
    await _evictFromCache(id);
    ref.invalidateSelf();
  }

  /// Remove a handled invite from the local snapshot — see
  /// IncomingRequestsNotifier._evictFromCache.
  Future<void> _evictFromCache(String inviteId) async {
    final userId = _sessionUserId;
    if (userId == null || userId.isEmpty) return;
    try {
      await ref
          .read(requestSnapshotCacheProvider)
          .removeInvite(userId, inviteId);
    } catch (_) {
      // Best effort.
    }
  }
}

final incomingGroupInvitesProvider =
    AsyncNotifierProvider<IncomingGroupInvitesNotifier, List<GroupInvite>>(
      IncomingGroupInvitesNotifier.new,
    );

/// Badge count for the home screen icon (friend requests + group invites).
final pendingRequestCountProvider = Provider<int>((ref) {
  final friends = ref.watch(incomingRequestsProvider).when(
        data: (list) => list.length,
        loading: () => 0,
        error: (_, __) => 0,
      );
  final invites = ref.watch(incomingGroupInvitesProvider).when(
        data: (list) => list.length,
        loading: () => 0,
        error: (_, __) => 0,
      );
  return friends + invites;
});

// ── Add Friend State ───────────────────────────────────────────────────────

class AddFriendState {
  const AddFriendState({
    this.foundUser,
    this.isSearching = false,
    this.searchError,
    this.requestSent = false,
    this.isSendingRequest = false,
  });

  final User? foundUser;
  final bool isSearching;
  final String? searchError;
  final bool requestSent;
  final bool isSendingRequest;

  AddFriendState copyWith({
    User? foundUser,
    bool? isSearching,
    String? searchError,
    bool? requestSent,
    bool? isSendingRequest,
    bool clearUser = false,
    bool clearError = false,
  }) =>
      AddFriendState(
        foundUser:        clearUser  ? null : foundUser  ?? this.foundUser,
        isSearching:      isSearching      ?? this.isSearching,
        searchError:      clearError ? null : searchError ?? this.searchError,
        requestSent:      requestSent      ?? this.requestSent,
        isSendingRequest: isSendingRequest ?? this.isSendingRequest,
      );
}

class AddFriendNotifier extends Notifier<AddFriendState> {
  @override
  AddFriendState build() => const AddFriendState();

  Future<void> searchByCode(String code) async {
    if (code.trim().length != 6) {
      // No clearError here: the flag beats a passed searchError.
      state = state.copyWith(
        clearUser: true,
        searchError: 'Friend code must be exactly 6 characters.',
      );
      return;
    }

    state = state.copyWith(isSearching: true, clearUser: true, clearError: true);

    try {
      final user = await ref
          .read(friendRepositoryProvider)
          .findUserByCode(code.trim().toUpperCase())
          .timeout(const Duration(seconds: 8));

      state = user == null
          ? state.copyWith(isSearching: false, searchError: 'No user found.')
          : state.copyWith(isSearching: false, foundUser: user);
    } catch (e) {
      debugPrint('Search by code error: $e');
      state = state.copyWith(
        isSearching: false,
        searchError: 'Search failed. Check your connection.',
      );
    }
  }

  Future<void> sendRequest() async {
    final user = state.foundUser;
    if (user == null) return;

    state = state.copyWith(isSendingRequest: true);

    try {
      await ref
          .read(friendRepositoryProvider)
          .sendRequest(user.id)
          .timeout(const Duration(seconds: 8));
      state = state.copyWith(isSendingRequest: false, requestSent: true);
    } catch (e) {
      debugPrint('Send request error: $e');
      state = state.copyWith(
        isSendingRequest: false,
        searchError: "Couldn't send the request. Try again.",
      );
    }
  }

  void reset() => state = const AddFriendState();
}

final addFriendProvider =
    NotifierProvider<AddFriendNotifier, AddFriendState>(AddFriendNotifier.new);
