import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/firebase_service.dart';

/// Platform admin(sinbun001@gmail.com)이 Flutter 앱으로 로그인했을 때 안내 화면.
/// Flutter 앱은 교회 단원용이고, 관리자 작업은 웹 어드민에서 수행.
class PlatformAdminNoticeScreen extends StatelessWidget {
  const PlatformAdminNoticeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 120, height: 120,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.admin_panel_settings_rounded,
                      size: 56, color: AppColors.primary),
                ),
              ),
              const SizedBox(height: 32),
              Text('플랫폼 관리자 계정',
                  style: AppText.headline(26), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(
                '이 계정은 플랫폼 전체의 관리자 권한을 가집니다.\n'
                '교회 승인, 플랫폼 관리 작업은 웹 어드민에서 진행해주세요.',
                style: AppText.body(14, color: AppColors.muted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('웹 어드민 주소', style: AppText.label()),
                  const SizedBox(height: 8),
                  Text(
                    'https://caleb-choir-2026-admin.web.app',
                    style: AppText.body(14, weight: FontWeight.w700, color: AppColors.primary),
                  ),
                  const SizedBox(height: 4),
                  Text('브라우저에서 위 주소로 접속해주세요',
                      style: AppText.body(12, color: AppColors.muted)),
                ]),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () async { await FirebaseService.signOut(); },
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: const Text('다른 계정으로 로그인'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
