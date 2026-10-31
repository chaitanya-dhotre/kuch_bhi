import 'dart:async';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pocketbase/pocketbase.dart' show ClientException, PocketBase;

import '../../core/constants/app_constants.dart';
import '../../core/network/pocketbase_client.dart';
import '../../core/utils/session_epoch.dart';
import '../../data/local/database/app_database.dart';
import '../../data/local/database/daos/media_blob_dao.dart';
import '../../data/local/database/daos/messages_dao.dart';
import '../../data/local/database/tables/media_blob_table.dart';
import '../../services/encryption_service.dart';
import '../../services/media_upload_service.dart';

/// Blob id for a media variant: `'<messageServerId>_f'` (full) or
/// `'<messageServerId>_t'` (thumbnail) — the same identity the legacy
/// `media_clear` cache prefix used (`'<serverId>_<f|t>_' + fileName`).
String mediaBlobId(String serverId, {required bool thumb}) =>
    '$serverId${thumb ? '_t' : '_f'}';

/// How long a media network call may stay silent before it counts as offline.
const _stallBound = Duration(seconds: 8);

/// MediaBlobStore — SOLE writer of blob rows + files (spec §4/§9).
///
/// Single entry point: [requestBlob] — every consumer (bubbles, viewer,
/// docs grid, future auto-download policies) calls this and nothing else
/// touches the store. Maintenance surfaces: [janitor] (startup — stale
/// `downloading` rows + orphan temp files) and [evictIfNeeded] (deferred
/// LRU eviction, never awaited by the write path).
///
/// FSM (spec §9): `queued → downloading → ready`; offline stays
/// `queued` (auto-resume on reconnect — failed ≠ offline); `failed`
/// carries `error_class` ∈ {dead_link, expired, verify, decrypt} and is
/// terminal; `evicted` = bytes dropped, metadata retained.
///
/// Spec §11 (fix round 1/I1): EVERY dao write and file write is gated by
/// [sessionStillValid] against the injected [epoch] seam — in-flight work
/// from a logged-out session aborts silently instead of repopulating the
/// logout wipe.
class MediaBlobStore {
  MediaBlobStore({
    required this.dao,
    required this.messages,
    required this.pbClient,
    required this.encryption,
    required Future<List<int>> Function(String conversationId) resolveKey,
    required int Function() epoch,
    Future<Directory> Function()? cacheDir,
    http.Client? httpClient,
  })  : _resolveKey = resolveKey,
        _epoch = epoch,
        _cacheDir = cacheDir ?? getTemporaryDirectory,
        _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null {
    // Startup maintenance (spec §9): janitor + first eviction pass, kicked
    // at construction — the store is built at app start (OutboxWorker
    // precedent). Never throws; tests await [ready].
    ready = _maintenance();
    // Auto-resume (spec §9): offline stays `queued`, drains on reconnect.
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        unawaited(onConnectivityRestored());
      }
    });
  }

  final MediaBlobDao dao;
  final MessagesDao messages;
  final PocketBaseClient pbClient;
  final EncryptionService encryption;
  final Future<List<int>> Function(String conversationId) _resolveKey;

  /// Session-epoch seam (spec §11): the repo's live `_sessionEpoch`
  /// counter; bumped on every auth identity change / logout. Tests inject
  /// a mutable holder.
  final int Function() _epoch;

  /// App-private parent dir (moved convention: `getTemporaryDirectory()` —
  /// the store then uses `<parent>/media_clear` exactly like the moved
  /// code). Tests inject a temp-dir factory.
  final Future<Directory> Function() _cacheDir;
  final http.Client _httpClient;
  final bool _ownsHttpClient;

  /// Completion of the construction-time janitor + eviction pass.
  late final Future<void> ready;

  StreamSubscription<List<ConnectivityResult>>? _connSub;

  /// In-flight pipelines keyed by blobId — concurrent [requestBlob] calls
  /// for the same blob coalesce into ONE download.
  final _inflight = <String, Future<LocalMediaFile?>>{};

  PocketBase get _pb => pbClient.pb;

  // ── Spec §11 write gate ─────────────────────────────────────────────────

  /// true ⇒ the session that captured [epochAtStart] is still current and
  /// the caller may write; false ⇒ ABORT silently (log, no throw).
  /// Repo precedent: `sessionStillValid` guards at
  /// message_repository_impl.dart (Review C1) — an async op spanning a
  /// logout must never repopulate the wiped store.
  bool _stillValid(int epochAtStart, String what) {
    if (sessionStillValid(
      epochAtStart: epochAtStart,
      currentEpoch: _epoch(),
      authValid: _pb.authStore.isValid,
    )) {
      return true;
    }
    debugPrint('[Media] $what skipped — session ended mid-flight '
        '(spec §11)');
    return false;
  }

  // ── Entry point (spec §9 SINGLE entry) ──────────────────────────────────

  /// State check inside → download / restore / no-op as needed.
  /// Returns the decrypted file, or null (offline, failed terminal, the
  /// `message_media` record has not landed yet — upload race #18, or the
  /// session ended mid-request).
  Future<LocalMediaFile?> requestBlob(String blobId, String reason) async {
    final epochAtStart = _epoch();
    var row = await dao.byId(blobId);
    if (row == null) {
      // First request: derive the message id from the blob id and create
      // the row (`'srv1_f'` → message `'srv1'`).
      final serverId = _parseBlobId(blobId).$1;
      if (!_stillValid(epochAtStart, 'blob row create')) return null;
      await dao.insert(MediaBlobTableCompanion.insert(
        blobId: blobId,
        messageId: serverId,
        lastAccess: DateTime.now(),
      ));
      row = await dao.byId(blobId);
      // Row gone = the logout wipe deleted it mid-request (spec §11) —
      // abort instead of the old `row!` NPE.
      if (row == null) return null;
    }

    // Terminal (spec §9): `failed` is NEVER auto-retried — only an
    // explicit future policy layer can move it.
    if (row.state == BlobState.failed) return null;

    // Coalesce: an in-flight pipeline (whatever state the row shows —
    // including a stale `downloading` whose process-local future is gone)
    // is shared by every concurrent caller.
    final existing = _inflight[blobId];
    if (existing != null) return existing;

    debugPrint('[Media] requestBlob $blobId reason=$reason '
        'state=${row.state.name}');
    final run = _runPipeline(row);
    _inflight[blobId] = run;
    try {
      return await run;
    } finally {
      _inflight.remove(blobId);
    }
  }

  // ── Pipeline: download → size/hash verify → decrypt (spec §9) ──────────

  Future<LocalMediaFile?> _runPipeline(MediaBlobTableData row) async {
    final blobId = row.blobId;
    // Spec §11: capture BEFORE the first state write; every later write in
    // this pipeline re-checks against this capture.
    final epochAtStart = _epoch();
    final (serverId, thumb) = _parseBlobId(blobId);
    final prefix = '${serverId}_${thumb ? 't' : 'f'}_';
    if (!_stillValid(epochAtStart, 'downloading write')) return null;
    await dao.setState(blobId, BlobState.downloading);
    try {
      // ── Cleartext cache + fast path — MOVED VERBATIM from
      // MediaUploadService.getDecryptedMedia (guard 5: body unchanged
      // except the two `getTemporaryDirectory`/`http.get` seams and the
      // §11 epoch gates, ledgered in the handoff). ──
      final cacheDir = await _cacheDir();
      final mediaCache = Directory('${cacheDir.path}/media_clear');
      if (!await mediaCache.exists()) {
        if (!_stillValid(epochAtStart, 'cache dir create')) return null;
        await mediaCache.create(recursive: true);
      }
      await for (final entity in mediaCache.list()) {
        if (entity is File && p.basename(entity.path).startsWith(prefix)) {
          if (!_stillValid(epochAtStart, 'fast-path ready write')) {
            return null;
          }
          await dao.setState(
            blobId,
            BlobState.ready,
            bytes: await entity.length(),
            localPath: entity.path,
            lastAccess: DateTime.now(),
          );
          return LocalMediaFile(
            file: entity,
            fileName: p.basename(entity.path),
          );
        }
      }

      // ── Record lookup — MOVED call. 404 here means the `message_media`
      // record has not landed yet (upload race #18): stay QUEUED so the
      // mediaArrived retry can succeed — this is NOT dead_link, unless the
      // message is over a day old (below). ──
      final record = await _lookupRecord(serverId);
      if (record == null) {
        // A day after sending, the record is not about to land: the server
        // purged it (expired) or the upload never finished. Either way no
        // retry can help, so this one is terminal.
        final sent = (await messages.getMessageByServerId(serverId))?.createdAt;
        if (sent != null &&
            DateTime.now().difference(sent) > const Duration(days: 1)) {
          await _fail(epochAtStart, blobId, 'dead_link');
          return null;
        }
        if (!_stillValid(epochAtStart, 'record-404 queue write')) {
          return null;
        }
        await dao.setState(blobId, BlobState.queued);
        return null;
      }

      String? readFile(dynamic data) {
        if (data is String) return data;
        if (data is List && data.isNotEmpty) return data.first.toString();
        return null;
      }

      final storedName =
          readFile(record.data[thumb ? 'thumbnail' : 'file']);
      if (storedName == null || storedName.isEmpty) {
        if (!_stillValid(epochAtStart, 'missing-file queue write')) {
          return null;
        }
        await dao.setState(blobId, BlobState.queued);
        return null;
      }

      final iv = record.getStringValue(thumb ? 'thumb_iv' : 'file_iv');

      // Strip the .enc suffix for the local file so viewers/open-external
      // get a sensible extension. — MOVED
      final localName = storedName.endsWith('.enc')
          ? storedName.substring(0, storedName.length - 4)
          : storedName;
      final localFile = File('${mediaCache.path}/$prefix$localName');

      if (!await localFile.exists()) {
        final url =
            '${_pb.baseUrl}/api/files/message_media/${record.id}/$storedName';
        // Seam: the injectable store client (MockClient test seam — brief
        // test 1).
        // A stall bound, not a size bound (files reach 100 MB): 8s with no
        // headers, or with no new bytes, throws into the catch → queued.
        // The abort closes the socket too, so a late answer is not left open.
        final abort = Completer<void>();
        TimeoutException stalled() {
          if (!abort.isCompleted) abort.complete();
          return TimeoutException('media download stalled', _stallBound);
        }

        final streamed = await _httpClient
            .send(http.AbortableRequest('GET', Uri.parse(url),
                abortTrigger: abort.future)
              ..headers['Authorization'] = _pb.authStore.token)
            .timeout(_stallBound, onTimeout: () => throw stalled());
        final resp = http.Response.bytes(
          await http.ByteStream(streamed.stream.timeout(_stallBound,
                  onTimeout: (sink) => sink
                    ..addError(stalled())
                    ..close()))
              .toBytes(),
          streamed.statusCode,
        );
        if (resp.statusCode != 200) {
          // MOVED diagnostic line.
          debugPrint('[Media] download failed ${resp.statusCode} for $url');
          // spec §9 classes: 404 → dead_link (remote gone); 401/403 →
          // expired (access revoked / retention); 5xx + rest → transient →
          // queued (offline ≠ failed).
          if (resp.statusCode == 404) {
            await _fail(epochAtStart, blobId, 'dead_link');
          } else if (resp.statusCode == 401 || resp.statusCode == 403) {
            await _fail(epochAtStart, blobId, 'expired');
          } else {
            await _safeQueued(epochAtStart, blobId);
          }
          return null;
        }

        // NEW crash artifact: a kill between download and commit leaves
        // ONLY this file — the startup janitor deletes it (spec §9).
        final part = File('${mediaCache.path}/$blobId.part');
        if (!_stillValid(epochAtStart, 'temp write')) return null;
        await part.writeAsBytes(resp.bodyBytes, flush: true);

        // NEW verify stage (spec §9: download → size/hash verify → decrypt).
        if (!_verifySync(resp.bodyBytes, row)) {
          await _fail(epochAtStart, blobId, 'verify');
          await _deleteQuietly(epochAtStart, part);
          return null;
        }

        // ── Decrypt — MOVED body (the `convKey` parameter became the
        // lazy resolveKey lookup; MissingKey → outer catch → queued). ──
        late final List<int> clear;
        if (iv.isEmpty) {
          // Legacy plaintext upload.
          clear = resp.bodyBytes;
        } else {
          final msg = await messages.getMessageByServerId(serverId);
          if (msg == null) {
            await _safeQueued(epochAtStart, blobId);
            await _deleteQuietly(epochAtStart, part);
            return null;
          }
          final convKey = await _resolveKey(msg.conversationId);
          final dec =
              await encryption.decryptBytes(resp.bodyBytes, iv, convKey);
          if (dec == null) {
            // MOVED diagnostic (record.id → record.id, same message).
            debugPrint(
                '[Media] decrypt failed for ${record.id} (thumb=$thumb)');
            await _fail(epochAtStart, blobId, 'decrypt');
            await _deleteQuietly(epochAtStart, part);
            return null;
          }
          clear = dec;
        }
        // MOVED write: decrypted bytes land ONLY at the final path.
        if (!_stillValid(epochAtStart, 'cleartext write')) return null;
        await localFile.writeAsBytes(clear, flush: true);
        await _deleteQuietly(epochAtStart, part);
      }

      // ── Metadata return — MOVED. ──
      final expiresRaw = record.data['expires_at']?.toString() ?? '';
      int? asInt(dynamic v) =>
          v == null ? null : int.tryParse(v.toString());
      final expiresAt = expiresRaw.isEmpty
          ? null
          : DateTime.tryParse(expiresRaw)?.toLocal();
      final result = LocalMediaFile(
        file: localFile,
        width: asInt(record.data['image_width']) ??
            asInt(record.data['video_width']),
        height: asInt(record.data['image_height']) ??
            asInt(record.data['video_height']),
        durationSeconds: asInt(record.data['duration_seconds']),
        expiresAt: expiresAt,
        mimeType: record.data['mime_type']?.toString(),
        fileName: record.getStringValue('file_name'),
      );

      if (!_stillValid(epochAtStart, 'ready write')) return null;
      await dao.setState(
        blobId,
        BlobState.ready,
        bytes: await localFile.length(),
        localPath: localFile.path,
        lastAccess: DateTime.now(),
        remoteRef: '${record.id}/$storedName',
      );
      // Deferred watermark trigger (spec §9): the eviction pass itself is
      // NEVER awaited by this write path.
      await _maybeEvictDeferred();
      return result;
    } catch (e) {
      // MOVED diagnostic line.
      debugPrint('[Media] getDecryptedMedia error: $e');
      // Offline / missing key / transient transport → queued (auto-resume
      // on reconnect; the catch NEVER produces a failed class).
      await _safeQueued(epochAtStart, blobId);
      return null;
    }
  }

  // ── Record lookup (thin wrapper over the moved SDK call) ───────────────

  /// `getFirstListItem(message_id="…")` → null when the server says 404
  /// (record not landed yet / unknown id); other failures rethrow into
  /// the pipeline's transient catch.
  Future<dynamic> _lookupRecord(String serverId) async {
    try {
      return await _pb
          .collection('message_media')
          .getFirstListItem('message_id="$serverId"')
          .timeout(_stallBound);
    } on ClientException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  // ── Verify (spec §9) ────────────────────────────────────────────────────

  /// Size/hash verify of the DOWNLOADED bytes against the blob row's
  /// expectations (null = unknown → pass). Hash: sha256 lowercase hex.
  bool _verifySync(List<int> downloaded, MediaBlobTableData row) {
    if (row.expectedSize != null && downloaded.length != row.expectedSize) {
      return false;
    }
    if (row.expectedHash != null) {
      final digest = Sha256().toSync().hashSync(downloaded);
      final hex = digest.bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      if (hex.toLowerCase() != row.expectedHash!.toLowerCase()) return false;
    }
    return true;
  }

  // ── Startup janitor (spec §9) ───────────────────────────────────────────

  /// Stale `downloading` rows → `queued` (process died mid-pipeline);
  /// orphan `.part` temp files deleted. Construction-time kick exposes
  /// its completion as [ready]. Spec §11: epoch captured at entry, every
  /// write re-checked against it.
  Future<void> janitor() async {
    final epochAtStart = _epoch();
    if (!_stillValid(epochAtStart, 'janitor reset')) return;
    await dao.resetDownloadingToQueued();
    final Directory cacheDir;
    try {
      cacheDir = await _cacheDir();
    } catch (_) {
      // No app dir yet (pre-init / test harness without path_provider) —
      // nothing to sweep, stay silent.
      return;
    }
    try {
      final mediaCache = Directory('${cacheDir.path}/media_clear');
      if (!await mediaCache.exists()) return;
      await for (final entity in mediaCache.list()) {
        if (entity is File && entity.path.endsWith('.part')) {
          // Per-iteration §11 re-check — a logout mid-sweep stops the
          // remaining deletes.
          if (!_stillValid(epochAtStart, 'janitor temp delete')) return;
          await _deleteQuietly(epochAtStart, entity);
        }
      }
    } catch (e) {
      debugPrint('[Media] janitor temp sweep failed: $e');
    }
  }

  // ── Deferred eviction (spec §9) ─────────────────────────────────────────

  /// LRU eviction over the `ready` bytes total: while total >
  /// [kMediaCacheMaxBytes], drop the oldest UNPROTECTED row — file
  /// deleted, state → `evicted`, metadata retained. Protected is the
  /// DERIVED predicate (spec §5.3, computed here — no column):
  /// `upload_pending ∨ message.starred ∨ message.pinned`.
  /// Spec §11: epoch captured at entry; re-checked before EACH file
  /// delete and EACH `evicted` state write.
  Future<void> evictIfNeeded() async {
    final epochAtStart = _epoch();
    var total = await dao.readyTotalBytes();
    if (total <= kMediaCacheMaxBytes) return;
    final candidates = await dao.readyLru(); // oldest lastAccess first
    for (final row in candidates) {
      if (total <= kMediaCacheMaxBytes) break;
      if (await _isProtected(row)) continue;
      if (row.localPath != null && row.localPath!.isNotEmpty) {
        if (!_stillValid(epochAtStart, 'evict file delete')) return;
        final file = File(row.localPath!);
        try {
          if (await file.exists()) await file.delete();
        } catch (e) {
          debugPrint(
              '[Media] evict delete failed for ${row.blobId}: $e');
          // Bytes still on disk — do NOT lie with `evicted`.
          continue;
        }
      }
      // Metadata kept (bytes/localPath/lastAccess untouched — setState
      // writes only what it is handed).
      if (!_stillValid(epochAtStart, 'evicted state write')) return;
      await dao.setState(row.blobId, BlobState.evicted);
      total -= row.bytes;
    }
  }

  /// Derived protection predicate — evaluated at eviction time (spec §5.3:
  /// "computed at eviction time so it cannot drift").
  Future<bool> _isProtected(MediaBlobTableData row) async {
    if (row.uploadPending) return true;
    if (row.messageId.isEmpty) return false;
    final msg = await messages.getMessageByServerId(row.messageId);
    return msg?.isStarred == true || msg?.isPinned == true;
  }

  // ── Connectivity auto-resume (spec §9) ──────────────────────────────────

  /// Connectivity restored: drain every `queued` row through the single
  /// entry (auto-resume — failed ≠ offline). Returns the drain future so
  /// tests can observe `downloading → ready`. Spec §11: epoch captured at
  /// entry — a logout mid-drain stops the REMAINING requestBlob starts.
  Future<void> onConnectivityRestored() async {
    final epochAtStart = _epoch();
    debugPrint('[Media] Connectivity restored. Draining queued blobs.');
    final queued = await dao.byState(BlobState.queued);
    for (final row in queued) {
      if (!_stillValid(epochAtStart, 'connectivity drain')) return;
      await requestBlob(row.blobId, 'connectivity-restored');
    }
  }

  // ── Internals ───────────────────────────────────────────────────────────

  Future<void> _maintenance() async {
    try {
      await janitor();
    } catch (e) {
      debugPrint('[Media] janitor failed: $e');
    }
    try {
      await evictIfNeeded();
    } catch (e) {
      debugPrint('[Media] startup eviction failed: $e');
    }
  }

  Future<void> _fail(
      int epochAtStart, String blobId, String errorClass) async {
    if (!_stillValid(epochAtStart, 'failed write')) return;
    await dao.setState(blobId, BlobState.failed, errorClass: errorClass);
  }

  Future<void> _safeQueued(int epochAtStart, String blobId) async {
    if (!_stillValid(epochAtStart, 'queued write')) return;
    try {
      await dao.setState(blobId, BlobState.queued);
    } catch (_) {
      // DB going away (teardown race) — nothing sane left to write.
    }
  }

  Future<void> _deleteQuietly(int epochAtStart, File file) async {
    if (!_stillValid(epochAtStart, 'temp delete')) return;
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best-effort cleanup — the janitor sweeps leftovers next start.
    }
  }

  /// Watermark check AFTER a successful `ready` write — the eviction pass
  /// itself is kicked fire-and-forget, never awaited by the write path
  /// (spec §9: trigger deferred, never on the write path).
  Future<void> _maybeEvictDeferred() async {
    try {
      final total = await dao.readyTotalBytes();
      if (total > kMediaCacheMaxBytes * kMediaCacheWatermark) {
        unawaited(evictIfNeeded().catchError((Object e) {
          debugPrint('[Media] deferred eviction error: $e');
        }));
      }
    } catch (_) {
      // Size probe is best-effort — eviction still runs at next app start.
    }
  }

  /// `'srv1_f'` → `(serverId: 'srv1', thumb: false)`; `'srv1_t'` → thumb.
  /// Server ids are 15-char `[a-z0-9]` (no underscores) — split is safe.
  (String, bool) _parseBlobId(String blobId) {
    if (blobId.endsWith('_t')) {
      return (blobId.substring(0, blobId.length - 2), true);
    }
    if (blobId.endsWith('_f')) {
      return (blobId.substring(0, blobId.length - 2), false);
    }
    return (blobId, false);
  }

  /// Cancels the connectivity subscription and closes the owned HTTP
  /// client (tests).
  void dispose() {
    _connSub?.cancel();
    _connSub = null;
    if (_ownsHttpClient) _httpClient.close();
  }
}
