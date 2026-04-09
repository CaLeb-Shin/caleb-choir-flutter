import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_providers.dart';

class VideosScreen extends ConsumerWidget {
  const VideosScreen({super.key});

  String? _getThumbnail(String url) {
    final match = RegExp(r'(?:youtu\.be/|youtube\.com/(?:watch\?v=|embed/|shorts/))([\w-]+)').firstMatch(url);
    if (match != null) return 'https://img.youtube.com/vi/${match.group(1)}/mqdefault.jpg';
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final videosAsync = ref.watch(videosProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero
          Text('찬양 갤러리', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 2, color: AppColors.secondary)),
          const SizedBox(height: 8),
          const Text('찬양 영상 및\n파트별 연습', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.primary, height: 1.25)),
          const SizedBox(height: 8),
          const Text('찬양대 전체 레퍼토리에 접근하고 함께 찬양을 연습하세요.', style: TextStyle(fontSize: 15, color: AppColors.muted, height: 1.5)),
          const SizedBox(height: 24),

          // Section Header
          const Text('영상 목록', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.primary)),
          const SizedBox(height: 16),

          // Videos List
          videosAsync.when(
            loading: () => const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())),
            error: (_, __) => const Center(child: Text('영상을 불러올 수 없습니다')),
            data: (videos) {
              if (videos.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: AppColors.surface, borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.primaryContainer.withValues(alpha: 0.1)),
                      child: const Icon(Icons.library_music, size: 40, color: AppColors.secondary),
                    ),
                    const SizedBox(height: 16),
                    const Text('등록된 영상이 없습니다', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.primary)),
                  ]),
                );
              }

              return Column(
                children: List.generate(videos.length, (i) {
                  final video = videos[i];
                  final thumb = video['thumbnailUrl'] ?? _getThumbnail(video['youtubeUrl'] ?? '');
                  final isFirst = i == 0;

                  return GestureDetector(
                    onTap: () => launchUrl(Uri.parse(video['youtubeUrl'] ?? '')),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isFirst ? AppColors.surfaceHigh : AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border(left: BorderSide(width: isFirst ? 3 : 1, color: isFirst ? AppColors.secondary : AppColors.border.withValues(alpha: 0.3))),
                      ),
                      child: Row(children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: thumb != null
                              ? CachedNetworkImage(imageUrl: thumb, width: 80, height: 64, fit: BoxFit.cover)
                              : Container(width: 80, height: 64, color: AppColors.primaryContainer, child: const Icon(Icons.music_note, color: Colors.white38)),
                        ),
                        const SizedBox(width: 16),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(video['title'] ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.primary), maxLines: 2, overflow: TextOverflow.ellipsis),
                          if (video['description'] != null) ...[
                            const SizedBox(height: 4),
                            Text(video['description'], style: const TextStyle(fontSize: 13, color: AppColors.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                          const SizedBox(height: 4),
                          Row(children: [
                            Icon(isFirst ? Icons.graphic_eq : Icons.play_circle_filled, size: 14, color: isFirst ? AppColors.secondary : AppColors.muted),
                            const SizedBox(width: 6),
                            Text(isFirst ? '최신 등록' : '', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: isFirst ? AppColors.secondary : AppColors.muted)),
                          ]),
                        ])),
                      ]),
                    ),
                  );
                }),
              );
            },
          ),

          // Resource Cards
          const SizedBox(height: 24),
          Divider(color: AppColors.border.withValues(alpha: 0.15)),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: _ResourceCard(icon: Icons.headset, title: '파트별 연습', desc: '본인의 파트를 개별 연습하세요')),
            const SizedBox(width: 12),
            Expanded(child: _ResourceCard(icon: Icons.history, title: '연습 기록', desc: '나의 연습 현황을 확인하세요')),
          ]),
        ],
      ),
    );
  }
}

class _ResourceCard extends StatelessWidget {
  final IconData icon;
  final String title, desc;
  const _ResourceCard({required this.icon, required this.title, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 28, color: AppColors.secondary),
        const SizedBox(height: 10),
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.primary)),
        const SizedBox(height: 6),
        Text(desc, style: const TextStyle(fontSize: 13, color: AppColors.muted, height: 1.4)),
      ]),
    );
  }
}
