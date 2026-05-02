import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_providers.dart';

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
    final time = _timeText(date);
    final needsAttendance = EventsScreen.boolFlag(event, 'needsAttendance');
    final needsSeating = EventsScreen.boolFlag(event, 'needsSeating');

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
                if (needsAttendance || needsSeating) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: [
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
