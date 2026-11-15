import 'dart:async';
import '../voice_body.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';
import 'package:video_compress/video_compress.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/app_haptic.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/busy_spinner.dart';
import '../../../core/widgets/press_scale.dart';
import '../../../domain/entities/message.dart';
import '../../../domain/repositories/message_repository.dart';
import '../../../infrastructure/repositories/message_repository_impl.dart';
import '../../../services/media_upload_service.dart';
import '../../../services/share_in_service.dart';
import '../../media/screens/media_edit_screen.dart';
import '../../share/share_payload.dart';
import '../message_offline_policy.dart';
import '../providers/chat_provider.dart';
import '../providers/voice_recorder_providers.dart';
import '../voice_draft_store.dart';
import '../../stickers/sticker_widgets.dart';
import 'attach_sheets.dart';
import 'reply_quote.dart';
import 'voice_recorder_panel.dart';
import 'voice_waveform.dart';

// ── Recording state ────────────────────────────────────────────────────────

enum _VoiceState { idle, holding, locked, paused, preview }

class MessageInput extends ConsumerStatefulWidget {
  const MessageInput({
    super.key,
    required this.onSend,
    required this.conversationId,
    this.onTyping,
    this.isLoading = false,
    this.canSendMessages = true,
    this.restrictionMessage,
    this.replySenderName,
    this.onSendFlight,
  });

  /// Motion C1: the text and the field's box on the frame of a text send,
  /// called just before [onSend].
  /// [text] is null for a voice note or a sticker.
  final void Function(String? text, Rect field)? onSendFlight;

  /// May return the send's future; a throw restores the text with a toast.
  final FutureOr<void> Function(String) onSend;
  final String conversationId;
  final VoidCallback? onTyping;
  final bool isLoading;
  final bool canSendMessages;
  final String? restrictionMessage;
  final String? replySenderName;

