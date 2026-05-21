import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class CalebScoreSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color backgroundColor;
  final Color borderColor;
  final Color spineColor;
  final double borderRadius;
  final bool showFold;
  final bool showVerticalMarks;
  final double staffOpacity;

  const CalebScoreSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.backgroundColor = AppColors.paper,
    this.borderColor = AppColors.paperLine,
    this.spineColor = AppColors.primary,
    this.borderRadius = 11,
    this.showFold = true,
    this.showVerticalMarks = true,
    this.staffOpacity = 0.55,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    return ClipRRect(
      borderRadius: radius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: radius,
          border: Border.all(color: borderColor),
        ),
        child: CustomPaint(
          painter: _CalebScoreSurfacePainter(
            spineColor: spineColor,
            lineColor: AppColors.paperLine.withValues(alpha: staffOpacity),
            foldColor: AppColors.paperFold,
            showFold: showFold,
            showVerticalMarks: showVerticalMarks,
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _CalebScoreSurfacePainter extends CustomPainter {
  final Color spineColor;
  final Color lineColor;
  final Color foldColor;
  final bool showFold;
  final bool showVerticalMarks;

  const _CalebScoreSurfacePainter({
    required this.spineColor,
    required this.lineColor,
    required this.foldColor,
    required this.showFold,
    required this.showVerticalMarks,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = lineColor
      ..strokeWidth = 1;
    final vertical = Paint()
      ..color = lineColor.withValues(alpha: 0.7)
      ..strokeWidth = 1;

    for (var y = 18.0; y < size.height; y += 34) {
      for (var i = 0; i < 5; i += 1) {
        final yy = y + (i * 4);
        canvas.drawLine(Offset(13, yy), Offset(size.width - 13, yy), line);
      }
    }

    if (showVerticalMarks) {
      for (final x in <double>[size.width * 0.34, size.width * 0.68]) {
        canvas.drawLine(Offset(x, 14), Offset(x, size.height - 14), vertical);
      }
    }

    final spine = Paint()
      ..color = spineColor
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, 5, size.height),
        const Radius.circular(2),
      ),
      spine,
    );

    if (!showFold || size.width < 72 || size.height < 42) return;

    const fold = 30.0;
    final foldPath = Path()
      ..moveTo(size.width - fold, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, fold)
      ..close();
    canvas.drawPath(
      foldPath,
      Paint()
        ..color = foldColor
        ..style = PaintingStyle.fill,
    );
    canvas.drawLine(
      Offset(size.width - fold, 0),
      Offset(size.width, fold),
      Paint()
        ..color = AppColors.paperLine
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(covariant _CalebScoreSurfacePainter oldDelegate) {
    return oldDelegate.spineColor != spineColor ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.foldColor != foldColor ||
        oldDelegate.showFold != showFold ||
        oldDelegate.showVerticalMarks != showVerticalMarks;
  }
}
