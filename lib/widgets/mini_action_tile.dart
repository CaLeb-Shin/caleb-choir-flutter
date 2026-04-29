import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'interactive.dart';

/// 갈렙 로고 톤을 닮은 홈 그리드용 메뉴 타일.
class MiniActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int? badgeCount;

  /// 새 콘텐츠 알림 (숫자 대신 'N' 라벨)
  final bool hasNew;

  /// 색상 톤: 'primary' (네이비) 또는 'secondary' (골드)
  final String tone;

  const MiniActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.badgeCount,
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
        ],
      ),
    );
  }
}

class _CalebMenuIcon extends StatelessWidget {
  final IconData icon;
  final Color accentColor;
  final Color haloColor;

  const _CalebMenuIcon({
    required this.icon,
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
                child: Icon(icon, size: 19, color: Colors.white),
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
