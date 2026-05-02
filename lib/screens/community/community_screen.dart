import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../../models/user.dart';
import '../../services/firebase_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/interactive.dart';
import 'post_compose_sheet.dart';
import 'post_detail_screen.dart';

class CommunityScreen extends ConsumerWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postsAsync = ref.watch(postsProvider);
    final announcementsAsync = ref.watch(announcementsProvider);
    final announcements = announcementsAsync.valueOrNull ?? [];
    final isAdmin = ref.watch(effectiveHasManagePermissionProvider);
    final myUid = FirebaseService.uid;

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('커뮤니티', style: AppText.headline(28)),
                        const SizedBox(height: 2),
                        Text(
                          '재미있는 사진과 짧은 영상을 올리고 하트로 응원해요',
                          style: AppText.body(12, color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                  if (isAdmin)
                    IconButton(
                      onPressed: () => _showAnnouncementDialog(context, ref),
                      icon: const Icon(
                        Icons.campaign_rounded,
                        color: AppColors.secondary,
                      ),
                      tooltip: '공지 작성',
                    ),
                ],
              ),
            ),

            if (announcements.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Tappable(
                  onTap: () {},
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.campaign_rounded,
                          size: 16,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            announcements.first['title'] ?? '',
                            style: AppText.body(
                              13,
                              weight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            Expanded(
              child: postsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stackTrace) =>
                    const Center(child: Text('게시물을 불러올 수 없습니다')),
                data: (posts) {
                  final weeklyTop = _weeklyTopPosts(posts);
                  if (posts.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.photo_camera_outlined,
                            size: 40,
                            color: AppColors.subtle,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '아직 올라온 게시물이 없습니다',
                            style: AppText.body(16, weight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '첫 번째 사진이나 영상을 올려보세요!',
                            style: AppText.body(13, color: AppColors.muted),
                          ),
                        ],
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(postsProvider);
                      ref.invalidate(announcementsProvider);
                    },
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        if (weeklyTop.isNotEmpty)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                14,
                                20,
                                14,
                              ),
                              child: _WeeklyCalebShowcase(posts: weeklyTop),
                            ),
                          ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
                            child: Row(
                              children: [
                                Text(
                                  '사진/영상 피드',
                                  style: AppText.body(
                                    15,
                                    weight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${posts.length}',
                                  style: AppText.body(
                                    12,
                                    weight: FontWeight.w800,
                                    color: AppColors.secondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                          sliver: SliverGrid(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 10,
                                  childAspectRatio: 0.78,
                                ),
                            delegate: SliverChildBuilderDelegate(
                              (context, i) => _PhotoPostTile(
                                post: posts[i],
                                myUid: myUid,
                                onReaction: (type) async {
                                  final postId = posts[i]['id']?.toString();
                                  if (postId == null || postId.isEmpty) return;
                                  await FirebaseService.toggleReaction(
                                    postId,
                                    type,
                                  );
                                  ref.invalidate(postsProvider);
                                },
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => PostDetailScreen(
                                      postId: posts[i]['id'],
                                    ),
                                  ),
                                ),
                              ),
                              childCount: posts.length,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        Positioned(
          right: 20,
          bottom: 18,
          child: SafeArea(
            minimum: const EdgeInsets.only(bottom: 4),
            child: _ComposeButton(onTap: () => _openComposeSheet(context)),
          ),
        ),
      ],
    );
  }

  void _openComposeSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PostComposeSheet(),
    );
  }

  void _showAnnouncementDialog(BuildContext context, WidgetRef ref) {
    final titleCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('공지 작성'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(hintText: '제목'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: contentCtrl,
              decoration: const InputDecoration(hintText: '내용 (선택)'),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              if (titleCtrl.text.trim().isNotEmpty) {
                await FirebaseService.createAnnouncement(
                  titleCtrl.text.trim(),
                  content: contentCtrl.text.trim(),
                );
                await NotificationService.sendToAll(
                  titleCtrl.text.trim(),
                  contentCtrl.text.trim(),
                );
                ref.invalidate(announcementsProvider);
              }
            },
            child: const Text('작성'),
          ),
        ],
      ),
    );
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
    } catch (_) {
      return '';
    }
  }

  static List<Map<String, dynamic>> _weeklyTopPosts(
    List<Map<String, dynamic>> posts,
  ) {
    final ranked = [...posts]
      ..sort((a, b) => _heartCount(b).compareTo(_heartCount(a)));
    final liked = ranked
        .where((post) => _heartCount(post) > 0)
        .take(2)
        .toList();
    return liked.isNotEmpty ? liked : ranked.take(2).toList();
  }

  static int _heartCount(Map<String, dynamic> post) {
    final reactions = (post['reactions'] as Map<String, dynamic>?) ?? {};
    return ((reactions['like'] as List<dynamic>?) ?? []).length;
  }
}

