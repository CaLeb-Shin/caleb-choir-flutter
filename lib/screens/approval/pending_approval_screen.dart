import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../../services/firebase_service.dart';

class PendingApprovalScreen extends ConsumerWidget {
  const PendingApprovalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).valueOrNull;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(profileProvider),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                // ── Clock icon
                Center(
                  child: Container(
                    width: 120, height: 120,
                    decoration: BoxDecoration(
                      color: AppColors.secondarySoft,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.hourglass_top_rounded,
                        size: 56, color: AppColors.secondary),
                  ),
                ),
                const SizedBox(height: 32),
                Text('승인 대기 중',
                  style: AppText.headline(28),
                  textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Text(
                  '관리자가 가입 신청을 검토하고 있어요.\n승인되면 바로 알림을 받으실 수 있습니다.',
                  style: AppText.body(14, color: AppColors.muted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),

                // ── Request info card
                if (profile != null)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLow,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('신청 정보', style: AppText.label()),
                      const SizedBox(height: 14),
                      _InfoRow(label: '이름', value: profile.displayName),
                      const SizedBox(height: 10),
                      _InfoRow(label: '신청 유형', value: profile.requestedRoleLabel),
                      if (profile.generation != null && profile.generation!.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _InfoRow(label: '기수', value: profile.generation!),
                      ],
                      if (profile.part != null) ...[
                        const SizedBox(height: 10),
                        _InfoRow(label: '파트', value: profile.partLabel),
                      ],
                    ]),
                  ),
                const SizedBox(height: 20),

                // ── Refresh hint
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    const Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                      '화면을 아래로 당겨서 상태를 새로고침할 수 있어요',
                      style: AppText.body(12, color: AppColors.primary, weight: FontWeight.w600),
                    )),
                  ]),
                ),
                const SizedBox(height: 40),

                // ── Logout
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () async {
                      await FirebaseService.signOut();
                    },
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: const Text('로그아웃'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      SizedBox(width: 80, child: Text(label, style: AppText.body(13, color: AppColors.muted))),
      Expanded(child: Text(value, style: AppText.body(14, weight: FontWeight.w700))),
    ]);
  }
}
