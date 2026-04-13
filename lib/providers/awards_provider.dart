import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/firebase_service.dart';

/// Aggregated awards/badge state for the community.
/// All computation is client-side from posts + attendance, no DB writes.
class AwardsState {
  /// userId -> badge counts (cumulative wins from past completed periods)
  final Map<String, UserAwardCounts> counts;

  /// userId of the current week's "이주의 갈렙" winner (most likes received this week)
  final String? currentWeeklyCalebUid;
  final int currentWeeklyCalebLikes;

  /// userId of the current month's "이달의 갈렙" winner
  final String? currentMonthlyCalebUid;
  final int currentMonthlyCalebLikes;

  /// userId of the current month's attendance champion
  final String? currentAttendanceChampionUid;
  final int currentAttendanceChampionCount;

  AwardsState({
    required this.counts,
    required this.currentWeeklyCalebUid,
    required this.currentWeeklyCalebLikes,
    required this.currentMonthlyCalebUid,
    required this.currentMonthlyCalebLikes,
    required this.currentAttendanceChampionUid,
    required this.currentAttendanceChampionCount,
  });

  UserAwardCounts countsFor(String? uid) =>
      counts[uid ?? ''] ?? const UserAwardCounts();

  bool isCurrentWeeklyCaleb(String? uid) => uid != null && uid == currentWeeklyCalebUid;
  bool isCurrentMonthlyCaleb(String? uid) => uid != null && uid == currentMonthlyCalebUid;
  bool isAttendanceChampion(String? uid) => uid != null && uid == currentAttendanceChampionUid;
}

class UserAwardCounts {
  final int weeklyCalebWins;
  final int monthlyCalebWins;
  const UserAwardCounts({this.weeklyCalebWins = 0, this.monthlyCalebWins = 0});
}

DateTime _startOfWeek(DateTime d) {
  // ISO week starts Monday
  final monday = d.subtract(Duration(days: d.weekday - 1));
  return DateTime(monday.year, monday.month, monday.day);
}

DateTime _startOfMonth(DateTime d) => DateTime(d.year, d.month, 1);

int _likesOnPost(Map<String, dynamic> post) {
  final reactions = (post['reactions'] as Map<String, dynamic>?) ?? const {};
  final likes = (reactions['like'] as List<dynamic>?) ?? const [];
  return likes.length;
}

/// Picks the user with the most aggregated likes within [posts]. Returns null if no posts.
({String? uid, int likes}) _topByLikes(Iterable<Map<String, dynamic>> posts) {
  final tally = <String, int>{};
  for (final p in posts) {
    final uid = p['userId'] as String?;
    if (uid == null) continue;
    tally[uid] = (tally[uid] ?? 0) + _likesOnPost(p);
  }
  if (tally.isEmpty) return (uid: null, likes: 0);
  String? topUid;
  int topLikes = -1;
  tally.forEach((uid, likes) {
    if (likes > topLikes) {
      topUid = uid;
      topLikes = likes;
    }
  });
  return (uid: topUid, likes: topLikes < 0 ? 0 : topLikes);
}

final awardsProvider = FutureProvider<AwardsState>((ref) async {
  final now = DateTime.now();
  // Reach back ~13 weeks for past weekly winners and ~6 months for monthly.
  final since = DateTime(now.year, now.month - 6, 1)
      .subtract(const Duration(days: 1));

  final posts = await FirebaseService.getPostsSince(since);

  // Bucket by week-start (Monday) and month-start to compute past winners.
  final weekBuckets = <DateTime, List<Map<String, dynamic>>>{};
  final monthBuckets = <DateTime, List<Map<String, dynamic>>>{};
  for (final p in posts) {
    final ts = p['createdAt'] as DateTime?;
    if (ts == null) continue;
    weekBuckets.putIfAbsent(_startOfWeek(ts), () => []).add(p);
    monthBuckets.putIfAbsent(_startOfMonth(ts), () => []).add(p);
  }

  final thisWeek = _startOfWeek(now);
  final thisMonth = _startOfMonth(now);

  // Current period winners.
  final weeklyTop = _topByLikes(weekBuckets[thisWeek] ?? const []);
  final monthlyTop = _topByLikes(monthBuckets[thisMonth] ?? const []);

  // Cumulative counts from COMPLETED past periods only (exclude current).
  final counts = <String, UserAwardCounts>{};
  weekBuckets.forEach((weekStart, weekPosts) {
    if (!weekStart.isBefore(thisWeek)) return;
    final winner = _topByLikes(weekPosts);
    if (winner.uid == null || winner.likes <= 0) return;
    final prev = counts[winner.uid!] ?? const UserAwardCounts();
    counts[winner.uid!] = UserAwardCounts(
      weeklyCalebWins: prev.weeklyCalebWins + 1,
      monthlyCalebWins: prev.monthlyCalebWins,
    );
  });
  monthBuckets.forEach((monthStart, monthPosts) {
    if (!monthStart.isBefore(thisMonth)) return;
    final winner = _topByLikes(monthPosts);
    if (winner.uid == null || winner.likes <= 0) return;
    final prev = counts[winner.uid!] ?? const UserAwardCounts();
    counts[winner.uid!] = UserAwardCounts(
      weeklyCalebWins: prev.weeklyCalebWins,
      monthlyCalebWins: prev.monthlyCalebWins + 1,
    );
  });

  // Attendance champion: most attendance records this month.
  final monthAttendance = await FirebaseService.getAttendanceSince(thisMonth);
  final attendanceTally = <String, int>{};
  for (final a in monthAttendance) {
    final uid = a['userId'] as String?;
    if (uid == null) continue;
    attendanceTally[uid] = (attendanceTally[uid] ?? 0) + 1;
  }
  String? championUid;
  int championCount = 0;
  attendanceTally.forEach((uid, n) {
    if (n > championCount) {
      championUid = uid;
      championCount = n;
    }
  });

  return AwardsState(
    counts: counts,
    currentWeeklyCalebUid: weeklyTop.likes > 0 ? weeklyTop.uid : null,
    currentWeeklyCalebLikes: weeklyTop.likes,
    currentMonthlyCalebUid: monthlyTop.likes > 0 ? monthlyTop.uid : null,
    currentMonthlyCalebLikes: monthlyTop.likes,
    currentAttendanceChampionUid: championCount > 0 ? championUid : null,
    currentAttendanceChampionCount: championCount,
  );
});
