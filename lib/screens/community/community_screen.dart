import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../../providers/awards_provider.dart';
import '../../models/user.dart';
import '../../services/firebase_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/interactive.dart';
import '../../widgets/user_badges.dart';
import 'post_detail_screen.dart';

class CommunityScreen extends ConsumerWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postsAsync = ref.watch(postsProvider);
    final announcementsAsync = ref.watch(announcementsProvider);
    final announcements = announcementsAsync.valueOrNull ?? [];
    final isAdmin = ref.watch(effectiveHasManagePermissionProvider);
    final awardsAsync = ref.watch(awardsProvider);
    final members = ref.watch(membersProvider).valueOrNull ?? [];
    Map<String, dynamic>? memberById(String? uid) {
      if (uid == null) return null;
      for (final m in members) {
        if (m['id'] == uid) return m;
      }
      return null;
    }

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

        // 명예의 전당: 이주의 갈렙 + 이달의 갈렙
        awardsAsync.maybeWhen(
          data: (awards) {
            final hasAny = awards.currentWeeklyCalebUid != null || awards.currentMonthlyCalebUid != null;
            if (!hasAny) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(children: [
                Expanded(
                  child: _CalebAwardCard(
                    label: '이주의 갈렙',
                    member: memberById(awards.currentWeeklyCalebUid),
                    likes: awards.currentWeeklyCalebLikes,
                    bg: const Color(0xFFFEF3C7),
                    fg: const Color(0xFFB45309),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _CalebAwardCard(
                    label: '이달의 갈렙',
                    member: memberById(awards.currentMonthlyCalebUid),
                    likes: awards.currentMonthlyCalebLikes,
                    bg: const Color(0xFFFCE7F3),
                    fg: const Color(0xFFBE185D),
                  ),
                ),
              ]),
            );
          },
          orElse: () => const SizedBox.shrink(),
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
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (context, i) => _PostCard(
                    post: posts[i],
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => PostDetailScreen(postId: posts[i]['id']),
                    )),
                  ),
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
    showDialog(context: context, builder: (dialogCtx) => AlertDialog(
      title: const Text('공지 작성'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: titleCtrl, decoration: const InputDecoration(hintText: '제목')),
        const SizedBox(height: 10),
        TextField(controller: contentCtrl, decoration: const InputDecoration(hintText: '내용 (선택)'), maxLines: 3),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('취소')),
        TextButton(onPressed: () async {
          Navigator.pop(dialogCtx);
          if (titleCtrl.text.trim().isNotEmpty) {
            await FirebaseService.createAnnouncement(titleCtrl.text.trim(), content: contentCtrl.text.trim());
            await NotificationService.sendToAll(titleCtrl.text.trim(), contentCtrl.text.trim());
            ref.invalidate(announcementsProvider);
          }
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

class _PostCard extends StatelessWidget {
  final Map<String, dynamic> post;
  final VoidCallback onTap;
  const _PostCard({required this.post, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final imageUrl = post['imageUrl'] as String?;
    final title = (post['title'] as String?) ?? '';
    final content = (post['content'] as String?) ?? '';
    final reactions = (post['reactions'] as Map<String, dynamic>?) ?? {};
    final commentCount = (post['commentCount'] as int?) ?? 0;
    final likeCount = ((reactions['like'] as List<dynamic>?) ?? []).length;
    final sadCount = ((reactions['sad'] as List<dynamic>?) ?? []).length;
    final prayCount = ((reactions['pray'] as List<dynamic>?) ?? []).length;

    return Tappable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (imageUrl != null && imageUrl.isNotEmpty)
            AspectRatio(
              aspectRatio: 4 / 3,
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: AppColors.surfaceLow),
                errorWidget: (_, __, ___) => Container(
                  color: AppColors.surfaceLow,
                  child: const Icon(Icons.broken_image_outlined, color: AppColors.muted),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (title.isNotEmpty)
                Text(title, style: AppText.headline(17), maxLines: 2, overflow: TextOverflow.ellipsis),
              if (content.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(content, style: AppText.body(13, color: AppColors.muted), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 12),
              Row(children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: AppColors.primarySoft,
                  child: Text(
                    User.partLabels[post['userPart']]?[0] ?? '?',
                    style: AppText.body(10, weight: FontWeight.w700, color: AppColors.primary),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(child: Text(
                  '${post['userName'] ?? ''} · ${CommunityScreen._timeAgo(post['createdAt'])}',
                  style: AppText.body(11, color: AppColors.muted),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                )),
                const SizedBox(width: 6),
                Flexible(child: UserBadges(userId: post['userId'] as String?)),
              ]),
              const SizedBox(height: 10),
              Wrap(spacing: 10, runSpacing: 4, children: [
                _MiniStat(emoji: '❤️', count: likeCount),
                _MiniStat(emoji: '😢', count: sadCount),
                _MiniStat(emoji: '🙏', count: prayCount),
                _MiniStat(emoji: '💬', count: commentCount),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String emoji;
  final int count;
  const _MiniStat({required this.emoji, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(emoji, style: const TextStyle(fontSize: 13)),
      const SizedBox(width: 3),
      Text('$count', style: AppText.body(12, weight: FontWeight.w600, color: AppColors.muted)),
    ]);
  }
}

class _CalebAwardCard extends StatelessWidget {
  final String label;
  final Map<String, dynamic>? member;
  final int likes;
  final Color bg;
  final Color fg;
  const _CalebAwardCard({
    required this.label,
    required this.member,
    required this.likes,
    required this.bg,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    final name = member?['name'] as String? ?? '집계 중';
    final part = member?['part'] as String?;
    final imageUrl = member?['imageUrl'] as String?;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          const Text('🏆', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 4),
          Text(label, style: AppText.body(11, weight: FontWeight.w800, color: fg)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          if (imageUrl != null && imageUrl.isNotEmpty)
            ClipOval(
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                width: 32, height: 32, fit: BoxFit.cover,
                placeholder: (_, __) => Container(width: 32, height: 32, color: Colors.white),
                errorWidget: (_, __, ___) => CircleAvatar(radius: 16, backgroundColor: Colors.white, child: Text(User.partLabels[part]?[0] ?? '?', style: AppText.body(12, weight: FontWeight.w700, color: fg))),
              ),
            )
          else
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.white,
              child: Text(User.partLabels[part]?[0] ?? '?', style: AppText.body(12, weight: FontWeight.w700, color: fg)),
            ),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: AppText.body(13, weight: FontWeight.w800, color: fg), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('❤️ $likes', style: AppText.body(11, weight: FontWeight.w600, color: fg.withValues(alpha: 0.8))),
          ])),
        ]),
      ]),
    );
  }
}
