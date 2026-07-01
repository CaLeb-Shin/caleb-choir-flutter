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
                if (info.isOver) ...[
                  const SizedBox(height: 14),
                  _overLimitCard(),
                ],
                const SizedBox(height: 14),
                _planExplainCard(),
                const SizedBox(height: 14),
                _manageNoteCard(),
              ],
            ),
    );
  }

  Widget _statusCard(SubscriptionInfo info) {
    final ratio = info.limit <= 0
        ? 0.0
        : (info.activeCount / info.limit).clamp(0.0, 1.0);
    final accent = info.isOver ? AppColors.error : AppColors.primary;
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
            info.isOver ? '한도를 초과했습니다' : '앞으로 ${info.remaining}명 더 등록할 수 있어요',
            style: AppText.body(
              13,
              weight: FontWeight.w700,
              color: info.isOver ? AppColors.error : AppColors.secondary,
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

  Widget _overLimitCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 20, color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '한도를 초과해 신규 단원 승인이 제한됩니다.\n관리자 웹에서 요금제를 올리면 다시 승인할 수 있어요.',
              style: AppText.body(13, height: 1.5, color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _planExplainCard() {
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
          Text('요금제 안내', style: AppText.headline(15)),
          const SizedBox(height: 8),
          _bullet('활성 단원 50명까지 무료로 이용할 수 있어요.'),
          _bullet('50명을 넘으면 10명 단위로 월 구독을 이용합니다.'),
          _bullet('미자립 교회는 별도 지원(후원)으로 무료·할인 적용이 가능합니다.'),
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
              '요금제 변경과 결제는 교회 관리자 웹에서 관리합니다.',
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
