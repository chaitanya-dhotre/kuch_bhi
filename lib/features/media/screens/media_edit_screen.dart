import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../services/media_upload_service.dart';
import '../../chat/message_offline_policy.dart';

/// The source-pixel rectangle visible through a frame after an InteractiveViewer transform.
Rect mediaFrameToSourceRect({
  required Size image,
  required Size frame,
  required Matrix4 transform,
}) {
  final cover = math.max(
    frame.width / image.width,
    frame.height / image.height,
  );
  final scale = transform.getMaxScaleOnAxis();
  final shift = transform.getTranslation();
  final left = (-shift.x / scale) / cover;
  final top = (-shift.y / scale) / cover;
  final width = frame.width / scale / cover;
  final height = frame.height / scale / cover;
  final maxLeft = math.max(0.0, image.width - width);
  final maxTop = math.max(0.0, image.height - height);
  return Rect.fromLTWH(
    left.clamp(0.0, maxLeft),
    top.clamp(0.0, maxTop),
    width,
    height,
  );
}

/// Converts a point in frame-local logical coordinates to source image pixels.
Offset mediaTouchToImagePixels({
  required Offset point,
  required Size image,
  required Size frame,
  required Matrix4 transform,
}) {
  final inverse = Matrix4.inverted(transform);
  final local = MatrixUtils.transformPoint(inverse, point);
  final cover = math.max(
    frame.width / image.width,
    frame.height / image.height,
  );
  return Offset(local.dx / cover, local.dy / cover);
}

Offset rotateMediaPointClockwise(Offset point, Size oldImage) =>
    Offset(oldImage.height - point.dy, point.dx);

Future<ui.Image> rotateMediaImageClockwise(ui.Image image) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..translate(image.height.toDouble(), 0)
    ..rotate(math.pi / 2);
  canvas.drawImage(image, Offset.zero, Paint());
  return recorder.endRecording().toImage(image.height, image.width);
}

