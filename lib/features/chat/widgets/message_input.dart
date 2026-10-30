import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';
import 'package:video_compress/video_compress.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/media_upload_service.dart';
import '../providers/chat_provider.dart';
import 'attach_sheets.dart';
import 'reply_quote.dart';

// ── Recording state ────────────────────────────────────────────────────────

enum _VoiceState { idle, recording, preview }

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
  });

  final void Function(String) onSend;
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
  final _recorder = AudioRecorder();
  _VoiceState _voiceState = _VoiceState.idle;
  Timer? _timer;
  int _elapsedSec = 0;
  String? _tempPath;
  bool _cancelled = false;
  double _dragOffsetX = 0;
  bool _stopInProgress = false;

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

  final _focusNode = FocusNode();

  // ── Pulse animation ──────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  bool _pulseMotionInitialized = false;
  bool _pulseReducedMotion = false;

  @override
  void initState() {
    super.initState();
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
      duration: const Duration(milliseconds: 800),
    );
    _pulseAnim = Tween<double>(
      begin: 0.7,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
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
    _pulseCtrl.dispose();
    _recorder.dispose();
    super.dispose();
  }

  // ── Text send ────────────────────────────────────────────────

  void _send() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _ctrl.clear();
    ref.read(replyProvider.notifier).state = null;
  }

  // ── Recording helpers ────────────────────────────────────────

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _startRecording() async {
    if (_voiceState != _VoiceState.idle || _isSendingVoice) return;

    final status = await Permission.microphone.request();
    if (!mounted) return;
    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission denied')),
      );
      return;
    }

    try {
      final tmpDir = await getTemporaryDirectory();
      final path =
          '${tmpDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      if (!mounted) {
        await _recorder.stop();
        return;
      }

      setState(() {
        _voiceState = _VoiceState.recording;
        _tempPath = path;
        _elapsedSec = 0;
        _cancelled = false;
        _dragOffsetX = 0;
        _stopInProgress = false;
      });

      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _elapsedSec++);
        // Auto-stop at 5 minutes (spec §6.5).
        if (_elapsedSec >= AppConstants.maxVoiceMessageSeconds) {
          _stopRecording();
        }
      });
    } catch (_) {
      _deleteFileQuietly(_tempPath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not start recording')),
        );
      }
    }
  }

  Future<void> _stopRecording({bool cancelled = false}) async {
    if (_voiceState != _VoiceState.recording || _stopInProgress) return;

    _stopInProgress = true;
    _timer?.cancel();
    _timer = null;

    final elapsed = _elapsedSec; // capture before reset
    final wasCancelled = cancelled || _cancelled;

    try {
      final path = await _recorder.stop();
      final filePath = path ?? _tempPath;

      if (wasCancelled || elapsed < 1) {
        _deleteFileQuietly(filePath);
        if (!mounted) return;
        setState(() {
          _voiceState = _VoiceState.idle;
          _elapsedSec = 0;
          _tempPath = null;
          _dragOffsetX = 0;
          _cancelled = false;
        });
        if (!wasCancelled && elapsed < 1) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Hold to record'),
              duration: Duration(seconds: 1),
            ),
          );
        }
        return;
      }

      if (!mounted) {
        _deleteFileQuietly(filePath);
        return;
      }

      final duration = _formatDuration(elapsed);
      setState(() {
        _voiceState = _VoiceState.preview;
        _previewDuration = duration;
        _tempPath = filePath;
        _dragOffsetX = 0;
        _cancelled = false;
      });
    } catch (_) {
      _deleteFileQuietly(_tempPath);
      if (mounted) {
        setState(() {
          _voiceState = _VoiceState.idle;
          _elapsedSec = 0;
          _tempPath = null;
          _dragOffsetX = 0;
          _cancelled = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save voice message')),
        );
      }
    } finally {
      _stopInProgress = false;
    }
  }

  void _deleteFileQuietly(String? path) {
    if (path == null) return;
    try {
      File(path).deleteSync();
    } catch (_) {}
  }

  void _discardPreview() {
    if (_tempPath != null) {
      try {
        File(_tempPath!).deleteSync();
      } catch (_) {}
    }
    setState(() {
      _voiceState = _VoiceState.idle;
      _tempPath = null;
      _previewDuration = null;
    });
  }

  Future<void> _sendVoice() async {
    if (_tempPath == null || _isSendingVoice) return;
    setState(() => _isSendingVoice = true);

    try {
      final file = File(_tempPath!);
      final durSecs = _durationTextToSeconds(_previewDuration ?? '0:00');

      // Repository handles message creation first, then media upload
      // File cleanup happens in _uploadMediaMessage after upload completes
      await ref
          .read(sendMediaMessageProvider.notifier)
          .send(
            conversationId: widget.conversationId,
            mediaType: 'voice',
            mediaFile: file,
            durationSeconds: durSecs,
            durationText: _previewDuration,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send voice: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSendingVoice = false;
          _voiceState = _VoiceState.idle;
          _tempPath = null;
          _previewDuration = null;
        });
      }
    }
  }

  int _durationTextToSeconds(String text) {
    final parts = text.split(':');
    if (parts.length != 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }

  // ── Image sharing ────────────────────────────────────────────

  Future<void> _onAttachPressed() async {
    final source = await showAttachSourceSheet(context);
    if (source == null) return;

    final picker = ImagePicker();

    switch (source) {
      case 'camera':
      case 'gallery':
        final picked = await picker.pickImage(
          source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
        );
        if (picked == null) return;
        final quality = mounted
            ? await showMediaQualitySheet(context, isVideo: false)
            : null;
        if (quality == null) return;
        _focusNode.requestFocus();
        await _sendImage(File(picked.path), quality);
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
        final quality = mounted
            ? await showMediaQualitySheet(context, isVideo: true)
            : null;
        if (quality == null) return;
        _focusNode.requestFocus();
        await _sendVideo(File(picked.path), quality);
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

  Future<void> _sendImage(File original, String quality) async {
    final generation = ++_uploadGeneration;
    setState(() => _isUploadingImage = true);

    try {
      final compressed = await ref
          .read(mediaUploadServiceProvider)
          .compressImage(original, quality);
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
    } catch (e) {
      if (!mounted || generation != _uploadGeneration) return;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send image: $e')));
      }
    } finally {
      if (_isUploadActive(generation)) {
        setState(() => _isUploadingImage = false);
      }
    }
  }

  Future<void> _sendDocument(File docFile) async {
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
    } catch (e) {
      if (!mounted || generation != _uploadGeneration) return;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send document: $e')));
      }
    } finally {
      if (_isUploadActive(generation)) {
        setState(() => _isUploadingDoc = false);
      }
    }
  }

  Future<void> _sendVideo(File original, String quality) async {
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
          .generateVideoThumbnail(original);
      if (!_isUploadActive(generation)) {
        _deleteFileQuietly(thumbnail.path);
        return;
      }

      final compressed = await ref
          .read(mediaUploadServiceProvider)
          .compressVideo(original, quality);
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
    } catch (e) {
      if (!mounted || generation != _uploadGeneration) return;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send video: $e')));
      }
    } finally {
      sub.unsubscribe();
      if (_isUploadActive(generation)) {
        setState(() => _isUploadingVideo = false);
      }
    }
  }

  bool _isUploadActive(int generation) =>
      mounted && generation == _uploadGeneration;

  void _cancelUpload(String type) {
    _uploadGeneration++;
    if (type == 'video') VideoCompress.cancelCompression();
    if (!mounted) return;
    setState(() {
      _isUploadingImage = false;
      _isUploadingVideo = false;
      _isUploadingDoc = false;
      _videoCompressProgress = 0;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Upload cancelled')));
  }

  BoxDecoration _floatingPanelDecoration(BuildContext context) => BoxDecoration(
    color: context.t.surface,
    border: Border.all(color: context.t.line),
    borderRadius: BorderRadius.circular(WarmPopTokens.radiusLg),
    boxShadow: [
      BoxShadow(
        color: context.t.shadow,
        blurRadius: 14,
        offset: const Offset(0, 4),
      ),
    ],
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
            child: child,
          ),
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final reply = ref.watch(replyProvider);

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
                onCancel: () => ref.read(replyProvider.notifier).state = null,
              ),
            ),

          if (_voiceState == _VoiceState.recording)
            _RecordingRow(
              elapsed: _elapsedSec,
              dragOffsetX: _dragOffsetX,
              pulseAnim: _pulseAnim,
              onDragUpdate: (dx) {
                setState(() {
                  _dragOffsetX = dx;
                  _cancelled = dx < -80;
                });
              },
              onStop: () => _stopRecording(cancelled: _cancelled),
            )
          else if (_voiceState == _VoiceState.preview)
            _VoicePreviewRow(
              filePath: _tempPath!,
              duration: _previewDuration ?? '0:00',
              isSending: _isSendingVoice,
              onDiscard: _discardPreview,
              onSend: _sendVoice,
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
              ctrl: _ctrl,
              focusNode: _focusNode,
              hasText: _hasText,
              isLoading: widget.isLoading,
              onAttach: _onAttachPressed,
              onSend: _send,
              onMicLongPressStart: _startRecording,
              onMicLongPressMoveUpdate: (dx) {
                setState(() {
                  _dragOffsetX = dx;
                  _cancelled = dx < -80;
                });
              },
              onMicLongPressEnd: () => _stopRecording(cancelled: _cancelled),
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
  });

  final String tooltip;
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
      message: tooltip,
      excludeFromSemantics: true,
      triggerMode: onLongPressStart == null
          ? TooltipTriggerMode.longPress
          : TooltipTriggerMode.manual,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        child: SizedBox(
          width: 48,
          height: 48,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            onLongPressStart: onLongPressStart,
            onLongPressMoveUpdate: onLongPressMoveUpdate,
            onLongPressEnd: onLongPressEnd,
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
    );
  }
}

