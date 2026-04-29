import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';

class AppBottomNavBar extends ConsumerWidget {
  final int? currentIndex;
  final bool popToRootOnTap;

  const AppBottomNavBar({
    super.key,
    this.currentIndex,
    this.popToRootOnTap = true,
  });

  static const _items = [
    (_NavGlyph.home, '홈'),
    (_NavGlyph.score, '악보'),
    (_NavGlyph.video, '영상'),
    (_NavGlyph.attendance, '출석'),
    (_NavGlyph.community, '소통'),
    (_NavGlyph.profile, '마이'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = currentIndex ?? ref.watch(tabIndexProvider);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(
          top: BorderSide(color: AppColors.border.withValues(alpha: 0.3)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(_items.length, (i) {
              final active = selectedIndex == i;
              final (glyph, label) = _items[i];
              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () {
                    ref.read(tabIndexProvider.notifier).state = i;
                    if (popToRootOnTap) {
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    }
                  },
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 58,
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: active ? 34 : 30,
                          height: active ? 34 : 30,
                          decoration: BoxDecoration(
                            color: active
                                ? AppColors.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(
                              active ? 10 : 9,
                            ),
                            border: Border.all(
                              color: active
                                  ? Colors.white.withValues(alpha: 0.12)
                                  : Colors.transparent,
                            ),
                            boxShadow: active
                                ? [
                                    BoxShadow(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.18,
                                      ),
                                      blurRadius: 10,
                                      offset: const Offset(0, 5),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              if (active)
                                Positioned(
                                  right: -8,
                                  top: -8,
                                  child: Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      color: AppColors.secondaryContainer
                                          .withValues(alpha: 0.26),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              _CalebNavGlyph(
                                glyph: glyph,
                                size: active ? 20 : 23,
                                color: active ? Colors.white : AppColors.muted,
                                accentColor: active
                                    ? AppColors.secondaryContainer
                                    : AppColors.secondary.withValues(
                                        alpha: 0.56,
                                      ),
                                active: active,
                              ),
                              if (active)
                                Positioned(
                                  right: 5,
                                  bottom: 5,
                                  child: Container(
                                    width: 5,
                                    height: 5,
                                    decoration: const BoxDecoration(
                                      color: AppColors.secondaryContainer,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: active
                                ? FontWeight.w800
                                : FontWeight.w500,
                            color: active ? AppColors.primary : AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

enum _NavGlyph { home, score, video, attendance, community, profile }

class _CalebNavGlyph extends StatelessWidget {
  final _NavGlyph glyph;
  final double size;
  final Color color;
  final Color accentColor;
  final bool active;

  const _CalebNavGlyph({
    required this.glyph,
    required this.size,
    required this.color,
    required this.accentColor,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _CalebNavGlyphPainter(
          glyph: glyph,
          color: color,
          accentColor: accentColor,
          active: active,
        ),
      ),
    );
  }
}

class _CalebNavGlyphPainter extends CustomPainter {
  final _NavGlyph glyph;
  final Color color;
  final Color accentColor;
  final bool active;

  const _CalebNavGlyphPainter({
    required this.glyph,
    required this.color,
    required this.accentColor,
    required this.active,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = active ? 2.25 : 2.05
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final accent = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;

    Offset p(double x, double y) => Offset(w * x, h * y);

    switch (glyph) {
      case _NavGlyph.home:
        final roof = Path()
          ..moveTo(w * 0.15, h * 0.48)
          ..lineTo(w * 0.50, h * 0.18)
          ..lineTo(w * 0.85, h * 0.48);
        canvas.drawPath(roof, stroke);
        final body = RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.25, h * 0.42, w * 0.50, h * 0.42),
          Radius.circular(w * 0.10),
        );
        canvas.drawRRect(body, stroke);
        canvas.drawLine(p(0.50, 0.84), p(0.50, 0.64), stroke);
        canvas.drawCircle(p(0.72, 0.32), w * 0.055, accent);
      case _NavGlyph.score:
        canvas.drawLine(p(0.60, 0.18), p(0.60, 0.67), stroke);
        canvas.drawLine(p(0.60, 0.18), p(0.82, 0.26), stroke);
        canvas.drawLine(p(0.82, 0.26), p(0.82, 0.39), stroke);
        canvas.drawOval(
          Rect.fromCenter(
            center: p(0.43, 0.72),
            width: w * 0.30,
            height: h * 0.20,
          ),
          stroke,
        );
        canvas.drawCircle(p(0.77, 0.70), w * 0.055, accent);
      case _NavGlyph.video:
        canvas.drawCircle(p(0.50, 0.50), w * 0.34, stroke);
        final play = Path()
          ..moveTo(w * 0.44, h * 0.36)
          ..lineTo(w * 0.44, h * 0.64)
          ..lineTo(w * 0.66, h * 0.50)
          ..close();
        canvas.drawPath(play, fill);
        canvas.drawCircle(p(0.70, 0.72), w * 0.045, accent);
      case _NavGlyph.attendance:
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.18, h * 0.24, w * 0.64, h * 0.58),
          Radius.circular(w * 0.10),
        );
        canvas.drawRRect(rect, stroke);
        canvas.drawLine(p(0.18, 0.42), p(0.82, 0.42), stroke);
        canvas.drawLine(p(0.34, 0.16), p(0.34, 0.30), stroke);
        canvas.drawLine(p(0.66, 0.16), p(0.66, 0.30), stroke);
        final check = Path()
          ..moveTo(w * 0.35, h * 0.61)
          ..lineTo(w * 0.46, h * 0.71)
          ..lineTo(w * 0.66, h * 0.54);
        canvas.drawPath(check, stroke);
        canvas.drawCircle(p(0.72, 0.30), w * 0.045, accent);
      case _NavGlyph.community:
        final bubble = RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.18, h * 0.24, w * 0.64, h * 0.46),
          Radius.circular(w * 0.12),
        );
        canvas.drawRRect(bubble, stroke);
        final tail = Path()
          ..moveTo(w * 0.39, h * 0.70)
          ..lineTo(w * 0.31, h * 0.84)
          ..lineTo(w * 0.51, h * 0.70);
        canvas.drawPath(tail, stroke);
        canvas.drawCircle(p(0.40, 0.47), w * 0.035, fill);
        canvas.drawCircle(p(0.58, 0.47), w * 0.035, fill);
        canvas.drawCircle(p(0.72, 0.32), w * 0.045, accent);
      case _NavGlyph.profile:
        canvas.drawCircle(p(0.50, 0.34), w * 0.16, stroke);
        final shoulders = Path()
          ..moveTo(w * 0.22, h * 0.82)
          ..cubicTo(w * 0.25, h * 0.62, w * 0.75, h * 0.62, w * 0.78, h * 0.82);
        canvas.drawPath(shoulders, stroke);
        canvas.drawCircle(p(0.72, 0.30), w * 0.045, accent);
    }
  }

  @override
  bool shouldRepaint(covariant _CalebNavGlyphPainter oldDelegate) {
    return oldDelegate.glyph != glyph ||
        oldDelegate.color != color ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.active != active;
  }
}
