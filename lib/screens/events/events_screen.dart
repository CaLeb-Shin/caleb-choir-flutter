import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../../services/firebase_service.dart';

class EventsScreen extends ConsumerWidget {
  const EventsScreen({super.key});

  static const _typeLabels = {
    'event': '일정',
    'rehearsal': '연습',
    'dressrehearsal': '리허설',
    'concert': '공연',
    'milestone': '기념',
  };

  static const _typeColors = {
    'event': Color(0xFF426C9F),
    'rehearsal': Color(0xFF2F7D3A),
    'dressrehearsal': Color(0xFF087F6E),
    'concert': Color(0xFFC76D16),
    'milestone': Color(0xFF6F4EB8),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(eventsProvider);
    final canManage = ref.watch(effectiveHasManagePermissionProvider);

    return eventsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => const Center(child: Text('일정을 불러올 수 없습니다')),
      data: (eventsList) {
        final items = [...eventsList]..sort(_compareByScheduleTime);
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 104),
          children: [
            Row(
              children: [
                Expanded(child: Text('일정', style: AppText.headline(28))),
                if (canManage) ...[
                  IconButton(
                    onPressed: () => _showAddEventDialog(context, ref),
                    icon: const Icon(
                      Icons.add_circle_rounded,
                      color: AppColors.secondary,
                    ),
                    tooltip: '일정 등록',
                  ),
                  const SizedBox(width: 2),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.secondarySoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${items.length}개',
                    style: AppText.body(
                      12,
                      weight: FontWeight.w800,
                      color: AppColors.secondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (items.isEmpty)
              const _EmptyScheduleState()
            else
              for (final event in items) _ScheduleTile(event: event),
          ],
        );
      },
    );
  }

  static int _compareByScheduleTime(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final aDate = _dateOf(a);
    final bDate = _dateOf(b);
    final aPast = aDate == null || aDate.isBefore(today);
    final bPast = bDate == null || bDate.isBefore(today);
    if (aPast != bPast) return aPast ? 1 : -1;
    if (aDate == null && bDate == null) return 0;
    if (aDate == null) return 1;
    if (bDate == null) return -1;
    return aDate.compareTo(bDate);
  }

  static DateTime? _dateOf(Map<String, dynamic> event) {
    final value = event['eventDate'] ?? event['date'];
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  static String typeLabel(dynamic type) {
    return _typeLabels[type?.toString()] ?? '일정';
  }

  static Color typeColor(dynamic type) {
    return _typeColors[type?.toString()] ?? _typeColors['event']!;
  }

  static String location(Map<String, dynamic> event) {
    for (final key in ['location', 'place', 'venue', 'address']) {
      final value = event[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return '장소 미정';
  }

  static bool boolFlag(Map<String, dynamic> event, String key) {
    final value = event[key];
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      return ['true', '1', 'yes', 'y'].contains(value.trim().toLowerCase());
    }
    return false;
  }

  void _showAddEventDialog(BuildContext context, WidgetRef ref) {
    final titleCtrl = TextEditingController();
    final dateCtrl = TextEditingController(
      text: DateTime.now().toIso8601String().split('T').first,
    );
    final timeCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    final descriptionCtrl = TextEditingController();
    final harmonyTitleCtrl = TextEditingController();
    final harmonyGuideCtrl = TextEditingController();
    final harmonyLyricsCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) {
        var selectedType = 'event';
        var needsAttendance = false;
        var needsSeating = false;
        var harmonyEnabled = false;
        var lyricFileName = '';
        var isSaving = false;

        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('일정 등록'),
            content: SizedBox(
              width: 430,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(hintText: '일정 제목'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: dateCtrl,
                      decoration: InputDecoration(
                        hintText: '날짜 (YYYY-MM-DD)',
                        suffixIcon: IconButton(
                          tooltip: '날짜 선택',
                          onPressed: () async {
                            final initialDate =
                                DateTime.tryParse(dateCtrl.text.trim()) ??
                                DateTime.now();
                            final picked = await showDatePicker(
                              context: context,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2035),
                              initialDate: initialDate,
                            );
                            if (picked == null) return;
                            dateCtrl.text = picked
                                .toIso8601String()
                                .split('T')
                                .first;
                          },
                          icon: const Icon(Icons.calendar_month_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: timeCtrl,
                      decoration: const InputDecoration(hintText: '시간 (선택)'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: locationCtrl,
                      decoration: const InputDecoration(hintText: '장소 (선택)'),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: selectedType,
                      decoration: const InputDecoration(hintText: '일정 종류'),
                      items: _typeLabels.entries
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => selectedType = value);
                      },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: descriptionCtrl,
                      decoration: const InputDecoration(hintText: '설명 (선택)'),
                      minLines: 2,
                      maxLines: 4,
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      value: needsAttendance,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '출석 체크 사용',
                        style: AppText.body(13, weight: FontWeight.w800),
                      ),
                      onChanged: (value) =>
                          setDialogState(() => needsAttendance = value),
                    ),
                    SwitchListTile(
                      value: needsSeating,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '자리판 사용',
                        style: AppText.body(13, weight: FontWeight.w800),
                      ),
                      onChanged: (value) =>
                          setDialogState(() => needsSeating = value),
                    ),
                    const Divider(height: 22),
                    SwitchListTile(
                      value: harmonyEnabled,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '하모니챗 릴레이 텍스트 같이 등록',
                        style: AppText.body(13, weight: FontWeight.w900),
                      ),
                      subtitle: Text(
                        '일정이 오늘의 릴레이 가이드로 열립니다',
                        style: AppText.body(11, color: AppColors.muted),
                      ),
                      onChanged: (value) =>
                          setDialogState(() => harmonyEnabled = value),
                    ),
                    if (harmonyEnabled) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: harmonyTitleCtrl,
                        decoration: const InputDecoration(
                          hintText: '릴레이 제목 (비우면 일정 제목)',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: harmonyGuideCtrl,
                        decoration: const InputDecoration(
                          hintText: '하모니챗 안내 문구 (선택)',
                        ),
                        minLines: 2,
                        maxLines: 4,
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: harmonyLyricsCtrl,
                        decoration: const InputDecoration(
                          hintText:
                              '노래방 가사 (선택)\n.txt는 줄마다, .lrc는 [00:12.30] 형식',
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
                          harmonyLyricsCtrl.text = utf8
                              .decode(bytes, allowMalformed: true)
                              .trim();
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
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(dialogCtx),
                child: const Text('취소'),
              ),
              TextButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final navigator = Navigator.of(dialogCtx);
                        final title = titleCtrl.text.trim();
                        final eventDate = dateCtrl.text.trim();
                        if (title.isEmpty || eventDate.isEmpty) {
                          messenger.showSnackBar(
                            const SnackBar(content: Text('제목과 날짜를 입력해주세요')),
                          );
                          return;
                        }
                        if (DateTime.tryParse(eventDate) == null) {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('날짜는 YYYY-MM-DD 형식으로 입력해주세요'),
                            ),
                          );
                          return;
                        }
                        final lyricsText = harmonyLyricsCtrl.text.trim();
                        final harmonyGuide = harmonyGuideCtrl.text.trim();
                        if (harmonyEnabled &&
                            harmonyGuide.isEmpty &&
                            lyricsText.isEmpty) {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('하모니챗 안내 문구나 가사를 입력해주세요'),
                            ),
                          );
                          return;
                        }
                        setDialogState(() => isSaving = true);
                        try {
                          if (ref.read(localPreviewModeProvider)) {
                            navigator.pop();
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('미리보기에서는 일정 저장을 건너뜁니다'),
                              ),
                            );
                            return;
                          }
                          await FirebaseService.createEvent(
                            title: title,
                            eventDate: eventDate,
                            time: timeCtrl.text.trim(),
                            location: locationCtrl.text.trim(),
                            description: descriptionCtrl.text.trim(),
                            type: selectedType,
                            needsAttendance: needsAttendance,
                            needsSeating: needsSeating,
                            harmonyEnabled: harmonyEnabled,
                            harmonyTitle: harmonyTitleCtrl.text.trim(),
                            harmonyGuide: harmonyGuide,
                            harmonyLyricsText: lyricsText,
                            harmonyLyricsTimeline: _lyricsTimelineFromText(
                              lyricsText,
                            ),
                          );
                          ref.invalidate(eventsProvider);
                          ref.invalidate(latestPartGuideProvider);
                          ref.invalidate(harmonyRelaysProvider);
                          navigator.pop();
                          messenger.showSnackBar(
                            const SnackBar(content: Text('일정을 등록했습니다')),
                          );
                        } catch (error) {
                          setDialogState(() => isSaving = false);
                          messenger.showSnackBar(
                            SnackBar(content: Text('일정 등록 실패: $error')),
                          );
                        }
                      },
                child: Text(isSaving ? '등록 중...' : '등록'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ScheduleTile extends StatelessWidget {
  final Map<String, dynamic> event;
  const _ScheduleTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final date = EventsScreen._dateOf(event);
    final title = event['title']?.toString().trim() ?? '일정';
    final description = event['description']?.toString().trim() ?? '';
    final type = event['type'];
    final color = EventsScreen.typeColor(type);
    final location = EventsScreen.location(event);
    final time = _firstNotEmpty([event['time']?.toString(), _timeText(date)]);
    final needsAttendance = EventsScreen.boolFlag(event, 'needsAttendance');
    final needsSeating = EventsScreen.boolFlag(event, 'needsSeating');
    final hasHarmony =
        EventsScreen.boolFlag(event, 'harmonyEnabled') ||
        _firstNotEmpty([
          event['harmonyTitle']?.toString(),
          event['harmonyGuide']?.toString(),
          event['harmonyLyricsText']?.toString(),
        ]).isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.42)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.035),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DateBlock(date: date),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        [if (time.isNotEmpty) time, location].join(' · '),
                        style: AppText.body(
                          12,
                          weight: FontWeight.w800,
                          color: AppColors.secondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _TypePill(
                      label: EventsScreen.typeLabel(type),
                      color: color,
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  title.isEmpty ? '일정' : title,
                  style: AppText.body(
                    16,
                    weight: FontWeight.w900,
                    color: AppColors.primary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: AppText.body(12, color: AppColors.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (needsAttendance || needsSeating || hasHarmony) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: [
                      if (hasHarmony)
                        const _MetaPill(
                          label: '하모니',
                          icon: Icons.queue_music_rounded,
                          color: AppColors.secondary,
                        ),
                      if (needsAttendance)
                        const _MetaPill(
                          label: '출석',
                          icon: Icons.fact_check_rounded,
                          color: AppColors.secondary,
                        ),
                      if (needsSeating)
                        const _MetaPill(
                          label: '자리판',
                          icon: Icons.event_seat_rounded,
                          color: AppColors.primary,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _timeText(DateTime? date) {
    if (date == null || (date.hour == 0 && date.minute == 0)) return '';
    return '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  static String _firstNotEmpty(Iterable<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isNotEmpty) return trimmed;
    }
    return '';
  }
}

class _DateBlock extends StatelessWidget {
  final DateTime? date;
  const _DateBlock({required this.date});

  @override
  Widget build(BuildContext context) {
    final scheduleDate = date;
    final monthDay = scheduleDate == null
        ? '-'
        : '${scheduleDate.month}/${scheduleDate.day}';
    final weekday = scheduleDate == null
        ? '날짜 미정'
        : '${const ['월', '화', '수', '목', '금', '토', '일'][scheduleDate.weekday - 1]}요일';
    return Container(
      width: 68,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Text(
            monthDay,
            style: AppText.body(
              18,
              weight: FontWeight.w900,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            weekday,
            style: AppText.body(
              10,
              weight: FontWeight.w700,
              color: AppColors.muted,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _TypePill extends StatelessWidget {
  final String label;
  final Color color;
  const _TypePill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppText.body(10, weight: FontWeight.w900, color: color),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  const _MetaPill({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: AppText.body(10, weight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }
}

class _EmptyScheduleState extends StatelessWidget {
  const _EmptyScheduleState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 30),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Icon(Icons.calendar_today_rounded, size: 30, color: AppColors.subtle),
          const SizedBox(height: 10),
          Text(
            '등록된 일정이 없습니다',
            style: AppText.body(15, weight: FontWeight.w800),
          ),
        ],
      ),
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
        : (int.tryParse(fractionText) ?? 0) / _mathPow10(fractionText.length);
    final lyric = (match.group(4) ?? '').trim();
    if (lyric.isEmpty) continue;
    entries.add({'timeSec': minutes * 60 + seconds + fraction, 'text': lyric});
  }
  entries.sort((a, b) {
    final at = (a['timeSec'] as num?)?.toDouble() ?? 0;
    final bt = (b['timeSec'] as num?)?.toDouble() ?? 0;
    return at.compareTo(bt);
  });
  return entries;
}

double _mathPow10(int exponent) {
  var value = 1.0;
  for (var i = 0; i < exponent; i += 1) {
    value *= 10;
  }
  return value;
}
