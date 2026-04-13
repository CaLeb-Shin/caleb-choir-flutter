import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../../models/user.dart';
import '../../services/firebase_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/interactive.dart';

class CommunityScreen extends ConsumerWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postsAsync = ref.watch(postsProvider);
    final announcementsAsync = ref.watch(announcementsProvider);
    final announcements = announcementsAsync.valueOrNull ?? [];
    final isAdmin = ref.watch(effectiveHasManagePermissionProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Row(children: [
            Expanded(child: Text('커뮤니티', style: AppText.headline(28))),
            // 관리자: 공지 작성 버튼
            if (isAdmin)
              IconButton(
                onPressed: () => _showAnnouncementDialog(context, ref),
                icon: const Icon(Icons.campaign_rounded, color: AppColors.secondary),
                tooltip: '공지 작성',
              ),
          ]),
        ),

        if (announcements.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Tappable(
              onTap: () {},
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  const Icon(Icons.campaign_rounded, size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    announcements.first['title'] ?? '',
                    style: AppText.body(13, weight: FontWeight.w600, color: AppColors.primary),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  )),
                ]),
              ),
            ),
          ),

        Expanded(
          child: postsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => const Center(child: Text('게시물을 불러올 수 없습니다')),
            data: (posts) {
              if (posts.isEmpty) {
                return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.chat_bubble_outline_rounded, size: 40, color: AppColors.subtle),
                  const SizedBox(height: 12),
                  Text('아직 게시물이 없습니다', style: AppText.body(16, weight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('첫 번째 게시물을 작성해보세요!', style: AppText.body(13, color: AppColors.muted)),
                ]));
              }
              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(postsProvider);
                  ref.invalidate(announcementsProvider);
                },
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                  itemCount: posts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final post = posts[i];
                    return Tappable(
                      onTap: () {},
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.card, borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: AppColors.primarySoft,
                              child: Text(
                                User.partLabels[post['userPart']]?[0] ?? '?',
                                style: AppText.body(14, weight: FontWeight.w700, color: AppColors.primary),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(post['userName'] ?? '', style: AppText.body(14, weight: FontWeight.w700)),
                              Text(
                                '${post['userGeneration'] ?? ''} · ${User.partLabels[post['userPart']] ?? ''} · ${_timeAgo(post['createdAt'])}',
                                style: AppText.body(11, color: AppColors.muted),
                              ),
                            ])),
                          ]),
                          const SizedBox(height: 12),
                          Text(post['content'] ?? '', style: AppText.body(14, height: 1.5), maxLines: 4, overflow: TextOverflow.ellipsis),
                          if (post['imageUrl'] != null) ...[
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.network(post['imageUrl'], height: 180, width: double.infinity, fit: BoxFit.cover),
                            ),
                          ],
                        ]),
                      ),
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

  void _showAnnouncementDialog(BuildContext context, WidgetRef ref) {
    final titleCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('공지 작성'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: titleCtrl, decoration: const InputDecoration(hintText: '제목')),
        const SizedBox(height: 10),
        TextField(controller: contentCtrl, decoration: const InputDecoration(hintText: '내용 (선택)'), maxLines: 3),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        TextButton(onPressed: () async {
          if (titleCtrl.text.trim().isNotEmpty) {
            await FirebaseService.createAnnouncement(titleCtrl.text.trim(), content: contentCtrl.text.trim());
            await NotificationService.sendToAll(titleCtrl.text.trim(), contentCtrl.text.trim());
            ref.invalidate(announcementsProvider);
          }
          if (context.mounted) Navigator.pop(context);
        }, child: const Text('작성')),
      ],
    ));
  }

  static String _timeAgo(dynamic dateStr) {
    if (dateStr == null) return '';
    try {
      final d = DateTime.parse(dateStr.toString());
      final diff = DateTime.now().difference(d);
      if (diff.inMinutes < 1) return '방금 전';
      if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
      if (diff.inHours < 24) return '${diff.inHours}시간 전';
      if (diff.inDays < 7) return '${diff.inDays}일 전';
      return '${d.month}/${d.day}';
    } catch (_) { return ''; }
  }
}
