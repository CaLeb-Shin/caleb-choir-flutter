import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../../models/user.dart' show User;
import '../../widgets/interactive.dart';
import '../../services/firebase_service.dart';
import '../attendance/attendance_screen.dart';
import '../community/community_screen.dart';
import '../polls/polls_screen.dart';
import '../seating/seating_screen.dart';
import '../events/events_screen.dart';
import '../sheet_music/sheet_music_screen.dart';
import '../videos/videos_screen.dart';
import '../admin/members_screen.dart';
import '../admin/approvals_screen.dart';
import '../../widgets/app_bottom_nav_bar.dart';
import '../../widgets/app_logo_title.dart';
import '../../widgets/mini_action_tile.dart';

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
    final seatingCharts = ref.watch(seatingChartsProvider).valueOrNull ?? [];
    final currentSeatingChart = _currentSeatingChart(seatingCharts);
    final currentSeatAssignments = currentSeatingChart == null
        ? const <Map<String, dynamic>>[]
        : ref
                  .watch(seatAssignmentsProvider(currentSeatingChart['id']))
                  .valueOrNull ??
              const <Map<String, dynamic>>[];

    return profileAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) =>
          const Center(child: Text('프로필을 불러올 수 없습니다')),
      data: (profile) {
        if (profile == null) return const SizedBox.shrink();
        final announcements = announcementsAsync.valueOrNull ?? [];
        final attendanceCount = historyAsync.valueOrNull?.length ?? 0;
        final session = sessionAsync.valueOrNull;
        final mySeat = _mySeat(currentSeatAssignments, profile.id);
        final now = DateTime.now();
        final weekday = ['월', '화', '수', '목', '금', '토', '일'][now.weekday - 1];
        final totalUploads = recentSheets.length + recentVids.length;

        // Pick upcoming events from Firestore (date >= today), up to 3
        final allEvents = eventsAsync.valueOrNull ?? [];
        final upcomingEvents =
            allEvents.where((e) {
              final d = e['date'];
              if (d == null || d is! String || d.isEmpty) return false;
              final parsed = DateTime.tryParse(d);
              if (parsed == null) return false;
              return !parsed.isBefore(DateTime(now.year, now.month, now.day));
            }).toList()..sort(
              (a, b) => (a['date'] as String).compareTo(b['date'] as String),
            );
        final weeklySchedules = _weeklyScheduleItems(
          session: session,
          upcomingEvents: upcomingEvents,
          now: now,
        );

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(profileProvider);
            ref.invalidate(announcementsProvider);
            ref.invalidate(myHistoryProvider);
            ref.invalidate(activeSessionProvider);
            ref.invalidate(eventsProvider);
            ref.invalidate(recentSheetMusicProvider);
            ref.invalidate(recentVideosProvider);
            ref.invalidate(seatingChartsProvider);
            if (currentSeatingChart != null) {
              ref.invalidate(
                seatAssignmentsProvider(currentSeatingChart['id']),
              );
            }
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset(
                        'assets/images/icon.png',
                        width: 32,
                        height: 32,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('C.C Note', style: AppText.headline(18)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.secondarySoft,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '${now.month}월 ${now.day}일 ($weekday)',
                        style: AppText.body(
                          11,
                          weight: FontWeight.w600,
                          color: AppColors.secondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // ── Welcome
                Text('환영합니다', style: AppText.label()),
                const SizedBox(height: 6),
                Text(
                  '${profile.name ?? "멤버"}님, 오늘도 함께 찬양해요',
                  style: AppText.headline(20, weight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                if (mySeat != null && currentSeatingChart != null) ...[
                  _MySeatHomeCard(
                    chart: currentSeatingChart,
                    seat: mySeat,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SeatingScreen(
                          initialChartId: currentSeatingChart['id']?.toString(),
                          initialChart: currentSeatingChart,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                // ── Upcoming Rehearsal / Active Session
                Tappable(
                  onTap: () {},
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF000E24), Color(0xFF00234B)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: weeklySchedules.isNotEmpty
                        ? _WeeklyScheduleCard(
                            schedules: weeklySchedules,
                            attendanceCount: attendanceCount,
                            onCheckIn: session == null
                                ? null
                                : () async {
                                    await FirebaseService.checkIn(
                                      session['id'],
                                    );
                                    ref.invalidate(myHistoryProvider);
                                  },
                            onDetails: session == null
                                ? () => _openSection(
                                    context,
                                    '일정',
                                    const EventsScreen(),
                                  )
                                : () =>
                                      ref
                                              .read(tabIndexProvider.notifier)
                                              .state =
                                          3,
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '다음 일정',
                                  style: AppText.body(
                                    10,
                                    weight: FontWeight.w700,
                                    color: Colors.white70,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                '예정된 연습이 없습니다',
                                style: AppText.headline(
                                  20,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '관리자가 일정을 등록하면 여기에 표시됩니다',
                                style: AppText.body(13, color: Colors.white54),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '총 $attendanceCount회 출석',
                                style: AppText.body(
                                  13,
                                  weight: FontWeight.w600,
                                  color: AppColors.secondaryContainer,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Quick Actions (3x3 grid, 키즈노트 스타일)
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 6,
                    horizontal: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.border.withValues(alpha: 0.3),
                    ),
                  ),
                  child: _buildActionGrid(context, ref, profile.isAdmin),
                ),
                const SizedBox(height: 10),

                // ── This Week's Uploads
                if (totalUploads > 0) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text('이번 주 업로드', style: AppText.headline(18)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.secondarySoft,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$totalUploads개',
                          style: AppText.body(
                            11,
                            weight: FontWeight.w700,
                            color: AppColors.secondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 90,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      children: [
                        ...recentSheets.map(
                          (s) => _UploadChip(
                            icon: Icons.description_rounded,
                            title: s['title'] ?? '',
                            sub: s['composer'] ?? '악보',
                            color: AppColors.primary,
                          ),
                        ),
                        ...recentVids.map(
                          (v) => _UploadChip(
                            icon: Icons.play_circle_rounded,
                            title: v['title'] ?? '',
                            sub: '영상',
                            color: AppColors.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                ],

                // ── Announcements Feed (Timeline)
                Row(
                  children: [
                    Expanded(child: Text('최근 소식', style: AppText.headline(18))),
                    Icon(
                      Icons.notifications_rounded,
                      size: 20,
                      color: AppColors.secondary,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLow,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: announcements.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Text(
                              '새로운 소식이 없습니다',
                              style: AppText.body(14, color: AppColors.muted),
                            ),
                          ),
                        )
                      : Column(
                          children: [
                            ...announcements.take(5).map((ann) {
                              final isRecent = _isRecent(ann['createdAt']);
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Column(
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: isRecent
                                                ? AppColors.secondaryContainer
                                                : AppColors.subtle,
                                          ),
                                        ),
                                        Container(
                                          width: 1,
                                          height: 40,
                                          color: AppColors.border.withValues(
                                            alpha: 0.3,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _timeAgo(ann['createdAt']),
                                            style: AppText.body(
                                              10,
                                              weight: FontWeight.w700,
                                              color: AppColors.muted,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            ann['title'] ?? '',
                                            style: AppText.body(
                                              14,
                                              weight: FontWeight.w700,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (ann['content'] != null) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              ann['content'] ?? '',
                                              style: AppText.body(
                                                12,
                                                color:
                                                    AppColors.onSurfaceVariant,
                                                height: 1.4,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            Tappable(
                              onTap: () =>
                                  ref.read(tabIndexProvider.notifier).state = 4,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Center(
                                  child: Text('전체 보기', style: AppText.label()),
                                ),
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

  static Map<String, dynamic>? _currentSeatingChart(
    List<Map<String, dynamic>> charts,
  ) {
    if (charts.isEmpty) return null;
    final published = charts.where((chart) => chart['isPublished'] == true);
    return published.isNotEmpty ? published.first : charts.first;
  }

  static Map<String, dynamic>? _mySeat(
    List<Map<String, dynamic>> assignments,
    String? userId,
  ) {
    if (userId == null) return null;
    for (final seat in assignments) {
      if (seat['userId'] == userId) return seat;
    }
    return null;
  }

  static String _formatSessionDate(dynamic d) {
    if (d == null) return '';
    try {
      final dt = DateTime.parse(d.toString());
      final wd = ['월', '화', '수', '목', '금', '토', '일'][dt.weekday - 1];
      return '${dt.year}년 ${dt.month}월 ${dt.day}일 ($wd)';
    } catch (_) {
      return '';
    }
  }

  static String _formatSessionTime(dynamic d) {
    if (d == null) return '';
    try {
      final dt = DateTime.parse(d.toString());
      return '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  static String _formatSessionLocation(Map<String, dynamic> session) {
    for (final key in ['location', 'place', 'venue', 'address']) {
      final value = session[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return '장소 미정';
  }

  static bool _isRecent(dynamic dateStr) {
    if (dateStr == null) return false;
    try {
      final d = DateTime.parse(dateStr.toString());
      return DateTime.now().difference(d).inHours < 24;
    } catch (_) {
      return false;
    }
  }

  void _openSection(
    BuildContext context,
    String title,
    Widget child, {
    int? navIndex,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _BackableSectionScreen(
          title: title,
          navIndex: navIndex,
          child: child,
        ),
      ),
    );
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
    } catch (_) {
      return '';
    }
  }

  Widget _buildActionGrid(BuildContext context, WidgetRef ref, bool isAdmin) {
    // 관리자 pending 개수 (가입 승인 대기)
    final pendingCount = isAdmin
        ? (ref.watch(pendingUsersProvider).valueOrNull?.length ?? 0)
        : 0;

    // 새 콘텐츠 여부 (최근 7일 이내 등록/미확인)
    final announcements = ref.watch(announcementsProvider).valueOrNull ?? [];
    final hasNewAnnouncement = announcements.any((a) => a['isRead'] == false);
    final hasNewSheetMusic =
        (ref.watch(recentSheetMusicProvider).valueOrNull ?? []).isNotEmpty;
    final hasNewVideos =
        (ref.watch(recentVideosProvider).valueOrNull ?? []).isNotEmpty;
    final posts = ref.watch(postsProvider).valueOrNull ?? [];
    final hasNewPosts = posts.any((p) => _isRecent(p['createdAt']));
    final events = ref.watch(eventsProvider).valueOrNull ?? [];
    final now = DateTime.now();
    final hasNewEvents = events.any((e) {
      final d = e['date'];
      if (d == null || d is! String || d.isEmpty) return false;
      final parsed = DateTime.tryParse(d);
      if (parsed == null) return false;
      // 앞으로 7일 이내의 일정이면 N 표시
      return !parsed.isBefore(DateTime(now.year, now.month, now.day)) &&
          parsed.difference(now).inDays <= 7;
    });
    final polls = ref.watch(pollsProvider).valueOrNull ?? [];
    final hasNewPolls = polls.any((p) => p['isOpen'] == true);

    final items = <Widget>[
      MiniActionTile(
        icon: Icons.qr_code_rounded,
        label: 'QR 출석',
        onTap: () => _openSection(
          context,
          'QR 출석',
          const AttendanceScreen(),
          navIndex: 3,
        ),
      ),
      MiniActionTile(
        icon: Icons.how_to_vote_rounded,
        label: '참석 투표',
        tone: 'secondary',
        hasNew: hasNewPolls,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PollsScreen()),
        ),
      ),
      MiniActionTile(
        icon: Icons.grid_view_rounded,
        label: '자리 배치판',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SeatingScreen()),
        ),
      ),
      MiniActionTile(
        icon: Icons.music_note_rounded,
        label: '악보&음원',
        tone: 'secondary',
        hasNew: hasNewSheetMusic,
        onTap: () => _openSection(
          context,
          '악보&음원',
          const SheetMusicScreen(),
          navIndex: 1,
        ),
      ),
      MiniActionTile(
        icon: Icons.play_circle_rounded,
        label: '영상',
        hasNew: hasNewVideos,
        onTap: () =>
            _openSection(context, '영상', const VideosScreen(), navIndex: 2),
      ),
      MiniActionTile(
        icon: Icons.campaign_rounded,
        label: '공지',
        tone: 'secondary',
        hasNew: hasNewAnnouncement,
        onTap: () =>
            _openSection(context, '공지', const CommunityScreen(), navIndex: 4),
      ),
      MiniActionTile(
        icon: Icons.chat_bubble_rounded,
        label: '커뮤니티',
        hasNew: hasNewPosts,
        onTap: () =>
            _openSection(context, '커뮤니티', const CommunityScreen(), navIndex: 4),
      ),
      MiniActionTile(
        icon: Icons.calendar_today_rounded,
        label: '일정',
        tone: 'secondary',
        hasNew: hasNewEvents,
        onTap: () => _openSection(context, '일정', const EventsScreen()),
      ),
      MiniActionTile(
        icon: Icons.people_rounded,
        label: '단원 명부',
        badgeCount: pendingCount > 0 ? pendingCount : null,
        onTap: () {
          if (isAdmin && pendingCount > 0) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ApprovalsScreen()),
            );
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MembersScreen()),
            );
          }
        },
      ),
    ];

    return Column(
      children: [
        for (int row = 0; row < 3; row++) ...[
          if (row > 0) const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (int col = 0; col < 3; col++)
                Expanded(child: Center(child: items[row * 3 + col])),
            ],
          ),
        ],
      ],
    );
  }

  static List<_WeeklyScheduleItem> _weeklyScheduleItems({
    required Map<String, dynamic>? session,
    required List<Map<String, dynamic>> upcomingEvents,
    required DateTime now,
  }) {
    final items = <_WeeklyScheduleItem>[];
    if (session != null) {
      items.add(
        _WeeklyScheduleItem(
          title: session['title']?.toString().trim().isNotEmpty == true
              ? session['title'].toString().trim()
              : '주일 찬양 연습',
          badge: '출석 진행 중',
          accent: AppColors.secondaryContainer,
          dateText: _formatSessionDate(session['openedAt']),
          timeText: _formatSessionTime(session['openedAt']),
          locationText: _formatSessionLocation(session),
          isActive: true,
        ),
      );
    }

    for (final event in upcomingEvents) {
      if (items.length >= 3) break;
      final date = DateTime.tryParse(
        event['eventDate']?.toString() ?? event['date']?.toString() ?? '',
      );
      if (date != null) {
        final today = DateTime(now.year, now.month, now.day);
        final eventDay = DateTime(date.year, date.month, date.day);
        if (eventDay.difference(today).inDays > 7) continue;
      }
      items.add(_WeeklyScheduleItem.fromEvent(event));
    }
    return items;
  }
}

class _BackableSectionScreen extends StatelessWidget {
  final String title;
  final int? navIndex;
  final Widget child;

  const _BackableSectionScreen({
    required this.title,
    required this.child,
    this.navIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          tooltip: '뒤로가기',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: AppLogoTitle(title: title),
      ),
      body: SafeArea(child: child),
      bottomNavigationBar: AppBottomNavBar(currentIndex: navIndex),
    );
  }
}

class _WeeklyScheduleItem {
  final String title;
  final String badge;
  final Color accent;
  final String dateText;
  final String timeText;
  final String locationText;
  final bool isActive;

  const _WeeklyScheduleItem({
    required this.title,
    required this.badge,
    required this.accent,
    required this.dateText,
    required this.timeText,
    required this.locationText,
    this.isActive = false,
  });

  factory _WeeklyScheduleItem.fromEvent(Map<String, dynamic> event) {
    const typeLabels = {
      'event': '일정',
      'rehearsal': '찬양',
      'dressrehearsal': '리허설',
      'concert': '공연',
      'milestone': '기념',
    };
    const typeColors = {
      'event': Color(0xFF9BB8E6),
      'rehearsal': Color(0xFFFED488),
      'dressrehearsal': Color(0xFF8DD7C4),
      'concert': Color(0xFFFFB4A2),
      'milestone': Color(0xFFD1B3FF),
    };
    final type = event['type']?.toString() ?? 'event';
    final date = DateTime.tryParse(
      event['eventDate']?.toString() ?? event['date']?.toString() ?? '',
    );
    final title = event['title']?.toString().trim();
    return _WeeklyScheduleItem(
      title: title?.isNotEmpty == true ? title! : '일정',
      badge: typeLabels[type] ?? '일정',
      accent: typeColors[type] ?? const Color(0xFF9BB8E6),
      dateText: date == null ? '' : _formatShortDate(date),
      timeText: event['time']?.toString().trim().isNotEmpty == true
          ? event['time'].toString().trim()
          : _formatShortTime(date),
      locationText: _eventLocation(event),
    );
  }

  static String _formatShortDate(DateTime date) {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    return '${date.month}/${date.day} (${weekdays[date.weekday - 1]})';
  }

  static String _formatShortTime(DateTime? date) {
    if (date == null || (date.hour == 0 && date.minute == 0)) return '';
    return '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  static String _eventLocation(Map<String, dynamic> event) {
    for (final key in ['location', 'place', 'venue', 'address']) {
      final value = event[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return '장소 미정';
  }
}

class _WeeklyScheduleCard extends StatelessWidget {
  final List<_WeeklyScheduleItem> schedules;
  final int attendanceCount;
  final Future<void> Function()? onCheckIn;
  final VoidCallback onDetails;

  const _WeeklyScheduleCard({
    required this.schedules,
    required this.attendanceCount,
    required this.onCheckIn,
    required this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    final activeSchedule = schedules.where((item) => item.isActive).isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '이번 주 스케줄',
                style: AppText.headline(20, color: Colors.white),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${schedules.length}개',
                style: AppText.body(
                  11,
                  weight: FontWeight.w900,
                  color: AppColors.secondaryContainer,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < schedules.length; i++) ...[
          _WeeklyScheduleRow(
            item: schedules[i],
            onCheckIn: schedules[i].isActive ? onCheckIn : null,
          ),
          if (i < schedules.length - 1) const SizedBox(height: 6),
        ],
        const SizedBox(height: 9),
        GestureDetector(
          onTap: onDetails,
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '총 $attendanceCount회 출석',
                  style: AppText.body(
                    12,
                    weight: FontWeight.w700,
                    color: AppColors.secondaryContainer,
                  ),
                ),
              ),
              Text(
                activeSchedule ? '출석 상세' : '일정 보기',
                style: AppText.body(
                  12,
                  weight: FontWeight.w900,
                  color: Colors.white.withValues(alpha: 0.76),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: Colors.white.withValues(alpha: 0.76),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WeeklyScheduleRow extends StatelessWidget {
  final _WeeklyScheduleItem item;
  final Future<void> Function()? onCheckIn;

  const _WeeklyScheduleRow({required this.item, this.onCheckIn});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: item.accent.withValues(alpha: item.isActive ? 1 : 0.22),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(
              item.isActive
                  ? Icons.qr_code_scanner_rounded
                  : Icons.event_note_rounded,
              size: 19,
              color: item.isActive ? AppColors.secondary : item.accent,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: item.accent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        item.badge,
                        style: AppText.body(
                          10,
                          weight: FontWeight.w900,
                          color: item.isActive
                              ? AppColors.secondaryContainer
                              : item.accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item.title,
                        style: AppText.body(
                          13,
                          weight: FontWeight.w900,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  [
                    item.dateText,
                    item.timeText,
                    item.locationText,
                  ].where((part) => part.trim().isNotEmpty).join(' · '),
                  style: AppText.body(
                    11,
                    weight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (item.isActive && onCheckIn != null) ...[
            const SizedBox(width: 8),
            SizedBox(
              height: 30,
              child: ElevatedButton(
                onPressed: onCheckIn,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondaryContainer,
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                  textStyle: AppText.body(11, weight: FontWeight.w900),
                ),
                child: const Text('출석'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MySeatHomeCard extends StatelessWidget {
  final Map<String, dynamic> chart;
  final Map<String, dynamic> seat;
  final VoidCallback onTap;

  const _MySeatHomeCard({
    required this.chart,
    required this.seat,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final part = seat['part']?.toString() ?? '';
    final row = ((seat['row'] as int?) ?? 0) + 1;
    final col = ((seat['col'] as int?) ?? 0) + 1;
    final label = chart['label']?.toString().trim() ?? '자리 배치판';
    final eventTitle =
        chart['sourcePollTitle']?.toString().trim().isNotEmpty == true
        ? chart['sourcePollTitle'].toString().trim()
        : label;
    final date = _formatSeatDate(chart['eventDate']);
    final coordinate = '${User.partLabels[part] ?? part} $row열 $col번';

    return Tappable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: AppColors.secondarySoft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.secondaryContainer.withValues(alpha: 0.82),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.secondaryContainer,
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(
                Icons.event_seat_rounded,
                size: 20,
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '내 자리',
                        style: AppText.body(
                          12,
                          weight: FontWeight.w900,
                          color: AppColors.secondary,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          '클릭하면 자리배치로 이동',
                          style: AppText.body(
                            11,
                            weight: FontWeight.w700,
                            color: AppColors.muted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  _SeatMetaRow(
                    label: '일정',
                    value: date.isEmpty ? eventTitle : '$date · $eventTitle',
                  ),
                  const SizedBox(height: 3),
                  _SeatMetaRow(label: '좌표', value: coordinate),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.chevron_right_rounded,
                size: 21,
                color: AppColors.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatSeatDate(dynamic rawDate) {
    final raw = rawDate?.toString().trim() ?? '';
    if (raw.isEmpty) return '';
    final date = DateTime.tryParse(raw);
    if (date == null) return raw;
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    return '${date.month}월 ${date.day}일 (${weekdays[date.weekday - 1]})';
  }
}

class _SeatMetaRow extends StatelessWidget {
  final String label;
  final String value;

  const _SeatMetaRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 40,
          child: Text(
            label,
            style: AppText.body(
              11,
              weight: FontWeight.w900,
              color: AppColors.secondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: AppText.body(
              13,
              weight: FontWeight.w800,
              color: AppColors.primary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ── Upload Chip for horizontal scroll
class _UploadChip extends StatelessWidget {
  final IconData icon;
  final String title, sub;
  final Color color;
  const _UploadChip({
    required this.icon,
    required this.title,
    required this.sub,
    required this.color,
  });

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const Spacer(),
          Text(
            title,
            style: AppText.body(13, weight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(sub, style: AppText.body(11, color: AppColors.muted)),
        ],
      ),
    );
  }
}
