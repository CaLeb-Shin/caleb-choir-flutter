import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class StoreScreen extends StatelessWidget {
  const StoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('스토어', style: AppText.headline(32)),
          const SizedBox(height: 8),
          Text(
            '찬양대와 교회가 함께 쓰는 굿즈 공간을 준비하고 있어요',
            style: AppText.body(15, color: AppColors.muted),
          ),
          const SizedBox(height: 26),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AppColors.border.withValues(alpha: 0.35),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: AppColors.secondarySoft,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.shopping_bag_rounded,
                    color: AppColors.secondary,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 22),
                Text('C.C Note Store', style: AppText.headline(24)),
                const SizedBox(height: 10),
                Text(
                  '다양한 교회 굿즈들을 구매할 수 있도록 준비 중입니다',
                  style: AppText.body(
                    18,
                    weight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '단체 티셔츠, 악보 바인더, 찬양대 굿즈, 행사 패키지까지 교회별 입점과 주문 흐름을 하나씩 만들어갈 예정입니다.',
                  style: AppText.body(14, color: AppColors.muted, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.surfaceLow,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppColors.border.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.pending_actions_rounded,
                  color: AppColors.secondary,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '입점 신청, 상품 검수, 주문/정산 시스템은 순차적으로 열릴 예정이에요.',
                    style: AppText.body(14, color: AppColors.muted, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
