import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../../models/user.dart' as app_user;

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);
    final announcementsAsync = ref.watch(announcementsProvider);
    final historyAsync = ref.watch(myHistoryProvider);

    return profileAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('프로필을 불러올 수 없습니다')),
      data: (profile) {
        if (profile == null) return const SizedBox.shrink();
        final announcements = announcementsAsync.valueOrNull ?? [];
        final unreadCount = announcements.where((a) => !(a['isRead'] ?? true)).length;
        final attendanceCount = historyAsync.valueOrNull?.length ?? 0;
        final today = DateTime.now();
        final dateStr = '${today.year}년 ${today.month}월 ${today.day}일';

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset('assets/images/icon.png', width: 36, height: 36),
                    ),
                    const SizedBox(width: 10),
                    const Text('갈렙 찬양대', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.primary)),
                  ]),
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.secondary,
                    child: Text(profile.partInitial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Welcome
              Text('환영합니다', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 2, color: AppColors.secondary)),
              const SizedBox(height: 6),
              Text('${profile.name ?? "멤버"}님,\n오늘도 함께 찬양해요',
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.primary, height: 1.3)),
              const SizedBox(height: 8),
              Text(dateStr, style: const TextStyle(fontSize: 14, color: AppColors.muted)),
              const SizedBox(height: 24),

              // Profile Hero Card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(profile.name ?? '', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
                          const SizedBox(height: 4),
                          Text('${profile.generation} · ${profile.partLabel}',
                            style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.7))),
                          const SizedBox(height: 16),
                          Row(children: [
                            _HeroStat(value: '$attendanceCount', label: '총 출석'),
                            Container(width: 1, height: 28, color: Colors.white.withValues(alpha: 0.2), margin: const EdgeInsets.symmetric(horizontal: 16)),
                            _HeroStat(value: profile.isAdmin ? '관리자' : '멤버', label: '역할'),
                          ]),
                        ],
                      ),
                    ),
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: AppColors.secondaryContainer,
                      child: Text(profile.partInitial, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.primaryContainer)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Quick Actions
              Row(children: [
                Expanded(child: _QuickAction(
                  icon: Icons.event_note, title: '출석하기', subtitle: '연습 출석 체크인',
                  isPrimary: true, onTap: () {},
                )),
                const SizedBox(width: 12),
                Expanded(child: _QuickAction(
                  icon: Icons.library_music, title: '찬양 영상', subtitle: '영상 라이브러리',
                  onTap: () {},
                )),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _QuickAction(
                  icon: Icons.forum, title: '커뮤니티', subtitle: '게시물 & 소통',
                  onTap: () {},
                )),
                const SizedBox(width: 12),
                Expanded(child: _QuickAction(
                  icon: Icons.notifications, title: '공지사항',
                  subtitle: unreadCount > 0 ? '$unreadCount 새 공지' : '최신 소식 확인',
                  onTap: () {},
                )),
              ]),
              const SizedBox(height: 24),

              // Announcements
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('최신 소식', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primary)),
                  Icon(Icons.notifications, color: AppColors.secondary, size: 20),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    if (announcements.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('공지사항이 없습니다', style: TextStyle(color: AppColors.muted)),
                      )
                    else
                      ...announcements.take(3).map((ann) => _AnnouncementItem(
                        title: ann['title'] ?? '',
                        time: _formatTime(ann['createdAt']),
                        isRead: ann['isRead'] ?? false,
                      )),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _formatTime(dynamic dateStr) {
    if (dateStr == null) return '';
    try {
      final d = DateTime.parse(dateStr.toString());
      final diff = DateTime.now().difference(d);
      if (diff.inMinutes < 1) return '방금 전';
      if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
      if (diff.inHours < 24) return '${diff.inHours}시간 전';
      if (diff.inDays < 7) return '${diff.inDays}일 전';
      return '${d.month}/${d.day}';
    } catch (_) {
      return '';
    }
  }
}

class _HeroStat extends StatelessWidget {
  final String value, label;
  const _HeroStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.6), letterSpacing: 1)),
    ]);
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final bool isPrimary;
  final VoidCallback onTap;

  const _QuickAction({required this.icon, required this.title, required this.subtitle, this.isPrimary = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isPrimary ? AppColors.primaryContainer : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: isPrimary ? null : Border.all(color: AppColors.border.withValues(alpha: 0.3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 32, color: isPrimary ? AppColors.secondaryContainer : AppColors.secondary),
          const SizedBox(height: 8),
          Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: isPrimary ? Colors.white : AppColors.primary)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(fontSize: 12, color: isPrimary ? Colors.white.withValues(alpha: 0.6) : AppColors.muted)),
        ]),
      ),
    );
  }
}

class _AnnouncementItem extends StatelessWidget {
  final String title, time;
  final bool isRead;
  const _AnnouncementItem({required this.title, required this.time, required this.isRead});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: isRead ? AppColors.border : AppColors.secondary),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(time, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.muted)),
          const SizedBox(height: 4),
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.primary), maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
        const Icon(Icons.chevron_right, size: 14, color: AppColors.muted),
      ]),
    );
  }
}
