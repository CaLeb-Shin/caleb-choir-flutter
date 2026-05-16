import 'dart:convert';

import 'package:file_picker/file_picker.dart';
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
            error: (error, stackTrace) =>
                const Center(child: Text('악보를 불러올 수 없습니다')),
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
                            if (group.conductorComment.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(13),
                                decoration: BoxDecoration(
                                  color: AppColors.secondaryContainer
                                      .withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: AppColors.secondary.withValues(
                                      alpha: 0.18,
                                    ),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '🎙️ 지휘자 코멘트',
                                      style: AppText.body(
                                        12,
                                        weight: FontWeight.w900,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      group.conductorComment,
                                      style: AppText.body(
                                        13,
                                        height: 1.45,
                                        color: AppColors.ink,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 14),
                            Column(
                              children: _resourcesForGroup(group)
                                  .map(
                                    (resource) => _PartResourceRow(
                                      partKey: resource.partKey,
                                      partLabel: resource.partLabel,
                                      sheetLabel: resource.sheetLabel,
                                      hasFile: resource.hasSheet,
                                      hasAudio: resource.hasAudio,
                                      hasMrAudio: resource.hasMrAudio,
                                      onOpenFile: () =>
                                          _openUrl(resource.sheetUrl),
                                      onOpenAudio: () =>
                                          _openUrl(resource.audioUrl),
                                      onOpenMrAudio: () =>
                                          _openUrl(resource.mrAudioUrl),
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
    final conductorCommentCtrl = TextEditingController();
    final lyricsCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) {
        String lyricFileName = '';
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('악보&음원 추가'),
            content: SingleChildScrollView(
              child: Column(
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
                  const SizedBox(height: 10),
                  TextField(
                    controller: conductorCommentCtrl,
                    decoration: const InputDecoration(
                      hintText: '🎙️ 지휘자 코멘트 (선택)',
                    ),
                    minLines: 2,
                    maxLines: 4,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: lyricsCtrl,
                    decoration: const InputDecoration(
                      hintText: '노래방 가사 (선택)\n.txt는 줄마다, .lrc는 [00:12.30] 형식',
                    ),
                    minLines: 3,
                    maxLines: 7,
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await FilePicker.platform.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['txt', 'lrc'],
                        withData: true,
                      );
                      final file = picked?.files.single;
                      final bytes = file?.bytes;
                      if (file == null || bytes == null || bytes.isEmpty) {
                        return;
                      }
                      final text = utf8.decode(bytes, allowMalformed: true);
                      lyricsCtrl.text = text.trim();
                      setDialogState(() => lyricFileName = file.name);
                    },
                    icon: const Icon(Icons.upload_file_rounded, size: 18),
                    label: Text(
                      lyricFileName.isEmpty
                          ? '가사 파일 선택 (.txt/.lrc)'
                          : lyricFileName,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('취소'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(dialogCtx);
                  final lyricsText = lyricsCtrl.text.trim();
                  if (titleCtrl.text.trim().isNotEmpty) {
                    await FirebaseService.addSheetMusic(
                      titleCtrl.text.trim(),
                      composer: composerCtrl.text.trim(),
                      conductorComment: conductorCommentCtrl.text.trim(),
                      lyricsText: lyricsText,
                      lyricsTimeline: _lyricsTimelineFromText(lyricsText),
                    );
                    ref.invalidate(sheetMusicProvider);
                  }
                },
                child: const Text('추가'),
              ),
            ],
          ),
        );
      },
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

List<Map<String, dynamic>> _lyricsTimelineFromText(String text) {
  final entries = <Map<String, dynamic>>[];
  final pattern = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]\s*(.*)');
  for (final line in text.split(RegExp(r'\r?\n'))) {
    final match = pattern.firstMatch(line.trim());
    if (match == null) continue;
    final minutes = int.tryParse(match.group(1) ?? '') ?? 0;
    final seconds = int.tryParse(match.group(2) ?? '') ?? 0;
    final fractionText = match.group(3) ?? '';
    final fraction = fractionText.isEmpty
        ? 0.0
        : (int.tryParse(fractionText) ?? 0) / mathPow10(fractionText.length);
    final lyric = (match.group(4) ?? '').trim();
    if (lyric.isEmpty) continue;
    entries.add({'timeSec': minutes * 60 + seconds + fraction, 'text': lyric});
  }
  entries.sort((a, b) {
    final at = (a['timeSec'] as num?)?.toDouble() ?? 0;
    final bt = (b['timeSec'] as num?)?.toDouble() ?? 0;
    return at.compareTo(bt);
  });
  if (entries.isNotEmpty) return entries;
  return _plainLyricsTimelineFromText(text);
}

List<Map<String, dynamic>> _plainLyricsTimelineFromText(String text) {
  final lines = _lyricsLinesForAutoTiming(text);
  return [
    for (var i = 0; i < lines.length; i += 1)
      {'timeSec': i * 3.2, 'text': lines[i]},
  ];
}

List<String> _lyricsLinesForAutoTiming(String text) {
  final sectionPattern = RegExp(
    r'^(intro|inter|interlude|verse|chorus|bridge|outro|ending|간주|전주)\s*\d*$',
    caseSensitive: false,
  );
  final lines = text.split(RegExp(r'\r?\n'));
  final result = <String>[];
  for (var i = 0; i < lines.length; i += 1) {
    final line = lines[i].trim();
    if (line.isEmpty) continue;
    if (i == 0 && RegExp(r'^\d{2}\.\d{2}\.\d{2}_').hasMatch(line)) {
      continue;
    }
    if (sectionPattern.hasMatch(line)) continue;
    result.add(line);
  }
  return result;
}

double mathPow10(int exponent) {
  var value = 1.0;
  for (var i = 0; i < exponent; i += 1) {
    value *= 10;
  }
  return value;
}

class _SheetMusicGroup {
  final String dateLabel;
  final String songTitle;
  final String composer;
  final String conductorComment;
  final List<Map<String, dynamic>> items;

  const _SheetMusicGroup({
    required this.dateLabel,
    required this.songTitle,
    required this.composer,
    required this.conductorComment,
    required this.items,
  });
}

class _PartResource {
  final String partKey;
  final String partLabel;
  final String sheetLabel;
  final String? sheetUrl;
  final String? audioUrl;
  final String? mrAudioUrl;

  const _PartResource({
    required this.partKey,
    required this.partLabel,
    required this.sheetLabel,
    this.sheetUrl,
    this.audioUrl,
    this.mrAudioUrl,
  });

  bool get hasSheet => sheetUrl != null && sheetUrl!.isNotEmpty;
  bool get hasAudio => audioUrl != null && audioUrl!.isNotEmpty;
  bool get hasMrAudio => mrAudioUrl != null && mrAudioUrl!.isNotEmpty;
}

const _choirPartOrder = [
  {'value': 'soprano', 'label': '소프라노'},
  {'value': 'alto', 'label': '알토'},
  {'value': 'tenor', 'label': '테너'},
  {'value': 'bass', 'label': '베이스'},
];

List<_SheetMusicGroup> _groupSheetMusic(List<Map<String, dynamic>> sheets) {
  final groups = <String, _SheetMusicGroup>{};

  for (final sheet in sheets) {
    final date = _dateDisplay(sheet['sheetDate']);
    final songTitle = _songTitle(sheet);
    final conductorComment = sheet['conductorComment']?.toString().trim() ?? '';
    final key = '$date::$songTitle';
    final existing = groups[key];

    if (existing == null) {
      groups[key] = _SheetMusicGroup(
        dateLabel: date.isEmpty ? '날짜 미지정' : date,
        songTitle: songTitle,
        composer: sheet['composer']?.toString() ?? '',
        conductorComment: conductorComment,
        items: [sheet],
      );
    } else {
      existing.items.add(sheet);
      if (existing.conductorComment.isEmpty && conductorComment.isNotEmpty) {
        groups[key] = _SheetMusicGroup(
          dateLabel: existing.dateLabel,
          songTitle: existing.songTitle,
          composer: existing.composer,
          conductorComment: conductorComment,
          items: existing.items,
        );
      }
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

List<_PartResource> _resourcesForGroup(_SheetMusicGroup group) {
  final main = group.items.firstWhere(
    (sheet) => (sheet['sheetPart']?.toString() ?? 'all') == 'all',
    orElse: () => group.items.first,
  );
  final mainSheetUrl = _stringValue(main['fileUrl']);
  final mainAudioUrl = _stringValue(main['audioUrl']);
  final mainMrAudioUrl = _stringValue(main['mrAudioUrl']);
  final partFiles = _mapValue(main['partFiles']);
  final mainIsAll = (main['sheetPart']?.toString() ?? 'all') == 'all';
  final hasSeparatePartRows = group.items.any(
    (sheet) => (sheet['sheetPart']?.toString() ?? 'all') != 'all',
  );
  final hasBundledParts = mainIsAll && !hasSeparatePartRows;

  if (!hasBundledParts) {
    return group.items.map((sheet) {
      final part = sheet['sheetPart']?.toString() ?? 'all';
      return _PartResource(
        partKey: part,
        partLabel: _partDisplay(part),
        sheetLabel: part == 'all' ? '총보 보기' : '악보 보기',
        sheetUrl: _stringValue(sheet['fileUrl']),
        audioUrl: _stringValue(sheet['audioUrl']),
        mrAudioUrl: _stringValue(sheet['mrAudioUrl']),
      );
    }).toList();
  }

  return [
    _PartResource(
      partKey: 'all',
      partLabel: '총보 / 전체',
      sheetLabel: '총보 보기',
      sheetUrl: mainSheetUrl,
      audioUrl: mainAudioUrl,
      mrAudioUrl: mainMrAudioUrl,
    ),
    ..._choirPartOrder.map((part) {
      final files = _mapValue(partFiles[part['value']]);
      final partSheetUrl = _stringValue(files['sheetUrl']);
      final partAudioUrl = _stringValue(files['guideAudioUrl']);
      final partMrAudioUrl = _stringValue(files['mrAudioUrl']);
      final hasPartSheet = partSheetUrl.isNotEmpty;

      return _PartResource(
        partKey: part['value']!,
        partLabel: part['label']!,
        sheetLabel: hasPartSheet ? '파트 악보' : '총보 보기',
        sheetUrl: hasPartSheet ? partSheetUrl : mainSheetUrl,
        audioUrl: partAudioUrl,
        mrAudioUrl: partMrAudioUrl,
      );
    }),
  ];
}

Map<String, dynamic> _mapValue(dynamic value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

String _stringValue(dynamic value) => value?.toString() ?? '';

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
  final String partKey;
  final String partLabel;
  final String sheetLabel;
  final bool hasFile;
  final bool hasAudio;
  final bool hasMrAudio;
  final VoidCallback onOpenFile;
  final VoidCallback onOpenAudio;
  final VoidCallback onOpenMrAudio;

  const _PartResourceRow({
    required this.partKey,
    required this.partLabel,
    required this.sheetLabel,
    required this.hasFile,
    required this.hasAudio,
    required this.hasMrAudio,
    required this.onOpenFile,
    required this.onOpenAudio,
    required this.onOpenMrAudio,
  });

  @override
  Widget build(BuildContext context) {
    final tone = _toneForPart(partKey);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.border),
      ),
      child: Row(
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 58),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(
              color: tone.accent.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              partLabel,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.body(
                12,
                weight: FontWeight.w900,
                color: tone.accent,
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
                  label: hasFile ? sheetLabel : '악보 없음',
                  enabled: hasFile,
                  onTap: onOpenFile,
                  accent: tone.accent,
                ),
                _ResourcePill(
                  icon: Icons.headphones_rounded,
                  label: hasAudio ? '가이드 듣기' : '가이드 없음',
                  enabled: hasAudio,
                  onTap: onOpenAudio,
                  accent: tone.accent,
                ),
                _ResourcePill(
                  icon: Icons.graphic_eq_rounded,
                  label: hasMrAudio ? 'MR 듣기' : 'MR 없음',
                  enabled: hasMrAudio,
                  onTap: onOpenMrAudio,
                  accent: tone.accent,
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
  final Color accent;

  const _ResourcePill({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? accent.withValues(alpha: 0.09) : Colors.white,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: enabled ? accent : AppColors.muted),
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

class _PartTone {
  final Color background;
  final Color border;
  final Color accent;

  const _PartTone({
    required this.background,
    required this.border,
    required this.accent,
  });
}

_PartTone _toneForPart(String partKey) {
  switch (partKey) {
    case 'soprano':
      return const _PartTone(
        background: Color(0xFFFFFBF1),
        border: Color(0xFFF3DEAC),
        accent: Color(0xFF9B6A16),
      );
    case 'alto':
      return const _PartTone(
        background: Color(0xFFF5FBF2),
        border: Color(0xFFCDE6C5),
        accent: Color(0xFF3F7C45),
      );
    case 'tenor':
      return const _PartTone(
        background: Color(0xFFF2F8FF),
        border: Color(0xFFC9DDF5),
        accent: Color(0xFF32679A),
      );
    case 'bass':
      return const _PartTone(
        background: Color(0xFFF8F5FF),
        border: Color(0xFFD9CFF5),
        accent: Color(0xFF6652A4),
      );
    default:
      return const _PartTone(
        background: Color(0xFFFFF8E8),
        border: Color(0xFFECD59A),
        accent: Color(0xFF8A661B),
      );
  }
}
