import 'dart:math' as math;
import 'package:flutter/material.dart';

class KakaoTalkLogo extends StatelessWidget {
  final double size;

  const KakaoTalkLogo({super.key, this.size = 22});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _KakaoTalkLogoPainter()),
    );
  }
}

class _KakaoTalkLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width, size.height) / 24;
    canvas.save();
    canvas.translate(
      (size.width - 24 * scale) / 2,
      (size.height - 24 * scale) / 2,
    );
    canvas.scale(scale);

    final paint = Paint()
      ..color = const Color(0xFF191919)
      ..style = PaintingStyle.fill;

    final bubble = Path()
      ..moveTo(12, 4)
      ..cubicTo(6.5, 4, 2.3, 7.5, 2.3, 12)
      ..cubicTo(2.3, 14.8, 4, 17.2, 6.4, 18.7)
      ..lineTo(5.7, 22.1)
      ..lineTo(9.3, 20.2)
      ..cubicTo(10.2, 20.4, 11.1, 20.5, 12, 20.5)
      ..cubicTo(17.5, 20.5, 21.7, 17, 21.7, 12)
      ..cubicTo(21.7, 7.5, 17.5, 4, 12, 4)
      ..close();
    canvas.drawPath(bubble, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class NaverLogo extends StatelessWidget {
  final double size;
  final Color color;

  const NaverLogo({super.key, this.size = 22, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _NaverLogoPainter(color)),
    );
  }
}

class _NaverLogoPainter extends CustomPainter {
  final Color color;

  const _NaverLogoPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final w = size.width;
    final h = size.height;

    final path = Path()
      ..moveTo(w * 0.12, h * 0.12)
      ..lineTo(w * 0.38, h * 0.12)
      ..lineTo(w * 0.62, h * 0.48)
      ..lineTo(w * 0.62, h * 0.12)
      ..lineTo(w * 0.88, h * 0.12)
      ..lineTo(w * 0.88, h * 0.88)
      ..lineTo(w * 0.62, h * 0.88)
      ..lineTo(w * 0.38, h * 0.52)
      ..lineTo(w * 0.38, h * 0.88)
      ..lineTo(w * 0.12, h * 0.88)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _NaverLogoPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class GoogleGLogo extends StatelessWidget {
  final double size;

  const GoogleGLogo({super.key, this.size = 22});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GoogleGLogoPainter()),
    );
  }
}

class _GoogleGLogoPainter extends CustomPainter {
  static const _blue = Color(0xFF4285F4);
  static const _red = Color(0xFFEA4335);
  static const _yellow = Color(0xFFFBBC05);
  static const _green = Color(0xFF34A853);

  @override
  void paint(Canvas canvas, Size size) {
    final shortest = math.min(size.width, size.height);
    final center = Offset(size.width / 2, size.height / 2);
    final strokeWidth = shortest * 0.18;
    final radius = shortest * 0.36;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    void arc(Color color, double start, double sweep) {
      paint.color = color;
      canvas.drawArc(
        rect,
        start * math.pi / 180,
        sweep * math.pi / 180,
        false,
        paint,
      );
    }

    arc(_blue, -38, 82);
    arc(_green, 44, 88);
    arc(_yellow, 132, 74);
    arc(_red, 206, 116);

    final barPaint = Paint()
      ..color = _blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;
    canvas.drawLine(
      Offset(center.dx + shortest * 0.02, center.dy),
      Offset(center.dx + shortest * 0.37, center.dy),
      barPaint,
    );

    final cutPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 1.15
      ..strokeCap = StrokeCap.butt;
    canvas.drawLine(
      Offset(center.dx + shortest * 0.22, center.dy - shortest * 0.17),
      Offset(center.dx + shortest * 0.44, center.dy - shortest * 0.17),
      cutPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
