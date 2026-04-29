import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_providers.dart';

class EventsScreen extends ConsumerWidget {
  const EventsScreen({super.key});

  static const _typeLabels = {'award': '우수 출석자', 'event': '이벤트', 'milestone': '마일스톤'};
  static const _typeIcons = {'award': Icons.emoji_events, 'event': Icons.celebration, 'milestone': Icons.flag};
  static const _typeColors = {'award': Color(0xFFFFD700), 'event': Color(0xFF775A19), 'milestone': Color(0xFF2E7D32)};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(eventsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero
          Text('C.C NOTE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 2, color: AppColors.secondary)),
          const SizedBox(height: 8),
          const Text('이벤트 & 시상', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.primary)),
          const SizedBox(height: 8),
          const Text('우수 출석자 시상, 특별 이벤트, 마일스톤을 확인하세요.', style: TextStyle(fontSize: 15, color: AppColors.muted, height: 1.5)),
          const SizedBox(height: 24),

          eventsAsync.when(
            loading: () => const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())),
            error: (_, __) => const Center(child: Text('이벤트를 불러올 수 없습니다')),
            data: (eventsList) {
              if (eventsList.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: AppColors.surface, borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
                  ),
                  child: Column(children: [
                    Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.secondaryContainer.withValues(alpha: 0.3)),
                      child: const Icon(Icons.emoji_events, size: 40, color: AppColors.secondary),
                    ),
                    const SizedBox(height: 16),
                    const Text('아직 이벤트가 없습니다', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.primary)),
                    const SizedBox(height: 6),
                    const Text('우수 출석자 시상이나 특별 이벤트가\n등록되면 여기에 표시됩니다', style: TextStyle(fontSize: 14, color: AppColors.muted), textAlign: TextAlign.center),
                  ]),
                );
              }

              return Column(
                children: eventsList.map<Widget>((event) {
                  final type = event['type'] ?? 'event';
                  final icon = _typeIcons[type] ?? Icons.celebration;
                  final color = _typeColors[type] ?? AppColors.secondary;
                  final label = _typeLabels[type] ?? '이벤트';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.surface, borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      // Event Image
                      if (event['imageUrl'] != null)
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                          child: Image.network(event['imageUrl'], height: 180, width: double.infinity, fit: BoxFit.cover),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          // Type Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(icon, size: 14, color: color),
                              const SizedBox(width: 6),
                              Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
                            ]),
                          ),
                          const SizedBox(height: 12),
                          Text(event['title'] ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primary)),
                          if (event['description'] != null) ...[
                            const SizedBox(height: 8),
                            Text(event['description'], style: const TextStyle(fontSize: 14, color: AppColors.muted, height: 1.5)),
                          ],
                          if (event['eventDate'] != null) ...[
                            const SizedBox(height: 12),
                            Row(children: [
                              const Icon(Icons.calendar_today, size: 14, color: AppColors.muted),
                              const SizedBox(width: 6),
                              Text(_formatDate(event['eventDate']), style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                            ]),
                          ],
                        ]),
                      ),
                    ]),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  static String _formatDate(dynamic dateStr) {
    if (dateStr == null) return '';
    try {
      final d = DateTime.parse(dateStr.toString());
      return '${d.year}년 ${d.month}월 ${d.day}일';
    } catch (_) {
      return dateStr.toString();
    }
  }
}
