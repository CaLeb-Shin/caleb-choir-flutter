import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'interactive.dart';

/// 갈렙 로고 톤을 닮은 홈 그리드용 메뉴 타일.
class MiniActionTile extends StatelessWidget {
  final IconData icon;
  final Widget? customIcon;
  final String label;
  final VoidCallback onTap;
  final int? badgeCount;
  final String? statusLabel;

  /// 새 콘텐츠 알림 (숫자 대신 'N' 라벨)
  final bool hasNew;

  /// 색상 톤: 'primary' (네이비) 또는 'secondary' (골드)
  final String tone;

  const MiniActionTile({
    super.key,
    required this.icon,
    this.customIcon,
    required this.label,
    required this.onTap,
    this.badgeCount,
    this.statusLabel,
    this.hasNew = false,
    this.tone = 'primary',
  });

  @override
  Widget build(BuildContext context) {
    final isGold = tone == 'secondary';
    final accentColor = isGold
        ? AppColors.secondaryContainer
        : const Color(0xFF9BB8E6);
    final haloColor = isGold ? AppColors.secondarySoft : AppColors.primarySoft;

    return Tappable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              _CalebMenuIcon(
                icon: icon,
                customIcon: customIcon,
                accentColor: accentColor,
                haloColor: haloColor,
              ),
              if (badgeCount != null && badgeCount! > 0)
                Positioned(
                  top: -5,
                  right: -5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.bg, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      badgeCount! > 9 ? '9+' : '$badgeCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                  ),
                )
              else if (hasNew)
                Positioned(
                  top: -5,
                  right: -5,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.bg, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'N',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          SizedBox(
            width: 72,
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.body(
                10,
                weight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ),
          if (statusLabel != null) ...[
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.secondarySoft,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                statusLabel!,
                style: AppText.body(
                  8,
                  weight: FontWeight.w800,
                  color: AppColors.secondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CalebMenuIcon extends StatelessWidget {
  final IconData icon;
  final Widget? customIcon;
  final Color accentColor;
  final Color haloColor;

  const _CalebMenuIcon({
    required this.icon,
    this.customIcon,
    required this.accentColor,
    required this.haloColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: haloColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.24),
              blurRadius: 14,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              right: -16,
              top: -16,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.32),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              left: -18,
              bottom: -20,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Center(
              child: Transform.translate(
                offset: const Offset(-1, -1),
                child: customIcon ?? Icon(icon, size: 19, color: Colors.white),
              ),
            ),
            Positioned(
              right: 7,
              bottom: 7,
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: accentColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.9),
                    width: 1.4,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StoreMenuGlyph extends StatelessWidget {
  final Color color;

  const StoreMenuGlyph({super.key, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 21,
      child: CustomPaint(painter: _StoreMenuGlyphPainter(color)),
    );
  }
}

class ScoreMenuGlyph extends StatelessWidget {
  final Color color;
  final Color accentColor;

  const ScoreMenuGlyph({
    super.key,
    this.color = Colors.white,
    this.accentColor = AppColors.secondaryContainer,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 22,
      child: CustomPaint(painter: _ScoreMenuGlyphPainter(color, accentColor)),
    );
  }
}

class HarmonyChatMenuGlyph extends StatelessWidget {
  final Color color;
  final Color accentColor;

  const HarmonyChatMenuGlyph({
    super.key,
    this.color = Colors.white,
    this.accentColor = AppColors.secondaryContainer,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 22,
      child: CustomPaint(
        painter: _HarmonyChatMenuGlyphPainter(color, accentColor),
      ),
    );
  }
}

class _HarmonyChatMenuGlyphPainter extends CustomPainter {
  final Color color;
  final Color accentColor;

  const _HarmonyChatMenuGlyphPainter(this.color, this.accentColor);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final accent = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;

    final leftBubble = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.12, h * 0.22, w * 0.36, h * 0.35),
      Radius.circular(w * 0.10),
    );
    final rightBubble = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.42, h * 0.38, w * 0.46, h * 0.35),
      Radius.circular(w * 0.10),
    );
    canvas.drawRRect(leftBubble, stroke);
    canvas.drawRRect(rightBubble, stroke);

    final leftTail = Path()
      ..moveTo(w * 0.22, h * 0.56)
      ..lineTo(w * 0.18, h * 0.70)
      ..lineTo(w * 0.34, h * 0.57);
    canvas.drawPath(leftTail, stroke);

    final rightTail = Path()
      ..moveTo(w * 0.72, h * 0.72)
      ..lineTo(w * 0.84, h * 0.84)
      ..lineTo(w * 0.78, h * 0.70);
    canvas.drawPath(rightTail, stroke);

    for (final dx in [0.23, 0.34, 0.55, 0.67, 0.78]) {
      canvas.drawCircle(
        Offset(w * dx, h * (dx < 0.5 ? 0.40 : 0.55)),
        1.05,
        fill,
      );
    }
    canvas.drawCircle(Offset(w * 0.78, h * 0.30), w * 0.06, accent);
  }

  @override
  bool shouldRepaint(covariant _HarmonyChatMenuGlyphPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.accentColor != accentColor;
  }
}

class _ScoreMenuGlyphPainter extends CustomPainter {
  final Color color;
  final Color accentColor;

  const _ScoreMenuGlyphPainter(this.color, this.accentColor);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final accent = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;

    final cover = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.18, h * 0.13, w * 0.64, h * 0.72),
      Radius.circular(w * 0.12),
    );
    canvas.drawRRect(cover, stroke);
    canvas.drawLine(
      Offset(w * 0.32, h * 0.20),
      Offset(w * 0.32, h * 0.78),
      stroke,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.43, h * 0.25, w * 0.26, h * 0.18),
        Radius.circular(w * 0.04),
      ),
      fill,
    );
    canvas.drawLine(
      Offset(w * 0.45, h * 0.56),
      Offset(w * 0.70, h * 0.56),
      stroke,
    );
    canvas.drawLine(
      Offset(w * 0.45, h * 0.68),
      Offset(w * 0.62, h * 0.68),
      stroke,
    );
    canvas.drawCircle(Offset(w * 0.72, h * 0.27), w * 0.055, accent);
  }

  @override
  bool shouldRepaint(covariant _ScoreMenuGlyphPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.accentColor != accentColor;
  }
}

class _StoreMenuGlyphPainter extends CustomPainter {
  final Color color;

  const _StoreMenuGlyphPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final bag = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.20, h * 0.36, w * 0.60, h * 0.46),
      Radius.circular(w * 0.11),
    );
    canvas.drawRRect(bag, stroke);

    final handle = Path()
      ..moveTo(w * 0.35, h * 0.39)
      ..cubicTo(w * 0.36, h * 0.18, w * 0.64, h * 0.18, w * 0.65, h * 0.39);
    canvas.drawPath(handle, stroke);

    final tag = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.48, h * 0.48, w * 0.18, h * 0.15),
      Radius.circular(w * 0.03),
    );
    canvas.drawRRect(tag, fill);
    canvas.drawCircle(Offset(w * 0.34, h * 0.56), w * 0.025, fill);
  }

  @override
  bool shouldRepaint(covariant _StoreMenuGlyphPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
