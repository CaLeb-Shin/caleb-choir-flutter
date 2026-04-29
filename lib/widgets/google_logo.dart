import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Google sign-in button mark.
class GoogleLogo extends StatelessWidget {
  final double size;
  const GoogleLogo({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  static const _blue = Color(0xFF4285F4);
  static const _red = Color(0xFFEA4335);
  static const _yellow = Color(0xFFFBBC05);
  static const _green = Color(0xFF34A853);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final shortest = math.min(size.width, size.height);
    final strokeWidth = shortest * 0.17;
    final radius = shortest * 0.36;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.square;

    void arc(Color color, double startDegree, double sweepDegree) {
      paint.color = color;
      canvas.drawArc(
        rect,
        startDegree * math.pi / 180,
        sweepDegree * math.pi / 180,
        false,
        paint,
      );
    }

    arc(_red, 205, 95);
    arc(_yellow, 135, 80);
    arc(_green, 45, 100);
    arc(_blue, -38, 84);

    final barPaint = Paint()
      ..color = _blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.square;
    final barStart = Offset(center.dx + shortest * 0.02, center.dy);
    final barEnd = Offset(center.dx + shortest * 0.33, center.dy);
    canvas.drawLine(barStart, barEnd, barPaint);

    final notchPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 1.08
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(
      Offset(center.dx + shortest * 0.24, center.dy - shortest * 0.14),
      Offset(center.dx + shortest * 0.4, center.dy - shortest * 0.14),
      notchPaint,
    );

    paint.color = _blue;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -38 * math.pi / 180,
      44 * math.pi / 180,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
