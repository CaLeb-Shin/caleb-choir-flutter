import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_theme.dart';
import '../../models/user.dart';
import '../../providers/app_providers.dart';
import '../../services/firebase_service.dart';
import '../../widgets/app_bottom_nav_bar.dart';
import '../../widgets/app_logo_title.dart';
import '../../widgets/interactive.dart';
import '../../widgets/user_badges.dart';

const reactionMeta = <String, ({String label, String emoji})>{
  'like': (label: '좋아요', emoji: '❤️'),
  'sad': (label: '슬퍼요', emoji: '😢'),
  'pray': (label: '기도해요', emoji: '🙏'),
};

class PostDetailScreen extends ConsumerStatefulWidget {
  final String postId;
  const PostDetailScreen({super.key, required this.postId});

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  final _commentCtrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _toggleReaction(String type) async {
    await FirebaseService.toggleReaction(widget.postId, type);
    ref.invalidate(postProvider(widget.postId));
    ref.invalidate(postsProvider);
  }

  Future<void> _sendComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await FirebaseService.addComment(widget.postId, text);
      _commentCtrl.clear();
      ref.invalidate(commentsProvider(widget.postId));
      ref.invalidate(postProvider(widget.postId));
      ref.invalidate(postsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('댓글 등록 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final postAsync = ref.watch(postProvider(widget.postId));
    final commentsAsync = ref.watch(commentsProvider(widget.postId));
    final myUid = FirebaseService.uid;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.primary),
          onPressed: () => Navigator.pop(context),
        ),
        title: AppLogoTitle(title: '게시물', textStyle: AppText.headline(17)),
      ),
      bottomNavigationBar: const AppBottomNavBar(currentIndex: 4),
      body: postAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('게시물을 불러올 수 없습니다')),
        data: (post) {
          if (post == null) return const Center(child: Text('삭제된 게시물입니다'));
          final reactions = (post['reactions'] as Map<String, dynamic>?) ?? {};
          final imageUrl = _postImageUrl(post);
          final mediaType = (post['mediaType'] as String?) ?? 'photo';
          final videoUrl = _postVideoUrl(post);
          final videoStatus = (post['videoStatus'] as String?) ?? 'processing';
          final title = (post['title'] as String?) ?? '';
          final content = (post['content'] as String?) ?? '';
          final isMine = post['userId'] == myUid;
          final detailCacheWidth =
              (MediaQuery.sizeOf(context).width *
                      MediaQuery.devicePixelRatioOf(context))
                  .clamp(720, 1400)
                  .round();

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    _PostHeader(
                      post: post,
                      isMine: isMine,
                      onDelete: () => _confirmDelete(context),
                    ),
                    const SizedBox(height: 16),
                    if (mediaType == 'video')
                      _VideoDetailCard(url: videoUrl, status: videoStatus)
                    else if (imageUrl.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          fadeInDuration: const Duration(milliseconds: 120),
                          memCacheWidth: detailCacheWidth,
                          maxWidthDiskCache: detailCacheWidth,
                          placeholder: (_, __) => Container(
                            height: 240,
                            color: AppColors.surfaceLow,
                            child: const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            height: 240,
                            color: AppColors.surfaceLow,
                            child: const Icon(
                              Icons.broken_image_outlined,
                              color: AppColors.muted,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text(title, style: AppText.headline(22)),
                    if (content.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(content, style: AppText.body(15, height: 1.6)),
                    ],
                    const SizedBox(height: 20),
                    _ReactionRow(
                      reactions: reactions,
                      myUid: myUid,
                      onTap: _toggleReaction,
                    ),
                    const SizedBox(height: 24),
                    Divider(
                      color: AppColors.border.withValues(alpha: 0.4),
                      height: 1,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '댓글 ${post['commentCount'] ?? 0}',
                      style: AppText.body(
                        13,
                        weight: FontWeight.w700,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    commentsAsync.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      error: (_, __) => const Text('댓글을 불러올 수 없습니다'),
                      data: (comments) {
                        if (comments.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: Text(
                                '첫 번째 댓글을 남겨보세요',
                                style: AppText.body(13, color: AppColors.muted),
                              ),
                            ),
                          );
                        }
                        return Column(
                          children: [
                            for (final c in comments) _CommentTile(comment: c),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              _CommentInput(
                controller: _commentCtrl,
                sending: _sending,
                onSend: _sendComment,
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('게시물 삭제'),
        content: const Text('정말 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await FirebaseService.deletePost(widget.postId);
              ref.invalidate(postsProvider);
              if (mounted) Navigator.pop(context);
            },
            child: const Text('삭제', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

class _VideoDetailCard extends StatelessWidget {
  final String? url;
  final String status;
  const _VideoDetailCard({required this.url, required this.status});

  @override
  Widget build(BuildContext context) {
    final hasUrl = url != null && url!.isNotEmpty;
    final isReady = status == 'ready' && hasUrl;
    final isFailed = status == 'failed';
    final canPlay = hasUrl && !isFailed;
    return Tappable(
      onTap: canPlay
          ? () =>
                launchUrl(Uri.parse(url!), mode: LaunchMode.externalApplication)
          : null,
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF061B33), Color(0xFF0A315F)],
            ),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Icon(
                    canPlay
                        ? Icons.play_arrow_rounded
                        : isFailed
                        ? Icons.error_outline_rounded
                        : Icons.hourglass_top_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  isReady
                      ? '영상 보기'
                      : canPlay
                      ? '영상 보기'
                      : isFailed
                      ? '영상 처리에 실패했습니다'
                      : '영상을 업로드 중입니다',
                  style: AppText.body(
                    15,
                    weight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isReady
                      ? '탭하면 재생됩니다'
                      : canPlay
                      ? '탭하면 재생됩니다'
                      : '잠시 후 다시 확인해주세요',
                  style: AppText.body(
                    12,
                    color: Colors.white.withValues(alpha: 0.68),
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

class _PostHeader extends StatelessWidget {
  final Map<String, dynamic> post;
  final bool isMine;
  final VoidCallback onDelete;
  const _PostHeader({
    required this.post,
    required this.isMine,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Avatar(
          name: post['userName'],
          part: post['userPart'],
          imageUrl: post['userImageUrl'],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      post['userName'] ?? '',
                      style: AppText.body(15, weight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: UserBadges(userId: post['userId'] as String?),
                  ),
                ],
              ),
              Text(
                '${post['userGeneration'] ?? ''} · ${User.partLabels[post['userPart']] ?? ''} · ${_timeAgo(post['createdAt'])}',
                style: AppText.body(11, color: AppColors.muted),
              ),
            ],
          ),
        ),
        if (isMine)
          IconButton(
            onPressed: onDelete,
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: AppColors.muted,
            ),
          ),
      ],
    );
  }

  static String _timeAgo(dynamic v) {
    if (v == null) return '';
    try {
      final d = DateTime.parse(v.toString());
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

class _Avatar extends StatelessWidget {
  final String? name;
  final String? part;
  final String? imageUrl;
  const _Avatar({this.name, this.part, this.imageUrl});

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: imageUrl!,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          fadeInDuration: const Duration(milliseconds: 100),
          memCacheWidth: 96,
          maxWidthDiskCache: 96,
          placeholder: (_, __) =>
              Container(width: 40, height: 40, color: AppColors.primarySoft),
          errorWidget: (_, __, ___) => _initials(),
        ),
      );
    }
    return _initials();
  }

  Widget _initials() {
    final label = User.partLabels[part]?[0] ?? '?';
    return CircleAvatar(
      radius: 20,
      backgroundColor: AppColors.primarySoft,
      child: Text(
        label,
        style: AppText.body(
          15,
          weight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _ReactionRow extends StatelessWidget {
  final Map<String, dynamic> reactions;
  final String? myUid;
  final Future<void> Function(String type) onTap;
  const _ReactionRow({
    required this.reactions,
    required this.myUid,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final entry in reactionMeta.entries) ...[
          _ReactionChip(
            type: entry.key,
            emoji: entry.value.emoji,
            label: entry.value.label,
            count: ((reactions[entry.key] as List<dynamic>?) ?? []).length,
            active: ((reactions[entry.key] as List<dynamic>?) ?? []).contains(
              myUid,
            ),
            onTap: () => onTap(entry.key),
          ),
          if (entry.key != reactionMeta.keys.last) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _ReactionChip extends StatefulWidget {
  final String type;
  final String emoji;
  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;
  const _ReactionChip({
    required this.type,
    required this.emoji,
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });

  @override
  State<_ReactionChip> createState() => _ReactionChipState();
}

class _ReactionChipState extends State<_ReactionChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    widget.onTap();
    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${widget.label} ${widget.count}',
      selected: widget.active,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final value = Curves.easeOutCubic.transform(_controller.value);
              return Positioned(
                top: -2 - (value * 34),
                child: IgnorePointer(
                  child: Opacity(
                    opacity: (1 - value).clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: 0.8 + value * 0.55,
                      child: Text(
                        widget.emoji,
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          AnimatedScale(
            scale: widget.active ? 1.04 : 1,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            child: Material(
              color: widget.active
                  ? AppColors.primarySoft
                  : AppColors.surfaceLow,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _handleTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.emoji, style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 6),
                      Text(
                        widget.label,
                        style: AppText.body(
                          12,
                          weight: FontWeight.w600,
                          color: widget.active
                              ? AppColors.primary
                              : AppColors.muted,
                        ),
                      ),
                      const SizedBox(width: 6),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: Text(
                          '${widget.count}',
                          key: ValueKey('${widget.type}-${widget.count}'),
                          style: AppText.body(
                            12,
                            weight: FontWeight.w700,
                            color: widget.active
                                ? AppColors.primary
                                : AppColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  final Map<String, dynamic> comment;
  const _CommentTile({required this.comment});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Avatar(
            name: comment['userName'],
            part: comment['userPart'],
            imageUrl: comment['userImageUrl'],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 2,
                  children: [
                    Text(
                      comment['userName'] ?? '',
                      style: AppText.body(13, weight: FontWeight.w700),
                    ),
                    UserBadges(userId: comment['userId'] as String?, max: 2),
                    Text(
                      _PostHeader._timeAgo(comment['createdAt']),
                      style: AppText.body(11, color: AppColors.muted),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  comment['content'] ?? '',
                  style: AppText.body(13, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentInput extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  const _CommentInput({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        10,
        10 + MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: AppColors.border.withValues(alpha: 0.4)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: '댓글 추가...',
                border: InputBorder.none,
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
            ),
          ),
          IconButton(
            onPressed: sending ? null : onSend,
            icon: sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded, color: AppColors.primary),
          ),
        ],
      ),
    );
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
