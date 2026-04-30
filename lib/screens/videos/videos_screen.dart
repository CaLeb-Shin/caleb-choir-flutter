import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../../services/firebase_service.dart';
import '../../widgets/interactive.dart';

class VideosScreen extends ConsumerWidget {
  const VideosScreen({super.key});

  String? _getThumbnail(String url) {
    final match = RegExp(
      r'(?:youtu\.be/|youtube(?:-nocookie)?\.com/(?:watch\?v=|embed/|shorts/))([\w-]+)',
    ).firstMatch(url);
    if (match != null) {
      return 'https://img.youtube.com/vi/${match.group(1)}/hqdefault.jpg';
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final videosAsync = ref.watch(videosProvider);
    final isAdmin = ref.watch(effectiveHasManagePermissionProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('영상', style: AppText.headline(28))),
              if (isAdmin)
                IconButton(
                  onPressed: () => _showAddDialog(context, ref),
                  icon: const Icon(
                    Icons.add_circle_rounded,
                    color: AppColors.secondary,
                  ),
                  tooltip: '영상 추가',
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '찬양 영상을 감상하고 함께 연습하세요',
            style: AppText.body(14, color: AppColors.muted),
          ),
          const SizedBox(height: 24),

          videosAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(60),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (error, stackTrace) =>
                const Center(child: Text('영상을 불러올 수 없습니다')),
            data: (videos) {
              if (videos.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 60),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.border.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.play_circle_rounded,
                        size: 40,
                        color: AppColors.subtle,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '등록된 영상이 없습니다',
                        style: AppText.body(16, weight: FontWeight.w600),
                      ),
                    ],
                  ),
                );
              }
              return Column(
                children: List.generate(videos.length, (i) {
                  final video = videos[i];
                  final thumb =
                      video['thumbnailUrl'] ??
                      _getThumbnail(video['youtubeUrl'] ?? '');

                  return Tappable(
                    onTap: () {
                      final url = video['youtubeUrl'] as String? ?? '';
                      final uri = Uri.tryParse(url);
                      if (uri == null) return;
                      launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                        webOnlyWindowName: '_blank',
                      );
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.border.withValues(alpha: 0.3),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AspectRatio(
                            aspectRatio: 16 / 9,
                            child: _VideoThumbnail(imageUrl: thumb),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        video['title'] ?? '',
                                        style: AppText.body(
                                          15,
                                          weight: FontWeight.w700,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (video['description'] != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          video['description'],
                                          style: AppText.body(
                                            13,
                                            color: AppColors.muted,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (isAdmin)
                                  IconButton(
                                    onPressed: () async {
                                      await FirebaseService.deleteVideo(
                                        video['id'],
                                      );
                                      ref.invalidate(videosProvider);
                                    },
                                    icon: Icon(
                                      Icons.delete_outline_rounded,
                                      size: 18,
                                      color: AppColors.error,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    final titleCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('영상 추가'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(hintText: '영상 제목'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: urlCtrl,
              decoration: const InputDecoration(hintText: 'YouTube URL'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(hintText: '설명 (선택)'),
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
              if (titleCtrl.text.trim().isNotEmpty &&
                  urlCtrl.text.trim().isNotEmpty) {
                await FirebaseService.addVideo(
                  titleCtrl.text.trim(),
                  urlCtrl.text.trim(),
                  description: descCtrl.text.trim(),
                );
                ref.invalidate(videosProvider);
              }
            },
            child: const Text('추가'),
          ),
        ],
      ),
    );
  }
}

class _VideoThumbnail extends StatelessWidget {
  final String? imageUrl;

  const _VideoThumbnail({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (imageUrl == null) {
      content = _fallback();
    } else {
      content = CachedNetworkImage(
        imageUrl: imageUrl!,
        fit: BoxFit.cover,
        placeholder: (context, url) => _fallback(),
        errorWidget: (context, url, error) => _fallback(),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        content,
        Container(color: Colors.black.withValues(alpha: 0.12)),
        Center(
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.88),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
            ),
            child: const Icon(
              Icons.play_arrow_rounded,
              color: Colors.white,
              size: 34,
            ),
          ),
        ),
      ],
    );
  }

  Widget _fallback() {
    return Container(
      color: AppColors.surfaceHigh,
      child: const Icon(
        Icons.play_circle_rounded,
        size: 48,
        color: AppColors.muted,
      ),
    );
  }
}