Future<Uint8List> mediaCropPngBytes({
  required ui.Image image,
  required Size frame,
  required Matrix4 transform,
  List<List<Offset>> strokes = const [],
  List<Color> strokeColors = const [],
}) async {
  final src = mediaFrameToSourceRect(
    image: Size(image.width.toDouble(), image.height.toDouble()),
    frame: frame,
    transform: transform,
  );
  final outW = src.width.round().clamp(1, image.width);
  final outH = src.height.round().clamp(1, image.height);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImageRect(
    image,
    src,
    Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
    Paint()..filterQuality = FilterQuality.high,
  );
  for (var i = 0; i < strokes.length; i++) {
    final stroke = strokes[i];
    if (stroke.length < 2) continue;
    final path = Path();
    for (var j = 0; j < stroke.length; j++) {
      final point = stroke[j];
      final x = (point.dx - src.left) * outW / src.width;
      final y = (point.dy - src.top) * outH / src.height;
      if (j == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = strokeColors[i]
        // 4 logical px at fit (the preview's width), whatever the zoom.
        ..strokeWidth =
            4 /
            math.max(frame.width / image.width, frame.height / image.height) *
            outW /
            src.width
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }
  final result = await recorder.endRecording().toImage(outW, outH);
  final bytes = await result.toByteData(format: ui.ImageByteFormat.png);
  result.dispose();
  if (bytes == null) throw StateError('PNG encode failed');
  return bytes.buffer.asUint8List();
}

class MediaEditResult {
  const MediaEditResult({
    this.file,
    this.trimStart,
    this.trimEnd,
    this.sourceDuration,
    this.formatHint,
  });
  final File? file;
  final int? trimStart;
  final int? trimEnd;
  final int? sourceDuration;
  final String? formatHint;
}

class MediaEditScreen extends StatefulWidget {
  const MediaEditScreen({super.key, required this.file, required this.type});
  final File file;
  final String type;
  @override
  State<MediaEditScreen> createState() => _MediaEditScreenState();
}

class _MediaEditScreenState extends State<MediaEditScreen> {
  static const drawColors = <Color>[
    Color(0xFFFFFFFF),
    Color(0xFF000000),
    Color(0xFFE5484D),
    Color(0xFFEFA00B),
    Color(0xFF0E9F6E),
    Color(0xFF4A6FA5),
  ];
  static const colorNames = <String>[
    'White',
    'Black',
    'Red',
    'Orange',
    'Green',
    'Blue',
  ];
  ui.Image? _image;
  VideoPlayerController? _video;
  final TransformationController _transform = TransformationController();
  String _tool = 'Crop';
  bool _square = false;
  int _colorIndex = 0;
  final List<List<Offset>> _strokes = [];
  final List<Color> _strokeColors = [];
  bool _edited = false, _failed = false, _ready = false, _gif = false;
  RangeValues _range = const RangeValues(0, 0);
  String _formatHint = 'jpeg';
  Size _currentFrame = Size.zero;
  bool get _videoType => widget.type == 'video';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (_videoType) {
        _video = VideoPlayerController.file(widget.file);
        await _video!.initialize();
        _video!.addListener(_keepInRange);
        final end = _video!.value.duration.inSeconds.clamp(0, 300).toDouble();
        _range = RangeValues(0, end);
      } else {
        final bytes = await widget.file.readAsBytes();
        _formatHint = MediaUploadService.imageFormatHint(bytes);
        _gif =
            widget.file.path.toLowerCase().endsWith('.gif') ||
            await MediaUploadService.isAnimatedImage(widget.file);
        final codec = await ui.instantiateImageCodec(bytes);
        _image = (await codec.getNextFrame()).image;
      }
      _ready = true;
    } catch (error) {
      debugPrint('[MediaEdit] source load failed: $error');
      _failed = true;
      if (mounted) {
        showToast(
          context,
          _videoType ? "Couldn't open that video." : "Couldn't use that photo.",
          error: true,
        );
        Navigator.of(context).removeRoute(ModalRoute.of(context)!, null);
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _close() async {
    if (_edited) {
      final discard = await showConfirmDialog(
        context: context,
        title: 'Discard changes?',
        body: 'Your crop and drawing will be lost.',
        confirmLabel: 'Discard',
        destructive: true,
      );
      if (!discard || !mounted) return;
    }
    Navigator.of(context).removeRoute(ModalRoute.of(context)!, null);
  }

  String _time(double seconds) =>
      '${seconds ~/ 60}:${(seconds.toInt() % 60).toString().padLeft(2, '0')}';

  Size _frameSize(Size area, ui.Image image) {
    if (_square) {
      final side = math.min(area.width, area.height);
      return Size.square(side);
    }
    final ratio = image.width / image.height;
    if (area.width / area.height > ratio) {
      return Size(area.height * ratio, area.height);
    }
    return Size(area.width, area.width / ratio);
  }

  void _centerTransform(Size frame, ui.Image image) {
    final cover = math.max(
      frame.width / image.width,
      frame.height / image.height,
    );
    _transform.value = Matrix4.identity()
      ..setTranslationRaw(
        -(image.width * cover - frame.width) / 2,
        -(image.height * cover - frame.height) / 2,
        0,
      );
  }

  Future<void> _rotate() async {
    final old = _image!;
    final next = await rotateMediaImageClockwise(old);
    for (final stroke in _strokes) {
      for (var i = 0; i < stroke.length; i++) {
        stroke[i] = rotateMediaPointClockwise(
          stroke[i],
          Size(old.width.toDouble(), old.height.toDouble()),
        );
      }
    }
    old.dispose();
    setState(() {
      _image = next;
      _edited = true;
      _transform.value = Matrix4.identity();
    });
  }

  Future<File?> _export(Size frame) async {
    final bytes = await mediaCropPngBytes(
      image: _image!,
      frame: frame,
      transform: _transform.value,
      strokes: _strokes,
      strokeColors: _strokeColors,
    );
    final file = File(
      '${Directory.systemTemp.path}/media_edit_${DateTime.now().microsecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(bytes);
    return file;
  }

  /// The preview plays only the trimmed range, and its position label
  /// follows playback.
  void _keepInRange() {
    final v = _video!.value;
    if (v.isPlaying && v.position >= Duration(seconds: _range.end.round())) {
      _video!.pause();
      _video!.seekTo(Duration(seconds: _range.start.round()));
    }
    if (mounted) setState(() {});
  }

  void _togglePlay() {
    final v = _video!.value;
    if (v.isPlaying) {
      _video!.pause();
      return;
    }
    final start = Duration(seconds: _range.start.round());
    if (v.position < start ||
        v.position >= Duration(seconds: _range.end.round())) {
      _video!.seekTo(start);
    }
    _video!.play();
  }

  void _send(Size frame) async {
    final file = _videoType || _gif || !_edited ? null : await _export(frame);
    if (!mounted) return;
    Navigator.of(context).removeRoute(
      ModalRoute.of(context)!,
      MediaEditResult(
        file: file,
        trimStart: _videoType ? _range.start.round() : null,
        trimEnd: _videoType ? _range.end.round() : null,
        sourceDuration: _videoType ? _video?.value.duration.inSeconds : null,
        formatHint: _videoType ? null : _formatHint,
      ),
    );
  }

  @override
  void dispose() {
    _video?.dispose();
    _image?.dispose();
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox.shrink();
    final t = context.t;
    if (_gif) {
      return Scaffold(
        backgroundColor: t.surface,
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  tooltip: 'Close',
                  onPressed: _close,
                  icon: const Icon(Icons.close),
                ),
              ),
              Expanded(child: Center(child: Image.file(widget.file))),
              const Text(kGifSentAsIs),
              Padding(
                padding: const EdgeInsets.all(16),
                child: AppButton(
                  key: const Key('media-editor-send'),
                  onPressed: _ready ? () => _send(Size.zero) : null,
                  child: const Text('Send'),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final trimMax = (_video?.value.duration.inSeconds.toDouble() ?? 1)
        .clamp(1, 300)
        .toDouble();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: t.surface,
        body: SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _close,
                    icon: const Icon(Icons.close),
                  ),
                  const Spacer(),
                  if (!_videoType)
                    TextButton(
                      onPressed: _ready ? _rotate : null,
                      child: const Text('Rotate', semanticsLabel: 'Rotate'),
                    ),
                ],
              ),
              Expanded(
                child: Center(
                  child: _videoType
                      ? (_video?.value.isInitialized == true
                            ? GestureDetector(
                                onTap: _togglePlay,
                                child: AspectRatio(
                                  aspectRatio: _video!.value.aspectRatio,
                                  child: VideoPlayer(_video!),
                                ),
                              )
                            : const SizedBox.shrink())
                      : _image == null
                      ? const SizedBox.shrink()
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final area = Size(
                              constraints.maxWidth,
                              constraints.maxHeight,
                            );
                            final frame = _frameSize(area, _image!);
                            _currentFrame = frame;
                            final image = _image!;
                            final cover = math.max(
                              frame.width / image.width,
                              frame.height / image.height,
                            );
                            if (_transform.value.isIdentity()) {
                              _centerTransform(frame, image);
                            }
                            final sw = image.width * cover,
                                sh = image.height * cover;
                            return SizedBox.expand(
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  ExcludeSemantics(
                                    child: ClipRect(
                                      child: SizedBox.fromSize(
                                        size: frame,
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onPanStart: _tool == 'Draw'
                                              ? (d) => setState(() {
                                                  _strokes.add([
                                                    mediaTouchToImagePixels(
                                                      point: d.localPosition,
                                                      image: Size(
                                                        image.width.toDouble(),
                                                        image.height.toDouble(),
                                                      ),
                                                      frame: frame,
                                                      transform:
                                                          _transform.value,
                                                    ),
                                                  ]);
                                                  _strokeColors.add(
                                                    drawColors[_colorIndex],
                                                  );
                                                  _edited = true;
                                                })
                                              : null,
                                          onPanUpdate: _tool == 'Draw'
                                              ? (d) => setState(
                                                  () => _strokes.last.add(
                                                    mediaTouchToImagePixels(
                                                      point: d.localPosition,
                                                      image: Size(
                                                        image.width.toDouble(),
                                                        image.height.toDouble(),
                                                      ),
                                                      frame: frame,
                                                      transform:
                                                          _transform.value,
                                                    ),
                                                  ),
                                                )
                                              : null,
                                          // Draw: one finger draws. The viewer's
                                          // scale recognizer would win that
                                          // gesture even with pan/zoom off.
                                          child: IgnorePointer(
                                            ignoring: _tool == 'Draw',
                                            child: InteractiveViewer(
                                              transformationController:
                                                  _transform,
                                              constrained: false,
                                              minScale: 1,
                                              maxScale: 5,
                                              panEnabled: _tool != 'Draw',
                                              scaleEnabled: _tool != 'Draw',
                                              boundaryMargin: EdgeInsets.zero,
                                              onInteractionEnd: (_) => setState(
                                                () => _edited = true,
                                              ),
                                              child: SizedBox(
                                                width: sw,
                                                height: sh,
                                                child: CustomPaint(
                                                  painter: _PhotoPainter(
                                                    image,
                                                    cover,
                                                    _strokes,
                                                    _strokeColors,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  IgnorePointer(
                                    child: CustomPaint(
                                      size: area,
                                      painter: _FrameShade(
                                        frame,
                                        t.ink.withValues(alpha: .32),
                                      ),
                                    ),
                                  ),
                                  Positioned.fromRect(
                                    rect: Rect.fromCenter(
                                      center: Offset(
                                        area.width / 2,
                                        area.height / 2,
                                      ),
                                      width: frame.width,
                                      height: frame.height,
                                    ),
                                    child: IgnorePointer(
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: t.surface.withValues(
                                              alpha: .55,
                                            ),
                                            width: 1,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ),
              if (_videoType) ...[
                Text(
                  '${_time((_video?.value.position.inMilliseconds ?? 0) / 1000)}'
                  '  ·  Length ${_time(_range.end - _range.start)}',
                  style: const TextStyle(
                    fontFeatures: [ui.FontFeature.tabularFigures()],
                  ),
                ),
                _AccessibleTrim(
                  range: _range,
                  max: trimMax,
                  time: _time,
                  changed: (v) => setState(() {
                    // The preview jumps to the handle that moved.
                    final moved = v.start != _range.start ? v.start : v.end;
                    _range = v;
                    _edited = true;
                    _video?.pause();
                    _video?.seekTo(Duration(seconds: moved.round()));
                  }),
                ),
              ] else
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 4,
                  children: [
                    TextButton(
                      onPressed: () => setState(() {
                        if (_square) {
                          _square = false;
                          _transform.value = Matrix4.identity();
                          _edited = true;
                        }
                      }),
                      child: const Text('Original'),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        if (!_square) {
                          _square = true;
                          _transform.value = Matrix4.identity();
                          _edited = true;
                        }
                      }),
                      child: const Text('Square'),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _tool = 'Crop'),
                      child: const Text('Crop'),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _tool = 'Draw'),
                      child: const Text('Draw'),
                    ),
                    if (_tool == 'Draw') ...[
                      for (var i = 0; i < drawColors.length; i++)
                        IconButton(
                          tooltip: colorNames[i],
                          onPressed: () => setState(() => _colorIndex = i),
                          icon: Icon(
                            Icons.circle,
                            color: drawColors[i],
                            size: 18,
                          ),
                        ),
                      TextButton(
                        onPressed: _strokes.isEmpty
                            ? null
                            : () => setState(() {
                                _strokes.removeLast();
                                _strokeColors.removeLast();
                              }),
                        child: const Text('Undo'),
                      ),
                      TextButton(
                        onPressed: _strokes.isEmpty
                            ? null
                            : () => setState(() {
                                _strokes.clear();
                                _strokeColors.clear();
                              }),
                        child: const Text('Clear'),
                      ),
                    ],
                  ],
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: AppButton(
                  key: const Key('media-editor-send'),
                  onPressed: _ready ? () => _send(_currentFrame) : null,
                  child: const Text('Send'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoPainter extends CustomPainter {
  const _PhotoPainter(this.image, this.scale, this.strokes, this.colors);
  final ui.Image image;
  final double scale;
  final List<List<Offset>> strokes;
  final List<Color> colors;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..filterQuality = FilterQuality.high,
    );
    for (var i = 0; i < strokes.length; i++) {
      if (strokes[i].length < 2) continue;
      final p = Path()
        ..moveTo(strokes[i].first.dx * scale, strokes[i].first.dy * scale);
      for (final point in strokes[i].skip(1)) {
        p.lineTo(point.dx * scale, point.dy * scale);
      }
      canvas.drawPath(
        p,
        Paint()
          ..color = colors[i]
          ..strokeWidth = 4
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  // The stroke lists are edited in place, so an identity check never sees a
  // new stroke, an Undo or a Clear.
  bool shouldRepaint(_PhotoPainter old) => true;
}

class _FrameShade extends CustomPainter {
  const _FrameShade(this.frame, this.color);
  final Size frame;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(
        Rect.fromCenter(
          center: Offset(size.width / 2, size.height / 2),
          width: frame.width,
          height: frame.height,
        ),
      );
    canvas.drawPath(outside, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_FrameShade old) =>
      old.frame != frame || old.color != color;
}

class _AccessibleTrim extends StatelessWidget {
  const _AccessibleTrim({
    required this.range,
    required this.max,
    required this.time,
    required this.changed,
  });
  final RangeValues range;
  final double max;
  final String Function(double) time;
  final ValueChanged<RangeValues> changed;
  @override
  Widget build(BuildContext context) => RangeSlider(
    values: range,
    min: 0,
    max: max,
    divisions: max.round(),
    semanticFormatterCallback: (value) => value == range.start
        ? 'Trim start ${time(value)}'
        : 'Trim end ${time(value)}',
    labels: RangeLabels(time(range.start), time(range.end)),
    onChanged: changed,
  );
}
