import 'package:flutter/material.dart';
import '../../core/theme/tokens.dart';

enum CapyMood { neutral, happy, sleepy }

/// Approved geometry (docs/Capybara.png). Do not "improve" numbers —
/// the user approved this art over three review rounds.
class CapybaraPainter extends CustomPainter {
  CapybaraPainter({
    required this.mood,
    required this.blink,
    required this.breathe,
    required this.showKey,
  });

  final CapyMood mood;
  final double blink; // 0 open … 1 closed
  final double breathe; // 0 rest … 1 expanded
  final bool showKey;

  static const body = Rect.fromLTWH(28, 48, 146, 96);
  static const bodyRadius = 46.0;
  static const earLeft = Offset(80, 52);
  static const earLeftRadius = 12.5;
  static const earRight = Offset(150, 58);
  static const earRightRadius = 11.0;
  static const snout = Rect.fromLTWH(21, 66, 50, 66);
  static const snoutRadius = 23.0;
  static const legFront = Rect.fromLTWH(52, 126, 28, 24);
  static const legMid = Rect.fromLTWH(96, 128, 30, 24);
  static const legBack = Rect.fromLTWH(138, 126, 24, 24);
  static const eyeLeft = Offset(88, 66);
  static const eyeRight = Offset(122, 62);
  static const eyeRadius = 5.5;

  Map<String, dynamic> debugDescription() => {
    'body': body,
    'bodyRadius': bodyRadius,
    'earLeft': earLeft,
    'earLeftRadius': earLeftRadius,
    'earRight': earRight,
    'snout': snout,
    'snoutRadius': snoutRadius,
    'snoutColor': WarmPopTokens.mascotSnout,
    'legFront': legFront,
    'legBack': legBack,
    'eyeLeft': eyeLeft,
    'eyeRight': eyeRight,
  };

  Set<Color> debugColors() => {
    WarmPopTokens.mascotBody,
    WarmPopTokens.mascotSnout,
    WarmPopTokens.mascotFace,
    WarmPopTokens.mascotShade,
    WarmPopTokens.mascotNostril,
  };

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 200, sy = size.height / 180;
    canvas.scale(sx, sy);
    final bodyPaint = Paint()..color = WarmPopTokens.mascotBody;
    final shadePaint = Paint()..color = WarmPopTokens.mascotShade;
    final snoutPaint = Paint()..color = WarmPopTokens.mascotSnout;
    final facePaint = Paint()..color = WarmPopTokens.mascotFace;
    final nostrilPaint = Paint()..color = WarmPopTokens.mascotNostril;
    final goldFill = Paint()..color = WarmPopTokens.keyGold;
    final goldStroke = Paint()
      ..color = WarmPopTokens.keyGold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;

    // Ears (behind body — silhouette nubs)
    canvas.drawCircle(earLeft, earLeftRadius, bodyPaint);
    canvas.drawCircle(earRight, earRightRadius, bodyPaint);

    // Body, with the breathe squeeze (origin = bottom center)
    canvas.save();
    canvas.translate(101, 144);
    canvas.scale(1 - 0.012 * breathe, 1 + 0.025 * breathe);
    canvas.translate(-101, -144);
    final bodyPath = Path()
      ..addRRect(RRect.fromRectAndRadius(body, Radius.circular(bodyRadius)));
    canvas.drawPath(bodyPath, bodyPaint);

    // Legs cross into the bottom edge (approved attachment)
    canvas.drawRRect(
      RRect.fromRectAndRadius(legFront, const Radius.circular(12)),
      shadePaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(legMid, const Radius.circular(12)),
      shadePaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(legBack, const Radius.circular(11)),
      shadePaint,
    );
    canvas.restore();

    // Snout block + nostrils
    canvas.drawRRect(
      RRect.fromRectAndRadius(snout, Radius.circular(snoutRadius)),
      snoutPaint,
    );
    _slit(canvas, const Offset(33, 78), -20, nostrilPaint);
    _slit(canvas, const Offset(49, 75), 14, nostrilPaint);

    // Mouth
    final mouth = Paint()
      ..color = WarmPopTokens.mascotNostril
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final mouthPath = mood != CapyMood.happy
        ? (Path()
            ..moveTo(35, 114)
            ..quadraticBezierTo(44, 121, 53, 114))
        : (Path()
            ..moveTo(35, 110)
            ..quadraticBezierTo(45, 120, 55, 110));
    canvas.drawPath(mouthPath, mouth);

    // Eyes — blink covers them; happy mood draws arcs instead of dots
    final lidPaint = Paint()..color = WarmPopTokens.mascotBody;
    if (mood == CapyMood.neutral) {
      if (blink < 0.5) {
        canvas.drawCircle(eyeLeft, eyeRadius, facePaint);
        canvas.drawCircle(eyeRight, eyeRadius, facePaint);
        canvas.drawCircle(
          eyeLeft + const Offset(2.5, -2.5),
          2,
          Paint()..color = Colors.white,
        );
        canvas.drawCircle(
          eyeRight + const Offset(2.5, -2.5),
          2,
          Paint()..color = Colors.white,
        );
      }
      if (blink > 0) {
        // Eyelid sweep: body-colored cap over each eye
        for (final e in [eyeLeft, eyeRight]) {
          canvas.save();
          canvas.translate(e.dx, e.dy - eyeRadius);
          canvas.scale(1, blink.clamp(0, 1));
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              const Rect.fromLTWH(-7, 0, 14, 12),
              const Radius.circular(6),
            ),
            lidPaint,
          );
          canvas.restore();
        }
      }
    } else if (mood == CapyMood.happy) {
      final arc = Paint()
        ..color = WarmPopTokens.mascotFace
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(
        Path()
          ..moveTo(82, 68)
          ..quadraticBezierTo(89, 59, 96, 68),
        arc,
      );
      canvas.drawPath(
        Path()
          ..moveTo(116, 64)
          ..quadraticBezierTo(123, 55, 130, 64),
        arc,
      );
    } else {
      final sleepy = Paint()
        ..color = WarmPopTokens.mascotFace
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: eyeLeft, radius: eyeRadius),
        0,
        3.14159265,
        false,
        sleepy,
      );
      canvas.drawArc(
        Rect.fromCircle(center: eyeRight, radius: eyeRadius),
        0,
        3.14159265,
        false,
        sleepy,
      );
    }

    // Key (key moment pose) — floating off the back-right
    if (showKey) {
      canvas.save();
      canvas.translate(172, 44);
      canvas.rotate(38 * 3.14159265 / 180);
      canvas.drawCircle(Offset.zero, 9, goldStroke);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(8, -2.5, 24, 5),
          const Radius.circular(2),
        ),
        goldFill,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(24, 2, 4, 7),
          const Radius.circular(1.5),
        ),
        goldFill,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(16, 2, 4, 6),
          const Radius.circular(1.5),
        ),
        goldFill,
      );
      canvas.restore();
    }
  }

  void _slit(Canvas canvas, Offset at, double deg, Paint paint) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(deg * 3.14159265 / 180);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-5, -2.25, 10, 4.5),
        const Radius.circular(2.25),
      ),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CapybaraPainter old) =>
      old.mood != mood ||
      old.blink != blink ||
      old.breathe != breathe ||
      old.showKey != showKey;
}
