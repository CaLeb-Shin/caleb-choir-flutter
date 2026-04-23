import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'interactive.dart';

/// 키즈노트 스타일의 작은 아이콘 타일 — 홈 그리드용
/// 네이비+골드 테마 유지
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
    final bgColor = isGold ? AppColors.secondarySoft : AppColors.primarySoft;
    final iconColor = isGold ? AppColors.secondary : AppColors.primary;

    return Tappable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Stack(clipBehavior: Clip.none, children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(18),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 30, color: iconColor),
          ),
          if (badgeCount != null && badgeCount! > 0)
            Positioned(
              top: -4, right: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
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
              top: -4, right: -4,
              child: Container(
                width: 20, height: 20,
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
        ]),
        const SizedBox(height: 8),
        SizedBox(
          width: 72,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.body(12, weight: FontWeight.w700),
          ),
        ),
      ]),
    );
  }
}