// ── Normal input row ───────────────────────────────────────────────────────

class _NormalInputRow extends StatelessWidget {
  const _NormalInputRow({
    required this.ctrl,
    required this.focusNode,
    required this.hasText,
    required this.isLoading,
    required this.onAttach,
    required this.onSend,
    required this.onMicLongPressStart,
    required this.onMicLongPressMoveUpdate,
    required this.onMicLongPressEnd,
  });

  final TextEditingController ctrl;
  final FocusNode focusNode;
  final bool hasText;
  final bool isLoading;
  final VoidCallback onAttach;
  final VoidCallback onSend;
  final VoidCallback onMicLongPressStart;
  final void Function(double) onMicLongPressMoveUpdate;
  final VoidCallback onMicLongPressEnd;

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
          const SizedBox(width: 8),
          Expanded(
            child: Container(
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
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: context.t.onAccent,
                              ),
                            )
                          : const Icon(Icons.send_rounded, size: 20),
                    )
                  : _ComposerAction(
                      key: const ValueKey('mic-action'),
                      tooltip: 'Record voice message',
                      backgroundColor: context.t.accent,
                      foregroundColor: context.t.onAccent,
                      onLongPressStart: (_) => onMicLongPressStart(),
                      onLongPressMoveUpdate: (d) =>
                          onMicLongPressMoveUpdate(d.offsetFromOrigin.dx),
                      onLongPressEnd: (_) => onMicLongPressEnd(),
                      icon: const Icon(Icons.mic, size: 22),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Recording row ──────────────────────────────────────────────────────────

class _RecordingRow extends StatelessWidget {
  const _RecordingRow({
    required this.elapsed,
    required this.dragOffsetX,
    required this.pulseAnim,
    required this.onDragUpdate,
    required this.onStop,
  });

  final int elapsed;
  final double dragOffsetX;
  final Animation<double> pulseAnim;
  final void Function(double) onDragUpdate;
  final VoidCallback onStop;

  String _fmt(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final cancelled = dragOffsetX < -80;
    return Listener(
      onPointerUp: (_) => onStop(),
      child: GestureDetector(
        onHorizontalDragUpdate: (d) => onDragUpdate(dragOffsetX + d.delta.dx),
        onHorizontalDragEnd: (_) => onStop(),
        onHorizontalDragCancel: onStop,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              ScaleTransition(
                scale: pulseAnim,
                child: Icon(Icons.mic, color: context.t.error, size: 28),
              ),
              const SizedBox(width: 12),
              Text(
                _fmt(elapsed),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: context.t.error,
                ),
              ),
              const Spacer(),
              AnimatedOpacity(
                opacity: cancelled ? 0.3 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: Row(
                  children: [
                    Icon(
                      Icons.chevron_left,
                      color: context.t.inkSoft,
                      size: 18,
                    ),
                    Text(
                      cancelled ? 'Release to cancel' : 'Slide to cancel',
                      style: TextStyle(color: context.t.inkSoft, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Voice preview row ──────────────────────────────────────────────────────

class _VoicePreviewRow extends StatefulWidget {
  const _VoicePreviewRow({
    required this.filePath,
    required this.duration,
    required this.isSending,
    required this.onDiscard,
    required this.onSend,
  });

  final String filePath;
  final String duration;
  final bool isSending;
  final VoidCallback onDiscard;
  final VoidCallback onSend;

  @override
  State<_VoicePreviewRow> createState() => _VoicePreviewRowState();
}

class _VoicePreviewRowState extends State<_VoicePreviewRow> {
  final _player = AudioPlayer();
  bool _isPlaying = false;
  bool _isLoading = false;
  Duration _position = Duration.zero;
  Duration _total = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player.positionStream.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    _player.durationStream.listen((dur) {
      if (mounted && dur != null) setState(() => _total = dur);
    });
    _player.playerStateStream.listen((state) {
      if (!mounted) return;
      final playing =
          state.playing && state.processingState != ProcessingState.completed;
      setState(() => _isPlaying = playing);
      if (state.processingState == ProcessingState.completed) {
        _player.seek(Duration.zero);
        _player.pause();
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _player.pause();
      return;
    }
    if (_total == Duration.zero) {
      setState(() => _isLoading = true);
      try {
        await _player.setFilePath(widget.filePath);
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
    await _player.play();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _total.inMilliseconds > 0
        ? (_position.inMilliseconds / _total.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final displayDuration = _total > Duration.zero
        ? _fmt(_total - _position)
        : widget.duration;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          // Discard button
          IconButton(
            onPressed: widget.isSending ? null : widget.onDiscard,
            icon: Icon(Icons.close, color: context.t.error),
            tooltip: 'Discard',
          ),

          // Voice preview pill
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: context.t.surface2,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  // Play / pause button
                  GestureDetector(
                    onTap: widget.isSending ? null : _togglePlay,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: context.t.accent.withValues(alpha: 0.15),
                      ),
                      child: _isLoading
                          ? Padding(
                              padding: const EdgeInsets.all(8),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: context.t.accent,
                              ),
                            )
                          : Icon(
                              _isPlaying ? Icons.pause : Icons.play_arrow,
                              color: context.t.accent,
                              size: 18,
                            ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Progress bar
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: context.t.line,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              context.t.accent,
                            ),
                            minHeight: 3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          displayDuration,
                          style: TextStyle(
                            fontSize: 11,
                            color: context.t.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Send button
          _ComposerAction(
            tooltip: 'Send voice message',
            backgroundColor: context.t.accent,
            foregroundColor: context.t.onAccent,
            onTap: widget.isSending ? null : widget.onSend,
            icon: widget.isSending
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.t.onAccent,
                    ),
                  )
                : const Icon(Icons.send_rounded, size: 20),
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