class _WeeklyCalebShowcase extends StatelessWidget {
  final List<Map<String, dynamic>> posts;
  const _WeeklyCalebShowcase({required this.posts});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.favorite_rounded,
                  size: 17,
                  color: AppColors.secondaryContainer,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '이주의 갈렙',
                      style: AppText.body(
                        15,
                        weight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '하트를 가장 많이 받은 게시물 1위와 2위',
                      style: AppText.body(
                        11,
                        color: Colors.white.withValues(alpha: 0.68),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < 2; i++) ...[
                Expanded(
                  child: i < posts.length
                      ? _WeeklyCalebCard(post: posts[i], rank: i + 1)
                      : _WeeklyCalebEmpty(rank: i + 1),
                ),
                if (i == 0) const SizedBox(width: 10),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ComposeButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ComposeButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '게시물 올리기',
      child: Tappable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.primaryContainer,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.edit_rounded, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}

class _WeeklyCalebCard extends StatelessWidget {
  final Map<String, dynamic> post;
  final int rank;
  const _WeeklyCalebCard({required this.post, required this.rank});

  @override
  Widget build(BuildContext context) {
    final title = (post['title'] as String?) ?? '';
    final part = User.partLabels[post['userPart']] ?? '파트';
    final hearts = CommunityScreen._heartCount(post);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1.16,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _PostMediaPreview(post: post),
                Positioned(top: 8, left: 8, child: _RankBadge(rank: rank)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppText.body(
                    12,
                    weight: FontWeight.w900,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${post['userName'] ?? ''} · $part',
                        style: AppText.body(
                          10,
                          color: Colors.white.withValues(alpha: 0.66),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(
                      Icons.favorite_rounded,
                      size: 12,
                      color: AppColors.secondaryContainer,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '$hearts',
                      style: AppText.body(
                        10,
                        weight: FontWeight.w900,
                        color: AppColors.secondaryContainer,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WeeklyCalebEmpty extends StatelessWidget {
  final int rank;
  const _WeeklyCalebEmpty({required this.rank});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 144),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Text(
        '$rank위 집계 중',
        style: AppText.body(
          12,
          weight: FontWeight.w800,
          color: Colors.white.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

class _PhotoPostTile extends StatelessWidget {
  final Map<String, dynamic> post;
  final String? myUid;
  final VoidCallback onTap;
  final Future<void> Function(String type) onReaction;
  const _PhotoPostTile({
    required this.post,
    required this.myUid,
    required this.onTap,
    required this.onReaction,
  });

  @override
  Widget build(BuildContext context) {
    final title = (post['title'] as String?) ?? '';
    final content = (post['content'] as String?) ?? '';
    final commentCount = (post['commentCount'] as int?) ?? 0;
    final reactions = (post['reactions'] as Map<String, dynamic>?) ?? {};

    return Tappable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _PostMediaPreview(post: post),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.08),
                      Colors.black.withValues(alpha: 0.72),
                    ],
                    stops: const [0.35, 0.62, 1],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: _FeedReactionStrip(
                reactions: reactions,
                myUid: myUid,
                onReaction: onReaction,
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: AppText.body(
                      13,
                      weight: FontWeight.w900,
                      color: Colors.white,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (content.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      content,
                      style: AppText.body(
                        10,
                        color: Colors.white.withValues(alpha: 0.78),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${post['userName'] ?? ''} · ${CommunityScreen._timeAgo(post['createdAt'])}',
                          style: AppText.body(
                            10,
                            color: Colors.white.withValues(alpha: 0.66),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(
                        Icons.mode_comment_rounded,
                        size: 12,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '$commentCount',
                        style: AppText.body(10, color: Colors.white70),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedReactionStrip extends StatelessWidget {
  final Map<String, dynamic> reactions;
  final String? myUid;
  final Future<void> Function(String type) onReaction;
  const _FeedReactionStrip({
    required this.reactions,
    required this.myUid,
    required this.onReaction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final entry in reactionMeta.entries) ...[
          _FeedReactionButton(
            type: entry.key,
            emoji: entry.value.emoji,
            label: entry.value.label,
            count: ((reactions[entry.key] as List<dynamic>?) ?? []).length,
            active: ((reactions[entry.key] as List<dynamic>?) ?? []).contains(
              myUid,
            ),
            onTap: () => onReaction(entry.key),
          ),
          if (entry.key != reactionMeta.keys.last) const SizedBox(width: 4),
        ],
      ],
    );
  }
}

class _FeedReactionButton extends StatelessWidget {
  final String type;
  final String emoji;
  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;
  const _FeedReactionButton({
    required this.type,
    required this.emoji,
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label $count',
      selected: active,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: active
                ? AppColors.secondaryContainer
                : Colors.black.withValues(alpha: 0.38),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active
                  ? Colors.white.withValues(alpha: 0.64)
                  : Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 3),
              Text(
                '$count',
                style: AppText.body(
                  10,
                  weight: FontWeight.w900,
                  color: active ? AppColors.primary : Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NetworkPhoto extends StatelessWidget {
  final String imageUrl;
  const _NetworkPhoto({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      return const _PhotoFallback();
    }
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (MediaQuery.sizeOf(context).width * pixelRatio / 2)
        .clamp(360, 760)
        .round();
    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 120),
      memCacheWidth: cacheWidth,
      maxWidthDiskCache: cacheWidth,
      placeholder: (context, url) => const _PhotoFallback(),
      errorWidget: (context, url, error) => const _PhotoFallback(),
    );
  }
}

class _PostMediaPreview extends StatelessWidget {
  final Map<String, dynamic> post;
  const _PostMediaPreview({required this.post});

  @override
  Widget build(BuildContext context) {
    final mediaType = (post['mediaType'] as String?) ?? 'photo';
    if (mediaType == 'video') {
      return _VideoPreview(
        status: (post['videoStatus'] as String?) ?? 'processing',
        hasPlayableSource: _postVideoUrl(post).isNotEmpty,
      );
    }
    return _NetworkPhoto(imageUrl: _postImageUrl(post));
  }
}

String _postImageUrl(Map<String, dynamic> post) {
  for (final key in ['imageUrl', 'mediaUrl', 'photoUrl', 'thumbnailUrl']) {
    final value = post[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return '';
}

String _postVideoUrl(Map<String, dynamic> post) {
  for (final key in ['videoUrl', 'videoSourceUrl', 'mediaUrl']) {
    final value = post[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return '';
}

class _VideoPreview extends StatelessWidget {
  final String status;
  final bool hasPlayableSource;
  const _VideoPreview({required this.status, required this.hasPlayableSource});

  @override
  Widget build(BuildContext context) {
    final isReady = status == 'ready';
    final isFailed = status == 'failed';
    final canPlay = isReady || (hasPlayableSource && !isFailed);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF061B33), Color(0xFF0A315F)],
        ),
      ),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                canPlay
                    ? Icons.play_arrow_rounded
                    : isFailed
                    ? Icons.error_outline_rounded
                    : Icons.hourglass_top_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 5),
              Text(
                isReady
                    ? '영상'
                    : canPlay
                    ? '원본'
                    : isFailed
                    ? '처리 실패'
                    : '압축 중',
                style: AppText.body(
                  11,
                  weight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoFallback extends StatelessWidget {
  const _PhotoFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primarySoft,
      child: Center(
        child: Icon(
          Icons.photo_camera_outlined,
          color: AppColors.primary.withValues(alpha: 0.32),
          size: 30,
        ),
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  final int rank;
  const _RankBadge({required this.rank});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: rank == 1 ? AppColors.secondaryContainer : Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Text(
        '$rank위',
        style: AppText.body(
          11,
          weight: FontWeight.w900,
          color: AppColors.primary,
        ),
      ),
    );
  }
}
