import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/firebase_service.dart';

/// Aggregated awards/badge state for the community.
/// All computation is client-side from posts + attendance + members.
class AwardsState {
  /// userId -> badge counts (cumulative wins from past completed periods)
  final Map<String, UserAwardCounts> counts;

  // Active titles
  final String? currentWeeklyCalebUid;
  final int currentWeeklyCalebLikes;
  final String? currentMonthlyCalebUid;
  final int currentMonthlyCalebLikes;
  final String? currentAttendanceChampionUid;
  final int currentAttendanceChampionCount;

  /// 이번 달 가장 많은 🙏 reactions 받은 사람.
  final String? currentPrayKingUid;
  final int currentPrayKingCount;

  /// 이번 달 가장 많은 댓글을 작성한 사람.
  final String? currentCommentKingUid;
  final int currentCommentKingCount;

  /// 이번 달 모든 출석 세션에 100% 참석한 사람들.
  final Set<String> perfectAttendanceUids;

  /// 가입한 지 30일 이내 사용자.
  final Set<String> newcomerUids;

  AwardsState({
    required this.counts,
    required this.currentWeeklyCalebUid,
    required this.currentWeeklyCalebLikes,
    required this.currentMonthlyCalebUid,
    required this.currentMonthlyCalebLikes,
    required this.currentAttendanceChampionUid,
    required this.currentAttendanceChampionCount,
    required this.currentPrayKingUid,
    required this.currentPrayKingCount,
    required this.currentCommentKingUid,
    required this.currentCommentKingCount,
    required this.perfectAttendanceUids,
    required this.newcomerUids,
  });

  UserAwardCounts countsFor(String? uid) =>
      counts[uid ?? ''] ?? const UserAwardCounts();

  bool isCurrentWeeklyCaleb(String? uid) => uid != null && uid == currentWeeklyCalebUid;
  bool isCurrentMonthlyCaleb(String? uid) => uid != null && uid == currentMonthlyCalebUid;
  bool isAttendanceChampion(String? uid) => uid != null && uid == currentAttendanceChampionUid;
  bool isPrayKing(String? uid) => uid != null && uid == currentPrayKingUid;
  bool isCommentKing(String? uid) => uid != null && uid == currentCommentKingUid;
  bool isPerfectAttendance(String? uid) => uid != null && perfectAttendanceUids.contains(uid);
  bool isNewcomer(String? uid) => uid != null && newcomerUids.contains(uid);
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
  // Reach back ~6 months for past weekly/monthly winners.
  final since = DateTime(now.year, now.month - 6, 1)
      .subtract(const Duration(days: 1));

  // Parallel fetches.
  final results = await Future.wait([
    FirebaseService.getPostsSince(since),
    FirebaseService.getAttendanceSince(DateTime(now.year, now.month, 1)),
    FirebaseService.getSessionsSince(DateTime(now.year, now.month, 1)),
    FirebaseService.getCommentsSince(DateTime(now.year, now.month, 1)),
    FirebaseService.getAllMembers(),
  ]);
  final posts = results[0];
  final monthAttendance = results[1];
  final monthSessions = results[2];
  final monthComments = results[3];
  final members = results[4];

  // Bucket posts by week-start (Monday) and month-start.
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

  // Current 갈렙 winners (most likes received).
  final weeklyTop = _topByLikes(weekBuckets[thisWeek] ?? const []);
  final monthlyTop = _topByLikes(monthBuckets[thisMonth] ?? const []);

  // Cumulative counts from COMPLETED past periods only.
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

  // 출석챔피언: 이번 달 출석 횟수 1위.
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

  // 개근: 이번 달 모든 세션 100% 참석. 세션이 1개 이상일 때만.
  final perfectUids = <String>{};
  final totalSessions = monthSessions.length;
  if (totalSessions > 0) {
    attendanceTally.forEach((uid, n) {
      if (n >= totalSessions) perfectUids.add(uid);
    });
  }

  // 기도왕: 이번 달 게시물에서 받은 🙏 reaction 수 1위.
  final prayReceivedTally = <String, int>{};
  for (final p in posts) {
    final ts = p['createdAt'] as DateTime?;
    if (ts == null || ts.isBefore(thisMonth)) continue;
    final author = p['userId'] as String?;
    if (author == null) continue;
    final reactions = (p['reactions'] as Map<String, dynamic>?) ?? const {};
    final prays = ((reactions['pray'] as List<dynamic>?) ?? const []).length;
    if (prays > 0) {
      prayReceivedTally[author] = (prayReceivedTally[author] ?? 0) + prays;
    }
  }
  String? prayKingUid;
  int prayKingCount = 0;
  prayReceivedTally.forEach((uid, n) {
    if (n > prayKingCount) {
      prayKingUid = uid;
      prayKingCount = n;
    }
  });

  // 댓글왕: 이번 달 댓글 작성 수 1위.
  final commentTally = <String, int>{};
  for (final c in monthComments) {
    final uid = c['userId'] as String?;
    if (uid == null) continue;
    commentTally[uid] = (commentTally[uid] ?? 0) + 1;
  }
  String? commentKingUid;
  int commentKingCount = 0;
  commentTally.forEach((uid, n) {
    if (n > commentKingCount) {
      commentKingUid = uid;
      commentKingCount = n;
    }
  });

  // 신입: 가입한 지 30일 이내.
  final newcomers = <String>{};
  final cutoff = now.subtract(const Duration(days: 30));
  for (final m in members) {
    final id = m['id'] as String?;
    if (id == null) continue;
    final created = m['createdAt'];
    DateTime? createdAt;
    if (created is Timestamp) {
      createdAt = created.toDate();
    } else if (created is DateTime) {
      createdAt = created;
    }
    if (createdAt != null && createdAt.isAfter(cutoff)) {
      newcomers.add(id);
    }
  }

  return AwardsState(
    counts: counts,
    currentWeeklyCalebUid: weeklyTop.likes > 0 ? weeklyTop.uid : null,
    currentWeeklyCalebLikes: weeklyTop.likes,
    currentMonthlyCalebUid: monthlyTop.likes > 0 ? monthlyTop.uid : null,
    currentMonthlyCalebLikes: monthlyTop.likes,
    currentAttendanceChampionUid: championCount > 0 ? championUid : null,
    currentAttendanceChampionCount: championCount,
    currentPrayKingUid: prayKingCount > 0 ? prayKingUid : null,
    currentPrayKingCount: prayKingCount,
    currentCommentKingUid: commentKingCount > 0 ? commentKingUid : null,
    currentCommentKingCount: commentKingCount,
    perfectAttendanceUids: perfectUids,
    newcomerUids: newcomers,
  );
});