  @override
  ConsumerState<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends ConsumerState<MessageInput>
    with SingleTickerProviderStateMixin {
  static final Map<String, String> _drafts = {};
  final _ctrl = TextEditingController();
  bool _hasText = false;

  // ── Recording ────────────────────────────────────────────────
  late final AudioRecorder _recorder;
  late final MicPermission _micPermission;
  late final Future<Directory> Function() _voiceDraftDir;
  StreamSubscription<RecordState>? _recordStateSubscription;
  late final AppLifecycleListener _lifecycle;
  _VoiceState _voiceState = _VoiceState.idle;
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  String? _tempPath;
  bool _cancelled = false;
  double _dragOffsetX = 0;
  double _dragOffsetY = 0;
  int? _voicePointerId;
  Offset? _holdOrigin;
  int _dragAxis = 0;
  bool _stopInProgress = false;
  bool _starting = false;
  List<double> _levels = [];
  int _durationSeconds = 0;
  bool _isDraft = false;
  // L3: a voice draft save outlives the composer; reopening its chat waits.
  static final Map<String, Future<void>> _draftSaves = {};
  Timer? _draftRetry;

  // ── Preview ──────────────────────────────────────────────────
  String? _previewDuration; // e.g. '0:42'
  bool _isSendingVoice = false;

  // ── Image upload ─────────────────────────────────────────────
  bool _isUploadingImage = false;

  // ── Video upload ─────────────────────────────────────────────
  bool _isUploadingVideo = false;
  double _videoCompressProgress = 0.0;

  // ── Document upload ───────────────────────────────────────────
  bool _isUploadingDoc = false;
  int _uploadGeneration = 0;

  // ── Album upload (12.5 B6) ────────────────────────────────────
  bool _isPreparingAlbum = false;
  int _prepareIndex = 0;
  int _prepareTotal = 0;
  final List<File> _albumTempFiles = [];

  final _focusNode = FocusNode();
  final _fieldKey = GlobalKey();

  // ── Pulse animation ──────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  bool _pulseMotionInitialized = false;
  bool _pulseReducedMotion = false;

  @override
  void initState() {
    super.initState();
    _recorder = ref.read(voiceRecorderFactoryProvider)();
    _micPermission = ref.read(micPermissionProvider);
    _voiceDraftDir = ref.read(voiceDraftDirProvider);
    _recordStateSubscription = _recorder.onStateChanged().listen(
      _onRecordState,
      // The native recorder died: keep what it wrote rather than show a
      // clock running over a dead mic.
      onError: (Object _) => unawaited(_stopRecording()),
    );
    _lifecycle = AppLifecycleListener(onHide: _handleAppHide);
    _ctrl.text = _drafts[widget.conversationId] ?? '';
    _hasText = _ctrl.text.trim().isNotEmpty;
    _ctrl.addListener(() {
      final has = _ctrl.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
      if (_ctrl.text.isEmpty) {
        _drafts.remove(widget.conversationId);
      } else {
        _drafts[widget.conversationId] = _ctrl.text;
      }
      if (has) widget.onTyping?.call();
    });

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800), // motion-allow: recorder pulse
    );
    _pulseAnim = Tween<double>(
      begin: 0.7,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut)); // motion-allow: recorder pulse

    // 12.1 E1: a share handed to this chat runs once, after the first frame
    // or as soon as the picker hands it over.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadVoiceDraft());
      _takeShare();
    });
    ref.listenManual(chatShareProvider(widget.conversationId), (_, next) {
      if (next != null) Future.microtask(_takeShare);
    });
  }

  @override
  void didUpdateWidget(covariant MessageInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.canSendMessages && widget.canSendMessages) {
      // L4: a group starts unable to send until its key settles.
      unawaited(_loadVoiceDraft());
    }
    if (oldWidget.canSendMessages &&
        !widget.canSendMessages &&
        _voiceState != _VoiceState.idle) {
      // After this build: _keepVoiceAsDraft ends in a setState.
      unawaited(Future.microtask(_keepVoiceAsDraft));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (_pulseMotionInitialized && reducedMotion == _pulseReducedMotion) {
      return;
    }

    _pulseMotionInitialized = true;
    _pulseReducedMotion = reducedMotion;
    if (reducedMotion) {
      _pulseCtrl
        ..stop()
        ..value = 1.0;
    } else {
      _pulseCtrl.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    if (_ctrl.text.isNotEmpty) {
      _drafts[widget.conversationId] = _ctrl.text;
    }
    _ctrl.dispose();
    _focusNode.dispose();
    _timer?.cancel();
    _draftRetry?.cancel();
    _lifecycle.dispose();
    _trackDraftSave(widget.conversationId, _saveDraftThenDisposeRecorder());
    _pulseCtrl.dispose();
    _recordStateSubscription?.cancel();
    super.dispose();
  }

  AutoDisposeStateProvider<Message?> get _reply =>
      replyProvider(widget.conversationId);

  // ── Text send ────────────────────────────────────────────────

  /// Motion C1: where the sent message starts its flight: the text field,
  /// or the whole composer while the recorder or an upload row replaces it.
  void _reportFlight(String? text) {
    final box =
        (_fieldKey.currentContext ?? context).findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) return;
    widget.onSendFlight?.call(text, box.localToGlobal(Offset.zero) & box.size);
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    final reply = ref.read(_reply);
    _reportFlight(text);
    appHaptic(HapticsType.light);
    // Called before the reply clears: the chat screen reads it inside onSend.
    final sending = Future.sync(() => widget.onSend(text));
    _ctrl.clear();
    ref.read(_reply.notifier).state = null;
    try {
      await sending;
    } catch (_) {
      // Rejected before the row landed (offline sends queue instead): give
      // the text and the reply back rather than losing them.
      if (!mounted) return;
      if (_ctrl.text.isEmpty) _ctrl.text = text;
      ref.read(_reply.notifier).state ??= reply;
      showToast(context, "Couldn't send. Try again.", error: true);
    }
  }

  // ── Sticker send (mascot §J3) ─────────────────────────────────

  Future<void> _onStickersPressed() {
    precacheChatStickers(context);
    return _openStickerSheet();
  }

  Future<void> _openStickerSheet() => showStickerSheet(
    context,
    onSend: (sticker) async {
      _reportFlight(null);
      final reply = ref.read(_reply);
      ref.read(_reply.notifier).state = null;
      try {
        await ref
            .read(messageRepositoryProvider)
            .sendSticker(
              conversationId: widget.conversationId,
              stickerId: sticker.id,
              replyToLocalId: reply?.localId,
            );
      } catch (_) {
        // Rejected before the row landed, as a text send: give the reply back.
        if (!mounted) return;
        ref.read(_reply.notifier).state ??= reply;
        showToast(context, "Couldn't send. Try again.", error: true);
      }
    },
  );

  // ── Recording helpers ────────────────────────────────────────

  Future<void> _startRecording({bool lockImmediately = false}) async {
    // A draft still being saved for this chat would be replaced, unseen.
    if (_voiceState != _VoiceState.idle ||
        _isSendingVoice ||
        _starting ||
        _draftSaves.containsKey(widget.conversationId)) {
      return;
    }
    _starting = true;
    try {
      final status = await _micPermission.status();
      if (!mounted) return;
      if (status != PermissionStatus.granted) {
        if (status == PermissionStatus.permanentlyDenied ||
            status == PermissionStatus.restricted) {
          final open = await showConfirmDialog(
            context: context,
            title: 'Microphone is off',
            body:
                'Turn on the microphone for Kuch Bhi in your phone\'s settings to record voice notes.',
            confirmLabel: 'Open settings',
            cancelLabel: 'Not now',
          );
          if (open) await _micPermission.openSettings();
        } else {
          final requested = await _micPermission.request();
          if (mounted) {
            showToast(
              context,
              requested == PermissionStatus.granted
                  ? 'Microphone on. Hold to record.'
                  : 'Kuch Bhi needs the microphone to record voice notes.',
              error: requested != PermissionStatus.granted,
            );
          }
        }
        return;
      }

      final tmpDir = await getTemporaryDirectory();
      final path =
          '${tmpDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      _tempPath = path;
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          numChannels: 1,
          bitRate: 64000,
        ),
        path: path,
      );
      if (!mounted) {
        _deleteFileQuietly(path);
        return;
      }
      if (!widget.canSendMessages) {
        // I5 only sees a non-idle state: sending closed during start(), and
        // no panel would show under the banner that this mic is on.
        await _recorder.cancel();
        _deleteFileQuietly(path);
        _resetVoiceState();
        return;
      }
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() {
        _voiceState = _VoiceState.holding;
        _elapsed = Duration.zero;
        _levels = [];
        _durationSeconds = 0;
        _isDraft = false;
        _cancelled = false;
        _dragOffsetX = 0;
        _dragOffsetY = 0;
        _dragAxis = 0;
        _stopInProgress = false;
      });
      appHaptic(HapticsType.light);
      _startWaveTimer();
      if (lockImmediately) {
        setState(() => _voiceState = _VoiceState.locked);
        appHaptic(HapticsType.light);
      } else if (_voicePointerId == null) {
        // The finger lifted while start() was still pending: stop at once
        // (preview, or the under-1 s path).
        unawaited(_stopRecording());
      }
    } catch (_) {
      _deleteFileQuietly(_tempPath);
      _resetVoiceState();
      if (mounted) {
        showToast(
          context,
          "Couldn't start recording. The microphone may be in use.",
          error: true,
        );
      }
    } finally {
      _starting = false;
    }
  }

  void _startWaveTimer() {
    _timer?.cancel();
    final base = _elapsed;
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      if (!mounted ||
          (_voiceState != _VoiceState.holding &&
              _voiceState != _VoiceState.locked))
        return;
      final elapsed = base + Duration(milliseconds: timer.tick * 100); // motion-allow: recorder clock
      if (elapsed.inSeconds >= AppConstants.maxVoiceMessageSeconds) {
        _elapsed = const Duration(seconds: AppConstants.maxVoiceMessageSeconds);
        _timer?.cancel();
        await _stopRecording(showMaxToast: true);
        return;
      }
      setState(() => _elapsed = elapsed);
      try {
        final amplitude = await _recorder.getAmplitude();
        if (mounted &&
            (_voiceState == _VoiceState.holding ||
                _voiceState == _VoiceState.locked)) {
          setState(() => _levels = [..._levels, waveLevel(amplitude.current)]);
        }
      } catch (_) {}
    });
  }

  Future<void> _stopRecording({
    bool cancelled = false,
    bool showMaxToast = false,
  }) async {
    // Not mounted: a pointer-up can land after dispose, which has saved it.
    if (!mounted ||
        (_voiceState != _VoiceState.holding &&
            _voiceState != _VoiceState.locked) ||
        _stopInProgress)
      return;
    setState(() => _stopInProgress = true);
    _timer?.cancel();
    _timer = null;
    final elapsed = _elapsed;
    final wasCancelled = cancelled || _cancelled;
    try {
      if (wasCancelled || elapsed < const Duration(seconds: 1)) {
        await _recorder.cancel();
        _deleteFileQuietly(_tempPath);
        _resetVoiceState();
        if (!wasCancelled && mounted) showToast(context, 'Hold to record');
        return;
      }
      final path = await _recorder.stop();
      final filePath = path ?? _tempPath;
      if (filePath == null) {
        _resetVoiceState();
        return;
      }
      await _showVoicePreview(filePath, elapsed, isDraft: false);
      if (showMaxToast && mounted)
        showToast(context, 'Voice notes can be up to 5 minutes.');
    } catch (_) {
      if (!mounted) return; // dispose keeps it as a draft
      _deleteFileQuietly(_tempPath);
      _resetVoiceState();
      showToast(context, "Couldn't save the voice note.", error: true);
    } finally {
      if (mounted) setState(() => _stopInProgress = false);
    }
  }

  Future<void> _showVoicePreview(
    String filePath,
    Duration elapsed, {
    required bool isDraft,
  }) async {
    final duration = (elapsed.inMilliseconds / 1000).round();
    _durationSeconds = duration < 1 ? 1 : duration;
    if (!mounted) return;
    setState(() {
      _voiceState = _VoiceState.preview;
      _previewDuration = formatMmSs(_durationSeconds);
      _tempPath = filePath;
      _isDraft = isDraft;
      _dragOffsetX = 0;
      _dragOffsetY = 0;
      _cancelled = false;
    });
  }

  Future<void> _pauseRecording() async {
    if (_voiceState != _VoiceState.locked || _stopInProgress) return;
    try {
      await _recorder.pause();
      // A stop or a focus-loss pause may have landed during the await.
      if (!mounted || _voiceState != _VoiceState.locked || _stopInProgress) {
        return;
      }
      _timer?.cancel();
      _timer = null;
      setState(() => _voiceState = _VoiceState.paused);
    } catch (_) {
      if (mounted)
        showToast(context, "Couldn't pause the recording.", error: true);
    }
  }

  Future<void> _resumeRecording() async {
    if (_voiceState != _VoiceState.paused || _stopInProgress) return;
    try {
      await _recorder.resume();
      if (!mounted || _voiceState != _VoiceState.paused || _stopInProgress) {
        return;
      }
      setState(() => _voiceState = _VoiceState.locked);
      _startWaveTimer();
    } catch (_) {
      if (mounted)
        showToast(context, "Couldn't resume the recording.", error: true);
    }
  }

  Future<void> _stopAndListen() async {
    if (_voiceState != _VoiceState.paused || _stopInProgress) return;
    setState(() => _stopInProgress = true);
    try {
      final path = await _recorder.stop();
      final filePath = path ?? _tempPath;
      if (filePath != null)
        await _showVoicePreview(filePath, _elapsed, isDraft: false);
    } catch (_) {
      if (!mounted) return; // dispose keeps it as a draft
      _deleteFileQuietly(_tempPath);
      _resetVoiceState();
      showToast(context, "Couldn't save the voice note.", error: true);
    } finally {
      if (mounted) setState(() => _stopInProgress = false);
    }
  }

  Future<void> _sendLockedVoice() async {
    if ((_voiceState != _VoiceState.locked &&
            _voiceState != _VoiceState.paused) ||
        _stopInProgress)
      return;
    setState(() => _stopInProgress = true);
    _timer?.cancel();
    _timer = null;
    try {
      final path = await _recorder.stop();
      if (!mounted) return;
      if (path != null) _tempPath = path;
      // F3: the clock has not run through _showVoicePreview on this path.
      final seconds = (_elapsed.inMilliseconds / 1000).round();
      _durationSeconds = seconds < 1 ? 1 : seconds;
      _previewDuration = formatMmSs(_durationSeconds);
      await _sendVoice();
    } catch (_) {
      if (!mounted) return;
      _deleteFileQuietly(_tempPath);
      _resetVoiceState();
      showToast(context, "Couldn't save the voice note.", error: true);
    } finally {
      if (mounted) setState(() => _stopInProgress = false);
    }
  }

  void _deleteFileQuietly(String? path) {
    if (path == null) return;
    try {
      File(path).deleteSync();
    } catch (_) {}
  }

  Future<void> _discardPreview() async {
    if (_isDraft) {
      await deleteVoiceDraft(widget.conversationId, _voiceDraftDir);
    } else {
      _deleteFileQuietly(_tempPath);
    }
    _resetVoiceState();
  }

  /// ✕ in any panel: while recording (locked or paused) the mic is still on,
  /// so the file must be cancelled before the panel goes away.
  Future<void> _discardVoice() async {
    if (_stopInProgress) return;
    if (_voiceState == _VoiceState.locked ||
        _voiceState == _VoiceState.paused) {
      _timer?.cancel();
      _timer = null;
      try {
        await _recorder.cancel();
      } catch (_) {}
      // A resume already queued may have restarted it during the await.
      _timer?.cancel();
      _timer = null;
      _deleteFileQuietly(_tempPath);
      _resetVoiceState();
      return;
    }
    await _discardPreview();
  }

  Future<void> _sendVoice() async {
    if (_tempPath == null || _isSendingVoice) return;
    final file = File(_tempPath!);
    if (!file.existsSync()) {
      if (_isDraft)
        await deleteVoiceDraft(widget.conversationId, _voiceDraftDir);
      _resetVoiceState();
      return;
    }
    setState(() => _isSendingVoice = true);

    try {
      // Repository handles message creation first, then media upload
      // File cleanup happens in _uploadMediaMessage after upload completes
      _reportFlight(null);
      await ref
          .read(sendMediaMessageProvider.notifier)
          .send(
            conversationId: widget.conversationId,
            mediaType: 'voice',
            mediaFile: file,
            durationSeconds: _durationSeconds,
            // D-3 A: the 36 levels ride in the encrypted body.
            durationText: _previewDuration == null
                ? null
                : voiceBodyWithLevels(_previewDuration!, _levels),
          );
      if (_isDraft)
        await deleteVoiceDraft(widget.conversationId, _voiceDraftDir);
      if (mounted) {
        _resetVoiceState();
      }
    } catch (_) {
      if (mounted) {
        showToast(context, "Couldn't send voice note. Try again.", error: true);
        if (!file.existsSync()) {
          if (_isDraft)
            await deleteVoiceDraft(widget.conversationId, _voiceDraftDir);
          _resetVoiceState();
        } else if (_voiceState != _VoiceState.preview) {
          await _showVoicePreview(file.path, _elapsed, isDraft: _isDraft);
        }
      }
    } finally {
      if (mounted) setState(() => _isSendingVoice = false);
    }
  }

  void _resetVoiceState() {
    if (!mounted) return;
    setState(() {
      _voiceState = _VoiceState.idle;
      _elapsed = Duration.zero;
      _tempPath = null;
      _previewDuration = null;
      _durationSeconds = 0;
      _levels = [];
      _isDraft = false;
      _dragOffsetX = 0;
      _dragOffsetY = 0;
      _cancelled = false;
      _dragAxis = 0;
    });
  }

  Future<void> _onRecordState(RecordState state) async {
    if (state != RecordState.pause) return;
    if (_voiceState == _VoiceState.holding) {
      await _stopRecording();
    } else if (_voiceState == _VoiceState.locked) {
      _timer?.cancel();
      _timer = null;
      if (mounted) setState(() => _voiceState = _VoiceState.paused);
    }
  }

  Future<void> _handleAppHide() async {
    if (_voiceState == _VoiceState.holding) {
      await _stopRecording();
    } else if (_voiceState == _VoiceState.locked) {
      await _pauseRecording();
    }
  }

  void _onMicPointerDown(PointerDownEvent event) {
    // Only a press on the mic owns a hold, or a palm on the text field would
    // take it over during the long-press wait.
    if (_voiceState != _VoiceState.idle || _starting) return;
    _voicePointerId = event.pointer;
    _holdOrigin = event.position;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_voiceState != _VoiceState.holding || event.pointer != _voicePointerId)
      return;
    final origin = _holdOrigin;
    if (origin == null) return;
    final dx = event.position.dx - origin.dx;
    final dy = event.position.dy - origin.dy;
    if (_dragAxis == 0) {
      if (dx.abs() > 16) {
        _dragAxis = 1;
      } else if (dy.abs() > 16) {
        _dragAxis = 2;
      }
    }
    if (_dragAxis == 1) {
      final next = dx.clamp(-120.0, 0.0).toDouble();
      final crossed = next <= -80 && !_cancelled;
      if (crossed || (next > -80 && _cancelled)) appHaptic(HapticsType.light);
      if (mounted) {
        setState(() {
          _dragOffsetX = next;
          _dragOffsetY = 0;
          _cancelled = next <= -80;
        });
      }
    } else if (_dragAxis == 2) {
      final next = dy.clamp(-80.0, 0.0).toDouble();
      if (next <= -80) {
        appHaptic(HapticsType.light);
        if (mounted) {
          setState(() {
            _voiceState = _VoiceState.locked;
            _dragOffsetX = 0;
            _dragOffsetY = 0;
          });
        }
      } else if (mounted) {
        setState(() => _dragOffsetY = next);
      }
    }
  }

  void _onPointerUp(PointerEvent event) {
    if (event.pointer != _voicePointerId) return;
    _voicePointerId = null;
    if (_voiceState == _VoiceState.holding) {
      unawaited(_stopRecording(cancelled: _cancelled));
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _onPointerUp(event);
  }

  /// I5: sending closed mid-recording. It goes the way leaving the chat does,
  /// and comes back as a Draft when sending opens (L4).
  void _keepVoiceAsDraft() {
    // A send or stop in flight already owns the file.
    if (!mounted || _isSendingVoice || _stopInProgress) return;
    _trackDraftSave(widget.conversationId, _saveRecordingAsDraft());
    _resetVoiceState();
  }

  Future<void> _loadVoiceDraft() async {
    if (!mounted) return;
    await _draftSaves[widget.conversationId];
    // L4: not able to send = leave it on disk; only ✕, a send or sign-out
    // remove a draft. Sending opening runs this again.
    if (!mounted ||
        !widget.canSendMessages ||
        _voiceState != _VoiceState.idle) {
      return;
    }
    final draft = await loadVoiceDraft(widget.conversationId, _voiceDraftDir);
    if (!mounted || draft == null || _voiceState != _VoiceState.idle) return;
    if (_composerBusy) {
      // A share's editor, dialog or upload got here first: the panel would
      // cover its row and its Cancel, so the draft waits its turn.
      _draftRetry?.cancel();
      _draftRetry = Timer(
        const Duration(milliseconds: 500), // motion-allow: recorder
        () => unawaited(_loadVoiceDraft()),
      );
      return;
    }
    await _showVoicePreview(
      draft.file.path,
      Duration(seconds: draft.seconds),
      isDraft: true,
    );
    if (mounted) setState(() => _levels = draft.levels);
  }

  void _trackDraftSave(String conversationId, Future<void> save) {
    final earlier = _draftSaves[conversationId];
    late final Future<void> tracked;
    tracked = Future.wait<void>([
      if (earlier != null) earlier,
      save,
    ]).whenComplete(() {
      if (identical(_draftSaves[conversationId], tracked)) {
        _draftSaves.remove(conversationId);
      }
    });
    _draftSaves[conversationId] = tracked;
  }

  Future<void> _saveDraftThenDisposeRecorder() async {
    await _saveRecordingAsDraft();
    try {
      await _recorder.dispose();
    } catch (_) {}
  }

  /// Everything it needs is read before the first await: dispose and I5 move
  /// the state on straight after calling this.
  Future<void> _saveRecordingAsDraft() async {
    final conversationId = widget.conversationId;
    final state = _voiceState;
    final path = _tempPath;
    final elapsed = _elapsed;
    final levels = List<double>.from(_levels);
    final isDraft = _isDraft;
    final durationSeconds = _durationSeconds;
    _timer?.cancel();
    _timer = null;
    try {
      if (state == _VoiceState.holding ||
          state == _VoiceState.locked ||
          state == _VoiceState.paused) {
        if (state == _VoiceState.holding &&
            elapsed < const Duration(seconds: 1)) {
          await _recorder.cancel();
        } else {
          final stopped = await _recorder.stop();
          final filePath = stopped ?? path;
          if (filePath != null) {
            final seconds = (elapsed.inMilliseconds / 1000).round();
            if (seconds >= 1) {
              await saveVoiceDraft(
                conversationId,
                File(filePath),
                seconds,
                levels,
                _voiceDraftDir,
              );
            } else {
              _deleteFileQuietly(filePath);
            }
          }
        }
      } else if (state == _VoiceState.preview && path != null && !isDraft) {
        await saveVoiceDraft(
          conversationId,
          File(path),
          durationSeconds,
          levels,
          _voiceDraftDir,
        );
      }
    } catch (error) {
      debugPrint('[Voice] draft save failed: ${error.runtimeType}');
    }
  }

  // ── Share from another app (12.1 E1–E5) ──────────────────────

  ReadyShare? _heldShare;

  void _takeShare() {
    if (!mounted) return;
    final ctl = ref.read(chatShareProvider(widget.conversationId).notifier);
    final share = ctl.state;
    if (share == null) return;
    ctl.state = null; // a rebuild never runs it twice
    final older = _heldShare;
    if (older != null) _deleteShareFolders(older);
    _heldShare = share;
    if (_maybeRunShare()) return;
    // Held: a group's send rule settles after its first frames, and a send
    // or editor already running in this chat finishes first.
    var ticks = 0;
    Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!identical(_heldShare, share)) return timer.cancel();
      if (!mounted) {
        timer.cancel();
        _deleteShareFolders(share); // the chat closed first
        return;
      }
      if (_maybeRunShare()) return timer.cancel();
      // Backstop for D6: still not allowed to send → drop it and its copies.
      if (!widget.canSendMessages && ++ticks >= 30) {
        // 15 s
        timer.cancel();
        _heldShare = null;
        _deleteShareFolders(share);
        showToast(
          context,
          "You can't send messages in this chat.",
          error: true,
        );
      }
    });
  }

  bool get _composerBusy =>
      _voiceState != _VoiceState.idle ||
      _starting ||
      _isSendingVoice ||
      _isPreparingAlbum ||
      _isUploadingImage ||
      _isUploadingVideo ||
      _isUploadingDoc ||
      ModalRoute.of(context)?.isCurrent == false; // an editor or sheet on top

  /// Runs the held share when this composer may send and is idle: a new send
  /// would otherwise cancel the one in flight (upload generation).
  bool _maybeRunShare() {
    final share = _heldShare;
    if (share == null || !mounted) return false;
    if (!widget.canSendMessages || _composerBusy) return false;
    _heldShare = null;
    _runShare(share);
    return true;
  }

  /// C4: photos and videos first (one → single, more → album), then the
  /// documents after one confirm, then the text into the composer.
  Future<void> _runShare(ReadyShare share) async {
    final media = [
      for (final f in share.files)
        if (f.kind != SharedKind.document) f,
    ];
    final docs = [
      for (final f in share.files)
        if (f.kind == SharedKind.document) f,
    ];
    try {
      try {
        if (media.length == 1) {
          final only = media.single;
          await _sendSinglePicked(
            File(only.path),
            only.kind == SharedKind.video ? 'video' : 'image',
          );
        } else if (media.length > 1) {
          await _sendAlbumPicked([
            for (final f in media) XFile(f.path, mimeType: f.mime),
          ]);
        }
      } catch (e) {
        debugPrint('[Share] media part failed: ${e.runtimeType}');
      }

      // E3 / decision 11: a shared document asks once; E4: even after a
      // cancelled media part.
      if (docs.isNotEmpty && mounted) {
        final ok = await showConfirmDialog(
          context: context,
          title: 'Send to ${share.chatName}?',
          body: docs.length == 1
              ? p.basename(docs.single.path)
              : '${docs.length} files',
          confirmLabel: 'Send',
        );
        for (final d in docs) {
          if (!ok || !mounted) break;
          await _sendDocument(File(d.path));
        }
      }

      final text = share.text;
      if (text != null && mounted) {
        final draft = _ctrl.text;
        _ctrl.text = draft.trim().isEmpty ? text : '$draft\n$text';
        _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
        _focusNode.requestFocus();
      }
    } finally {
      _deleteShareFolders(share); // E5: a moved document is already gone
    }
  }

  void _deleteShareFolders(ReadyShare share) {
    for (final f in share.files) {
      final dir = p.dirname(f.path);
      // Only ever cache/share_in/<n>/.
      if (p.basename(p.dirname(dir)) != 'share_in') continue;
      try {
        Directory(dir).deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  // ── Image sharing ────────────────────────────────────────────

  Future<void> _onAttachPressed() async {
    final source = await showAttachSourceSheet(context);
    if (source == null) return;

    final picker = ImagePicker();

    switch (source) {
      case 'camera':
        final picked = await picker.pickImage(source: ImageSource.camera);
        if (picked == null) return;
        await _sendSinglePicked(File(picked.path), 'image');
        break;

      case 'gallery':
        // 12.5 B1/B3: photos and videos in one picker, at most 20.
        final picked = await picker.pickMultipleMedia(
          limit: AppConstants.maxAlbumItems,
        );
        if (picked.isEmpty) return;
        final files = picked.length > AppConstants.maxAlbumItems
            ? picked.take(AppConstants.maxAlbumItems).toList()
            : picked;
        if (picked.length > AppConstants.maxAlbumItems && mounted) {
          showToast(
            context,
            'Only the first ${AppConstants.maxAlbumItems} were added.',
          );
        }
        if (files.length == 1) {
          final only = files.single;
          await _sendSinglePicked(File(only.path), _mediaTypeOf(only));
        } else {
          await _sendAlbumPicked(files);
        }
        break;

      case 'video_camera':
      case 'video_gallery':
        final picked = await picker.pickVideo(
          source: source == 'video_camera'
              ? ImageSource.camera
              : ImageSource.gallery,
          maxDuration: const Duration(minutes: 5),
        );
        if (picked == null) return;
        await _sendSinglePicked(File(picked.path), 'video');
        break;

      case 'document':
        final result = await FilePicker.platform.pickFiles(
          type: FileType.any,
          allowMultiple: false,
          withReadStream: false,
        );
        if (result == null || result.files.isEmpty) return;
        final path = result.files.single.path;
        if (path == null) return;
        _focusNode.requestFocus();
        await _sendDocument(File(path));
        break;
    }
  }

  /// B2: one picked item keeps today's single flow exactly.
  Future<void> _sendSinglePicked(File original, String type) async {
    if (!_withinMediaLimit(original)) return;
    final edited = mounted
        ? await Navigator.of(context).push<MediaEditResult>(
            MaterialPageRoute(
              builder: (_) => MediaEditScreen(file: original, type: type),
            ),
          )
        : null;
    if (edited == null) return;

    if (type == 'video') {
      final quality = mounted
          ? await showMediaQualitySheet(context, isVideo: true)
          : null;
      if (quality == null) return;
      _focusNode.requestFocus();
      await _sendVideo(
        edited.file ?? original,
        quality,
        startTime: edited.trimStart,
        endTime: edited.trimEnd,
        sourceDuration: edited.sourceDuration,
      );
      return;
    }

    final file = edited.file ?? original;
    final isGif =
        await MediaUploadService.isAnimatedImage(file) ||
        file.path.toLowerCase().endsWith('.gif');
    final quality = isGif
        ? 'normal'
        : mounted
        ? await showMediaQualitySheet(context, isVideo: false)
        : null;
    if (quality == null) return;
    _focusNode.requestFocus();
    await _sendImage(file, quality, formatHint: edited.formatHint);
  }

  String _mediaTypeOf(XFile file) {
    final mime = file.mimeType?.toLowerCase();
    if (mime != null && mime.startsWith('video/')) return 'video';
    final ext = file.path.toLowerCase().split('.').last;
    const videoExts = {
      'mp4',
      'mov',
      'm4v',
      'avi',
      'mkv',
      'webm',
      '3gp',
      'mpeg',
      'mpg',
    };
    return videoExts.contains(ext) ? 'video' : 'image';
  }

  /// B2–B6: two or more items go through the album editor, one quality
  /// choice, item-by-item compression, then one album send.
  Future<void> _sendAlbumPicked(List<XFile> picked) async {
    final originals = [for (final f in picked) File(f.path)];
    final types = [for (final f in picked) _mediaTypeOf(f)];
    final edited = mounted
        ? await Navigator.of(context).push<List<MediaEditResult>>(
            MaterialPageRoute(
              builder: (_) => MediaEditScreen.album(
                items: [
                  for (var i = 0; i < originals.length; i++)
                    MediaEditItem(file: originals[i], type: types[i]),
                ],
              ),
            ),
          )
        : null;
    if (edited == null || edited.isEmpty || !mounted) return;

    // A removed item is absent from the results; each result names its source.
    final kept = <({File file, String type, MediaEditResult edit})>[];
    final tooBig = <File>[];
    for (final result in edited) {
      final path = result.sourcePath;
      final file = result.file ?? (path != null ? File(path) : null);
      if (file == null) continue;
      final type = result.type ?? 'image';
      if (mediaTooBig(file)) {
        tooBig.add(file);
      } else {
        kept.add((file: file, type: type, edit: result));
      }
    }

    if (kept.isEmpty) {
      showToast(context, kUploadTooBig, error: true);
      return;
    }
    if (tooBig.isNotEmpty) {
      showToast(
        context,
        tooBig.length == 1
            ? '1 item is over 100 MB and was left out.'
            : '${tooBig.length} items are over 100 MB and were left out.',
        error: true,
      );
    }

    final isGif = <bool>[];
    for (final item in kept) {
      isGif.add(
        item.type == 'image' &&
            (await MediaUploadService.isAnimatedImage(item.file) ||
                item.file.path.toLowerCase().endsWith('.gif')),
      );
    }
    final allGif = isGif.every((gif) => gif);

    String? quality;
    if (allGif) {
      quality = 'normal';
    } else {
      final hasPhoto = kept.any((item) => item.type == 'image');
      final hasVideo = kept.any((item) => item.type == 'video');
      if (!mounted) return;
      quality = await showMediaQualitySheet(
        context,
        isVideo: !hasPhoto,
        mixed: hasPhoto && hasVideo,
      );
      if (quality == null) return;
    }

    if (!mounted) return;
    _focusNode.requestFocus();
    await _prepareAndSendAlbum(kept, quality);
  }

  Future<void> _prepareAndSendAlbum(
    List<({File file, String type, MediaEditResult edit})> items,
    String quality,
  ) async {
    final generation = ++_uploadGeneration;
    _albumTempFiles.clear();
    setState(() {
      _isPreparingAlbum = true;
      _prepareIndex = 0;
      _prepareTotal = items.length;
    });

    final out = <AlbumSendItem>[];
    try {
      for (var i = 0; i < items.length; i++) {
        if (!_isUploadActive(generation)) return;
        setState(() => _prepareIndex = i);
        final item = items[i];
        final edit = item.edit;
        final itemTemps = <File>[];

        if (item.type == 'video') {
          final thumbnail = await ref
              .read(mediaUploadServiceProvider)
              .generateVideoThumbnail(
                item.file,
                position: edit.trimStart ?? -1,
              );
          itemTemps.add(thumbnail);
          _albumTempFiles.add(thumbnail);
          if (!_isUploadActive(generation)) {
            _discardAlbumTemps();
            return;
          }

          final compressed = await ref
              .read(mediaUploadServiceProvider)
              .compressVideo(
                item.file,
                quality,
                startTime: edit.trimStart,
                endTime: edit.trimEnd,
                sourceDuration: edit.sourceDuration,
              );
          itemTemps.add(compressed);
          _albumTempFiles.add(compressed);
          if (!_isUploadActive(generation)) {
            _discardAlbumTemps();
            return;
          }
          if (mediaTooBig(compressed)) {
            _discardFiles(itemTemps);
            continue;
          }

          final info = await VideoCompress.getMediaInfo(compressed.path);
          if (!_isUploadActive(generation)) {
            _discardAlbumTemps();
            return;
          }
          out.add((
            mediaType: 'video',
            mediaFile: compressed,
            thumbnailFile: thumbnail,
            durationSeconds: (info.duration ?? 0) ~/ 1000,
            durationText: null,
            videoWidth: info.width,
            videoHeight: info.height,
          ));
        } else {
          final compressed = await ref
              .read(mediaUploadServiceProvider)
              .compressImage(
                item.file,
                quality,
                formatHint: edit.formatHint,
              );
          itemTemps.add(compressed);
          _albumTempFiles.add(compressed);
          if (!_isUploadActive(generation)) {
            _discardAlbumTemps();
            return;
          }
          if (mediaTooBig(compressed)) {
            _discardFiles(itemTemps);
            continue;
          }

          final thumbnail = await ref
              .read(mediaUploadServiceProvider)
              .generateImageThumbnail(compressed);
          itemTemps.add(thumbnail);
          _albumTempFiles.add(thumbnail);
          if (!_isUploadActive(generation)) {
            _discardAlbumTemps();
            return;
          }
          out.add((
            mediaType: 'image',
            mediaFile: compressed,
            thumbnailFile: thumbnail,
            durationSeconds: null,
            durationText: null,
            videoWidth: null,
            videoHeight: null,
          ));
        }
      }

      if (!_isUploadActive(generation)) return;
      final left = items.length - out.length;
      if (out.isEmpty) {
        if (mounted) showToast(context, kUploadTooBig, error: true);
        return;
      }
      if (left > 0 && mounted) {
        showToast(
          context,
          left == 1
              ? '1 item is over 100 MB and was left out.'
              : '$left items are over 100 MB and were left out.',
          error: true,
        );
      }
      // Past this point a cancel cannot stop the send: hide the row and stop
      // tracking the files, which the repository now owns.
      _albumTempFiles.clear();
      setState(() => _isPreparingAlbum = false);
      try {
        await ref
            .read(messageRepositoryProvider)
            .sendMediaAlbum(
              conversationId: widget.conversationId,
              items: out,
              quality: quality,
            );
      } catch (_) {
        // Items not taken by the repository are still temp files.
        _discardFiles([
          for (final it in out) ...[it.mediaFile, ?it.thumbnailFile],
        ]);
        rethrow;
      }
    } catch (e) {
      debugPrint('Album send failed: $e');
      _discardAlbumTemps();
      if (mounted && _isUploadActive(generation)) {
        showToast(context, "Couldn't send. Try again.", error: true);
      }
    } finally {
      if (mounted && _isUploadActive(generation) && _isPreparingAlbum) {
        setState(() => _isPreparingAlbum = false);
      }
    }
  }

  void _discardAlbumTemps() {
    _discardFiles(_albumTempFiles);
    _albumTempFiles.clear();
  }

  void _discardFiles(List<File> files) {
    for (final file in files) {
      _deleteFileQuietly(file.path);
    }
  }

  Future<void> _sendImage(
    File original,
    String quality, {
    String? formatHint,
  }) async {
    if (!_withinMediaLimit(original)) return;
    final generation = ++_uploadGeneration;
    setState(() => _isUploadingImage = true);

    try {
      final compressed = await ref
          .read(mediaUploadServiceProvider)
          .compressImage(original, quality, formatHint: formatHint);
      if (!_withinMediaLimit(compressed)) {
        _deleteFileQuietly(compressed.path);
        return;
      }
      if (!_isUploadActive(generation)) {
        _deleteFileQuietly(compressed.path);
        return;
      }

      final thumbnail = await ref
          .read(mediaUploadServiceProvider)
          .generateImageThumbnail(compressed);
      if (!_isUploadActive(generation)) {
        _deleteFileQuietly(compressed.path);
        _deleteFileQuietly(thumbnail.path);
        return;
      }

      await ref
          .read(sendMediaMessageProvider.notifier)
          .send(
            conversationId: widget.conversationId,
            mediaType: 'image',
            mediaFile: compressed,
            thumbnailFile: thumbnail,
            quality: quality,
          );
    } catch (_) {
      if (!mounted || generation != _uploadGeneration) return;
      showToast(context, "Couldn't send photo. Try again.", error: true);
    } finally {
      if (_isUploadActive(generation)) {
        setState(() => _isUploadingImage = false);
      }
    }
  }

  Future<void> _sendDocument(File docFile) async {
    if (!_withinMediaLimit(docFile)) return; // decision 13: before any work
    final generation = ++_uploadGeneration;
    setState(() => _isUploadingDoc = true);
    try {
      if (!_isUploadActive(generation)) return;
      await ref
          .read(sendMediaMessageProvider.notifier)
          .send(
            conversationId: widget.conversationId,
            mediaType: 'document',
            mediaFile: docFile,
          );
    } catch (_) {
      if (!mounted || generation != _uploadGeneration) return;
      showToast(context, "Couldn't send document. Try again.", error: true);
    } finally {
      if (_isUploadActive(generation)) {
        setState(() => _isUploadingDoc = false);
      }
    }
  }

  Future<void> _sendVideo(
    File original,
    String quality, {
    int? startTime,
    int? endTime,
    int? sourceDuration,
  }) async {
    if (!_withinMediaLimit(original)) return;
    final generation = ++_uploadGeneration;
    setState(() {
      _isUploadingVideo = true;
      _videoCompressProgress = 0.0;
    });

    // Subscribe to compression progress
    final sub = VideoCompress.compressProgress$.subscribe((progress) {
      if (_isUploadActive(generation)) {
        setState(() => _videoCompressProgress = progress / 100);
      }
    });

    try {
      // Generate thumbnail from ORIGINAL before compression deletes it
      final thumbnail = await ref
          .read(mediaUploadServiceProvider)
          .generateVideoThumbnail(original, position: startTime ?? -1);
      if (!_isUploadActive(generation)) {
        _deleteFileQuietly(thumbnail.path);
        return;
      }

      final compressed = await ref
          .read(mediaUploadServiceProvider)
          .compressVideo(
            original,
            quality,
            startTime: startTime,
            endTime: endTime,
            sourceDuration: sourceDuration,
          );
      if (!_withinMediaLimit(compressed)) {
        _deleteFileQuietly(compressed.path);
        _deleteFileQuietly(thumbnail.path);
        return;
      }
      if (!_isUploadActive(generation)) {
        _deleteFileQuietly(compressed.path);
        _deleteFileQuietly(thumbnail.path);
        return;
      }

      // Get video duration and dimensions from compressed file
      final info = await VideoCompress.getMediaInfo(compressed.path);
      if (!_isUploadActive(generation)) {
        _deleteFileQuietly(compressed.path);
        _deleteFileQuietly(thumbnail.path);
        return;
      }
      final durationSec = (info.duration ?? 0) ~/ 1000;
      final videoWidth = info.width;
      final videoHeight = info.height;

      await ref
          .read(sendMediaMessageProvider.notifier)
          .send(
            conversationId: widget.conversationId,
            mediaType: 'video',
            mediaFile: compressed,
            thumbnailFile: thumbnail,
            quality: quality,
            durationSeconds: durationSec,
            videoWidth: videoWidth,
            videoHeight: videoHeight,
          );
    } catch (_) {
      if (!mounted || generation != _uploadGeneration) return;
      showToast(context, "Couldn't send video. Try again.", error: true);
    } finally {
      sub.unsubscribe();
      if (_isUploadActive(generation)) {
        setState(() => _isUploadingVideo = false);
      }
    }
  }

  bool _isUploadActive(int generation) =>
      mounted && generation == _uploadGeneration;

  bool _withinMediaLimit(File file) {
    if (!mediaTooBig(file)) return true;
    showToast(context, kUploadTooBig, error: true);
    return false;
  }

  void _cancelUpload(String type) {
    _uploadGeneration++;
    // An album can be mid-way through a video item too.
    if (type == 'video' || type == 'album') VideoCompress.cancelCompression();
    _discardAlbumTemps();
    if (!mounted) return;
    setState(() {
      _isUploadingImage = false;
      _isUploadingVideo = false;
      _isUploadingDoc = false;
      _isPreparingAlbum = false;
      _videoCompressProgress = 0;
    });
    showToast(context, 'Upload cancelled');
  }

  BoxDecoration _floatingPanelDecoration(BuildContext context) => BoxDecoration(
    color: context.t.surface,
    border: Border.all(color: context.t.line),
    borderRadius: BorderRadius.circular(WarmPopTokens.radiusLg),
    boxShadow: WarmPopTokens.cardShadow(context.t.shadow),
  );

  Widget _floatingPanel(BuildContext context, Widget child) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        child: SizedBox(
          width: double.infinity,
          child: DecoratedBox(
            decoration: _floatingPanelDecoration(context),
            child: Listener(
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              onPointerCancel: _onPointerCancel,
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final reply = ref.watch(_reply);

    final restriction =
        widget.restrictionMessage ??
        (!widget.canSendMessages ? 'Only admins can send messages' : null);

    if (restriction != null) {
      return _floatingPanel(
        context,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 16, color: context.t.inkFaint),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  restriction,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.t.inkFaint, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return _floatingPanel(
      context,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Reply preview bar
          if (reply != null && _voiceState == _VoiceState.idle)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: ReplyQuote.fromMessage(
                reply,
                widget.replySenderName ?? 'them',
                compact: true,
                onCancel: () => ref.read(_reply.notifier).state = null,
              ),
            ),

          if (_voiceState == _VoiceState.holding)
            VoiceHoldStrip(
              elapsed: _elapsed,
              levels: _levels,
              dragX: _dragOffsetX,
              dragY: _dragOffsetY,
              cancelled: _cancelled,
              pulse: _pulseAnim,
            )
          else if (_voiceState == _VoiceState.locked ||
              _voiceState == _VoiceState.paused ||
              _voiceState == _VoiceState.preview)
            VoiceRecorderPanel(
              mode: switch (_voiceState) {
                _VoiceState.locked => VoiceRecorderPanelMode.locked,
                _VoiceState.paused => VoiceRecorderPanelMode.paused,
                _ => VoiceRecorderPanelMode.preview,
              },
              filePath: _tempPath ?? '',
              seconds: _voiceState == _VoiceState.preview
                  ? _durationSeconds
                  : _elapsed.inSeconds,
              levels: _levels,
              isDraft: _isDraft,
              isSending: _isSendingVoice || _stopInProgress,
              onDelete: () => unawaited(_discardVoice()),
              onCenter: () {
                if (_voiceState == _VoiceState.locked) {
                  unawaited(_pauseRecording());
                } else if (_voiceState == _VoiceState.paused) {
                  unawaited(_resumeRecording());
                }
              },
              onSend: () {
                if (_voiceState == _VoiceState.preview) {
                  unawaited(_sendVoice());
                } else {
                  unawaited(_sendLockedVoice());
                }
              },
              onStopAndListen: () => unawaited(_stopAndListen()),
            )
          else if (_isPreparingAlbum)
            _AlbumPreparingRow(
              index: _prepareIndex,
              total: _prepareTotal,
              onCancel: () => _cancelUpload('album'),
            )
          else if (_isUploadingImage)
            _ImageUploadRow(onCancel: () => _cancelUpload('image'))
          else if (_isUploadingVideo)
            _VideoUploadRow(
              progress: _videoCompressProgress,
              onCancel: () => _cancelUpload('video'),
            )
          else if (_isUploadingDoc)
            _DocUploadRow(onCancel: () => _cancelUpload('document'))
          else
            _NormalInputRow(
              fieldKey: _fieldKey,
              ctrl: _ctrl,
              focusNode: _focusNode,
              hasText: _hasText,
              isLoading: widget.isLoading,
              onAttach: _onAttachPressed,
              onStickers: () => unawaited(_onStickersPressed()),
              onSend: _send,
              accessibleNavigation: MediaQuery.accessibleNavigationOf(context),
              onMicPointerDown: _onMicPointerDown,
              onMicTap: () => unawaited(_startRecording(lockImmediately: true)),
              onMicLongPressStart: (_) => unawaited(_startRecording()),
            ),
        ],
      ),
    );
  }
}

class _ComposerAction extends StatelessWidget {
  const _ComposerAction({
    super.key,
    required this.tooltip,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.icon,
    this.onTap,
    this.onLongPressStart,
    this.onLongPressMoveUpdate,
    this.onLongPressEnd,
    this.tapHint,
  });

  final String tooltip;

  /// Shown as a tooltip above the button on a quick tap (the mic records
  /// only on a hold); a toast here would cover the composer.
  final String? tapHint;
  final Color backgroundColor;
  final Color foregroundColor;
  final Widget icon;
  final VoidCallback? onTap;
  final GestureLongPressStartCallback? onLongPressStart;
  final GestureLongPressMoveUpdateCallback? onLongPressMoveUpdate;
  final GestureLongPressEndCallback? onLongPressEnd;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null || onLongPressStart != null;
    return Tooltip(
      message: tapHint ?? tooltip,
      excludeFromSemantics: true,
      triggerMode: tapHint != null
          ? TooltipTriggerMode.tap
          : onLongPressStart == null
          ? TooltipTriggerMode.longPress
          : TooltipTriggerMode.manual,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        hint: tapHint,
        child: SizedBox(
          width: 48,
          height: 48,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            onLongPressStart: onLongPressStart,
            onLongPressMoveUpdate: onLongPressMoveUpdate,
            onLongPressEnd: onLongPressEnd,
            child: PressScale(
              enabled: enabled,
              child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: backgroundColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: backgroundColor.withValues(alpha: 0.24),
                      blurRadius: 7,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Center(
                    child: ExcludeSemantics(
                      child: IconTheme(
                        data: IconThemeData(color: foregroundColor),
                        child: icon,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Normal input row ───────────────────────────────────────────────────────

class _NormalInputRow extends StatelessWidget {
  const _NormalInputRow({
    required this.fieldKey,
    required this.ctrl,
    required this.focusNode,
    required this.hasText,
    required this.isLoading,
    required this.onAttach,
    required this.onStickers,
    required this.onSend,
    required this.accessibleNavigation,
    required this.onMicPointerDown,
    required this.onMicTap,
    required this.onMicLongPressStart,
  });

  final GlobalKey fieldKey;
  final TextEditingController ctrl;
  final FocusNode focusNode;
  final bool hasText;
  final bool isLoading;
  final VoidCallback onAttach;
  final VoidCallback onStickers;
  final VoidCallback onSend;
  final bool accessibleNavigation;
  final PointerDownEventListener onMicPointerDown;
  final VoidCallback onMicTap;
  final GestureLongPressStartCallback onMicLongPressStart;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          // Attachment button — always visible
          _ComposerAction(
            tooltip: 'Attach file',
            backgroundColor: context.t.surface2,
            foregroundColor: context.t.inkSoft,
            icon: const Icon(Icons.attach_file, size: 21),
            onTap: onAttach,
          ),
          const SizedBox(width: 4),
          _ComposerAction(
            key: const Key('composer-stickers'),
            tooltip: 'Stickers',
            backgroundColor: context.t.surface2,
            foregroundColor: context.t.inkSoft,
            icon: const Icon(Icons.emoji_emotions_outlined, size: 21),
            onTap: onStickers,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              key: fieldKey,
              constraints: const BoxConstraints(minHeight: 48),
              decoration: BoxDecoration(
                color: context.t.surface2,
                border: Border.all(color: context.t.line),
                borderRadius: BorderRadius.circular(WarmPopTokens.radiusXl),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: ctrl,
                      focusNode: focusNode,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      cursorColor: context.t.accent,
                      style: TextStyle(fontSize: 15, color: context.t.ink),
                      decoration: InputDecoration(
                        hintText: 'Message',
                        hintStyle: TextStyle(color: context.t.inkFaint),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                      ),
                      onSubmitted: (_) => onSend(),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 48,
            height: 48,
            child: AnimatedSwitcher(
              duration: WarmPopTokens.motionBase,
              transitionBuilder: (child, animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: hasText
                  ? _ComposerAction(
                      key: const ValueKey('send-action'),
                      tooltip: 'Send message',
                      backgroundColor: context.t.accent,
                      foregroundColor: context.t.onAccent,
                      onTap: isLoading ? null : onSend,
                      icon: isLoading
                          ? BusySpinner(
                              size: 18,
                              strokeWidth: 2,
                              color: context.t.onAccent,
                            )
                          : const Icon(Icons.send_rounded, size: 20),
                    )
                  : Listener(
                      onPointerDown: onMicPointerDown,
                      child: MergeSemantics(
                        // J2: under TalkBack the hint is the double tap, and
                        // there is no hold tooltip.
                        child: Semantics(
                          hint: accessibleNavigation
                              ? 'Double tap to record'
                              : null,
                          child: _ComposerAction(
                            key: const ValueKey('mic-action'),
                            tooltip: 'Record voice message',
                            backgroundColor: context.t.accent,
                            foregroundColor: context.t.onAccent,
                            tapHint: accessibleNavigation
                                ? null
                                : 'Hold to record',
                            onTap: accessibleNavigation ? onMicTap : null,
                            // TalkBack's long click has no finger to release.
                            onLongPressStart: accessibleNavigation
                                ? null
                                : onMicLongPressStart,
                            icon: const Icon(Icons.mic, size: 22),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Album preparing row ────────────────────────────────────────────────────

/// B6: compression runs item by item; the existing floating row says which
/// one and its cancel drops the whole album (nothing is sent).
class _AlbumPreparingRow extends StatelessWidget {
  const _AlbumPreparingRow({
    required this.index,
    required this.total,
    required this.onCancel,
  });

  final int index;
  final int total;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(Icons.photo_library_outlined, color: context.t.inkFaint, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Preparing ${index + 1} of $total',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 12),
          BusySpinner(size: 16, strokeWidth: 2),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onCancel,
            tooltip: 'Cancel upload',
            icon: Icon(Icons.close, color: context.t.inkSoft),
          ),
        ],
      ),
    );
  }
}

// ── Image upload progress row ──────────────────────────────────────────────

class _ImageUploadRow extends StatelessWidget {
  const _ImageUploadRow({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(Icons.image_outlined, color: context.t.inkFaint, size: 22),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Sending photo…',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                SizedBox(height: 6),
                LinearProgressIndicator(minHeight: 3),
              ],
            ),
          ),
          IconButton(
            onPressed: onCancel,
            tooltip: 'Cancel upload',
            icon: Icon(Icons.close, color: context.t.inkSoft),
          ),
        ],
      ),
    );
  }
}

// ── Video upload progress row ──────────────────────────────────────────────

class _VideoUploadRow extends StatelessWidget {
  const _VideoUploadRow({required this.progress, required this.onCancel});

  final double progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final pct = (progress * 100).clamp(0, 100).toStringAsFixed(0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(Icons.videocam_outlined, color: context.t.inkFaint, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text(
                      'Compressing video…',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$pct%',
                      style: TextStyle(fontSize: 12, color: context.t.inkFaint),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: progress > 0 ? progress : null,
                  minHeight: 3,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onCancel,
            tooltip: 'Cancel upload',
            icon: Icon(Icons.close, color: context.t.inkSoft),
          ),
        ],
      ),
    );
  }
}

// ── Document upload progress row ───────────────────────────────────────────

class _DocUploadRow extends StatelessWidget {
  const _DocUploadRow({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(Icons.attach_file_outlined, color: context.t.inkFaint, size: 22),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Sending document…',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                SizedBox(height: 6),
                LinearProgressIndicator(minHeight: 3),
              ],
            ),
          ),
          IconButton(
            onPressed: onCancel,
            tooltip: 'Cancel upload',
            icon: Icon(Icons.close, color: context.t.inkSoft),
          ),
        ],
      ),
    );
  }
}
