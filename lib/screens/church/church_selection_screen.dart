import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/firebase_service.dart';
import 'church_search_screen.dart';
import 'church_register_screen.dart';

/// 로그인 직후 3갈래 선택 화면: 찬양대원 / 파트장 / 새 교회 등록
class ChurchSelectionScreen extends StatelessWidget {
  const ChurchSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.church_rounded, size: 40, color: AppColors.primary),
                ),
              ),
              const SizedBox(height: 24),
              Text('환영합니다', style: AppText.label(), textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text('어떻게 시작하시겠어요?', style: AppText.headline(26), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(
                '가입 유형을 선택해주세요',
                style: AppText.body(14, color: AppColors.muted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 36),

              _OptionCard(
                icon: Icons.music_note_rounded,
                title: '찬양대원으로 가입',
                subtitle: '교회를 찾아 단원으로 신청합니다',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ChurchSearchScreen(requestedRole: 'member'),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _OptionCard(
                icon: Icons.star_rounded,
                title: '파트장으로 가입',
                subtitle: '교회를 찾아 파트장으로 신청합니다',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ChurchSearchScreen(requestedRole: 'part_leader'),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _OptionCard(
                icon: Icons.add_business_rounded,
                title: '새 교회 등록',
                subtitle: '우리 교회를 직접 등록하고 관리합니다',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ChurchRegisterScreen()),
                ),
                highlight: true,
              ),

              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.secondarySoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.secondary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    '모든 가입 유형은 관리자 승인이 필요합니다',
                    style: AppText.body(12, weight: FontWeight.w600, color: AppColors.secondary),
                  )),
                ]),
              ),
              const SizedBox(height: 24),
              Center(child: TextButton(
                onPressed: () async { await FirebaseService.signOut(); },
                child: Text('다른 계정으로 로그인', style: AppText.body(13, color: AppColors.muted)),
              )),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool highlight;

  const _OptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = highlight ? AppColors.primary : AppColors.surfaceLow;
    final iconBg = highlight ? Colors.white.withValues(alpha: 0.15) : AppColors.card;
    final iconColor = highlight ? Colors.white : AppColors.primary;
    final titleColor = highlight ? Colors.white : AppColors.ink;
    final subColor = highlight ? Colors.white.withValues(alpha: 0.8) : AppColors.muted;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.body(16, weight: FontWeight.w800, color: titleColor)),
                const SizedBox(height: 4),
                Text(subtitle, style: AppText.body(12, color: subColor)),
              ],
            )),
            Icon(Icons.chevron_right_rounded, color: subColor),
          ]),
        ),
      ),
    );
  }
}
