import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class HarmonyChatDevelopmentScreen extends StatelessWidget {
  const HarmonyChatDevelopmentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: AppColors.surfaceLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.border.withValues(alpha: 0.45),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.secondarySoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '개발중',
                    style: AppText.body(
                      11,
                      weight: FontWeight.w800,
                      color: AppColors.secondary,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text('하모니챗은 준비 중입니다', style: AppText.headline(22)),
                const SizedBox(height: 10),
                Text(
                  '출석, 악보&음원, 자리 배치판은 먼저 공개하고 하모니챗은 안정화 후 열 예정입니다.',
                  style: AppText.body(
                    14,
                    color: AppColors.onSurfaceVariant,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text('지금 사용할 수 있는 메뉴', style: AppText.headline(17)),
          const SizedBox(height: 10),
          _ReadyFeatureRow(
            icon: Icons.qr_code_rounded,
            title: '출석&투표',
            description: 'QR 출석과 참석 투표를 확인할 수 있습니다.',
          ),
          _ReadyFeatureRow(
            icon: Icons.description_rounded,
            title: '악보&음원',
            description: '등록된 악보와 파트 음원을 확인할 수 있습니다.',
          ),
          _ReadyFeatureRow(
            icon: Icons.event_seat_rounded,
            title: '자리 배치판',
            description: '공개된 자리 배치와 내 자리를 확인할 수 있습니다.',
          ),
        ],
      ),
    );
  }
}

class _ReadyFeatureRow extends StatelessWidget {
  const _ReadyFeatureRow({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.body(14, weight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: AppText.body(12, color: AppColors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
