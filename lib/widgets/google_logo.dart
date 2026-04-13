import 'dart:math';
import 'package:flutter/material.dart';

/// 공식 Google "G" 로고를 CustomPainter로 그리는 위젯
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
  // Google 공식 브랜드 컬러
  static const _blue = Color(0xFF4285F4);
  static const _red = Color(0xFFEA4335);
  static const _yellow = Color(0xFFFBBC05);
  static const _green = Color(0xFF34A853);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final strokeWidth = radius * 0.42;
    final innerRadius = radius - strokeWidth / 2;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    // Blue arc (right side, -50° to 50°)
    paint.color = _blue;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: innerRadius),
      -50 * pi / 180,
      100 * pi / 180,
      false,
      paint,
    );

    // Green arc (bottom right, 50° to 120°)
    paint.color = _green;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: innerRadius),
      50 * pi / 180,
      70 * pi / 180,
      false,
      paint,
    );

    // Yellow arc (bottom left, 120° to 195°)
    paint.color = _yellow;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: innerRadius),
      120 * pi / 180,
      75 * pi / 180,
      false,
      paint,
    );

    // Red arc (top, 195° to 310°)
    paint.color = _red;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: innerRadius),
      195 * pi / 180,
      115 * pi / 180,
      false,
      paint,
    );

    // Blue horizontal bar (right middle)
    final barPaint = Paint()
      ..color = _blue
      ..style = PaintingStyle.fill;

    final barTop = center.dy - strokeWidth / 2;
    final barLeft = center.dx - radius * 0.05;
    canvas.drawRect(
      Rect.fromLTWH(barLeft, barTop, radius * 0.55, strokeWidth),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
