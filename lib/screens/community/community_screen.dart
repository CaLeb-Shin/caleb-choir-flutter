import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../../models/user.dart';

class CommunityScreen extends ConsumerWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postsAsync = ref.watch(postsProvider);
    final announcementsAsync = ref.watch(announcementsProvider);
    final announcements = announcementsAsync.valueOrNull ?? [];
    final unreadCount = announcements.where((a) => !(a['isRead'] ?? true)).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('공동체', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2, color: AppColors.secondary)),
                const Text('커뮤니티', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.primary)),
              ]),
              Stack(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border.withValues(alpha: 0.3))),
                  child: const Icon(Icons.notifications, size: 18, color: AppColors.primary),
                ),
                if (unreadCount > 0)
                  Positioned(top: -2, right: -2, child: Container(
                    width: 18, height: 18,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.error),
                    child: Center(child: Text('$unreadCount', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700))),
                  )),
              ]),
            ],
          ),
        ),

        // Announcement Banner
        if (announcements.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.secondaryContainer.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.secondary.withValues(alpha: 0.2)),
              ),
              child: Row(children: [
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(color: AppColors.secondary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.notifications, size: 14, color: AppColors.secondary),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(announcements.first['title'] ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.primary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                const Icon(Icons.chevron_right, size: 14, color: AppColors.secondary),
              ]),
            ),
          ),

        // Posts
        Expanded(
          child: postsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => const Center(child: Text('게시물을 불러올 수 없습니다')),
            data: (posts) {
              if (posts.isEmpty) {
                return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.primaryContainer.withValues(alpha: 0.1)),
                    child: const Icon(Icons.forum, size: 36, color: AppColors.muted),
                  ),
                  const SizedBox(height: 16),
                  const Text('아직 게시물이 없습니다', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.primary)),
                  const SizedBox(height: 6),
                  const Text('첫 번째 게시물을 작성해보세요!', style: TextStyle(fontSize: 14, color: AppColors.muted)),
                ]));
              }

              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(postsProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                  itemCount: posts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final post = posts[i];
                    return Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppColors.surface, borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border.withValues(alpha: 0.2)),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Container(
                            width: 42, height: 42,
                            decoration: BoxDecoration(color: AppColors.primaryContainer, borderRadius: BorderRadius.circular(14)),
                            child: Center(child: Text(
                              User.partLabels[post['userPart']]?[0] ?? '?',
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                            )),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(post['userName'] ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.primary)),
                            Text('${post['userGeneration'] ?? ''} · ${User.partLabels[post['userPart']] ?? ''} · ${_formatTime(post['createdAt'])}',
                              style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                          ])),
                        ]),
                        const SizedBox(height: 14),
                        Text(post['content'] ?? '', style: const TextStyle(fontSize: 15, color: AppColors.onSurface, height: 1.5), maxLines: 4, overflow: TextOverflow.ellipsis),
                        if (post['imageUrl'] != null) ...[
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(post['imageUrl'], height: 200, width: double.infinity, fit: BoxFit.cover),
                          ),
                        ],
                      ]),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
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
