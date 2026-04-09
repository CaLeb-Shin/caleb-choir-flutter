import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../../services/firebase_service.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);
    final historyAsync = ref.watch(myHistoryProvider);

    return profileAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('프로필을 불러올 수 없습니다')),
      data: (profile) {
        if (profile == null) return const SizedBox.shrink();
        final attendanceCount = historyAsync.valueOrNull?.length ?? 0;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Text('마이페이지', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2, color: AppColors.secondary)),
              const SizedBox(height: 2),
              const Text('내 프로필', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.primary)),
              const SizedBox(height: 20),

              // Profile Hero
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(color: AppColors.primaryContainer, borderRadius: BorderRadius.circular(24)),
                child: Column(children: [
                  Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(color: AppColors.secondaryContainer, borderRadius: BorderRadius.circular(28)),
                    child: Center(child: Text(profile.partInitial, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.primaryContainer))),
                  ),
                  const SizedBox(height: 16),
                  Text(profile.name ?? '', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(profile.partLabel, style: TextStyle(fontSize: 15, color: Colors.white.withValues(alpha: 0.6))),
                  const SizedBox(height: 16),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    _MetaChip(label: profile.generation ?? ''),
                    const SizedBox(width: 8),
                    _MetaChip(label: profile.isAdmin ? '관리자' : '멤버'),
                  ]),
                ]),
              ),
              const SizedBox(height: 16),

              // Stats Row
              Row(children: [
                Expanded(child: _StatCard(value: '$attendanceCount', label: '총 출석')),
                const SizedBox(width: 10),
                Expanded(child: _StatCard(value: profile.isAdmin ? '관리자' : '멤버', label: '역할')),
                const SizedBox(width: 10),
                Expanded(child: _StatCard(value: profile.partInitial, label: '파트')),
              ]),
              const SizedBox(height: 16),

              // Contact Info
              if (profile.phone != null && profile.phone!.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.surface, borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(color: AppColors.primaryContainer.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.person, size: 18, color: AppColors.secondary),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('연락처', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.muted, letterSpacing: 0.5)),
                      const SizedBox(height: 2),
                      Text(profile.phone!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.primary)),
                    ])),
                  ]),
                ),

              // Menu
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface, borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
                ),
                child: Column(children: [
                  _MenuItem(icon: Icons.person, label: '프로필 수정', onTap: () {}),
                  Divider(height: 0.5, color: AppColors.border.withValues(alpha: 0.15)),
                  _MenuItem(icon: Icons.calendar_today, label: '출석 기록', onTap: () {}),
                  Divider(height: 0.5, color: AppColors.border.withValues(alpha: 0.15)),
                  _MenuItem(icon: Icons.arrow_back, label: '로그아웃', isDestructive: true, onTap: () {
                    showDialog(context: context, builder: (_) => AlertDialog(
                      title: const Text('로그아웃'),
                      content: const Text('정말 로그아웃 하시겠습니까?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
                        TextButton(
                          onPressed: () async {
                            await FirebaseService.signOut();
                            if (context.mounted) Navigator.pop(context);
                          },
                          child: const Text('로그아웃', style: TextStyle(color: AppColors.error)),
                        ),
                      ],
                    ));
                  }),
                ]),
              ),
              const SizedBox(height: 24),
              const Center(child: Text('갈렙찬양대 v1.0.0', style: TextStyle(fontSize: 12, color: AppColors.muted))),
            ],
          ),
        );
      },
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  const _MetaChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.8))),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value, label;
  const _StatCard({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
      ),
      child: Column(children: [
        Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.primary)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.muted, letterSpacing: 0.5)),
      ]),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDestructive;
  final VoidCallback onTap;
  const _MenuItem({required this.icon, required this.label, this.isDestructive = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? AppColors.error : AppColors.primary;
    final bgColor = isDestructive ? AppColors.error.withValues(alpha: 0.07) : AppColors.primaryContainer.withValues(alpha: 0.07);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: isDestructive ? AppColors.error : AppColors.secondary),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color))),
          const Icon(Icons.chevron_right, size: 16, color: AppColors.muted),
        ]),
      ),
    );
  }
}
