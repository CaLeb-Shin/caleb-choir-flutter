import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../../services/firebase_service.dart';
import '../profile_setup/profile_setup_screen.dart';
import '../church/church_selection_screen.dart';

class RejectedScreen extends ConsumerWidget {
  const RejectedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final reason = profile?.rejectionReason;
    final isPlatformScope = profile?.approvalScope == 'platform';

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              Center(
                child: Container(
                  width: 120, height: 120,
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.cancel_rounded,
                      size: 56, color: AppColors.error),
                ),
              ),
              const SizedBox(height: 32),
              Text(isPlatformScope ? '교회 등록이 거절되었습니다' : '가입이 거절되었습니다',
                  style: AppText.headline(26), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(
                isPlatformScope
                  ? '다른 교회에 가입하거나 교회를 다시 등록할 수 있습니다'
                  : '정보를 수정하여 다시 신청하거나, 다른 교회에 가입할 수 있습니다',
                style: AppText.body(14, color: AppColors.muted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              if (reason != null && reason.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('거절 사유', style: AppText.label(color: AppColors.error)),
                    const SizedBox(height: 8),
                    Text(reason, style: AppText.body(14, color: AppColors.ink)),
                  ]),
                ),
              const SizedBox(height: 32),

              // "같은 정보로 다시 신청" — church scope일 때만 의미 있음
              // (platform scope에서 새 교회를 다시 등록하려면 이름부터 새로 입력해야 하므로 아래 '다른 경로' 사용)
              if (!isPlatformScope) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => ProfileSetupScreen(
                          mode: ProfileSetupMode.reapply,
                          requestedRole: profile?.requestedRole ?? 'member',
                        ),
                      ));
                    },
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: const Text('같은 정보로 다시 신청'),
                  ),
                ),
                const SizedBox(height: 10),
              ],

              SizedBox(
                width: double.infinity,
                child: isPlatformScope
                  ? ElevatedButton(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const ChurchSelectionScreen(),
                      )),
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: const Text('다른 교회에 가입 또는 재등록'),
                    )
                  : OutlinedButton(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const ChurchSelectionScreen(),
                      )),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: const Text('다른 교회에 가입'),
                    ),
              ),
              const SizedBox(height: 24),
              Center(child: TextButton(
                onPressed: () async { await FirebaseService.signOut(); },
                child: Text('로그아웃', style: AppText.body(13, color: AppColors.muted)),
              )),
            ],
          ),
        ),
      ),
    );
  }
}
