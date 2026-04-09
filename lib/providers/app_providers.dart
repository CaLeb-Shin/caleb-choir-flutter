import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import '../services/firebase_service.dart';
import '../models/user.dart';

// Auth state stream
final authStateProvider = StreamProvider<fb.User?>((ref) {
  return FirebaseService.authStateChanges;
});

// Current user profile
final profileProvider = FutureProvider<User?>((ref) async {
  final authState = ref.watch(authStateProvider);
  if (authState.valueOrNull == null) return null;
  final data = await FirebaseService.getProfile();
  if (data == null) return null;
  return User.fromMap(data);
});

// Active attendance session
final activeSessionProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  return FirebaseService.getActiveSession();
});

// My attendance history
final myHistoryProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return FirebaseService.getMyHistory();
});

// Videos list
final videosProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return FirebaseService.getVideos();
});

// Posts list
final postsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return FirebaseService.getPosts();
});

// Announcements list
final announcementsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return FirebaseService.getAnnouncements();
});

// Sheet music list
final sheetMusicProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return FirebaseService.getSheetMusic();
});

// Events list
final eventsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return FirebaseService.getEvents();
});

// All members (admin)
final membersProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return FirebaseService.getAllMembers();
});
