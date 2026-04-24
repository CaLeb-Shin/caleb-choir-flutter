import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import '../services/firebase_service.dart';
import '../models/user.dart';
import '../models/church.dart';

// ─── Navigation ───
final tabIndexProvider = StateProvider<int>((ref) => 0);

// ─── Logged-out flag (로그아웃 안내 메시지 1회 표시용) ───
final loggedOutProvider = StateProvider<bool>((ref) => false);

// ─── View-as-Member (관리자가 일반 단원 시점으로 시스템을 살피기 위한 로컬 토글) ───
// Firestore 의 실제 role 은 건드리지 않고 UI 렌더에만 영향을 줌.
final viewAsMemberProvider = StateProvider<bool>((ref) => false);

/// 현재 세션에서 "관리자 UI" 를 보여줄지 여부. 실제 admin 이면서
/// viewAsMember 토글이 꺼져있을 때만 true.
final effectiveIsAdminProvider = Provider<bool>((ref) {
  final profile = ref.watch(profileProvider).valueOrNull;
  final viewAsMember = ref.watch(viewAsMemberProvider);
  return (profile?.isAdmin ?? false) && !viewAsMember;
});

/// 관리자 + 임원(officer) 모두 포함한 관리 권한. viewAsMember 토글 반영.
final effectiveHasManagePermissionProvider = Provider<bool>((ref) {
  final profile = ref.watch(profileProvider).valueOrNull;
  final viewAsMember = ref.watch(viewAsMemberProvider);
  return (profile?.hasManagePermission ?? false) && !viewAsMember;
});

// ─── Auth ───
final authStateProvider = StreamProvider<fb.User?>((ref) {
  return FirebaseService.authStateChanges;
});

// ─── User Profile ───
final profileProvider = FutureProvider<User?>((ref) async {
  final authState = ref.watch(authStateProvider);
  final fbUser = authState.valueOrNull;
  if (fbUser == null) return null;
  // 관리자 이메일이면 자동 admin 권한 부여
  await FirebaseService.ensurePlatformAdminRole();
  final data = await FirebaseService.getProfile();
  if (data == null) return null;
  return User.fromMap(data);
});

/// 실시간 프로필 스트림 (관리자 승인 시 UI 자동 전환용)
/// 추가로 FirebaseService.currentChurchId 캐시도 동기화 — 도메인 메서드가 동기 접근하기 위함.
final myProfileStreamProvider = StreamProvider<User?>((ref) {
  final authState = ref.watch(authStateProvider);
  final fbUser = authState.valueOrNull;
  if (fbUser == null) {
    FirebaseService.setCurrentChurchId(null);
    return Stream.value(null);
  }
  // 로그인 시 한 번 platform admin 자동 부트스트랩 실행
  FirebaseService.ensurePlatformAdminRole();
  return FirebaseService.watchMyProfile().map((data) {
    if (data == null) {
      FirebaseService.setCurrentChurchId(null);
      return null;
    }
    FirebaseService.setCurrentChurchId(data['churchId'] as String?);
    return User.fromMap(data);
  });
});

// ─── Multi-tenant (Church) ───
/// 현재 로그인 유저의 churchId. 미소속/신청 전이면 null.
final currentChurchIdProvider = Provider<String?>((ref) {
  return ref.watch(myProfileStreamProvider).valueOrNull?.churchId;
});

/// 현재 유저가 속한 교회 정보. churchId가 null이면 null.
final currentChurchProvider = FutureProvider<Church?>((ref) async {
  final id = ref.watch(currentChurchIdProvider);
  if (id == null) return null;
  final data = await FirebaseService.getChurch(id);
  return data == null ? null : Church.fromMap(data);
});

/// 승인된 교회 검색 (ChurchSearchScreen용). query 변경 시 자동 재조회.
final churchSearchProvider = FutureProvider.family<List<Church>, String>((ref, query) async {
  final list = await FirebaseService.searchApprovedChurches(query);
  return list.map((m) => Church.fromMap(m)).toList();
});

// ─── Admin: Pending Approvals ───
final pendingUsersProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return FirebaseService.getPendingUsers();
});

final rejectedUsersProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return FirebaseService.getRejectedUsers();
});

// ─── Attendance ───
final activeSessionProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  return FirebaseService.getActiveSession();
});

final myHistoryProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return FirebaseService.getMyHistory();
});

final recentSessionsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return FirebaseService.getRecentSessions(limit: 5);
});

// ─── Content ───
final videosProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return FirebaseService.getVideos();
});

final postsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return FirebaseService.getPosts();
});

final postProvider = FutureProvider.family<Map<String, dynamic>?, String>((ref, postId) async {
  return FirebaseService.getPost(postId);
});

final commentsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, postId) async {
  return FirebaseService.getComments(postId);
});

final announcementsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return FirebaseService.getAnnouncements();
});

final sheetMusicProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return FirebaseService.getSheetMusic();
});

final eventsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return FirebaseService.getEvents();
});

final membersProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return FirebaseService.getAllMembers();
});

// ─── Part Leader ───
final effectiveIsPartLeaderProvider = Provider<bool>((ref) {
  final profile = ref.watch(profileProvider).valueOrNull;
  final viewAsMember = ref.watch(viewAsMemberProvider);
  return (profile?.isPartLeader ?? false) && !viewAsMember;
});

// ─── Polls ───
final pollsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return FirebaseService.getPolls();
});

final pollVotesProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, pollId) async {
  return FirebaseService.getPollVotes(pollId);
});

// ─── Seating ───
final seatingChartsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final profile = ref.watch(profileProvider).valueOrNull;
  final publishedOnly = profile?.role == 'member';
  return FirebaseService.getSeatingCharts(publishedOnly: publishedOnly);
});

final seatAssignmentsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, chartId) async {
  return FirebaseService.getSeatAssignments(chartId);
});

// ─── This Week's Uploads ───
final recentSheetMusicProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final all = await FirebaseService.getSheetMusic();
  final weekAgo = DateTime.now().subtract(const Duration(days: 7));
  return all.where((s) {
    final created = s['createdAt'];
    if (created == null) return false;
    try {
      final d = created is Timestamp ? created.toDate() : DateTime.parse(created.toString());
      return d.isAfter(weekAgo);
    } catch (_) {
      return false;
    }
  }).toList();
});

final recentVideosProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final all = await FirebaseService.getVideos();
  final weekAgo = DateTime.now().subtract(const Duration(days: 7));
  return all.where((v) {
    final created = v['createdAt'];
    if (created == null) return false;
    try {
      final d = created is Timestamp ? created.toDate() : DateTime.parse(created.toString());
      return d.isAfter(weekAgo);
    } catch (_) {
      return false;
    }
  }).toList();
});
