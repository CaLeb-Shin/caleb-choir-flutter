import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import '../services/firebase_service.dart';
import '../models/user.dart';

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
  await FirebaseService.ensureAdminRole();
  final data = await FirebaseService.getProfile();
  if (data == null) return null;
  return User.fromMap(data);
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
