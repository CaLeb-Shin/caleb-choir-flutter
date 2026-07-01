import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import '../../theme/app_theme.dart';

/// Read-only subscription status for a church admin. Billing itself is managed
/// on the admin web (no in-app purchase — App Store anti-steering compliance).
class SubscriptionScreen extends ConsumerWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(subscriptionInfoProvider);
    return Scaffold(
      appBar: AppBar(title: Text('구독 · 요금제', style: AppText.headline(18))),
      body: info == null
          ? Center(
              child: Text(
                '교회 정보를 불러올 수 없습니다',
                style: AppText.body(14, color: AppColors.muted),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              children: [
                _statusCard(info),
                const SizedBox(height: 14),
                _planInfoCard(info.isOver),
                // 구독(결제) 안내는 100명을 넘었을 때만 노출.
                if (info.isOver) ...[
                  const SizedBox(height: 14),
                  _manageNoteCard(),
                ],
              ],
            ),
    );
  }

  Widget _statusCard(SubscriptionInfo info) {
    final ratio = info.limit <= 0
        ? 0.0
        : (info.activeCount / info.limit).clamp(0.0, 1.0);
    final accent = info.isOver ? AppColors.secondary : AppColors.primary;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  info.church.displayName,
                  style: AppText.headline(18),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _planBadge(info.planLabel, info.isOver),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${info.activeCount}',
                style: AppText.headline(34, color: accent),
              ),
              const SizedBox(width: 6),
              Text(
                '/ ${info.limit}명',
                style: AppText.body(16, color: AppColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('현재 활성 단원 / 허용 한도', style: AppText.label()),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: AppColors.border.withValues(alpha: 0.4),
              valueColor: AlwaysStoppedAnimation(accent),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            info.isOver ? '무료 100명을 넘었어요' : '앞으로 ${info.remaining}명 더 무료로 등록할 수 있어요',
            style: AppText.body(
              13,
              weight: FontWeight.w700,
              color: AppColors.secondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _planBadge(String label, bool over) {
    final color = over ? AppColors.error : AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppText.body(12.5, weight: FontWeight.w800, color: color),
      ),
    );
  }

  Widget _planInfoCard(bool isOver) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('요금 안내', style: AppText.headline(15)),
          const SizedBox(height: 8),
          _bullet('찬양대원 100명까지는 언제나 무료예요.'),
          // 100명을 넘었을 때만 구독 안내를 보여준다.
          if (isOver)
            _bullet('100명을 넘으면 10명 단위로 구독해 함께 이어가요.'),
        ],
      ),
    );
  }

  Widget _manageNoteCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 20, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '구독·결제는 교회 관리자 웹에서 관리합니다.',
              style: AppText.body(13, height: 1.5, color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7, right: 8),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.secondary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: AppText.body(
                13,
                height: 1.5,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
