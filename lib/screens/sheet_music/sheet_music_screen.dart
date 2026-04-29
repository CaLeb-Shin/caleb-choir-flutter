import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../../services/firebase_service.dart';

class SheetMusicScreen extends ConsumerWidget {
  const SheetMusicScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sheetMusicAsync = ref.watch(sheetMusicProvider);
    final isAdmin = ref.watch(effectiveHasManagePermissionProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('악보&음원', style: AppText.headline(28))),
              if (isAdmin)
                IconButton(
                  onPressed: () => _showAddDialog(context, ref),
                  icon: const Icon(
                    Icons.add_circle_rounded,
                    color: AppColors.secondary,
                  ),
                  tooltip: '악보&음원 추가',
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '악보를 보면서 파트 음원을 함께 연습하세요',
            style: AppText.body(14, color: AppColors.muted),
          ),
          const SizedBox(height: 24),

          sheetMusicAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(60),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (_, __) => const Center(child: Text('악보를 불러올 수 없습니다')),
            data: (sheets) {
              if (sheets.isEmpty) {
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
                        Icons.music_note_rounded,
                        size: 40,
                        color: AppColors.subtle,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '등록된 악보&음원이 없습니다',
                        style: AppText.body(16, weight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '관리자가 업로드하면 여기에 표시됩니다',
                        style: AppText.body(13, color: AppColors.muted),
                      ),
                    ],
                  ),
                );
              }
              final groups = _groupSheetMusic(sheets);
              return Column(
                children: groups
                    .map<Widget>(
                      (group) => Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppColors.border.withValues(alpha: 0.3),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.04),
                              blurRadius: 18,
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
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: AppColors.primarySoft,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(
                                    Icons.music_note_rounded,
                                    color: AppColors.primary,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        group.dateLabel,
                                        style: AppText.body(
                                          12,
                                          weight: FontWeight.w800,
                                          color: AppColors.secondary,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        group.songTitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppText.body(
                                          17,
                                          weight: FontWeight.w800,
                                        ),
                                      ),
                                      if (group.composer.isNotEmpty) ...[
                                        const SizedBox(height: 3),
                                        Text(
                                          group.composer,
                                          style: AppText.body(
                                            13,
                                            color: AppColors.muted,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (isAdmin)
                                  IconButton(
                                    onPressed: () async {
                                      for (final sheet in group.items) {
                                        await FirebaseService.deleteSheetMusic(
                                          sheet['id'],
                                        );
                                      }
                                      ref.invalidate(sheetMusicProvider);
                                    },
                                    icon: Icon(
                                      Icons.delete_outline_rounded,
                                      size: 18,
                                      color: AppColors.error,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Column(
                              children: group.items
                                  .map(
                                    (sheet) => _PartResourceRow(
                                      partLabel: _partDisplay(
                                        sheet['sheetPart'],
                                      ),
                                      hasFile:
                                          (sheet['fileUrl'] as String?)
                                              ?.isNotEmpty ==
                                          true,
                                      hasAudio:
                                          (sheet['audioUrl'] as String?)
                                              ?.isNotEmpty ==
                                          true,
                                      onOpenFile: () =>
                                          _openUrl(sheet['fileUrl']),
                                      onOpenAudio: () =>
                                          _openUrl(sheet['audioUrl']),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    final titleCtrl = TextEditingController();
    final composerCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('악보&음원 추가'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(hintText: '곡 제목'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: composerCtrl,
              decoration: const InputDecoration(hintText: '작곡가 (선택)'),
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
                await FirebaseService.addSheetMusic(
                  titleCtrl.text.trim(),
                  composer: composerCtrl.text.trim(),
                );
                ref.invalidate(sheetMusicProvider);
              }
            },
            child: const Text('추가'),
          ),
        ],
      ),
    );
  }

  static Future<void> _openUrl(dynamic rawUrl) async {
    final url = rawUrl?.toString();
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _SheetMusicGroup {
  final String dateLabel;
  final String songTitle;
  final String composer;
  final List<Map<String, dynamic>> items;

  const _SheetMusicGroup({
    required this.dateLabel,
    required this.songTitle,
    required this.composer,
    required this.items,
  });
}

List<_SheetMusicGroup> _groupSheetMusic(List<Map<String, dynamic>> sheets) {
  final groups = <String, _SheetMusicGroup>{};

  for (final sheet in sheets) {
    final date = _dateDisplay(sheet['sheetDate']);
    final songTitle = _songTitle(sheet);
    final key = '$date::$songTitle';
    final existing = groups[key];

    if (existing == null) {
      groups[key] = _SheetMusicGroup(
        dateLabel: date.isEmpty ? '날짜 미지정' : date,
        songTitle: songTitle,
        composer: sheet['composer']?.toString() ?? '',
        items: [sheet],
      );
    } else {
      existing.items.add(sheet);
    }
  }

  final list = groups.values.toList();
  for (final group in list) {
    group.items.sort((a, b) {
      final order = ['all', 'soprano', 'alto', 'tenor', 'bass', 'instrument'];
      final ai = order.indexOf(a['sheetPart']?.toString() ?? 'all');
      final bi = order.indexOf(b['sheetPart']?.toString() ?? 'all');
      return (ai < 0 ? 99 : ai).compareTo(bi < 0 ? 99 : bi);
    });
  }
  return list;
}

String _songTitle(Map<String, dynamic> sheet) {
  final songTitle = sheet['songTitle']?.toString().trim();
  if (songTitle != null && songTitle.isNotEmpty) return songTitle;
  final title = sheet['title']?.toString().trim() ?? '제목 없음';
  final slashIndex = title.indexOf('/');
  if (slashIndex >= 0 && slashIndex + 1 < title.length) {
    return title.substring(slashIndex + 1).trim();
  }
  return title;
}

String _dateDisplay(dynamic rawDate) {
  final value = rawDate?.toString() ?? '';
  if (value.isEmpty) return '';
  return value.replaceAll('-', '.');
}

String _partDisplay(dynamic rawPart) {
  switch (rawPart?.toString()) {
    case 'all':
      return '전체';
    case 'soprano':
      return '소프라노';
    case 'alto':
      return '알토';
    case 'tenor':
      return '테너';
    case 'bass':
      return '베이스';
    case 'instrument':
      return '반주/악기';
    default:
      return rawPart?.toString() ?? '전체';
  }
}

class _PartResourceRow extends StatelessWidget {
  final String partLabel;
  final bool hasFile;
  final bool hasAudio;
  final VoidCallback onOpenFile;
  final VoidCallback onOpenAudio;

  const _PartResourceRow({
    required this.partLabel,
    required this.hasFile,
    required this.hasAudio,
    required this.onOpenFile,
    required this.onOpenAudio,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 68,
            child: Text(
              partLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.body(
                13,
                weight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                _ResourcePill(
                  icon: Icons.description_rounded,
                  label: hasFile ? '악보 보기' : '악보 없음',
                  enabled: hasFile,
                  onTap: onOpenFile,
                ),
                _ResourcePill(
                  icon: Icons.headphones_rounded,
                  label: hasAudio ? '음원 듣기' : '음원 없음',
                  enabled: hasAudio,
                  onTap: onOpenAudio,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResourcePill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _ResourcePill({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? AppColors.primarySoft : Colors.white,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: enabled ? AppColors.primary : AppColors.muted,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: AppText.body(
                  12,
                  color: enabled ? AppColors.primary : AppColors.muted,
                  weight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
