import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/user.dart';
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
    final profile = ref.watch(profileProvider).valueOrNull;
    final relayPartOptions = _relayPartOptionsFor(profile);

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
              for (final event in items)
                _ScheduleTile(
                  event: event,
                  canManage: canManage,
                  relayPartOptions: relayPartOptions,
                  ref: ref,
                ),
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

    showDialog(
      context: context,
      builder: (dialogCtx) {
        var selectedType = 'event';
        var needsAttendance = false;
        var needsSeating = false;
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
                    const SizedBox(height: 8),
                    Text(
                      '하모니챗 릴레이와 가사 싱크는 일정 저장 후 카드에서 따로 준비할 수 있어요.',
                      style: AppText.body(12, color: AppColors.muted),
                    ),
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
                          );
                          ref.invalidate(eventsProvider);
                          navigator.pop();
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text(
                                '일정을 등록했습니다. 하모니챗은 일정 카드에서 따로 준비해주세요.',
                              ),
                            ),
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
  final bool canManage;
  final List<_RelayPartOption> relayPartOptions;
  final WidgetRef ref;

  const _ScheduleTile({
    required this.event,
    required this.canManage,
    required this.relayPartOptions,
    required this.ref,
  });

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
    final hasLyricsSync = _lyricsTimelineFromValue(
      event['harmonyLyricsTimeline'],
    ).isNotEmpty;
    final harmonySegmentCount = _harmonySegmentsForPart(
      event['harmonySegments'],
      'all',
    ).length;

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
                      if (hasLyricsSync)
                        const _MetaPill(
                          label: '싱크',
                          icon: Icons.lyrics_rounded,
                          color: AppColors.secondary,
                        ),
                      if (harmonySegmentCount > 0)
                        _MetaPill(
                          label: '$harmonySegmentCount소절',
                          icon: Icons.call_split_rounded,
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
                if (canManage) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _openHarmonyGuideSheet(context),
                        icon: Icon(
                          hasHarmony
                              ? Icons.lyrics_rounded
                              : Icons.queue_music_rounded,
                          size: 18,
                        ),
                        label: Text(hasHarmony ? '가사 싱크' : '하모니 준비'),
                      ),
                      if (hasHarmony && relayPartOptions.isNotEmpty)
                        FilledButton.icon(
                          onPressed: () => _openRelayCreateSheet(context),
                          icon: const Icon(
                            Icons.playlist_add_rounded,
                            size: 18,
                          ),
                          label: const Text('릴레이 만들기'),
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

  void _openHarmonyGuideSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EventHarmonyGuideSheet(event: event, ref: ref),
    );
  }

  void _openRelayCreateSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateEventRelaySheet(
        event: event,
        partOptions: relayPartOptions,
        ref: ref,
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

class _EventHarmonyGuideSheet extends StatefulWidget {
  const _EventHarmonyGuideSheet({required this.event, required this.ref});

  final Map<String, dynamic> event;
  final WidgetRef ref;

  @override
  State<_EventHarmonyGuideSheet> createState() =>
      _EventHarmonyGuideSheetState();
}

class _EventHarmonyGuideSheetState extends State<_EventHarmonyGuideSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _guideController;
  late final TextEditingController _lyricsController;
  final List<_LyricSyncLine> _syncLines = [];
  final List<_HarmonySegmentLine> _segmentLines = [];
  String _lyricFileName = '';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final eventTitle = widget.event['title']?.toString().trim() ?? '';
    final harmonyTitle = widget.event['harmonyTitle']?.toString().trim() ?? '';
    _titleController = TextEditingController(
      text: harmonyTitle.isEmpty ? eventTitle : harmonyTitle,
    );
    _guideController = TextEditingController(
      text: widget.event['harmonyGuide']?.toString() ?? '',
    );
    _lyricsController = TextEditingController(
      text: widget.event['harmonyLyricsText']?.toString() ?? '',
    );
    final existingSync = _syncLinesFromValue(
      widget.event['harmonyLyricsTimeline'],
    );
    _replaceSyncLines(
      existingSync.isEmpty && _lyricsController.text.trim().isNotEmpty
          ? _syncLinesFromText(_lyricsController.text)
          : existingSync,
      disposeOld: false,
    );
    _replaceSegmentLines(
      _segmentLinesFromValue(widget.event['harmonySegments']),
      disposeOld: false,
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _guideController.dispose();
    _lyricsController.dispose();
    for (final line in _syncLines) {
      line.dispose();
    }
    for (final line in _segmentLines) {
      line.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '하모니챗 준비',
                          style: AppText.body(20, weight: FontWeight.w900),
                        ),
                      ),
                      IconButton(
                        onPressed: _isSaving
                            ? null
                            : () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                        tooltip: '닫기',
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '일정은 그대로 두고 릴레이 가이드와 가사 싱크만 따로 저장합니다.',
                    style: AppText.body(12, color: AppColors.muted),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _titleController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '릴레이 제목',
                      hintText: '비우면 일정 제목을 사용합니다',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _guideController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: '하모니챗 안내 문구',
                      hintText: '진입음, 호흡, 가사 느낌을 짧게 적어주세요',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _lyricsController,
                    minLines: 4,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      labelText: '가사',
                      hintText: '.txt는 줄마다, .lrc는 [00:12.30] 형식으로 붙여넣어 주세요',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _pickLyricsFile,
                        icon: const Icon(Icons.upload_file_rounded, size: 18),
                        label: Text(
                          _lyricFileName.isEmpty ? '가사 파일 선택' : _lyricFileName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _rebuildSyncFromLyrics,
                        icon: const Icon(Icons.sync_rounded, size: 18),
                        label: const Text('가사로 싱크 만들기'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '가사 싱크',
                          style: AppText.body(15, weight: FontWeight.w900),
                        ),
                      ),
                      Text(
                        '${_syncLines.length}줄',
                        style: AppText.body(12, color: AppColors.muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_syncLines.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLow,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.border.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        '가사를 넣고 싱크를 만들면 줄별 시간을 조정할 수 있어요.',
                        style: AppText.body(12, color: AppColors.muted),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 280),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _syncLines.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final line = _syncLines[index];
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 86,
                                child: TextField(
                                  controller: line.timeController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    hintText: '00:00.00',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: line.textController,
                                  minLines: 1,
                                  maxLines: 2,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    hintText: '가사',
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '녹음 소절',
                          style: AppText.body(15, weight: FontWeight.w900),
                        ),
                      ),
                      Text(
                        '${_segmentLines.length}개',
                        style: AppText.body(12, color: AppColors.muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _rebuildSegmentsFromSync,
                        icon: const Icon(Icons.call_split_rounded, size: 18),
                        label: const Text('싱크로 소절 만들기'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _addSegmentLine,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('소절 추가'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_segmentLines.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLow,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.border.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        '소절을 나누지 않으면 한 개 릴레이로 녹음됩니다.',
                        style: AppText.body(12, color: AppColors.muted),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 300),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _segmentLines.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final segment = _segmentLines[index];
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 70,
                                child: TextField(
                                  controller: segment.startController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    labelText: '시작',
                                    hintText: '00:00',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              SizedBox(
                                width: 70,
                                child: TextField(
                                  controller: segment.endController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    labelText: '끝',
                                    hintText: '00:08',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: TextField(
                                  controller: segment.labelController,
                                  minLines: 1,
                                  maxLines: 2,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    labelText: '라벨',
                                    hintText: '1소절',
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () => _removeSegmentLine(index),
                                icon: const Icon(Icons.close_rounded, size: 18),
                                tooltip: '소절 삭제',
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isSaving ? null : _save,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_rounded, size: 18),
                      label: Text(_isSaving ? '저장 중...' : '하모니 준비 저장'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickLyricsFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'lrc'],
      withData: true,
    );
    final file = picked?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null || bytes.isEmpty) return;
    _lyricsController.text = utf8.decode(bytes, allowMalformed: true).trim();
    _replaceSyncLines(_syncLinesFromText(_lyricsController.text));
    setState(() => _lyricFileName = file.name);
  }

  void _rebuildSyncFromLyrics() {
    final lyrics = _lyricsController.text.trim();
    if (lyrics.isEmpty) {
      _showMessage('가사를 먼저 입력해주세요.');
      return;
    }
    _replaceSyncLines(_syncLinesFromText(lyrics));
    setState(() {});
  }

  void _replaceSyncLines(List<_LyricSyncLine> lines, {bool disposeOld = true}) {
    if (disposeOld) {
      for (final line in _syncLines) {
        line.dispose();
      }
    }
    _syncLines
      ..clear()
      ..addAll(lines);
  }

  void _replaceSegmentLines(
    List<_HarmonySegmentLine> lines, {
    bool disposeOld = true,
  }) {
    if (disposeOld) {
      for (final line in _segmentLines) {
        line.dispose();
      }
    }
    _segmentLines
      ..clear()
      ..addAll(lines);
  }

  void _rebuildSegmentsFromSync() {
    final timeline = _timelinePayload();
    if (timeline == null) {
      _showMessage('가사 시간은 00:12.30 또는 초 단위 숫자로 입력해주세요.');
      return;
    }
    final source = timeline.isNotEmpty
        ? timeline
        : _lyricsTimelineFromText(_lyricsController.text.trim());
    if (source.isEmpty) {
      _showMessage('가사 싱크를 먼저 만들어주세요.');
      return;
    }
    final nextLines = <_HarmonySegmentLine>[];
    for (var index = 0; index < source.length; index += 1) {
      final start = (source[index]['timeSec'] as num?)?.toDouble() ?? 0;
      final nextStart = index + 1 < source.length
          ? (source[index + 1]['timeSec'] as num?)?.toDouble() ?? start
          : start + 4.0;
      final end = nextStart > start ? nextStart : start + 4.0;
      nextLines.add(
        _HarmonySegmentLine(
          label: '${index + 1}소절',
          startSec: start,
          endSec: end,
        ),
      );
    }
    _replaceSegmentLines(nextLines);
    setState(() {});
  }

  void _addSegmentLine() {
    final lastEnd = _segmentLines.isEmpty
        ? 0.0
        : _parseSyncTime(_segmentLines.last.endController.text.trim()) ?? 0.0;
    setState(() {
      _segmentLines.add(
        _HarmonySegmentLine(
          label: '${_segmentLines.length + 1}소절',
          startSec: lastEnd,
          endSec: lastEnd + 4.0,
        ),
      );
    });
  }

  void _removeSegmentLine(int index) {
    if (index < 0 || index >= _segmentLines.length) return;
    final line = _segmentLines.removeAt(index);
    line.dispose();
    setState(() {});
  }

  Future<void> _save() async {
    final eventId = widget.event['id']?.toString() ?? '';
    final eventTitle = widget.event['title']?.toString().trim() ?? '';
    final harmonyTitle = _firstFilled([
      _titleController.text,
      eventTitle,
      '하모니 릴레이',
    ]);
    final guide = _guideController.text.trim();
    final lyrics = _lyricsController.text.trim();
    if (eventId.isEmpty) {
      _showMessage('일정 ID를 찾을 수 없습니다.');
      return;
    }
    if (guide.isEmpty && lyrics.isEmpty) {
      _showMessage('안내 문구나 가사를 입력해주세요.');
      return;
    }
    final timeline = _timelinePayload();
    if (timeline == null) {
      _showMessage('가사 시간은 00:12.30 또는 초 단위 숫자로 입력해주세요.');
      return;
    }
    final segments = _segmentPayload();
    if (segments == null) {
      _showMessage('녹음 소절 시간은 00:12.30 또는 초 단위로 입력하고, 끝은 시작보다 늦어야 해요.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _isSaving = true);
    try {
      if (widget.ref.read(localPreviewModeProvider)) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
      } else {
        await FirebaseService.updateEventHarmonyGuide(
          eventId: eventId,
          harmonyTitle: harmonyTitle,
          harmonyGuide: guide,
          harmonyLyricsText: lyrics,
          harmonyLyricsTimeline: timeline.isEmpty && lyrics.isNotEmpty
              ? _lyricsTimelineFromText(lyrics)
              : timeline,
          harmonySegments: segments.isEmpty
              ? const <String, dynamic>{}
              : {
                  'parts': {'all': segments},
                },
        );
        widget.ref.invalidate(eventsProvider);
        widget.ref.invalidate(latestPartGuideProvider);
        widget.ref.invalidate(harmonyRelaysProvider);
      }
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('하모니챗 준비를 저장했습니다. 이제 릴레이를 따로 만들 수 있어요.')),
      );
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
      if (mounted) setState(() => _isSaving = false);
    }
  }

  List<Map<String, dynamic>>? _timelinePayload() {
    final payload = <Map<String, dynamic>>[];
    for (final line in _syncLines) {
      final text = line.textController.text.trim();
      if (text.isEmpty) continue;
      final seconds = _parseSyncTime(line.timeController.text.trim());
      if (seconds == null) return null;
      payload.add({'timeSec': seconds, 'text': text});
    }
    payload.sort((a, b) {
      final at = (a['timeSec'] as num?)?.toDouble() ?? 0;
      final bt = (b['timeSec'] as num?)?.toDouble() ?? 0;
      return at.compareTo(bt);
    });
    return payload;
  }

  List<Map<String, dynamic>>? _segmentPayload() {
    final raw = <Map<String, dynamic>>[];
    for (final line in _segmentLines) {
      final start = _parseSyncTime(line.startController.text.trim());
      final end = _parseSyncTime(line.endController.text.trim());
      if (start == null || end == null || end <= start) return null;
      final label = _firstFilled([
        line.labelController.text,
        '${raw.length + 1}소절',
      ]);
      raw.add({'label': label, 'startSec': start, 'endSec': end});
    }
    raw.sort((a, b) {
      final at = (a['startSec'] as num?)?.toDouble() ?? 0;
      final bt = (b['startSec'] as num?)?.toDouble() ?? 0;
      return at.compareTo(bt);
    });
    return [
      for (var index = 0; index < raw.length; index += 1)
        {
          'id': 'seg-${(index + 1).toString().padLeft(2, '0')}',
          'order': index + 1,
          'label': raw[index]['label']?.toString() ?? '${index + 1}소절',
          'startSec': (raw[index]['startSec'] as num?)?.toDouble() ?? 0,
          'endSec': (raw[index]['endSec'] as num?)?.toDouble() ?? 0,
          'durationSec':
              ((raw[index]['endSec'] as num?)?.toDouble() ?? 0) -
              ((raw[index]['startSec'] as num?)?.toDouble() ?? 0),
        },
    ];
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _CreateEventRelaySheet extends StatefulWidget {
  const _CreateEventRelaySheet({
    required this.event,
    required this.partOptions,
    required this.ref,
  });

  final Map<String, dynamic> event;
  final List<_RelayPartOption> partOptions;
  final WidgetRef ref;

  @override
  State<_CreateEventRelaySheet> createState() => _CreateEventRelaySheetState();
}

class _CreateEventRelaySheetState extends State<_CreateEventRelaySheet> {
  late String _selectedPart;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _selectedPart = widget.partOptions.first.part;
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final guide = _eventHarmonyGuide(widget.event);
    final title = guide['title']?.toString() ?? '하모니 릴레이';
    final guideText = guide['guide']?.toString() ?? '';
    final lyricsCount = _lyricsTimelineFromValue(
      guide['lyricsTimeline'],
    ).length;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        decoration: const BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '릴레이 만들기',
                      style: AppText.body(20, weight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                    onPressed: _isCreating
                        ? null
                        : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: '닫기',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(title, style: AppText.body(16, weight: FontWeight.w900)),
              if (guideText.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  guideText,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(12, color: AppColors.muted, height: 1.35),
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _selectedPart,
                decoration: const InputDecoration(labelText: '릴레이 파트'),
                items: widget.partOptions
                    .map(
                      (part) => DropdownMenuItem(
                        value: part.part,
                        child: Text(part.label),
                      ),
                    )
                    .toList(),
                onChanged: _isCreating
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() => _selectedPart = value);
                      },
              ),
              const SizedBox(height: 10),
              Text(
                lyricsCount == 0
                    ? '저장된 가사 싱크 없이 릴레이를 만듭니다.'
                    : '저장된 가사 싱크 $lyricsCount줄을 릴레이에 적용합니다.',
                style: AppText.body(12, color: AppColors.muted),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isCreating ? null : _createRelay,
                  icon: _isCreating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.playlist_add_rounded, size: 18),
                  label: Text(_isCreating ? '릴레이 여는 중...' : '릴레이 만들기'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createRelay() async {
    setState(() => _isCreating = true);
    try {
      if (widget.ref.read(localPreviewModeProvider)) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
      } else {
        await FirebaseService.createHarmonyRelayFromGuide(
          part: _selectedPart,
          guide: _eventHarmonyGuide(widget.event, part: _selectedPart),
        );
        widget.ref.invalidate(harmonyRelaysProvider);
      }
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('하모니챗 릴레이를 만들었습니다.')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
        setState(() => _isCreating = false);
      }
    }
  }
}

class _LyricSyncLine {
  _LyricSyncLine({required double timeSec, required String text})
    : timeController = TextEditingController(text: _formatSyncTime(timeSec)),
      textController = TextEditingController(text: text);

  final TextEditingController timeController;
  final TextEditingController textController;

  void dispose() {
    timeController.dispose();
    textController.dispose();
  }
}

class _HarmonySegmentLine {
  _HarmonySegmentLine({
    required String label,
    required double startSec,
    required double endSec,
  }) : labelController = TextEditingController(text: label),
       startController = TextEditingController(text: _formatSyncTime(startSec)),
       endController = TextEditingController(text: _formatSyncTime(endSec));

  final TextEditingController labelController;
  final TextEditingController startController;
  final TextEditingController endController;

  void dispose() {
    labelController.dispose();
    startController.dispose();
    endController.dispose();
  }
}

class _RelayPartOption {
  const _RelayPartOption({required this.part, required this.label});

  final String part;
  final String label;
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

List<_RelayPartOption> _relayPartOptionsFor(User? profile) {
  final parts = <String>[];
  if (profile?.isAdmin ?? false) {
    parts.addAll(User.selectableParts.where((part) => part != 'officer_part'));
  } else {
    final leaderPart = profile?.partLeaderFor?.trim() ?? '';
    final memberPart = profile?.part?.trim() ?? '';
    if (leaderPart.isNotEmpty) parts.add(leaderPart);
    if (memberPart.isNotEmpty) parts.add(memberPart);
  }
  return parts
      .where((part) => part.isNotEmpty)
      .toSet()
      .map(
        (part) =>
            _RelayPartOption(part: part, label: User.partLabels[part] ?? part),
      )
      .toList();
}

Map<String, dynamic> _eventHarmonyGuide(
  Map<String, dynamic> event, {
  String part = '',
}) {
  final eventTitle = event['title']?.toString().trim() ?? '';
  final title = _firstFilled([
    event['harmonyTitle']?.toString(),
    eventTitle,
    '하모니 릴레이',
  ]);
  final eventDate =
      event['eventDate']?.toString() ?? event['date']?.toString() ?? '';
  final lyricsText = event['harmonyLyricsText']?.toString() ?? '';
  return {
    'title': title,
    'songTitle': title,
    'eventId': event['id']?.toString() ?? '',
    'sourceEventId': event['id']?.toString() ?? '',
    'sheetDate': eventDate,
    'eventDate': eventDate,
    'guide': event['harmonyGuide']?.toString() ?? '',
    'lyricsText': lyricsText,
    'lyricsTimeline': _lyricsTimelineFromValue(event['harmonyLyricsTimeline']),
    'lyricLines': _lyricsLinesForAutoTiming(lyricsText),
    'segments': _harmonySegmentsForPart(event['harmonySegments'], part),
  };
}

List<_LyricSyncLine> _syncLinesFromValue(dynamic value) {
  return _lyricsTimelineFromValue(value)
      .map(
        (entry) => _LyricSyncLine(
          timeSec: (entry['timeSec'] as num?)?.toDouble() ?? 0,
          text: entry['text']?.toString() ?? '',
        ),
      )
      .toList();
}

List<_HarmonySegmentLine> _segmentLinesFromValue(dynamic value) {
  return _harmonySegmentsForPart(value, 'all')
      .map(
        (segment) => _HarmonySegmentLine(
          label: _firstFilled([
            segment['label']?.toString(),
            '${(segment['order'] as num?)?.toInt() ?? 1}소절',
          ]),
          startSec: (segment['startSec'] as num?)?.toDouble() ?? 0,
          endSec: (segment['endSec'] as num?)?.toDouble() ?? 0,
        ),
      )
      .toList();
}

List<_LyricSyncLine> _syncLinesFromText(String text) {
  return _lyricsTimelineFromText(text)
      .map(
        (entry) => _LyricSyncLine(
          timeSec: (entry['timeSec'] as num?)?.toDouble() ?? 0,
          text: entry['text']?.toString() ?? '',
        ),
      )
      .toList();
}

List<Map<String, dynamic>> _harmonySegmentsForPart(dynamic value, String part) {
  if (value is! Map) return const [];
  final map = Map<String, dynamic>.from(value);
  final partsValue = map['parts'];
  if (partsValue is! Map) return const [];
  final parts = Map<String, dynamic>.from(partsValue);
  final raw = parts[part] ?? parts['all'];
  if (raw is! List) {
    for (final value in parts.values) {
      if (value is List && value.isNotEmpty) {
        return _normalizeHarmonySegments(value);
      }
    }
    return const [];
  }
  return _normalizeHarmonySegments(raw);
}

List<Map<String, dynamic>> _normalizeHarmonySegments(List raw) {
  final segments =
      raw
          .whereType<Map>()
          .map((segment) {
            final start = (segment['startSec'] as num?)?.toDouble() ?? 0;
            final end = (segment['endSec'] as num?)?.toDouble() ?? start;
            return {
              'id': segment['id']?.toString() ?? '',
              'order': (segment['order'] as num?)?.toInt() ?? 0,
              'label': segment['label']?.toString() ?? '',
              'startSec': start,
              'endSec': end,
              'durationSec':
                  (segment['durationSec'] as num?)?.toDouble() ?? (end - start),
            };
          })
          .where((segment) {
            final end = (segment['endSec'] as num?)?.toDouble() ?? 0;
            final start = (segment['startSec'] as num?)?.toDouble() ?? 0;
            return end > start;
          })
          .toList()
        ..sort((a, b) {
          final aOrder = (a['order'] as num?)?.toInt() ?? 0;
          final bOrder = (b['order'] as num?)?.toInt() ?? 0;
          if (aOrder != bOrder) return aOrder.compareTo(bOrder);
          final at = (a['startSec'] as num?)?.toDouble() ?? 0;
          final bt = (b['startSec'] as num?)?.toDouble() ?? 0;
          return at.compareTo(bt);
        });
  return segments;
}

List<Map<String, dynamic>> _lyricsTimelineFromValue(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((entry) {
        return {
          'timeSec': (entry['timeSec'] as num?)?.toDouble() ?? 0,
          'text': entry['text']?.toString() ?? '',
        };
      })
      .where((entry) => (entry['text']?.toString() ?? '').trim().isNotEmpty)
      .toList()
    ..sort((a, b) {
      final at = (a['timeSec'] as num?)?.toDouble() ?? 0;
      final bt = (b['timeSec'] as num?)?.toDouble() ?? 0;
      return at.compareTo(bt);
    });
}

String _formatSyncTime(double seconds) {
  final totalCentiseconds = (seconds * 100)
      .round()
      .clamp(0, 24 * 60 * 60 * 100)
      .toInt();
  final totalSeconds = totalCentiseconds ~/ 100;
  final minutes = totalSeconds ~/ 60;
  final second = totalSeconds % 60;
  final centiseconds = totalCentiseconds % 100;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${second.toString().padLeft(2, '0')}.'
      '${centiseconds.toString().padLeft(2, '0')}';
}

double? _parseSyncTime(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final secondsOnly = double.tryParse(trimmed);
  if (secondsOnly != null) return secondsOnly;
  final match = RegExp(
    r'^(\d{1,3}):([0-5]?\d)(?:[.:](\d{1,3}))?$',
  ).firstMatch(trimmed);
  if (match == null) return null;
  final minutes = int.tryParse(match.group(1) ?? '') ?? 0;
  final seconds = int.tryParse(match.group(2) ?? '') ?? 0;
  final fractionText = match.group(3) ?? '';
  final fraction = fractionText.isEmpty
      ? 0.0
      : (int.tryParse(fractionText) ?? 0) / _mathPow10(fractionText.length);
  return minutes * 60 + seconds + fraction;
}

String _firstFilled(List<String?> values) {
  for (final value in values) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isNotEmpty) return trimmed;
  }
  return '';
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

double _mathPow10(int exponent) {
  var value = 1.0;
  for (var i = 0; i < exponent; i += 1) {
    value *= 10;
  }
  return value;
}
