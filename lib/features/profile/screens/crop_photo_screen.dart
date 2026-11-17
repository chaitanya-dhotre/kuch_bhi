import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/widgets/page_app_bar.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_toast.dart';

/// Output side of the cropped avatar, in pixels.
const kAvatarCropSide = 512;

/// Registry P1: gallery → crop step → file. `null` = cancelled; a picker
/// failure shows the toast and returns `null`.
Future<File?> pickCroppedPhoto(BuildContext context) async {
  try {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 80,
    );
    if (picked == null) return null;
    try {
      if (!context.mounted) return null;
      // F5: move and scale before the photo is used; null = cancelled.
      return await Navigator.of(context).push<File>(
        MaterialPageRoute(
          builder: (_) => CropPhotoScreen(file: File(picked.path)),
        ),
      );
    } finally {
      // F22: the picker's copy is decoded by now; never leave it in temp.
      deleteTempPhoto(File(picked.path));
    }
  } on PlatformException catch (e) {
    debugPrint('[Photo] pickImage failed: $e');
    if (context.mounted) {
      showToast(context, "Couldn't open your photos.", error: true);
    }
    return null;
  }
}

/// F22: best-effort delete of a picked or cropped photo left in temp. Only
/// inside the app's temp dir, so a picker that ever hands back the user's
/// own gallery file can't make us delete it.
void deleteTempPhoto(File? file) {
  if (file == null) return;
  () async {
    final temp = (await getTemporaryDirectory()).path;
    if (p.isWithin(temp, file.path)) await file.delete();
  }().then((_) {}, onError: (_) {});
}

/// F5: the square of [image] (in image pixels) visible in a [viewport]-sized
/// square, when the image is laid out at cover size and transformed by [m]
/// (an InteractiveViewer matrix: uniform scale + translation).
Rect cropRectInImage({
  required Size image,
  required double viewport,
  required Matrix4 m,
}) {
  final cover = math.max(viewport / image.width, viewport / image.height);
  final scale = m.getMaxScaleOnAxis();
  final shift = m.getTranslation();
  final side = viewport / scale / cover;
  final left = (-shift.x / scale) / cover;
  final top = (-shift.y / scale) / cover;
  return Rect.fromLTWH(
    left.clamp(0.0, math.max(0.0, image.width - side)),
    top.clamp(0.0, math.max(0.0, image.height - side)),
    side,
    side,
  );
}

/// F5: move and scale a picked photo inside a circular guide. Pops with the
/// cropped PNG file, or null on cancel.
class CropPhotoScreen extends StatefulWidget {
  const CropPhotoScreen({super.key, required this.file});

  final File file;

  @override
  State<CropPhotoScreen> createState() => _CropPhotoScreenState();
}

class _CropPhotoScreenState extends State<CropPhotoScreen> {
  final _transform = TransformationController();
  ui.Image? _image;
  double _viewport = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _transform.dispose();
    _image?.dispose();
    super.dispose();
  }

  Size get _imageSize =>
      Size(_image!.width.toDouble(), _image!.height.toDouble());

  Future<void> _load() async {
    try {
      final codec =
          await ui.instantiateImageCodec(await widget.file.readAsBytes());
      final image = (await codec.getNextFrame()).image;
      if (!mounted) {
        image.dispose();
        return;
      }
      // Portrait app: the viewport is the screen width less the 16 gutters.
      final viewport = MediaQuery.sizeOf(context).width - 32;
      final cover = math.max(viewport / image.width, viewport / image.height);
      // Open centred.
      _transform.value = Matrix4.translationValues(
        -(image.width * cover - viewport) / 2,
        -(image.height * cover - viewport) / 2,
        0,
      );
      setState(() {
        _image = image;
        _viewport = viewport;
      });
    } catch (e) {
      debugPrint('[Profile] crop load failed: $e');
      _fail();
    }
  }

  void _fail() {
    if (!mounted) return;
    showToast(context, "Couldn't use that photo.", error: true);
    Navigator.of(context).pop();
  }

  Future<void> _use() async {
    setState(() => _busy = true);
    try {
      final src = cropRectInImage(
        image: _imageSize,
        viewport: _viewport,
        m: _transform.value,
      );
      const side = kAvatarCropSide;
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawImageRect(
        _image!,
        src,
        Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
      final out = await recorder.endRecording().toImage(side, side);
      final png = await out.toByteData(format: ui.ImageByteFormat.png);
      out.dispose();
      if (png == null) throw StateError('PNG encode failed');
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/avatar_crop_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(png.buffer.asUint8List(), flush: true);
      if (mounted) Navigator.of(context).pop(file);
    } catch (e) {
      debugPrint('[Profile] crop failed: $e');
      if (mounted) setState(() => _busy = false);
      _fail();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final image = _image;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: t.bg,
        appBar: pageAppBar(context, 'Move and scale'),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: image == null
                      ? const SizedBox.shrink()
                      : _viewportFor(context, image),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        variant: AppButtonVariant.text,
                        onPressed:
                            _busy ? null : () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppButton(
                        onPressed: image == null || _busy ? null : _use,
                        busy: _busy,
                        child: const Text('Use photo'),
                      ),
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

  Widget _viewportFor(BuildContext context, ui.Image image) {
    final t = context.t;
    final cover =
        math.max(_viewport / image.width, _viewport / image.height);
    return Semantics(
      label: 'Photo preview. Pinch to zoom, drag to move.',
      child: SizedBox.square(
        dimension: _viewport,
        child: Stack(
          children: [
            ClipRect(
              child: InteractiveViewer(
                transformationController: _transform,
                constrained: false,
                minScale: 1,
                maxScale: 4,
                // Zero margin keeps the photo covering the whole square.
                boundaryMargin: EdgeInsets.zero,
                child: SizedBox(
                  width: image.width * cover,
                  height: image.height * cover,
                  child: RawImage(image: image, fit: BoxFit.fill),
                ),
              ),
            ),
            IgnorePointer(
              child: CustomPaint(
                size: Size.square(_viewport),
                painter: _CircleGuidePainter(
                  veil: t.bg.withAlpha(166), // 65%
                  ring: t.bg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Veils everything outside the avatar circle and rings its edge.
class _CircleGuidePainter extends CustomPainter {
  const _CircleGuidePainter({required this.veil, required this.ring});

  final Color veil;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final circle = Offset.zero & size;
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(circle)
        ..addOval(circle),
      Paint()..color = veil,
    );
    canvas.drawOval(
      circle.deflate(1),
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_CircleGuidePainter old) =>
      old.veil != veil || old.ring != ring;
}
