import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../../services/firebase_service.dart';
import 'sheet_viewer_screen.dart';

class SheetMusicScreen extends ConsumerWidget {
  const SheetMusicScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sheetMusicAsync = ref.watch(sheetMusicProvider);
    final isAdmin = ref.watch(effectiveHasManagePermissionProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(sheetMusicProvider),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            sliver: SliverList(
              delegate: SliverChildListDelegate.fixed([
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
              ]),
            ),
          ),
          sheetMusicAsync.when(
            loading: () => const SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(60),
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
            error: (error, stackTrace) => const SliverToBoxAdapter(
              child: Center(child: Text('악보를 불러올 수 없습니다')),
            ),
            data: (sheets) {
              if (sheets.isEmpty) {
                return const SliverPadding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 40),
                  sliver: SliverToBoxAdapter(child: _EmptySheetMusicPanel()),
                );
              }
              final groups = _groupSheetMusic(sheets);
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final group = groups[index];
                    return _SheetMusicCard(
                      group: group,
                      isAdmin: isAdmin,
                      onDelete: () async {
                        for (final sheet in group.items) {
                          await FirebaseService.deleteSheetMusic(sheet['id']);
                        }
                        ref.invalidate(sheetMusicProvider);
                      },
                    );
                  }, childCount: groups.length),
                ),
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
                    decoration: const InputDecoration(hintText: '지휘자 코멘트 (선택)'),
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
                      conductorComment: _cleanConductorComment(
                        conductorCommentCtrl.text,
                      ),
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
    final conductorComment = _cleanConductorComment(
      sheet['conductorComment']?.toString(),
    );
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
      mrAudioUrl: _stringValue(main['mrAudioUrl']),
    ),
    ..._choirPartOrder.map((part) {
      final files = _mapValue(partFiles[part['value']]);
      final partSheetUrl = _stringValue(files['sheetUrl']);
      final partAudioUrl = _stringValue(files['guideAudioUrl']);
      final partMrUrl = _stringValue(files['mrAudioUrl']);
      final hasPartSheet = partSheetUrl.isNotEmpty;

      return _PartResource(
        partKey: part['value']!,
        partLabel: part['label']!,
        sheetLabel: hasPartSheet ? '파트 악보' : '총보 보기',
        sheetUrl: hasPartSheet ? partSheetUrl : mainSheetUrl,
        audioUrl: partAudioUrl,
        mrAudioUrl: partMrUrl,
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

String _cleanConductorComment(String? value) {
  var text = value?.trim() ?? '';
  final decorativePrefixes = [
    String.fromCharCodes([0x1F399, 0xFE0F]),
    String.fromCharCode(0x1F399),
    String.fromCharCode(0x1F3A4),
  ];
  var didRemovePrefix = true;
  while (didRemovePrefix) {
    didRemovePrefix = false;
    for (final prefix in decorativePrefixes) {
      if (text.startsWith(prefix)) {
        text = text.substring(prefix.length).trimLeft();
        didRemovePrefix = true;
      }
    }
  }
  return text.trim();
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

class _EmptySheetMusicPanel extends StatelessWidget {
  const _EmptySheetMusicPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset(
              'assets/images/icon.png',
              width: 64,
              height: 64,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '등록된 악보&음원이 없습니다',
            style: AppText.body(16, weight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          Text(
            '관리자가 업로드하면 여기에 표시됩니다',
            style: AppText.body(13, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

/// True when the sheet's date is before today, so it can be collapsed in the
/// list. Accepts "YYYY-MM-DD", "YYYY.MM.DD" or ISO strings.
bool _isPastSheetDate(dynamic raw) {
  final value = raw?.toString().trim() ?? '';
  if (value.isEmpty) return false;
  final normalized = value.replaceAll('.', '-').replaceAll('/', '-');
  final parsed = DateTime.tryParse(normalized);
  if (parsed == null) return false;
  final now = DateTime.now();
  final date = DateTime(parsed.year, parsed.month, parsed.day);
  final today = DateTime(now.year, now.month, now.day);
  return date.isBefore(today);
}

class _SheetMusicCard extends StatefulWidget {
  final _SheetMusicGroup group;
  final bool isAdmin;
  final Future<void> Function()? onDelete;

  const _SheetMusicCard({
    required this.group,
    required this.isAdmin,
    this.onDelete,
  });

  @override
  State<_SheetMusicCard> createState() => _SheetMusicCardState();
}

class _SheetMusicCardState extends State<_SheetMusicCard> {
  late final bool _isPast;
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _isPast =
        widget.group.items.isNotEmpty &&
        _isPastSheetDate(widget.group.items.first['sheetDate']);
    // Past sheets start collapsed; current and upcoming ones stay open.
    _expanded = !_isPast;
  }

  void _toggle() {
    if (!_isPast) return;
    setState(() => _expanded = !_expanded);
  }

  void _openViewer(
    BuildContext context,
    _PartResource res, {
    required bool withSheet,
    required bool withAudio,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SheetViewerScreen(
          title: widget.group.songTitle,
          partLabel: res.partLabel,
          sheetUrl: withSheet ? res.sheetUrl : null,
          guideAudioUrl: withAudio ? res.audioUrl : null,
          mrAudioUrl: withAudio ? res.mrAudioUrl : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final isAdmin = widget.isAdmin;
    final onDelete = widget.onDelete;
    final resources = _resourcesForGroup(group);
    final collapsed = _isPast && !_expanded;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _toggle,
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(13),
                          child: Image.asset(
                            'assets/images/icon.png',
                            width: 54,
                            height: 54,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                group.dateLabel,
                                style: AppText.body(
                                  12,
                                  weight: FontWeight.w900,
                                  color: AppColors.secondary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                group.songTitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.body(
                                  18,
                                  weight: FontWeight.w900,
                                ),
                              ),
                              if (group.composer.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  group.composer,
                                  style: AppText.body(
                                    13,
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_isPast)
                  IconButton(
                    onPressed: _toggle,
                    icon: Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 22,
                      color: AppColors.onSurfaceVariant,
                    ),
                    style: IconButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                if (isAdmin)
                  IconButton(
                    onPressed: onDelete == null
                        ? null
                        : () async {
                            await onDelete();
                          },
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: AppColors.error,
                    ),
                    style: IconButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ],
            ),
            if (collapsed)
              GestureDetector(
                onTap: _toggle,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.download_rounded,
                        size: 16,
                        color: AppColors.secondary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '총보·파트 음원 ${resources.length}개 · 눌러서 펼쳐 받기',
                          style: AppText.body(
                            12.5,
                            weight: FontWeight.w700,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              if (group.conductorComment.isNotEmpty) ...[
                const SizedBox(height: 15),
                _ConductorCue(comment: group.conductorComment),
              ],
              const SizedBox(height: 12),
              Column(
                children: [
                  for (var i = 0; i < resources.length; i += 1)
                    _PartResourceRow(
                      partKey: resources[i].partKey,
                      partLabel: resources[i].partLabel,
                      sheetLabel: resources[i].sheetLabel,
                      hasFile: resources[i].hasSheet,
                      hasAudio: resources[i].hasAudio,
                      showDivider: i != resources.length - 1,
                      onOpenBoth: () => _openViewer(
                        context,
                        resources[i],
                        withSheet: true,
                        withAudio: true,
                      ),
                      onOpenFile: () => _openViewer(
                        context,
                        resources[i],
                        withSheet: true,
                        withAudio: false,
                      ),
                      onOpenAudio: () => _openViewer(
                        context,
                        resources[i],
                        withSheet: false,
                        withAudio: true,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConductorCue extends StatelessWidget {
  final String comment;

  const _ConductorCue({required this.comment});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 3,
          height: 52,
          decoration: BoxDecoration(
            color: AppColors.secondary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '지휘자 코멘트',
                style: AppText.body(
                  12,
                  weight: FontWeight.w900,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                comment,
                style: AppText.body(
                  13,
                  height: 1.45,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PartResourceRow extends StatelessWidget {
  final String partKey;
  final String partLabel;
  final String sheetLabel;
  final bool hasFile;
  final bool hasAudio;
  final bool showDivider;
  final VoidCallback onOpenBoth;
  final VoidCallback onOpenFile;
  final VoidCallback onOpenAudio;

  const _PartResourceRow({
    required this.partKey,
    required this.partLabel,
    required this.sheetLabel,
    required this.hasFile,
    required this.hasAudio,
    required this.showDivider,
    required this.onOpenBoth,
    required this.onOpenFile,
    required this.onOpenAudio,
  });

  @override
  Widget build(BuildContext context) {
    final tone = _toneForPart(partKey);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 88,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 3,
                        height: 22,
                        decoration: BoxDecoration(
                          color: tone.accent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          partLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body(
                            12,
                            weight: FontWeight.w900,
                            color: tone.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _actions(tone)),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            thickness: 1,
            color: const Color(0xFFD7CBB2).withValues(alpha: 0.55),
          ),
      ],
    );
  }

  Widget _actions(_PartTone tone) {
    // Both present → big "악보보면서 가이드 듣기" on top, 악보/가이드 separate below.
    if (hasFile && hasAudio) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PrimaryResourceButton(
            icon: Icons.queue_music_rounded,
            label: '악보보면서 가이드 듣기',
            accent: tone.accent,
            onTap: onOpenBoth,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _ResourcePill(
                  icon: Icons.description_rounded,
                  label: sheetLabel,
                  enabled: true,
                  onTap: onOpenFile,
                  accent: tone.accent,
                  expand: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ResourcePill(
                  icon: Icons.headphones_rounded,
                  label: '가이드 듣기',
                  enabled: true,
                  onTap: onOpenAudio,
                  accent: tone.accent,
                  expand: true,
                ),
              ),
            ],
          ),
        ],
      );
    }
    // Only one present → a single full-width button.
    if (hasFile) {
      return _PrimaryResourceButton(
        icon: Icons.description_rounded,
        label: sheetLabel,
        accent: tone.accent,
        onTap: onOpenFile,
      );
    }
    if (hasAudio) {
      return _PrimaryResourceButton(
        icon: Icons.headphones_rounded,
        label: '가이드 듣기',
        accent: tone.accent,
        onTap: onOpenAudio,
      );
    }
    return _ResourcePill(
      icon: Icons.block_rounded,
      label: '자료 없음',
      enabled: false,
      onTap: () {},
      accent: tone.accent,
      expand: true,
    );
  }
}

class _PrimaryResourceButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  const _PrimaryResourceButton({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(
                    13,
                    weight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
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
  final bool expand;

  const _ResourcePill({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    required this.accent,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          decoration: BoxDecoration(
            color: enabled
                ? Colors.white.withValues(alpha: 0.58)
                : Colors.white.withValues(alpha: 0.32),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: enabled
                  ? accent.withValues(alpha: 0.28)
                  : AppColors.border.withValues(alpha: 0.26),
            ),
          ),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: expand
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              Icon(icon, size: 14, color: enabled ? accent : AppColors.muted),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(
                    12,
                    color: enabled ? AppColors.primary : AppColors.muted,
                    weight: FontWeight.w700,
                  ),
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
  final Color accent;

  const _PartTone({required this.accent});
}

_PartTone _toneForPart(String partKey) {
  switch (partKey) {
    case 'soprano':
      return const _PartTone(accent: Color(0xFF9B6A16));
    case 'alto':
      return const _PartTone(accent: Color(0xFF3F7C45));
    case 'tenor':
      return const _PartTone(accent: Color(0xFF32679A));
    case 'bass':
      return const _PartTone(accent: Color(0xFF6652A4));
    default:
      return const _PartTone(accent: Color(0xFF8A661B));
  }
}
