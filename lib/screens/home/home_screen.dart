import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../../models/user.dart' show User;
import '../../config/feature_flags.dart';
import '../../widgets/interactive.dart';
import '../attendance/attendance_screen.dart';
import '../community/community_screen.dart';
import '../seating/seating_screen.dart';
import '../events/events_screen.dart';
import '../harmony_chat/harmony_chat_development_screen.dart';
import '../harmony_chat/harmony_chat_screen.dart';
import '../sheet_music/sheet_music_screen.dart';
import '../videos/videos_screen.dart';
import '../polls/polls_screen.dart';
import '../admin/members_screen.dart';
import '../admin/approvals_screen.dart';
import '../admin/subscription_screen.dart';
import '../../widgets/app_bottom_nav_bar.dart';
import '../../widgets/app_logo_title.dart';
import '../../widgets/mini_action_tile.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only the profile gate is watched at the top level. Every data-driven
    // section below is its own Consumer, so a tick from any live Firestore
    // stream (events, polls, …) rebuilds just that section instead of this
    // whole tree mid-scroll.
    final profileAsync = ref.watch(profileProvider);

    return profileAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) =>
          const Center(child: Text('프로필을 불러올 수 없습니다')),
      data: (profile) {
        if (profile == null) return const SizedBox.shrink();
        final now = DateTime.now();
        final weekday = ['월', '화', '수', '목', '금', '토', '일'][now.weekday - 1];

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(profileProvider);
            ref.invalidate(announcementsProvider);
            ref.invalidate(myHistoryProvider);
            ref.invalidate(activeSessionProvider);
            ref.invalidate(eventsProvider);
            ref.invalidate(currentChurchProvider);
            ref.invalidate(recentSheetMusicProvider);
            ref.invalidate(recentVideosProvider);
            ref.invalidate(pollsProvider);
            if (FeatureFlags.harmonyChatEnabled) {
              ref.invalidate(harmonyNotesProvider);
              ref.invalidate(harmonyRelaysProvider);
            }
            final charts =
                ref.read(seatingChartsProvider).valueOrNull ??
                const <Map<String, dynamic>>[];
            final currentChart = _currentSeatingChart(charts);
            ref.invalidate(seatingChartsProvider);
            if (currentChart != null) {
              ref.invalidate(seatAssignmentsProvider(currentChart['id']));
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

                // ── Welcome (watches currentChurch only)
                Consumer(
                  builder: (context, ref, _) => _welcome(context, ref, profile),
                ),
                const SizedBox(height: 16),

                // ── My seat (watches seating charts + my assignment)
                Consumer(
                  builder: (context, ref, _) =>
                      _mySeatSection(context, ref, profile),
                ),

                // ── Upcoming schedule (watches events + polls streams)
                Consumer(
                  builder: (context, ref, _) => _scheduleSection(context, ref),
                ),
                const SizedBox(height: 16),

                // ── Quick actions (grid isolates its own watches)
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
                  child: Consumer(
                    builder: (context, actionRef, _) => _buildActionGrid(
                      context,
                      actionRef,
                      isAdmin: profile.isAdmin,
                      canViewMembers: profile.hasManagePermission,
                      canViewBilling: profile.isAdmin || profile.isOfficer,
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // ── This week's uploads (watches recent sheets + videos)
                Consumer(
                  builder: (context, ref, _) => _uploadsSection(context, ref),
                ),

                // ── Announcements feed (watches announcements)
                Consumer(
                  builder: (context, ref, _) => _announcements(context, ref),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _welcome(BuildContext context, WidgetRef ref, User profile) {
    final currentChurch = ref.watch(currentChurchProvider).valueOrNull;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('환영합니다', style: AppText.label()),
            if (currentChurch != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    currentChurch.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(
                      11,
                      weight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '${profile.name ?? "멤버"}님, 오늘도 함께 찬양해요',
          style: AppText.headline(20, weight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _mySeatSection(BuildContext context, WidgetRef ref, User profile) {
    final seatingCharts =
        ref.watch(seatingChartsProvider).valueOrNull ??
        const <Map<String, dynamic>>[];
    final currentSeatingChart = _currentSeatingChart(seatingCharts);
    if (currentSeatingChart == null) return const SizedBox.shrink();
    final assignments =
        ref
            .watch(seatAssignmentsProvider(currentSeatingChart['id']))
            .valueOrNull ??
        const <Map<String, dynamic>>[];
    final mySeat = _mySeat(assignments, profile.id);
    if (mySeat == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _MySeatHomeCard(
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
    );
  }

  Widget _scheduleSection(BuildContext context, WidgetRef ref) {
    final allEvents =
        ref.watch(eventsProvider).valueOrNull ?? const <Map<String, dynamic>>[];
    final polls =
        ref.watch(pollsProvider).valueOrNull ?? const <Map<String, dynamic>>[];
    final seatingCharts =
        ref.watch(seatingChartsProvider).valueOrNull ??
        const <Map<String, dynamic>>[];
    final currentSeatingChart = _currentSeatingChart(seatingCharts);

    // Pick upcoming schedule entries from Firestore. Admin writes these to the
    // events collection with date/location/option flags.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final upcomingEvents =
        allEvents.where((e) {
            final parsed = _eventDateTime(e);
            if (parsed == null) return false;
            final eventDay = DateTime(parsed.year, parsed.month, parsed.day);
            return !eventDay.isBefore(today);
          }).toList()
          ..sort((a, b) => _eventDateTime(a)!.compareTo(_eventDateTime(b)!));
    final weeklySchedules = _weeklyScheduleItems(
      upcomingEvents: upcomingEvents,
      polls: polls,
    );

    return Tappable(
      onTap: () {},
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF00234B).withValues(alpha: 0.9),
              const Color(0xFF064F7A).withValues(alpha: 0.72),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00234B).withValues(alpha: 0.16),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: weeklySchedules.isNotEmpty
            ? _WeeklyScheduleCard(
                schedules: weeklySchedules,
                onVote: (item) => _openPollForSchedule(context, item),
                onAttendance: (item) =>
                    _openAttendanceForSchedule(context, item),
                onSeat: (item) => _openSeatForSchedule(
                  context,
                  _seatingChartForSchedule(seatingCharts, item) ??
                      currentSeatingChart,
                ),
                onDetails: () =>
                    _openSection(context, '일정', const EventsScreen()),
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
                    style: AppText.headline(20, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '관리자가 일정을 등록하면 여기에 표시됩니다',
                    style: AppText.body(13, color: Colors.white54),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _uploadsSection(BuildContext context, WidgetRef ref) {
    final recentSheets =
        ref.watch(recentSheetMusicProvider).valueOrNull ??
        const <Map<String, dynamic>>[];
    final recentVids =
        ref.watch(recentVideosProvider).valueOrNull ??
        const <Map<String, dynamic>>[];
    final totalUploads = recentSheets.length + recentVids.length;
    if (totalUploads == 0) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('이번 주 업로드', style: AppText.headline(18))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                  title: s['songTitle'] ?? s['title'] ?? '',
                  sub: '악보&음원',
                  color: AppColors.primary,
                  onTap: () => _openSection(
                    context,
                    '악보&음원',
                    const SheetMusicScreen(),
                    navIndex: 1,
                  ),
                ),
              ),
              ...recentVids.map(
                (v) => _UploadChip(
                  icon: Icons.play_circle_rounded,
                  title: v['title'] ?? '',
                  sub: '영상',
                  color: AppColors.secondary,
                  onTap: () =>
                      _openSection(context, '영상', const VideosScreen()),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
      ],
    );
  }

  Widget _announcements(BuildContext context, WidgetRef ref) {
    final announcements =
        ref.watch(announcementsProvider).valueOrNull ??
        const <Map<String, dynamic>>[];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                                        color: AppColors.onSurfaceVariant,
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
    );
  }

  static Map<String, dynamic>? _currentSeatingChart(
    List<Map<String, dynamic>> charts,
  ) {
    if (charts.isEmpty) return null;
    final published = charts.where((chart) => chart['isPublished'] == true);
    return published.isNotEmpty ? published.first : charts.first;
  }

  static Map<String, dynamic>? _seatingChartForSchedule(
    List<Map<String, dynamic>> charts,
    _WeeklyScheduleItem item,
  ) {
    final chartId = item.seatingChartId;
    if (chartId != null && chartId.isNotEmpty) {
      for (final chart in charts) {
        if (chart['id']?.toString() == chartId) return chart;
      }
    }
    final targetDate = item.targetDate;
    if (targetDate != null && targetDate.isNotEmpty) {
      for (final chart in charts) {
        if (_dateKeyFrom(chart['eventDate']) == targetDate ||
            _dateKeyFrom(chart['targetDate']) == targetDate) {
          return chart;
        }
      }
    }
    return null;
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

  void _openPollForSchedule(BuildContext context, _WeeklyScheduleItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _BackableSectionScreen(
          title: '투표',
          navIndex: 3,
          child: PollsScreen(
            initialPollId: item.pollId,
            initialTargetDate: item.targetDate,
            initialTitle: item.title,
          ),
        ),
      ),
    );
  }

  void _openAttendanceForSchedule(
    BuildContext context,
    _WeeklyScheduleItem item,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const _BackableSectionScreen(
          title: '출석',
          navIndex: 2,
          child: AttendanceScreen(),
        ),
      ),
    );
  }

  void _openSeatForSchedule(
    BuildContext context,
    Map<String, dynamic>? currentSeatingChart,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SeatingScreen(
          initialChartId: currentSeatingChart?['id']?.toString(),
          initialChart: currentSeatingChart,
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

  Widget _buildActionGrid(
    BuildContext context,
    WidgetRef ref, {
    required bool isAdmin,
    required bool canViewMembers,
    required bool canViewBilling,
  }) {
    // 관리자 pending 개수 (가입 승인 대기)
    final pendingCount = isAdmin
        ? (ref.watch(pendingUsersProvider).valueOrNull?.length ?? 0)
        : 0;

    // 새 콘텐츠 여부 (최근 7일 이내 등록/미확인)
    final hasNewSheetMusic =
        (ref.watch(recentSheetMusicProvider).valueOrNull ?? []).isNotEmpty;
    final hasNewVideos =
        (ref.watch(recentVideosProvider).valueOrNull ?? []).isNotEmpty;
    final posts = ref.watch(postsProvider).valueOrNull ?? [];
    final hasNewPosts = posts.any((p) => _isRecent(p['createdAt']));
    final harmonyChatEnabled = FeatureFlags.harmonyChatEnabled;
    final harmonyNotes = harmonyChatEnabled
        ? ref.watch(harmonyNotesProvider).valueOrNull ??
              const <Map<String, dynamic>>[]
        : const <Map<String, dynamic>>[];
    final harmonyRelays = harmonyChatEnabled
        ? ref.watch(harmonyRelaysProvider).valueOrNull ??
              const <Map<String, dynamic>>[]
        : const <Map<String, dynamic>>[];
    final hasNewHarmonyNotes =
        harmonyChatEnabled &&
        (harmonyNotes.any((n) => _isRecent(n['createdAt'])) ||
            harmonyRelays.any(
              (r) => _isRecent(r['createdAt']) || _isRecent(r['lastClipAt']),
            ));
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
    final hasOpenAttendance =
        ref.watch(activeSessionProvider).valueOrNull != null;

    final items = <Widget>[
      MiniActionTile(
        icon: Icons.qr_code_rounded,
        label: '출석',
        hasNew: hasOpenAttendance,
        onTap: () =>
            _openSection(context, '출석', const AttendanceScreen(), navIndex: 2),
      ),
      MiniActionTile(
        icon: Icons.how_to_vote_rounded,
        label: '투표',
        hasNew: hasNewPolls,
        onTap: () =>
            _openSection(context, '투표', const PollsScreen(), navIndex: 3),
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
        icon: Icons.description_rounded,
        customIcon: const ScoreMenuGlyph(),
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
        onTap: () => _openSection(context, '영상', const VideosScreen()),
      ),
      MiniActionTile(
        icon: Icons.chat_bubble_rounded,
        label: '커뮤니티',
        hasNew: hasNewPosts,
        onTap: () =>
            _openSection(context, '커뮤니티', const CommunityScreen(), navIndex: 4),
      ),
      MiniActionTile(
        icon: Icons.graphic_eq_rounded,
        customIcon: const HarmonyChatMenuGlyph(),
        label: '하모니챗',
        tone: 'secondary',
        statusLabel: harmonyChatEnabled ? null : '개발중',
        hasNew: hasNewHarmonyNotes,
        onTap: () => _openSection(
          context,
          '하모니챗',
          harmonyChatEnabled
              ? const HarmonyChatScreen()
              : const HarmonyChatDevelopmentScreen(),
        ),
      ),
      MiniActionTile(
        icon: Icons.calendar_today_rounded,
        label: '일정',
        tone: 'secondary',
        hasNew: hasNewEvents,
        onTap: () => _openSection(context, '일정', const EventsScreen()),
      ),
      if (canViewMembers)
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
      if (canViewBilling)
        MiniActionTile(
          icon: Icons.workspace_premium_rounded,
          label: '구독',
          tone: 'secondary',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
          ),
        ),
      MiniActionTile(
        icon: Icons.storefront_rounded,
        customIcon: const StoreMenuGlyph(),
        label: '스토어',
        tone: 'secondary',
        onTap: () {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('스토어 준비중!')));
        },
      ),
    ];

    return Column(
      children: [
        for (int row = 0; row < items.length; row += 3) ...[
          if (row > 0) const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (int col = 0; col < 3; col++)
                Expanded(
                  child: row + col < items.length
                      ? Center(child: items[row + col])
                      : const SizedBox.shrink(),
                ),
            ],
          ),
        ],
      ],
    );
  }

  static List<_WeeklyScheduleItem> _weeklyScheduleItems({
    required List<Map<String, dynamic>> upcomingEvents,
    required List<Map<String, dynamic>> polls,
  }) {
    final items = <_WeeklyScheduleItem>[];
    for (final event in upcomingEvents) {
      if (items.length >= 3) break;
      final targetDate = _dateKeyFrom(
        event['eventDate'] ?? event['date'] ?? event['targetDate'],
      );
      final directPollId = event['pollId']?.toString();
      final poll = directPollId == null || directPollId.isEmpty
          ? _matchingPoll(
              polls,
              targetDate: targetDate,
              title: event['title']?.toString(),
            )
          : polls.cast<Map<String, dynamic>?>().firstWhere(
                  (poll) => poll?['id']?.toString() == directPollId,
                  orElse: () => null,
                ) ??
                _matchingPoll(
                  polls,
                  targetDate: targetDate,
                  title: event['title']?.toString(),
                );
      items.add(_WeeklyScheduleItem.fromEvent(event, poll: poll));
    }
    return items;
  }

  static DateTime? _eventDateTime(Map<String, dynamic> event) {
    final value = event['eventDate'] ?? event['date'] ?? event['targetDate'];
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  static String? _dateKeyFrom(dynamic value) {
    if (value == null) return null;
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw.length >= 10 ? raw.substring(0, 10) : raw;
    return parsed.toIso8601String().split('T').first;
  }

  static Map<String, dynamic>? _matchingPoll(
    List<Map<String, dynamic>> polls, {
    String? targetDate,
    String? title,
  }) {
    final openPolls = polls.where((poll) => poll['isOpen'] == true).toList();
    if (targetDate != null && targetDate.isNotEmpty) {
      for (final poll in openPolls) {
        if (_dateKeyFrom(poll['targetDate']) == targetDate) return poll;
      }
    }

    final scheduleTitle = title?.trim();
    if (scheduleTitle != null && scheduleTitle.isNotEmpty) {
      for (final poll in openPolls) {
        final pollTitle = poll['title']?.toString().trim() ?? '';
        if (pollTitle.isEmpty) continue;
        if (pollTitle.contains(scheduleTitle) ||
            scheduleTitle.contains(pollTitle)) {
          return poll;
        }
      }
    }
    return null;
  }

  static bool _scheduleNeedsSeating(Map<String, dynamic> source) {
    final explicit =
        source['needsSeating'] ??
        source['hasSeating'] ??
        source['seatingEnabled'] ??
        source['requiresSeating'];
    if (explicit is bool) return explicit;
    if (explicit is num) return explicit != 0;
    if (explicit is String) {
      final normalized = explicit.trim().toLowerCase();
      if (['true', '1', 'yes', 'y'].contains(normalized)) return true;
      if (['false', '0', 'no', 'n'].contains(normalized)) return false;
    }

    final type = source['type']?.toString().toLowerCase() ?? '';
    final title = source['title']?.toString() ?? '';
    if (type == 'rehearsal' ||
        type == 'dressrehearsal' ||
        title.contains('연습') ||
        title.contains('리허설')) {
      return false;
    }
    return type == 'concert' ||
        type == 'performance' ||
        type == 'worship' ||
        type == 'service' ||
        title.contains('찬양') ||
        title.contains('예배') ||
        title.contains('공연');
  }

  static bool _scheduleNeedsAttendance(Map<String, dynamic> source) {
    final explicit =
        source['needsAttendance'] ??
        source['hasAttendance'] ??
        source['attendanceEnabled'] ??
        source['requiresAttendance'];
    if (explicit is bool) return explicit;
    if (explicit is num) return explicit != 0;
    if (explicit is String) {
      final normalized = explicit.trim().toLowerCase();
      if (['true', '1', 'yes', 'y'].contains(normalized)) return true;
      if (['false', '0', 'no', 'n'].contains(normalized)) return false;
    }

    final type = source['type']?.toString().toLowerCase() ?? '';
    final title = source['title']?.toString() ?? '';
    return type == 'rehearsal' ||
        type == 'dressrehearsal' ||
        type == 'concert' ||
        type == 'performance' ||
        type == 'worship' ||
        type == 'service' ||
        title.contains('연습') ||
        title.contains('리허설') ||
        title.contains('찬양') ||
        title.contains('예배') ||
        title.contains('공연');
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
  final String? targetDate;
  final String? pollId;
  final String? seatingChartId;
  final bool needsAttendance;
  final bool needsSeating;

  const _WeeklyScheduleItem({
    required this.title,
    required this.badge,
    required this.accent,
    required this.dateText,
    required this.timeText,
    required this.locationText,
    this.targetDate,
    this.pollId,
    this.seatingChartId,
    this.needsAttendance = false,
    this.needsSeating = false,
  });

  bool get canOpenPoll =>
      (pollId?.isNotEmpty ?? false) || (targetDate?.isNotEmpty ?? false);

  bool get hasPoll => pollId?.isNotEmpty ?? false;

  /// The schedule's date (date-only), parsed from [targetDate].
  DateTime? get _date {
    final raw = targetDate?.trim();
    if (raw == null || raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) return DateTime(parsed.year, parsed.month, parsed.day);
    final m = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(raw);
    if (m != null) {
      return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    }
    return null;
  }

  /// True only on the schedule's own date — gates the day-only 출석 button.
  bool get isToday {
    final d = _date;
    if (d == null) return false;
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  /// True once the schedule date has passed — closes the 투표 window.
  bool get isPast {
    final d = _date;
    if (d == null) return false;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).isAfter(d);
  }

  factory _WeeklyScheduleItem.fromEvent(
    Map<String, dynamic> event, {
    Map<String, dynamic>? poll,
  }) {
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
    final date = HomeScreen._eventDateTime(event);
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
      targetDate: date?.toIso8601String().split('T').first,
      pollId: poll?['id']?.toString() ?? event['pollId']?.toString(),
      seatingChartId: event['seatingChartId']?.toString(),
      needsAttendance:
          HomeScreen._scheduleNeedsAttendance(event) || poll != null,
      needsSeating: HomeScreen._scheduleNeedsSeating(event),
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
  final void Function(_WeeklyScheduleItem item)? onVote;
  final void Function(_WeeklyScheduleItem item)? onAttendance;
  final void Function(_WeeklyScheduleItem item)? onSeat;
  final VoidCallback onDetails;

  const _WeeklyScheduleCard({
    required this.schedules,
    required this.onVote,
    required this.onAttendance,
    required this.onSeat,
    required this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '다가오는 스케줄',
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
            // 투표: 일정 당일까지(당일 자정 전) 노출. 출석: 일정 당일에만 노출.
            onVote:
                onVote == null || !schedules[i].hasPoll || schedules[i].isPast
                ? null
                : () => onVote!(schedules[i]),
            onAttendance:
                onAttendance == null ||
                    !schedules[i].needsAttendance ||
                    !schedules[i].isToday
                ? null
                : () => onAttendance!(schedules[i]),
            onSeat: onSeat == null || !schedules[i].needsSeating
                ? null
                : () => onSeat!(schedules[i]),
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
                  '관리자가 등록한 일정만 표시됩니다',
                  style: AppText.body(
                    12,
                    weight: FontWeight.w700,
                    color: AppColors.secondaryContainer,
                  ),
                ),
              ),
              Text(
                '일정 보기',
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
  final VoidCallback? onVote;
  final VoidCallback? onAttendance;
  final VoidCallback? onSeat;

  const _WeeklyScheduleRow({
    required this.item,
    this.onVote,
    this.onAttendance,
    this.onSeat,
  });

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
                          color: item.accent,
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
          if (onVote != null || onAttendance != null || onSeat != null) ...[
            const SizedBox(width: 8),
            Column(
              children: [
                if (onVote != null)
                  _scheduleButton(label: '투표', onTap: onVote!, filled: true),
                if (onVote != null && (onAttendance != null || onSeat != null))
                  const SizedBox(height: 5),
                if (onAttendance != null)
                  _scheduleButton(
                    label: '출석',
                    onTap: onAttendance!,
                    filled: true,
                  ),
                if (onAttendance != null && onSeat != null)
                  const SizedBox(height: 5),
                if (onSeat != null)
                  _scheduleButton(label: '자리', onTap: onSeat!),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _scheduleButton({
    required String label,
    required VoidCallback onTap,
    bool filled = false,
  }) {
    return SizedBox(
      height: 27,
      width: 48,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: filled
              ? AppColors.secondaryContainer
              : Colors.white.withValues(alpha: 0.08),
          foregroundColor: filled ? AppColors.primary : Colors.white,
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side: BorderSide(
              color: filled
                  ? Colors.transparent
                  : Colors.white.withValues(alpha: 0.28),
            ),
          ),
          textStyle: AppText.body(11, weight: FontWeight.w900),
        ),
        child: Text(label, maxLines: 1, overflow: TextOverflow.clip),
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
    final partLabel = User.partLabels[part] ?? part;
    final coordinate = '$partLabel $row열 $col번';
    final scheduleLine = date.isEmpty ? eventTitle : '$date · $eventTitle';

    return Tappable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFF7E6), Color(0xFFFFFFFF)],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AppColors.secondaryContainer.withValues(alpha: 0.82),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.secondary.withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _SeatPassPainter())),
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 13, 12, 13),
              child: Row(
                children: [
                  const _SeatPassMark(),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '내 자리',
                                style: AppText.body(
                                  11,
                                  weight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                '자리배치로 이동',
                                style: AppText.body(
                                  11,
                                  weight: FontWeight.w800,
                                  color: AppColors.muted,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          scheduleLine,
                          style: AppText.body(
                            12,
                            weight: FontWeight.w800,
                            color: AppColors.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          coordinate,
                          style: AppText.headline(
                            18,
                            weight: FontWeight.w900,
                            color: AppColors.primary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 36,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.82),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.secondaryContainer.withValues(
                          alpha: 0.42,
                        ),
                      ),
                    ),
                    child: const Icon(
                      Icons.chevron_right_rounded,
                      size: 25,
                      color: AppColors.secondary,
                    ),
                  ),
                ],
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

class _SeatPassMark extends StatelessWidget {
  const _SeatPassMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 62,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.20),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -10,
            top: -10,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppColors.secondaryContainer.withValues(alpha: 0.28),
                shape: BoxShape.circle,
              ),
            ),
          ),
          const Center(
            child: Icon(
              Icons.event_seat_rounded,
              size: 25,
              color: AppColors.secondaryContainer,
            ),
          ),
          Positioned(
            left: 11,
            right: 11,
            bottom: 10,
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                color: AppColors.secondaryContainer.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SeatPassPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rail = Paint()
      ..color = AppColors.secondary
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, 5, size.height),
        const Radius.circular(2),
      ),
      rail,
    );

    final grid = Paint()
      ..color = AppColors.secondaryContainer.withValues(alpha: 0.24)
      ..strokeWidth = 1;
    for (var x = size.width * 0.58; x < size.width - 46; x += 18) {
      canvas.drawLine(Offset(x, 18), Offset(x, size.height - 18), grid);
    }
    for (var y = 20.0; y < size.height - 16; y += 14) {
      canvas.drawLine(Offset(92, y), Offset(size.width - 44, y), grid);
    }

    final fold = Path()
      ..moveTo(size.width - 54, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, 54)
      ..close();
    canvas.drawPath(
      fold,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.50)
        ..style = PaintingStyle.fill,
    );
    canvas.drawLine(
      Offset(size.width - 54, 0),
      Offset(size.width, 54),
      Paint()
        ..color = AppColors.secondaryContainer.withValues(alpha: 0.44)
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(covariant _SeatPassPainter oldDelegate) => false;
}

// ── Upload Chip for horizontal scroll
class _UploadChip extends StatelessWidget {
  final IconData icon;
  final String title, sub;
  final Color color;
  final VoidCallback onTap;

  const _UploadChip({
    required this.icon,
    required this.title,
    required this.sub,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tappable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
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
      ),
    );
  }
}
