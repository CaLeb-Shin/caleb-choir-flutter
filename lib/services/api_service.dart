import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiService {
  static const String _tokenKey = 'app_session_token';

  late final Dio _dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // TODO: Update this to your actual API server URL
  String baseUrl;

  ApiService({this.baseUrl = 'http://localhost:3000'}) {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await getToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
    ));
  }

  Future<String?> getToken() => _storage.read(key: _tokenKey);
  Future<void> setToken(String token) => _storage.write(key: _tokenKey, value: token);
  Future<void> clearToken() => _storage.delete(key: _tokenKey);

  // Generic tRPC-style query
  Future<dynamic> query(String path, [Map<String, dynamic>? input]) async {
    final params = input != null ? {'input': Uri.encodeComponent(_jsonEncode(input))} : null;
    final response = await _dio.get('/api/trpc/$path', queryParameters: params);
    return response.data['result']?['data'];
  }

  // Generic tRPC-style mutation
  Future<dynamic> mutate(String path, [Map<String, dynamic>? input]) async {
    final response = await _dio.post('/api/trpc/$path', data: input);
    return response.data['result']?['data'];
  }

  String _jsonEncode(Map<String, dynamic> data) {
    // Simple JSON encode for tRPC query params
    final entries = data.entries.map((e) => '"${e.key}":${_encodeValue(e.value)}');
    return '{${entries.join(',')}}';
  }

  String _encodeValue(dynamic value) {
    if (value is String) return '"$value"';
    if (value is num || value is bool) return '$value';
    if (value == null) return 'null';
    return '"$value"';
  }

  // ============ Auth ============
  Future<Map<String, dynamic>?> getMe() async {
    try {
      return await query('auth.me') as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  Future<void> logout() => mutate('auth.logout');

  // ============ Profile ============
  Future<Map<String, dynamic>?> getProfile() async {
    try {
      return await query('profile.get') as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  Future<void> updateProfile({
    required String name,
    required String generation,
    required String part,
    required String phone,
  }) async {
    await mutate('profile.update', {
      'name': name,
      'generation': generation,
      'part': part,
      'phone': phone,
    });
  }

  // ============ Attendance ============
  Future<Map<String, dynamic>?> getActiveSession() async {
    try {
      return await query('attendanceSession.active') as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> checkIn(int sessionId) async {
    return await mutate('attendance.checkIn', {'sessionId': sessionId});
  }

  Future<List<dynamic>> getMyHistory() async {
    try {
      return await query('attendance.myHistory') as List<dynamic>? ?? [];
    } catch (_) {
      return [];
    }
  }

  // ============ Videos ============
  Future<List<dynamic>> getVideos() async {
    try {
      return await query('videos.list') as List<dynamic>? ?? [];
    } catch (_) {
      return [];
    }
  }

  // ============ Posts ============
  Future<List<dynamic>> getPosts() async {
    try {
      return await query('posts.list') as List<dynamic>? ?? [];
    } catch (_) {
      return [];
    }
  }

  Future<void> createPost(String content, {String? imageUrl}) async {
    await mutate('posts.create', {
      'content': content,
      if (imageUrl != null) 'imageUrl': imageUrl,
    });
  }

  // ============ Announcements ============
  Future<List<dynamic>> getAnnouncements() async {
    try {
      return await query('announcements.list') as List<dynamic>? ?? [];
    } catch (_) {
      return [];
    }
  }

  Future<void> markAnnouncementRead(int id) async {
    await mutate('announcements.markRead', {'id': id});
  }

  // ============ Sheet Music ============
  Future<List<dynamic>> getSheetMusic() async {
    try {
      return await query('sheetMusic.list') as List<dynamic>? ?? [];
    } catch (_) {
      return [];
    }
  }

  // ============ Events ============
  Future<List<dynamic>> getEvents() async {
    try {
      return await query('events.list') as List<dynamic>? ?? [];
    } catch (_) {
      return [];
    }
  }

  // ============ Attendance Export ============
  Future<Map<String, dynamic>> getAttendanceCsv() async {
    try {
      return await query('attendanceExport.csv') as Map<String, dynamic>? ?? {};
    } catch (_) {
      return {};
    }
  }
}
