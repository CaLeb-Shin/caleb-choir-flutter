import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../models/user.dart';

// API Service singleton
final apiServiceProvider = Provider<ApiService>((ref) => ApiService());

// Current user profile
final profileProvider = FutureProvider<User?>((ref) async {
  final api = ref.read(apiServiceProvider);
  final data = await api.getProfile();
  if (data == null) return null;
  return User.fromJson(data);
});

// Active attendance session
final activeSessionProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final api = ref.read(apiServiceProvider);
  return api.getActiveSession();
});

// My attendance history
final myHistoryProvider = FutureProvider<List<dynamic>>((ref) async {
  final api = ref.read(apiServiceProvider);
  return api.getMyHistory();
});

// Videos list
final videosProvider = FutureProvider<List<dynamic>>((ref) async {
  final api = ref.read(apiServiceProvider);
  return api.getVideos();
});

// Posts list
final postsProvider = FutureProvider<List<dynamic>>((ref) async {
  final api = ref.read(apiServiceProvider);
  return api.getPosts();
});

// Announcements list
final announcementsProvider = FutureProvider<List<dynamic>>((ref) async {
  final api = ref.read(apiServiceProvider);
  return api.getAnnouncements();
});

// Sheet music list
final sheetMusicProvider = FutureProvider<List<dynamic>>((ref) async {
  final api = ref.read(apiServiceProvider);
  return api.getSheetMusic();
});

// Events list
final eventsProvider = FutureProvider<List<dynamic>>((ref) async {
  final api = ref.read(apiServiceProvider);
  return api.getEvents();
});
