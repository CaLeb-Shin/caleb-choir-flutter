import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../../widgets/interactive.dart';
import '../../services/firebase_service.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);
    final announcementsAsync = ref.watch(announcementsProvider);
    final historyAsync = ref.watch(myHistoryProvider);
    final sessionAsync = ref.watch(activeSessionProvider);
    final eventsAsync = ref.watch(eventsProvider);
    final recentSheets = ref.watch(recentSheetMusicProvider).valueOrNull ?? [];
    final recentVids = ref.watch(recentVideosProvider).valueOrNull ?? [];

    return profileAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('프로필을 불러올 수 없습니다')),
      data: (profile) {
        if (profile == null) return const SizedBox.shrink();
        final announcements = announcementsAsync.valueOrNull ?? [];
        final attendanceCount = historyAsync.valueOrNull?.length ?? 0;
        final session = sessionAsync.valueOrNull;
        final now = DateTime.now();
        final weekday = ['월', '화', '수', '목', '금', '토', '일'][now.weekday - 1];
        final totalUploads = recentSheets.length + recentVids.length;

        // Pick upcoming events from Firestore (date >= today), up to 3
        final allEvents = eventsAsync.valueOrNull ?? [];
        final upcomingEvents = allEvents.where((e) {
          final d = e['date'];
          if (d == null || d is! String || d.isEmpty) return false;
          final parsed = DateTime.tryParse(d);
          if (parsed == null) return false;
          return !parsed.isBefore(DateTime(now.year, now.month, now.day));
        }).toList()
          ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
        final upcomingTop = upcomingEvents.take(3).toList();

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(profileProvider);
            ref.invalidate(announcementsProvider);
            ref.invalidate(myHistoryProvider);
            ref.invalidate(activeSessionProvider);
            ref.invalidate(eventsProvider);
            ref.invalidate(recentSheetMusicProvider);
            ref.invalidate(recentVideosProvider);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header
                Row(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset('assets/images/icon.png', width: 32, height: 32),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text('갈렙찬양대', style: AppText.headline(18))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: AppColors.secondarySoft, borderRadius: BorderRadius.circular(16)),
                    child: Text('${now.month}월 ${now.day}일 ($weekday)', style: AppText.body(11, weight: FontWeight.w600, color: AppColors.secondary)),
                  ),
                ]),
                const SizedBox(height: 28),

                // ── Welcome
                Text('환영합니다', style: AppText.label()),
                const SizedBox(height: 8),
                Text('${profile.name ?? "멤버"}님,\n오늘도 함께 찬양해요', style: AppText.headline(26, weight: FontWeight.w700)),
                const SizedBox(height: 24),

                // ── Upcoming Rehearsal / Active Session
                Tappable(
                  onTap: () {},
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF000E24), Color(0xFF00234B)],
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: session != null
                        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: AppColors.secondaryContainer, borderRadius: BorderRadius.circular(6)),
                              child: Text('출석 진행 중', style: AppText.body(10, weight: FontWeight.w700, color: AppColors.secondary)),
                            ),
                            const SizedBox(height: 14),
                            Text(session['title'] ?? '연습', style: AppText.headline(22, color: Colors.white)),
                            const SizedBox(height: 12),
                            _InfoRow(icon: Icons.calendar_today_rounded, text: _formatSessionDate(session['openedAt'])),
                            const SizedBox(height: 6),
                            _InfoRow(icon: Icons.schedule_rounded, text: _formatSessionTime(session['openedAt'])),
                            const SizedBox(height: 18),
                            Row(children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () async {
                                    await FirebaseService.checkIn(session['id']);
                                    ref.invalidate(myHistoryProvider);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.secondaryContainer,
                                    foregroundColor: AppColors.primary,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                  ),
                                  child: const Text('출석하기'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => ref.read(tabIndexProvider.notifier).state = 3,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                  ),
                                  child: const Text('상세보기'),
                                ),
                              ),
                            ]),
                          ])
                        : upcomingTop.isNotEmpty
                            ? _buildUpcomingEventsCard(upcomingTop, attendanceCount, now)
                            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                              child: Text('다음 일정', style: AppText.body(10, weight: FontWeight.w700, color: Colors.white70)),
                            ),
                            const SizedBox(height: 14),
                            Text('예정된 연습이 없습니다', style: AppText.headline(20, color: Colors.white)),
                            const SizedBox(height: 8),
                            Text('관리자가 일정을 등록하면 여기에 표시됩니다', style: AppText.body(13, color: Colors.white54)),
                            const SizedBox(height: 16),
                            Text('총 $attendanceCount회 출석', style: AppText.body(13, weight: FontWeight.w600, color: AppColors.secondaryContainer)),
                          ]),
                  ),
                ),
                const SizedBox(height: 24),

                // ── Quick Actions (2x2 grid)
                Row(children: [
                  Expanded(child: _ActionCard(
                    icon: Icons.qr_code_scanner_rounded, title: 'QR 출석', desc: 'QR코드로 빠른 출석',
                    isDark: true, onTap: () => ref.read(tabIndexProvider.notifier).state = 3,
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: _ActionCard(
                    icon: Icons.music_note_rounded, title: '악보 열람', desc: '파트별 악보 확인',
                    onTap: () => ref.read(tabIndexProvider.notifier).state = 1,
                  )),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _ActionCard(
                    icon: Icons.play_circle_rounded, title: '영상 보기', desc: '찬양 영상 감상',
                    onTap: () => ref.read(tabIndexProvider.notifier).state = 2,
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: _ActionCard(
                    icon: Icons.chat_bubble_rounded, title: '커뮤니티', desc: '소통하기',
                    isDark: true, onTap: () => ref.read(tabIndexProvider.notifier).state = 4,
                  )),
                ]),
                const SizedBox(height: 28),

                // ── This Week's Uploads
                if (totalUploads > 0) ...[
                  Row(children: [
                    Expanded(child: Text('이번 주 업로드', style: AppText.headline(18))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: AppColors.secondarySoft, borderRadius: BorderRadius.circular(8)),
                      child: Text('$totalUploads개', style: AppText.body(11, weight: FontWeight.w700, color: AppColors.secondary)),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 90,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      children: [
                        ...recentSheets.map((s) => _UploadChip(
                          icon: Icons.description_rounded, title: s['title'] ?? '', sub: s['composer'] ?? '악보', color: AppColors.primary,
                        )),
                        ...recentVids.map((v) => _UploadChip(
                          icon: Icons.play_circle_rounded, title: v['title'] ?? '', sub: '영상', color: AppColors.secondary,
                        )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                ],

                // ── Announcements Feed (Timeline)
                Row(children: [
                  Expanded(child: Text('최근 소식', style: AppText.headline(18))),
                  Icon(Icons.notifications_rounded, size: 20, color: AppColors.secondary),
                ]),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLow,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: announcements.isEmpty
                      ? Center(child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Text('새로운 소식이 없습니다', style: AppText.body(14, color: AppColors.muted)),
                        ))
                      : Column(
                          children: [
                            ...announcements.take(5).map((ann) {
                              final isRecent = _isRecent(ann['createdAt']);
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Column(children: [
                                    Container(
                                      width: 8, height: 8,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isRecent ? AppColors.secondaryContainer : AppColors.subtle,
                                      ),
                                    ),
                                    Container(width: 1, height: 40, color: AppColors.border.withValues(alpha: 0.3)),
                                  ]),
                                  const SizedBox(width: 14),
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(_timeAgo(ann['createdAt']),
                                      style: AppText.body(10, weight: FontWeight.w700, color: AppColors.muted)),
                                    const SizedBox(height: 3),
                                    Text(ann['title'] ?? '', style: AppText.body(14, weight: FontWeight.w700),
                                      maxLines: 1, overflow: TextOverflow.ellipsis),
                                    if (ann['content'] != null) ...[
                                      const SizedBox(height: 2),
                                      Text(ann['content'] ?? '', style: AppText.body(12, color: AppColors.onSurfaceVariant, height: 1.4),
                                        maxLines: 2, overflow: TextOverflow.ellipsis),
                                    ],
                                  ])),
                                ]),
                              );
                            }),
                            Tappable(
                              onTap: () => ref.read(tabIndexProvider.notifier).state = 4,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Center(child: Text('전체 보기', style: AppText.label())),
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _formatSessionDate(dynamic d) {
    if (d == null) return '';
    try {
      final dt = DateTime.parse(d.toString());
      final wd = ['월', '화', '수', '목', '금', '토', '일'][dt.weekday - 1];
      return '${dt.year}년 ${dt.month}월 ${dt.day}일 ($wd)';
    } catch (_) { return ''; }
  }

  static String _formatSessionTime(dynamic d) {
    if (d == null) return '';
    try {
      final dt = DateTime.parse(d.toString());
      return '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) { return ''; }
  }

  static bool _isRecent(dynamic dateStr) {
    if (dateStr == null) return false;
    try {
      final d = DateTime.parse(dateStr.toString());
      return DateTime.now().difference(d).inHours < 24;
    } catch (_) { return false; }
  }

  static String _timeAgo(dynamic dateStr) {
    if (dateStr == null) return '';
    try {
      final d = DateTime.parse(dateStr.toString());
      final diff = DateTime.now().difference(d);
      if (diff.inMinutes < 1) return '방금 전';
      if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
      if (diff.inHours < 24) return '${diff.inHours}시간 전';
      if (diff.inDays < 7) return '${diff.inDays}일 전';
      return '${d.month}/${d.day}';
    } catch (_) { return ''; }
  }

  Widget _buildUpcomingEventsCard(List<Map<String, dynamic>> events, int attendanceCount, DateTime now) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
        child: Text('다음 일정', style: AppText.body(10, weight: FontWeight.w700, color: Colors.white70)),
      ),
      const SizedBox(height: 14),
      for (int i = 0; i < events.length; i++) ...[
        if (i > 0) ...[
          const SizedBox(height: 12),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.1)),
          const SizedBox(height: 12),
        ],
        _eventRow(events[i], now, primary: i == 0),
      ],
      const SizedBox(height: 16),
      Text('총 $attendanceCount회 출석', style: AppText.body(13, weight: FontWeight.w600, color: AppColors.secondaryContainer)),
    ]);
  }

  Widget _eventRow(Map<String, dynamic> ev, DateTime now, {required bool primary}) {
    const typeLabels = {
      'event': '일반',
      'rehearsal': '연습',
      'dressrehearsal': '리허설',
      'concert': '공연',
      'milestone': '기념',
    };
    const typeBadgeColors = {
      'rehearsal': Color(0xFF4ADE80),
      'dressrehearsal': Color(0xFF2DD4BF),
      'concert': Color(0xFFFBBF24),
      'event': Color(0xFF60A5FA),
      'milestone': Color(0xFFA78BFA),
    };
    const wd = ['일', '월', '화', '수', '목', '금', '토'];
    final type = (ev['type'] as String?) ?? 'event';
    final label = typeLabels[type] ?? '일정';
    final badgeColor = typeBadgeColors[type] ?? const Color(0xFF60A5FA);
    final date = DateTime.tryParse((ev['date'] as String?) ?? '');
    final dateText = date == null
        ? ''
        : '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')} (${wd[date.weekday % 7]}) ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    String dday = '';
    if (date != null) {
      final t1 = DateTime(date.year, date.month, date.day);
      final t0 = DateTime(now.year, now.month, now.day);
      final diff = t1.difference(t0).inDays;
      dday = diff == 0 ? 'D-DAY' : (diff > 0 ? 'D-$diff' : 'D+${-diff}');
    }
    final loc = (ev['location'] as String?) ?? '';

    final titleSize = primary ? 20.0 : 15.0;
    final titleWeight = primary ? FontWeight.w700 : FontWeight.w600;
    final metaSize = primary ? 13.0 : 11.0;

    final metaParts = <String>[
      if (dateText.isNotEmpty) dateText,
      if (loc.isNotEmpty) loc,
    ];
    final metaText = metaParts.join('  ·  ');

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: badgeColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(5)),
          child: Text(label, style: AppText.body(10, weight: FontWeight.w700, color: badgeColor)),
        ),
        if (dday.isNotEmpty) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(5)),
            child: Text(dday, style: AppText.body(10, weight: FontWeight.w700, color: Colors.white)),
          ),
        ],
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            (ev['title'] as String?) ?? '',
            style: AppText.body(titleSize, weight: titleWeight, color: Colors.white),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
      if (metaText.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(
          metaText,
          style: AppText.body(metaSize, color: Colors.white70),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    ]);
  }
}

// ── Small info row for session card
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 16, color: Colors.white54),
      const SizedBox(width: 8),
      Text(text, style: AppText.body(13, color: Colors.white70)),
    ]);
  }
}

// ── Quick Action Card
class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title, desc;
  final bool isDark;
  final VoidCallback onTap;
  const _ActionCard({required this.icon, required this.title, required this.desc, this.isDark = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tappable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? AppColors.primaryContainer : AppColors.surfaceLow,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 28, color: isDark ? AppColors.secondaryContainer : AppColors.secondary),
          const SizedBox(height: 12),
          Text(title, style: AppText.body(16, weight: FontWeight.w700, color: isDark ? Colors.white : AppColors.ink)),
          const SizedBox(height: 4),
          Text(desc, style: AppText.body(12, color: isDark ? Colors.white54 : AppColors.muted)),
        ]),
      ),
    );
  }
}

// ── Upload Chip for horizontal scroll
class _UploadChip extends StatelessWidget {
  final IconData icon;
  final String title, sub;
  final Color color;
  const _UploadChip({required this.icon, required this.title, required this.sub, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: color),
        const Spacer(),
        Text(title, style: AppText.body(13, weight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(sub, style: AppText.body(11, color: AppColors.muted)),
      ]),
    );
  }
}
