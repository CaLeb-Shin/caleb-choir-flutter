import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../models/church.dart';
import '../../providers/app_providers.dart';
import '../../services/firebase_service.dart';

class PendingApprovalScreen extends ConsumerStatefulWidget {
  const PendingApprovalScreen({super.key});

  @override
  ConsumerState<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends ConsumerState<PendingApprovalScreen> {
  Church? _church;
  bool _churchLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadChurch();
  }

  Future<void> _loadChurch() async {
    final profile = ref.read(profileProvider).valueOrNull;
    if (profile == null) return;
    final id = profile.approvalScope == 'platform'
        ? profile.requestedChurchId
        : profile.churchId;
    if (id == null) {
      setState(() => _churchLoaded = true);
      return;
    }
    try {
      final data = await FirebaseService.getChurch(id);
      if (!mounted) return;
      setState(() {
        _church = data == null ? null : Church.fromMap(data);
        _churchLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _churchLoaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final isPlatformScope = profile?.approvalScope == 'platform';
    final churchName = _church?.name ?? '';
    final title = isPlatformScope ? '교회 등록 심사 중' : '가입 승인 대기 중';
    final message = isPlatformScope
        ? '새 교회 등록 신청이 접수되었습니다.\n플랫폼 관리자의 검토 후 승인됩니다.'
        : (churchName.isEmpty
            ? '교회 관리자가 가입 신청을 검토하고 있어요.\n승인되면 바로 알림을 받으실 수 있습니다.'
            : '"$churchName" 관리자가 가입 신청을 검토하고 있어요.\n승인되면 바로 알림을 받으실 수 있습니다.');

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(profileProvider);
            await _loadChurch();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                Center(
                  child: Container(
                    width: 120, height: 120,
                    decoration: BoxDecoration(
                      color: AppColors.secondarySoft,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isPlatformScope ? Icons.add_business_rounded : Icons.hourglass_top_rounded,
                      size: 56, color: AppColors.secondary,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Text(title, style: AppText.headline(26), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Text(message, style: AppText.body(14, color: AppColors.muted), textAlign: TextAlign.center),
                const SizedBox(height: 36),

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
                      if (_churchLoaded && churchName.isNotEmpty) ...[
                        _InfoRow(label: '교회', value: churchName),
                        const SizedBox(height: 10),
                      ],
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
                const SizedBox(height: 36),

                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () async { await FirebaseService.signOut(); },
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
