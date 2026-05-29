import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
import 'package:shared_preferences/shared_preferences.dart';

typedef UploadProgress = void Function(double progress);

class FirebaseService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final fb.FirebaseAuth _auth = fb.FirebaseAuth.instance;
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;
  static final _userDataFutures = <String, Future<Map<String, dynamic>?>>{};
  static final _userDataCache = <String, Map<String, dynamic>?>{};
  static const _cachedProfileKey = 'cc_note_cached_profile_v1';
  static Map<String, dynamic>? _cachedProfileMemory;

  /// 자동 관리자 이메일 화이트리스트
  static const adminEmails = {'sinbun001@gmail.com'};

  /// 현재 로그인 유저의 churchId 캐시. myProfileStreamProvider에서 업데이트.
  static String? _currentChurchIdCache;
  static String? get currentChurchId => _currentChurchIdCache;
  static void setCurrentChurchId(String? id) {
    _currentChurchIdCache = id;
  }

  /// 도메인 메서드용 — churchId가 없으면 명시적 에러.
  static String _requireChurchId() {
    final id = _currentChurchIdCache;
    if (id == null) {
      throw Exception('교회가 선택되지 않았거나 승인 대기 중입니다');
    }
    return id;
  }

  // ============ Auth ============
  static fb.User? get currentUser => _auth.currentUser;
  static String? get uid => _auth.currentUser?.uid;
  static Stream<fb.User?> get authStateChanges => _auth.authStateChanges();

  static Stream<fb.User?> authStateChangesWithCurrentUser() async* {
    final current = _auth.currentUser;
    if (current != null) {
      yield current;
    }
    var skippedInitialCurrentUser = false;
    await for (final user in _auth.authStateChanges()) {
      if (!skippedInitialCurrentUser &&
          current != null &&
          user?.uid == current.uid) {
        skippedInitialCurrentUser = true;
        continue;
      }
      yield user;
    }
  }

  static Future<void> signOut() async {
    _currentChurchIdCache = null;
    _userDataFutures.clear();
    _userDataCache.clear();
    await clearCachedProfile();
    await _auth.signOut();

    // 카카오 로그아웃 시도 (카카오로 로그인한 경우)
    try {
      await kakao.UserApi.instance.logout().timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  // ============ User Profile ============
  static Future<Map<String, dynamic>?> getProfile() async {
    if (uid == null) return null;
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    final profile = {'id': uid, ...doc.data()!};
    unawaited(cacheProfile(profile));
    return profile;
  }

  static Future<void> warmCachedProfile() async {
    _cachedProfileMemory = await _readCachedProfile();
  }

  static Map<String, dynamic>? cachedProfileSnapshot() {
    final cached = _cachedProfileMemory;
    if (cached == null) return null;
    final activeUid = uid;
    if (activeUid != null && cached['id']?.toString() != activeUid) {
      return null;
    }
    return cached;
  }

  static Future<Map<String, dynamic>?> getCachedProfile() async {
    final memory = cachedProfileSnapshot();
    if (memory != null) return memory;
    _cachedProfileMemory = await _readCachedProfile();
    return cachedProfileSnapshot();
  }

  static Future<Map<String, dynamic>?> _readCachedProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = prefs.getString(_cachedProfileKey);
      if (encoded == null || encoded.isEmpty) return null;
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) return null;
      return decoded;
    } catch (_) {
      return null;
    }
  }

  static Future<void> cacheProfile(Map<String, dynamic> profile) async {
    try {
      _cachedProfileMemory = _jsonSafeMap(profile);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cachedProfileKey,
        jsonEncode(_cachedProfileMemory),
      );
    } catch (_) {}
  }

  static Future<void> clearCachedProfile() async {
    try {
      _cachedProfileMemory = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cachedProfileKey);
    } catch (_) {}
  }

  static Future<void> createProfile(Map<String, dynamic> data) async {
    if (uid == null) return;
    final email = currentUser?.email;
    final isWhitelisted =
        email != null && adminEmails.contains(email.toLowerCase());

    // 관리자 화이트리스트 이메일은 자동 승인 + admin role
    final autoApproval = isWhitelisted
        ? {'role': 'admin', 'approvalStatus': 'approved'}
        : {
            'role': null, // 승인 후 관리자가 확정
            'approvalStatus': 'pending',
          };

    await _db.collection('users').doc(uid).set({
      ...data,
      ...autoApproval,
      'email': email,
      'profileCompleted': true,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// 거절된 유저가 다시 신청: 상태 pending으로 리셋
  static Future<void> reapplyApproval(Map<String, dynamic> data) async {
    if (uid == null) return;
    await _db.collection('users').doc(uid).update({
      ...data,
      'approvalStatus': 'pending',
      'rejectionReason': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// 부트스트랩 이메일이면 platform admin 플래그를 보장.
  /// users 문서가 없으면 isPlatformAdmin=true로 생성. 있으면 건드리지 않음
  /// (Firestore rules에 의해 self update로 isPlatformAdmin 변경은 불가능함).
  /// Phase 2부터 role/churchId는 건드리지 않음 — 교회 소속은 별도 플로우로 관리.
  static Future<void> ensurePlatformAdminRole() async {
    final email = currentUser?.email?.toLowerCase();
    if (email == null || !adminEmails.contains(email) || uid == null) return;
    final doc = await _db.collection('users').doc(uid).get();
    if (doc.exists) return;
    await _db.collection('users').doc(uid).set({
      'email': email,
      'name': currentUser?.displayName,
      'isPlatformAdmin': true,
      'profileCompleted': false,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// 관리자 전용: 다른 사용자 등급 변경
  static Future<void> updateUserRole(String userId, String role) async {
    await _db.collection('users').doc(userId).update({'role': role});
  }

  /// 관리자 전용: 다른 사용자 등급/파트/기수 변경
  static Future<void> updateUserAdminFields(
    String userId, {
    required String role,
    required String part,
    required String generation,
  }) async {
    final updates = <String, dynamic>{
      'role': role,
      'part': part,
      'generation': generation.trim(),
    };

    if (role == 'part_leader') {
      updates['partLeaderFor'] = part;
      updates['partLeaderTitle'] = 'leader';
    } else {
      updates['partLeaderFor'] = FieldValue.delete();
      updates['partLeaderTitle'] = FieldValue.delete();
    }

    await _db.collection('users').doc(userId).update(updates);
  }

  // ============ Approval Workflow ============
  static Future<List<Map<String, dynamic>>> getPendingUsers() async {
    final snapshot = await _db
        .collection('users')
        .where('churchId', isEqualTo: _requireChurchId())
        .where('approvalStatus', isEqualTo: 'pending')
        .get();
    return snapshot.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  static Future<List<Map<String, dynamic>>> getRejectedUsers() async {
    final snapshot = await _db
        .collection('users')
        .where('churchId', isEqualTo: _requireChurchId())
        .where('approvalStatus', isEqualTo: 'rejected')
        .get();
    return snapshot.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  static Future<void> approveUser(
    String userId, {
    required String role,
    String? partLeaderFor,
    String? partLeaderTitle,
  }) async {
    await _db.collection('users').doc(userId).update({
      'approvalStatus': 'approved',
      'role': role,
      'partLeaderFor': partLeaderFor,
      'partLeaderTitle': role == 'part_leader'
          ? (partLeaderTitle ?? 'leader')
          : FieldValue.delete(),
      'rejectionReason': FieldValue.delete(),
      'approvedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> rejectUser(String userId, String reason) async {
    await _db.collection('users').doc(userId).update({
      'approvalStatus': 'rejected',
      'rejectionReason': reason,
      'role': null,
      'partLeaderFor': null,
      'partLeaderTitle': FieldValue.delete(),
      'rejectedAt': FieldValue.serverTimestamp(),
    });
  }

  /// 현재 유저의 프로필 실시간 스트림 (승인 상태 변화 감지용)
  static Stream<Map<String, dynamic>?> watchMyProfile({
    bool emitCached = false,
  }) async* {
    if (uid == null) return;
    if (emitCached) {
      final cached = cachedProfileSnapshot() ?? await getCachedProfile();
      if (cached != null && cached['id']?.toString() == uid) {
        yield cached;
      }
    }
    yield* _db.collection('users').doc(uid).snapshots().map((doc) {
      if (!doc.exists) {
        unawaited(clearCachedProfile());
        return null;
      }
      final profile = {'id': doc.id, ...doc.data()!};
      unawaited(cacheProfile(profile));
      return profile;
    });
  }

  static Future<void> updateProfile(Map<String, dynamic> data) async {
    if (uid == null) return;
    await _db.collection('users').doc(uid).update(data);
  }

  /// 프로필 이미지 업로드 → downloadUrl 반환
  static Future<String?> uploadProfileImage(
    Uint8List bytes, {
    String contentType = 'image/jpeg',
    UploadProgress? onProgress,
  }) async {
    if (uid == null) return null;
    if (bytes.length > 5 * 1024 * 1024) {
      throw Exception('프로필 사진은 5MB 이하로 올려주세요');
    }
    final ref = FirebaseStorage.instance
        .ref()
        .child('profile_images')
        .child(uid!)
        .child('profile.jpg');
    final task = ref.putData(bytes, SettableMetadata(contentType: contentType));
    await _waitUpload(task, onProgress: onProgress);
    return await ref.getDownloadURL();
  }

  static int _createdAtDesc(Map<String, dynamic> a, Map<String, dynamic> b) {
    return _timestampFieldDesc('createdAt', a, b);
  }

  static int _timestampFieldDesc(
    String field,
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    return _timestampMillis(b[field]).compareTo(_timestampMillis(a[field]));
  }

  static int _timestampFieldAsc(
    String field,
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    return _timestampMillis(a[field]).compareTo(_timestampMillis(b[field]));
  }

  static int _timestampMillis(dynamic value) {
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    if (value is DateTime) return value.millisecondsSinceEpoch;
    if (value is String) {
      return DateTime.tryParse(value)?.millisecondsSinceEpoch ?? 0;
    }
    return 0;
  }

  static String _timestampIso(dynamic value) {
    final millis = _timestampMillis(value);
    if (millis == 0) return '';
    return DateTime.fromMillisecondsSinceEpoch(millis).toIso8601String();
  }

  static Map<String, dynamic> _jsonSafeMap(Map<String, dynamic> value) {
    return {
      for (final entry in value.entries) entry.key: _jsonSafeValue(entry.value),
    };
  }

  static dynamic _jsonSafeValue(dynamic value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is DateTime) return value.toIso8601String();
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): _jsonSafeValue(entry.value),
      };
    }
    if (value is Iterable) {
      return value.map(_jsonSafeValue).toList(growable: false);
    }
    return value.toString();
  }

  static Future<Map<String, dynamic>?> _safeUserData(dynamic userId) async {
    final id = userId?.toString();
    if (id == null || id.isEmpty) return null;
    if (_userDataCache.containsKey(id)) return _userDataCache[id];
    return _userDataFutures.putIfAbsent(id, () async {
      try {
        final doc = await _db.collection('users').doc(id).get();
        final data = doc.data();
        _userDataCache[id] = data;
        return data;
      } catch (_) {
        _userDataFutures.remove(id);
        return null;
      }
    });
  }

  static Map<String, dynamic>? _cachedUserData(dynamic userId) {
    final id = userId?.toString();
    if (id == null || id.isEmpty) return null;
    return _userDataCache[id];
  }

  static Map<String, dynamic> _authorFields(
    Map<String, dynamic> data,
    Map<String, dynamic>? userData,
  ) {
    final userId = data['userId']?.toString();
    final createdByAdmin = data['createdByAdmin'] == true || userId == 'admin';
    return {
      'userName':
          userData?['name'] ??
          data['userName'] ??
          data['authorName'] ??
          (createdByAdmin ? '관리자' : ''),
      'userPart': userData?['part'] ?? data['userPart'] ?? '',
      'userGeneration': userData?['generation'] ?? data['userGeneration'] ?? '',
      'userImageUrl':
          userData?['profileImageUrl'] ??
          userData?['imageUrl'] ??
          data['userImageUrl'] ??
          data['authorImageUrl'],
    };
  }

  static Map<String, int> _reactionCountsFrom(Map<String, dynamic> data) {
    final countsRaw = data['reactionCounts'] as Map<String, dynamic>?;
    final legacyRaw = data['reactions'] as Map<String, dynamic>?;
    return {
      for (final type in const ['like', 'sad', 'pray'])
        type:
            (countsRaw?[type] as num?)?.toInt() ??
            ((legacyRaw?[type] as List<dynamic>?) ?? const []).length,
    };
  }

  static String? _legacyReactionType(Map<String, dynamic> data, String userId) {
    final reactionsRaw = data['reactions'] as Map<String, dynamic>?;
    if (reactionsRaw == null) return null;
    for (final type in const ['like', 'sad', 'pray']) {
      final list = (reactionsRaw[type] as List<dynamic>?) ?? const [];
      if (list.map((value) => value.toString()).contains(userId)) {
        return type;
      }
    }
    return null;
  }

  static Future<String?> _myReactionForPost(
    String postId,
    Map<String, dynamic> data,
  ) async {
    final userId = uid;
    if (userId == null) return null;
    try {
      final doc = await _db
          .collection('posts')
          .doc(postId)
          .collection('reactions')
          .doc(userId)
          .get();
      final type = doc.data()?['type']?.toString();
      if (type != null && {'like', 'sad', 'pray'}.contains(type)) {
        return type;
      }
    } catch (_) {}
    return _legacyReactionType(data, userId);
  }

  static bool _postHasStoredAuthorFields(Map<String, dynamic> data) {
    return (data['userName']?.toString().trim().isNotEmpty ?? false) ||
        (data['authorName']?.toString().trim().isNotEmpty ?? false) ||
        data['createdByAdmin'] == true ||
        data['userId'] == 'admin';
  }

  static Map<String, dynamic> _postListSnapshotWithUserData(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    Map<String, dynamic>? userData,
  ) {
    final data = doc.data();
    final userId = uid;
    return {
      'id': doc.id,
      ...data,
      ..._authorFields(data, userData),
      'reactionCounts': _reactionCountsFrom(data),
      'myReaction': userId == null ? null : _legacyReactionType(data, userId),
      'createdAt': _timestampIso(data['createdAt']),
    };
  }

  static bool _postNeedsAuthorLookup(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final id = data['userId']?.toString();
    return !_postHasStoredAuthorFields(data) &&
        id != null &&
        id.isNotEmpty &&
        !_userDataCache.containsKey(id);
  }

  static Map<String, dynamic> _postListSnapshotFast(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final userData = _postHasStoredAuthorFields(data)
        ? null
        : _cachedUserData(data['userId']);
    return _postListSnapshotWithUserData(doc, userData);
  }

  static Future<Map<String, dynamic>> _postListSnapshot(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();
    final hasStoredAuthorName = _postHasStoredAuthorFields(data);
    final userData = hasStoredAuthorName
        ? null
        : await _safeUserData(data['userId']);
    return _postListSnapshotWithUserData(doc, userData);
  }

  static Future<Map<String, dynamic>> _postSnapshotWithAuthorAndReaction(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data()!;
    final userDataFuture = _safeUserData(data['userId']);
    final myReactionFuture = _myReactionForPost(doc.id, data);
    final userData = await userDataFuture;
    final myReaction = await myReactionFuture;
    return {
      'id': doc.id,
      ...data,
      ..._authorFields(data, userData),
      'reactionCounts': _reactionCountsFrom(data),
      'myReaction': myReaction,
      'createdAt': _timestampIso(data['createdAt']),
    };
  }

  static Future<List<Map<String, dynamic>>> getAllMembers() async {
    final snapshot = await _db
        .collection('users')
        .where('churchId', isEqualTo: _requireChurchId())
        .where('profileCompleted', isEqualTo: true)
        .get();
    return snapshot.docs
        .map((d) => {'id': d.id, ...d.data()})
        .where(
          (m) =>
              m['approvalStatus'] == null || m['approvalStatus'] == 'approved',
        )
        .toList();
  }

  // ============ Attendance Sessions ============
  static Future<Map<String, dynamic>?> getActiveSession() async {
    final snapshot = await _db
        .collection('attendance_sessions')
        .where('churchId', isEqualTo: _requireChurchId())
        .where('isOpen', isEqualTo: true)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    final doc = snapshot.docs.first;
    return {'id': doc.id, ...doc.data()};
  }

  static Stream<Map<String, dynamic>?> watchActiveSession() {
    return _db
        .collection('attendance_sessions')
        .where('churchId', isEqualTo: _requireChurchId())
        .where('isOpen', isEqualTo: true)
        .limit(1)
        .snapshots()
        .map((snapshot) {
          if (snapshot.docs.isEmpty) return null;
          final doc = snapshot.docs.first;
          return {'id': doc.id, ...doc.data()};
        });
  }

  static Future<List<Map<String, dynamic>>> getRecentSessions({
    int limit = 20,
  }) async {
    final snapshot = await _db
        .collection('attendance_sessions')
        .where('churchId', isEqualTo: _requireChurchId())
        .orderBy('openedAt', descending: true)
        .limit(limit)
        .get();
    return snapshot.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  static Future<void> openSession(String title) async {
    await _db.collection('attendance_sessions').add({
      'churchId': _requireChurchId(),
      'title': title,
      'openedBy': uid,
      'isOpen': true,
      'openedAt': FieldValue.serverTimestamp(),
      'attendanceDate': DateTime.now().toIso8601String().split('T')[0],
    });
  }

  static Future<void> closeSession(String sessionId) async {
    await _db.collection('attendance_sessions').doc(sessionId).update({
      'isOpen': false,
      'closedAt': FieldValue.serverTimestamp(),
    });
  }

  // ============ Attendance Check-in ============
  static Future<Map<String, dynamic>> checkIn(String sessionId) async {
    if (uid == null) throw Exception('로그인이 필요합니다');
    final churchId = _requireChurchId();
    final attendanceId = '${sessionId}_$uid';
    final attendanceRef = _db.collection('attendance').doc(attendanceId);

    final existing = await attendanceRef.get();
    if (existing.exists) {
      return {'alreadyCheckedIn': true};
    }

    await attendanceRef.set({
      'churchId': churchId,
      'userId': uid,
      'sessionId': sessionId,
      ..._authorFields({'userId': uid}, await _safeUserData(uid)),
      'checkedInAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: false));

    return {'alreadyCheckedIn': false};
  }

  static Future<List<Map<String, dynamic>>> getMyHistory() async {
    if (uid == null) return [];
    final snapshot = await _db
        .collection('attendance')
        .where('churchId', isEqualTo: _requireChurchId())
        .where('userId', isEqualTo: uid)
        .get();

    final sessionFutures =
        <String, Future<DocumentSnapshot<Map<String, dynamic>>>>{};
    final records = await Future.wait(
      snapshot.docs.map((doc) async {
        final data = doc.data();
        final sessionId = data['sessionId']?.toString() ?? '';
        final sessionDoc = sessionId.isEmpty
            ? null
            : await sessionFutures.putIfAbsent(
                sessionId,
                () =>
                    _db.collection('attendance_sessions').doc(sessionId).get(),
              );
        return {
          'id': doc.id,
          'sessionTitle': sessionDoc?.data()?['title'] ?? '',
          'checkedInAt':
              (data['checkedInAt'] as Timestamp?)?.toDate().toIso8601String() ??
              '',
        };
      }),
    );
    records.sort((a, b) => _timestampFieldDesc('checkedInAt', a, b));
    return records;
  }

  static Future<List<Map<String, dynamic>>> getSessionAttendees(
    String sessionId,
  ) async {
    final snapshot = await _db
        .collection('attendance')
        .where('churchId', isEqualTo: _requireChurchId())
        .where('sessionId', isEqualTo: sessionId)
        .get();

    final attendees = <Map<String, dynamic>>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final userData = (data['userName'] == null || data['userPart'] == null)
          ? await _safeUserData(data['userId'])
          : null;
      final author = _authorFields(data, userData);
      attendees.add({
        'id': doc.id,
        'userName': author['userName'] ?? '',
        'userPart': author['userPart'] ?? '',
        'checkedInAt':
            (data['checkedInAt'] as Timestamp?)?.toDate().toIso8601String() ??
            '',
      });
    }
    return attendees;
  }

  // ============ Videos ============
  static Future<List<Map<String, dynamic>>> getVideos({int? limit}) async {
    Query<Map<String, dynamic>> query = _db
        .collection('videos')
        .where('churchId', isEqualTo: _requireChurchId())
        .orderBy('createdAt', descending: true);
    if (limit != null) query = query.limit(limit);
    final snapshot = await query.get();
    return snapshot.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  // ============ Awards data ============
  /// Posts created on/after [since], with userId+reactions intact (light shape).
  static Future<List<Map<String, dynamic>>> getPostsSince(
    DateTime since,
  ) async {
    final snapshot = await _db
        .collection('posts')
        .where('churchId', isEqualTo: _requireChurchId())
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .orderBy('createdAt', descending: true)
        .get();
    final posts = snapshot.docs.map((d) {
      final data = d.data();
      return {
        'id': d.id,
        'userId': data['userId'],
        'reactions': data['reactions'] ?? {},
        'reactionCounts': _reactionCountsFrom(data),
        'createdAt': (data['createdAt'] as Timestamp?)?.toDate(),
      };
    }).toList();
    return posts;
  }

  /// Attendance records on/after [since].
  static Future<List<Map<String, dynamic>>> getAttendanceSince(
    DateTime since,
  ) async {
    final snapshot = await _db
        .collection('attendance')
        .where('churchId', isEqualTo: _requireChurchId())
        .where('checkedInAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .orderBy('checkedInAt', descending: true)
        .get();
    return snapshot.docs.map((d) {
      final data = d.data();
      return {
        'id': d.id,
        'userId': data['userId'],
        'sessionId': data['sessionId'],
        'checkedInAt': (data['checkedInAt'] as Timestamp?)?.toDate(),
      };
    }).toList();
  }

  /// Attendance sessions opened on/after [since].
  static Future<List<Map<String, dynamic>>> getSessionsSince(
    DateTime since,
  ) async {
    final snapshot = await _db
        .collection('attendance_sessions')
        .where('churchId', isEqualTo: _requireChurchId())
        .where('openedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .orderBy('openedAt', descending: true)
        .get();
    return snapshot.docs.map((d) {
      final data = d.data();
      return {
        'id': d.id,
        'openedAt': (data['openedAt'] as Timestamp?)?.toDate(),
      };
    }).toList();
  }

  /// All comments authored on/after [since], across every post.
  static Future<List<Map<String, dynamic>>> getCommentsSince(
    DateTime since,
  ) async {
    final snapshot = await _db
        .collectionGroup('comments')
        .where('churchId', isEqualTo: _requireChurchId())
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .orderBy('createdAt', descending: true)
        .get();
    return snapshot.docs.map((d) {
      final data = d.data();
      return {
        'id': d.id,
        'userId': data['userId'],
        'createdAt': (data['createdAt'] as Timestamp?)?.toDate(),
      };
    }).toList();
  }

  // ============ Posts ============
  static Future<List<Map<String, dynamic>>> getPosts() async {
    final snapshot = await _db
        .collection('posts')
        .where('churchId', isEqualTo: _requireChurchId())
        .orderBy('createdAt', descending: true)
        .limit(50)
        .get();
    return Future.wait(snapshot.docs.map(_postListSnapshot));
  }

  static Stream<List<Map<String, dynamic>>> watchPosts() {
    return _db
        .collection('posts')
        .where('churchId', isEqualTo: _requireChurchId())
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots(includeMetadataChanges: true)
        .asyncExpand((snapshot) async* {
          yield snapshot.docs.map(_postListSnapshotFast).toList();
          if (snapshot.docs.any(_postNeedsAuthorLookup)) {
            yield await Future.wait(snapshot.docs.map(_postListSnapshot));
          }
        });
  }

  static Future<Map<String, dynamic>?> getPost(String postId) async {
    final doc = await _db.collection('posts').doc(postId).get();
    if (!doc.exists) return null;
    return _postSnapshotWithAuthorAndReaction(doc);
  }

  static Stream<Map<String, dynamic>?> watchPost(String postId) {
    return _db.collection('posts').doc(postId).snapshots().asyncMap((
      doc,
    ) async {
      if (!doc.exists) return null;
      return _postSnapshotWithAuthorAndReaction(doc);
    });
  }

  /// 게시물 이미지 업로드 → downloadUrl 반환
  static Future<String?> uploadPostImage(
    Uint8List bytes, {
    String contentType = 'image/jpeg',
    UploadProgress? onProgress,
  }) async {
    if (uid == null) return null;
    if (bytes.length > 15 * 1024 * 1024) {
      throw Exception('사진은 15MB 이하로 올려주세요');
    }
    final filename = '${DateTime.now().millisecondsSinceEpoch}_$uid.jpg';
    final ref = FirebaseStorage.instance
        .ref()
        .child('post_images')
        .child(filename);
    final task = ref.putData(bytes, SettableMetadata(contentType: contentType));
    await _waitUpload(task, onProgress: onProgress);
    return await ref.getDownloadURL();
  }

  /// 게시물 영상 업로드 → 저장된 Storage path 반환
  static Future<String?> uploadPostVideoSource(
    Uint8List bytes, {
    required String postId,
    String contentType = 'video/mp4',
    String extension = 'mp4',
    UploadProgress? onProgress,
  }) async {
    if (uid == null) return null;
    if (bytes.length > 120 * 1024 * 1024) {
      throw Exception('영상은 120MB 이하로 올려주세요');
    }
    final safeExtension = extension.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final filename =
        '${postId}_${DateTime.now().millisecondsSinceEpoch}_$uid.${safeExtension.isEmpty ? 'mp4' : safeExtension}';
    final ref = FirebaseStorage.instance
        .ref()
        .child('post_videos')
        .child('source')
        .child(filename);
    final task = ref.putData(
      bytes,
      SettableMetadata(
        contentType: contentType,
        customMetadata: {
          'postId': postId,
          'churchId': _requireChurchId(),
          'userId': uid!,
        },
      ),
    );
    await _waitUpload(task, onProgress: onProgress);
    return ref.fullPath;
  }

  static Future<String?> getStorageDownloadUrl(String storagePath) async {
    if (storagePath.trim().isEmpty) return null;
    return FirebaseStorage.instance.ref(storagePath).getDownloadURL();
  }

  static Future<TaskSnapshot> _waitUpload(
    UploadTask task, {
    UploadProgress? onProgress,
  }) async {
    if (onProgress != null) {
      await for (final snapshot in task.snapshotEvents) {
        final total = snapshot.totalBytes;
        if (total > 0) {
          onProgress(
            (snapshot.bytesTransferred / total).clamp(0.0, 1.0).toDouble(),
          );
        }
        if (snapshot.state == TaskState.success) return snapshot;
      }
    }
    return task;
  }

  static String _safeStorageName(String fileName) {
    final cleaned = fileName
        .trim()
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[^0-9A-Za-z가-힣._-]'), '');
    return cleaned.isEmpty ? 'audio_note.m4a' : cleaned;
  }

  // ============ Harmony Chat ============
  static int harmonyXpForLevel(int level) {
    final safeLevel = level.clamp(1, 100).toInt();
    if (safeLevel <= 1) return 0;
    return (safeLevel - 1) * (safeLevel - 1) * 70;
  }

  static int harmonyLevelForXp(int xp) {
    final safeXp = xp < 0 ? 0 : xp;
    var level = 1;
    while (level < 100 && safeXp >= harmonyXpForLevel(level + 1)) {
      level += 1;
    }
    return level;
  }

  static String _todayKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  static Stream<Map<String, dynamic>> watchHarmonyPracticeProgress() {
    final userId = uid;
    if (userId == null) {
      return Stream.value({
        'id': '',
        'userId': '',
        'xp': 0,
        'level': 1,
        'practiceCount': 0,
        'completedTutorialSteps': <String, dynamic>{},
      });
    }
    return _db
        .collection('harmony_practice_progress')
        .doc(userId)
        .snapshots()
        .map((doc) {
          final data = doc.data() ?? <String, dynamic>{};
          final xp = (data['xp'] as num?)?.toInt() ?? 0;
          final level = harmonyLevelForXp(xp);
          return {
            'id': doc.id,
            ...data,
            'userId': userId,
            'xp': xp,
            'level': level,
            'nextLevelXp': harmonyXpForLevel((level + 1).clamp(1, 100).toInt()),
            'practiceCount': (data['practiceCount'] as num?)?.toInt() ?? 0,
            'completedTutorialSteps':
                data['completedTutorialSteps'] ?? <String, dynamic>{},
            'createdAt': _timestampIso(data['createdAt']),
            'updatedAt': _timestampIso(data['updatedAt']),
          };
        });
  }

  static Stream<Map<String, dynamic>?> watchActiveHarmonyPracticeMission({
    required String part,
  }) {
    if (part.trim().isEmpty) return Stream.value(null);
    return _db
        .collection('harmony_practice_missions')
        .where('churchId', isEqualTo: _requireChurchId())
        .where('active', isEqualTo: true)
        .limit(40)
        .snapshots()
        .map((snapshot) {
          final missions =
              snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).where((
                mission,
              ) {
                final missionPart = mission['part']?.toString() ?? 'all';
                return missionPart == 'all' || missionPart == part;
              }).toList()..sort((a, b) {
                final byUpdated = _timestampFieldDesc('updatedAt', a, b);
                return byUpdated == 0 ? _createdAtDesc(a, b) : byUpdated;
              });
          if (missions.isEmpty) return null;
          final mission = missions.first;
          return {
            ...mission,
            'xpReward': (mission['xpReward'] as num?)?.toInt() ?? 25,
            'targetPractices':
                (mission['targetPractices'] as num?)?.toInt() ?? 1,
            'createdAt': _timestampIso(mission['createdAt']),
            'updatedAt': _timestampIso(mission['updatedAt']),
          };
        });
  }

  static Stream<List<Map<String, dynamic>>> watchMyHarmonyPracticeSubmissions({
    required String part,
  }) {
    final userId = uid;
    if (userId == null || part.trim().isEmpty) return Stream.value(const []);
    return _db
        .collection('harmony_practice_submissions')
        .where('churchId', isEqualTo: _requireChurchId())
        .where('userId', isEqualTo: userId)
        .limit(40)
        .snapshots()
        .asyncMap((snapshot) async {
          final submissions = <Map<String, dynamic>>[];
          for (final doc in snapshot.docs) {
            final data = doc.data();
            if ((data['part']?.toString() ?? '') != part) continue;
            final feedbackByData = await _safeUserData(data['feedbackBy']);
            submissions.add({
              'id': doc.id,
              ...data,
              'feedbackByName':
                  data['feedbackByName'] ??
                  feedbackByData?['name'] ??
                  feedbackByData?['nickname'] ??
                  '',
              'createdAt': _timestampIso(data['createdAt']),
              'updatedAt': _timestampIso(data['updatedAt']),
              'feedbackAt': _timestampIso(data['feedbackAt']),
            });
          }
          submissions.sort(_createdAtDesc);
          return submissions;
        });
  }

  static Future<String> createHarmonyPracticeSubmission({
    required String part,
    required String title,
    required String audioUrl,
    required String audioFileName,
    required String mrAudioUrl,
    required String mrAudioFileName,
    required int durationSeconds,
    String? missionId,
    String? missionTitle,
    int xpAwarded = 25,
  }) async {
    if (uid == null) throw Exception('로그인이 필요합니다');
    final churchId = _requireChurchId();
    final safeXp = xpAwarded.clamp(5, 250).toInt();
    final userData = await _safeUserData(uid);
    final todayKey = _todayKey();
    final submissionRef = _db.collection('harmony_practice_submissions').doc();
    final progressRef = _db.collection('harmony_practice_progress').doc(uid);
    final batch = _db.batch();

    batch.set(submissionRef, {
      'churchId': churchId,
      'userId': uid,
      'part': part,
      'title': title.trim().isEmpty ? '개인연습' : title.trim(),
      'missionId': missionId?.trim() ?? '',
      'missionTitle': missionTitle?.trim() ?? '',
      'audioUrl': audioUrl,
      'audioFileName': audioFileName,
      'mrAudioUrl': mrAudioUrl,
      'mrAudioFileName': mrAudioFileName,
      'durationSeconds': durationSeconds,
      'xpAwarded': safeXp,
      'practiceDate': todayKey,
      'status': 'pending_feedback',
      'leaderFeedback': '',
      ..._authorFields({
        'userId': uid,
        'userName': currentUser?.displayName,
      }, userData),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    batch.set(progressRef, {
      'churchId': churchId,
      'userId': uid,
      'part': part,
      'xp': FieldValue.increment(safeXp),
      'practiceCount': FieldValue.increment(1),
      'lastPracticeDate': todayKey,
      'practiceDates': FieldValue.arrayUnion([todayKey]),
      'completedTutorialSteps': {
        'mrRecording': true,
        'dailyMission': true,
        'feedbackRequest': true,
      },
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();
    return submissionRef.id;
  }

  static Stream<List<Map<String, dynamic>>> watchHarmonyNotes({
    required String part,
  }) {
    if (part.trim().isEmpty) return Stream.value(const []);
    return _db
        .collection('harmony_notes')
        .where('churchId', isEqualTo: _requireChurchId())
        .where('part', isEqualTo: part)
        .limit(80)
        .snapshots()
        .asyncMap((snapshot) async {
          final notes = <Map<String, dynamic>>[];
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final userData = await _safeUserData(data['userId']);
            notes.add({
              'id': doc.id,
              ...data,
              ..._authorFields(data, userData),
              'createdAt': _timestampIso(data['createdAt']),
            });
          }
          notes.sort(_createdAtDesc);
          return notes;
        });
  }

  static Future<String> uploadHarmonyAudio(
    Uint8List bytes, {
    required String fileName,
    required String contentType,
    UploadProgress? onProgress,
  }) async {
    if (uid == null) throw Exception('로그인이 필요합니다');
    if (bytes.length > 50 * 1024 * 1024) {
      throw Exception('음성 파일은 50MB 이하로 올려주세요');
    }
    final churchId = _requireChurchId();
    final safeName = _safeStorageName(fileName);
    final ref = FirebaseStorage.instance
        .ref()
        .child('churches')
        .child(churchId)
        .child('harmony_audio')
        .child(uid!)
        .child('${DateTime.now().millisecondsSinceEpoch}_$safeName');
    final task = ref.putData(
      bytes,
      SettableMetadata(
        contentType: contentType,
        customMetadata: {
          'churchId': churchId,
          'userId': uid!,
          'originalName': fileName,
        },
      ),
    );
    await _waitUpload(task, onProgress: onProgress);
    return ref.getDownloadURL();
  }

  static Future<String> createHarmonyNote({
    required String part,
    required String title,
    required String audioUrl,
    required String audioFileName,
    String? prompt,
  }) async {
    if (uid == null) throw Exception('로그인이 필요합니다');
    final userData = await _safeUserData(uid);
    final data = {
      'churchId': _requireChurchId(),
      'userId': uid,
      'part': part,
      'title': title.trim(),
      'prompt': prompt?.trim() ?? '',
      'audioUrl': audioUrl,
      'audioFileName': audioFileName,
      ..._authorFields({
        'userId': uid,
        'userName': currentUser?.displayName,
      }, userData),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final doc = await _db.collection('harmony_notes').add(data);
    return doc.id;
  }

  static Future<void> deleteHarmonyNote(String noteId) async {
    await _db.collection('harmony_notes').doc(noteId).delete();
  }

  static Stream<List<Map<String, dynamic>>> watchHarmonyRelays({
    required String part,
  }) {
    if (part.trim().isEmpty) return Stream.value(const []);
    return _db
        .collection('harmony_relays')
        .where('churchId', isEqualTo: _requireChurchId())
        .where('part', isEqualTo: part)
        .limit(30)
        .snapshots()
        .asyncMap((snapshot) async {
          final relays = <Map<String, dynamic>>[];
          List<Map<String, dynamic>>? sheetMusicCache;
          Future<List<Map<String, dynamic>>> loadSheetMusic() async {
            return sheetMusicCache ??= await getSheetMusic();
          }

          for (final doc in snapshot.docs) {
            var data = Map<String, dynamic>.from(doc.data());
            if (_harmonyRelayNeedsGuideFallback(data)) {
              data = _mergeHarmonyRelayGuideFallback(
                data,
                await loadSheetMusic(),
                part,
              );
            }
            final clipsSnapshot = await _db
                .collection('harmony_relay_clips')
                .where('churchId', isEqualTo: _requireChurchId())
                .where('relayId', isEqualTo: doc.id)
                .where('part', isEqualTo: part)
                .get();
            final clips = <Map<String, dynamic>>[];
            for (final clipDoc in clipsSnapshot.docs) {
              final clipData = clipDoc.data();
              final userData = await _safeUserData(clipData['userId']);
              clips.add({
                'id': clipDoc.id,
                ...clipData,
                ..._authorFields(clipData, userData),
                'createdAt': _timestampIso(clipData['createdAt']),
              });
            }
            clips.sort((a, b) => _timestampFieldAsc('createdAt', a, b));
            relays.add({
              'id': doc.id,
              ...data,
              'clips': clips,
              'createdAt': _timestampIso(data['createdAt']),
              'lastClipAt': _timestampIso(data['lastClipAt']),
            });
          }
          relays.sort((a, b) {
            final byLast = _timestampFieldDesc('lastClipAt', a, b);
            return byLast == 0 ? _createdAtDesc(a, b) : byLast;
          });
          return relays;
        });
  }

  static Future<Map<String, dynamic>?> getLatestPartGuideForRelay({
    required String part,
  }) async {
    if (part.trim().isEmpty) return null;
    final eventGuide = await _latestEventHarmonyGuideForRelay(part: part);
    if (eventGuide != null) return eventGuide;

    final sheets = await getSheetMusic();
    sheets.sort((a, b) {
      final aDate = _dateSortValue(a['sheetDate'], fallback: a['createdAt']);
      final bDate = _dateSortValue(b['sheetDate'], fallback: b['createdAt']);
      return bDate.compareTo(aDate);
    });

    for (final sheet in sheets) {
      final sheetPart = sheet['sheetPart']?.toString() ?? 'all';
      final songTitle = _firstNotEmpty([
        sheet['songTitle']?.toString(),
        sheet['title']?.toString(),
        '파트 가이드',
      ]);
      final sheetDate = sheet['sheetDate']?.toString() ?? '';
      final conductorComment = sheet['conductorComment']?.toString() ?? '';
      final harmonySegments = _harmonySegmentsForPart(sheet, part);

      if (sheetPart == part) {
        final guideUrl = sheet['audioUrl']?.toString() ?? '';
        final mrUrl = sheet['mrAudioUrl']?.toString() ?? '';
        if (guideUrl.isNotEmpty || mrUrl.isNotEmpty) {
          return {
            'sheetMusicId': sheet['id'],
            'title': songTitle,
            'songTitle': songTitle,
            'sheetDate': sheetDate,
            'part': part,
            'guideAudioUrl': guideUrl,
            'guideAudioFileName': sheet['audioFileName']?.toString() ?? '',
            'mrAudioUrl': mrUrl,
            'mrAudioFileName': sheet['mrAudioFileName']?.toString() ?? '',
            'guide': conductorComment,
            'lyricsText': sheet['lyricsText']?.toString() ?? '',
            'lyricsTimeline': _lyricsTimelineFromValue(sheet['lyricsTimeline']),
            'lyricLines': _lyricLinesFromText(
              sheet['lyricsText']?.toString() ?? '',
            ),
            'composer': sheet['composer']?.toString() ?? '',
            'sheetUrl': sheet['fileUrl']?.toString() ?? '',
            'sourcePollId': sheet['sourcePollId']?.toString() ?? '',
            'sourceEventId': sheet['sourceEventId']?.toString() ?? '',
            'segments': harmonySegments,
          };
        }
      }

      final partFiles = _asStringMap(sheet['partFiles']);
      final partFile = _asStringMap(partFiles[part]);
      final guideUrl = _firstNotEmpty([
        partFile['guideAudioUrl']?.toString(),
        sheet['audioUrl']?.toString(),
      ]);
      final mrUrl = _firstNotEmpty([
        partFile['mrAudioUrl']?.toString(),
        sheet['mrAudioUrl']?.toString(),
      ]);
      if (guideUrl.isNotEmpty || mrUrl.isNotEmpty) {
        final mainSheetUrl = sheet['fileUrl']?.toString() ?? '';
        final partSheetUrl = partFile['sheetUrl']?.toString() ?? '';
        final partLyricsText = _firstNotEmpty([
          partFile['lyricsText']?.toString(),
          sheet['lyricsText']?.toString(),
        ]);
        final partLyricsTimeline = _lyricsTimelineFromValue(
          partFile['lyricsTimeline'],
        );
        final sheetLyricsTimeline = _lyricsTimelineFromValue(
          sheet['lyricsTimeline'],
        );
        return {
          'sheetMusicId': sheet['id'],
          'title': songTitle,
          'songTitle': songTitle,
          'sheetDate': sheetDate,
          'part': part,
          'guideAudioUrl': guideUrl,
          'guideAudioFileName': _firstNotEmpty([
            partFile['guideAudioFileName']?.toString(),
            sheet['audioFileName']?.toString(),
          ]),
          'mrAudioUrl': mrUrl,
          'mrAudioFileName': _firstNotEmpty([
            partFile['mrAudioFileName']?.toString(),
            sheet['mrAudioFileName']?.toString(),
          ]),
          'guide': conductorComment,
          'lyricsText': partLyricsText,
          'lyricsTimeline': partLyricsTimeline.isNotEmpty
              ? partLyricsTimeline
              : sheetLyricsTimeline,
          'lyricLines': _lyricLinesFromText(partLyricsText),
          'composer': sheet['composer']?.toString() ?? '',
          'sheetUrl': partSheetUrl.isNotEmpty ? partSheetUrl : mainSheetUrl,
          'sourcePollId': sheet['sourcePollId']?.toString() ?? '',
          'sourceEventId': sheet['sourceEventId']?.toString() ?? '',
          'segments': harmonySegments,
        };
      }
    }
    return null;
  }

  static Future<Map<String, dynamic>?> _latestEventHarmonyGuideForRelay({
    required String part,
  }) async {
    final events = await getEvents();
    final candidates = events.where((event) {
      final enabled = event['harmonyEnabled'] == true;
      final guide = event['harmonyGuide']?.toString().trim() ?? '';
      final lyrics = event['harmonyLyricsText']?.toString().trim() ?? '';
      return enabled && (guide.isNotEmpty || lyrics.isNotEmpty);
    }).toList();
    if (candidates.isEmpty) return null;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    candidates.sort((a, b) {
      final aDate = _dateSortValue(a['eventDate'] ?? a['date']);
      final bDate = _dateSortValue(b['eventDate'] ?? b['date']);
      final aDay = DateTime(aDate.year, aDate.month, aDate.day);
      final bDay = DateTime(bDate.year, bDate.month, bDate.day);
      final aPast = aDay.isBefore(today);
      final bPast = bDay.isBefore(today);
      if (aPast != bPast) return aPast ? 1 : -1;
      return aPast ? bDate.compareTo(aDate) : aDate.compareTo(bDate);
    });

    final event = candidates.first;
    final title = _firstNotEmpty([
      event['harmonyTitle']?.toString(),
      event['title']?.toString(),
      '오늘의 일정',
    ]);
    final lyricsText = event['harmonyLyricsText']?.toString() ?? '';
    final timeline = _lyricsTimelineFromValue(event['harmonyLyricsTimeline']);
    return {
      'title': title,
      'songTitle': title,
      'eventId': event['id']?.toString() ?? '',
      'eventDate':
          event['eventDate']?.toString() ?? event['date']?.toString() ?? '',
      'sheetDate':
          event['eventDate']?.toString() ?? event['date']?.toString() ?? '',
      'guide': event['harmonyGuide']?.toString() ?? '',
      'lyricsText': lyricsText,
      'lyricsTimeline': timeline,
      'lyricLines': _lyricLinesFromText(lyricsText),
      'sourceEventId': event['id']?.toString() ?? '',
      'segments': _harmonySegmentsForPart(event, part),
    };
  }

  static Future<String> createHarmonyRelayFromGuide({
    required String part,
    required Map<String, dynamic> guide,
  }) async {
    final sourceId = guide['sheetMusicId']?.toString() ?? '';
    final churchId = _requireChurchId();
    final title = _firstNotEmpty([
      guide['songTitle']?.toString(),
      guide['title']?.toString(),
      '오늘의 가이드',
    ]);
    final sheetDate = guide['sheetDate']?.toString() ?? '';
    final sourceEventId = guide['sourceEventId']?.toString() ?? '';
    final sourcePollId = guide['sourcePollId']?.toString() ?? '';
    final missionSourceId = sourceId.isNotEmpty ? sourceId : sourceEventId;
    final rawSegments = (guide['segments'] as List?) ?? const [];
    final lyricLines = _lyricLinesFromText(
      guide['lyricsText']?.toString() ?? '',
    );
    final lyricTimeline = _lyricsTimelineFromValue(guide['lyricsTimeline']);
    final segments =
        rawSegments
            .whereType<Map>()
            .map((segment) => Map<String, dynamic>.from(segment))
            .toList()
          ..sort((a, b) {
            final aOrder = (a['order'] as num?)?.toInt() ?? 0;
            final bOrder = (b['order'] as num?)?.toInt() ?? 0;
            return aOrder.compareTo(bOrder);
          });

    if (missionSourceId.isNotEmpty && segments.isNotEmpty) {
      final missionGroupId = '${missionSourceId}_$part';
      final existing = await _db
          .collection('harmony_relays')
          .where('churchId', isEqualTo: churchId)
          .where('part', isEqualTo: part)
          .where('missionGroupId', isEqualTo: missionGroupId)
          .get();
      final existingBySegment =
          <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
      for (final doc in existing.docs) {
        final data = doc.data();
        if (data['churchId'] == churchId && data['part'] == part) {
          existingBySegment[data['segmentId']?.toString() ?? ''] = doc;
        }
      }

      final createdIds = <String>[];
      final notifiedUsers = <String>{};
      var handoffSeeded = false;
      for (var index = 0; index < segments.length; index += 1) {
        final segment = segments[index];
        final segmentId = _firstNotEmpty([
          segment['id']?.toString(),
          'seg-${(index + 1).toString().padLeft(2, '0')}',
        ]);
        final label = _firstNotEmpty([
          segment['label']?.toString(),
          '${index + 1}소절',
        ]);
        final segmentLyricsLine =
            segment['lyricsLine']?.toString().trim() ?? '';
        final segmentNextLyricsLine =
            segment['nextLyricsLine']?.toString().trim() ?? '';
        final existingDoc = existingBySegment[segmentId];
        if (existingDoc != null) {
          final existingData = existingDoc.data();
          final currentAssigneeId =
              existingData['currentAssigneeId']?.toString() ?? '';
          final existingCompleted = _harmonyRelayDataCompleted(existingData);
          final shouldAssign =
              !handoffSeeded && currentAssigneeId.isEmpty && !existingCompleted;
          final assignee = shouldAssign
              ? await _pickHarmonyAssignee(
                  part: part,
                  sourcePollId: sourcePollId,
                  excludeUserIds: {uid},
                )
              : null;
          await existingDoc.reference.update({
            'guideAudioUrl': guide['guideAudioUrl']?.toString() ?? '',
            'guideAudioFileName': guide['guideAudioFileName']?.toString() ?? '',
            'mrAudioUrl': guide['mrAudioUrl']?.toString() ?? '',
            'mrAudioFileName': guide['mrAudioFileName']?.toString() ?? '',
            'sourceSheetMusicId': sourceId,
            'sourceTitle': title,
            'sourceDate': sheetDate,
            'sourceSheetUrl': guide['sheetUrl']?.toString() ?? '',
            'sourcePollId': sourcePollId,
            'sourceEventId': sourceEventId,
            'lyricsText': guide['lyricsText']?.toString() ?? '',
            'lyricsTimeline': lyricTimeline,
            'lyricsLine': _firstNotEmpty([
              segmentLyricsLine,
              _lyricLineForSegment(
                lyricTimeline,
                lyricLines,
                index,
                (segment['startSec'] as num?)?.toDouble() ?? 0,
                (segment['endSec'] as num?)?.toDouble() ?? 0,
              ),
            ]),
            'nextLyricsLine': _firstNotEmpty([
              segmentNextLyricsLine,
              _nextLyricLineForSegment(
                lyricTimeline,
                lyricLines,
                index,
                (segment['endSec'] as num?)?.toDouble() ?? 0,
              ),
            ]),
            'missionTotalSegments': segments.length,
            'segmentOrder': (segment['order'] as num?)?.toInt() ?? index + 1,
            'segmentStartSec': (segment['startSec'] as num?)?.toDouble() ?? 0,
            'segmentEndSec': (segment['endSec'] as num?)?.toDouble() ?? 0,
            'segmentDurationSec':
                (segment['durationSec'] as num?)?.toDouble() ?? 0,
            if (assignee != null) ...{
              'currentAssigneeId': assignee['id']?.toString() ?? '',
              'currentAssigneeName': assignee['name']?.toString() ?? '',
              'assignedAt': FieldValue.serverTimestamp(),
            },
            'updatedAt': FieldValue.serverTimestamp(),
          });
          createdIds.add(existingDoc.id);
          final assigneeId = assignee?['id']?.toString() ?? '';
          if (assigneeId.isNotEmpty && notifiedUsers.add(assigneeId)) {
            await _createRelayNotification(
              toUserId: assigneeId,
              relayId: existingDoc.id,
              title: '하모니 릴레이 미션이 열렸어요',
              body: '$title $label을 이어서 불러주세요.',
            );
          }
          if (!existingCompleted &&
              (currentAssigneeId.isNotEmpty || assignee != null)) {
            handoffSeeded = true;
          }
          continue;
        }

        final assignee = handoffSeeded
            ? null
            : await _pickHarmonyAssignee(
                part: part,
                sourcePollId: sourcePollId,
                excludeUserIds: {uid},
              );
        final relayId = await createHarmonyRelay(
          part: part,
          title: '$title 릴레이',
          segmentLabel: label,
          guide: guide['guide']?.toString(),
          guideAudioUrl: guide['guideAudioUrl']?.toString(),
          guideAudioFileName: guide['guideAudioFileName']?.toString(),
          mrAudioUrl: guide['mrAudioUrl']?.toString(),
          mrAudioFileName: guide['mrAudioFileName']?.toString(),
          sourceSheetMusicId: sourceId,
          sourceTitle: title,
          sourceDate: sheetDate,
          sourceSheetUrl: guide['sheetUrl']?.toString(),
          sourcePollId: sourcePollId,
          sourceEventId: sourceEventId,
          lyricsText: guide['lyricsText']?.toString(),
          lyricsTimeline: lyricTimeline,
          lyricsLine: _firstNotEmpty([
            segmentLyricsLine,
            _lyricLineForSegment(
              lyricTimeline,
              lyricLines,
              index,
              (segment['startSec'] as num?)?.toDouble() ?? 0,
              (segment['endSec'] as num?)?.toDouble() ?? 0,
            ),
          ]),
          nextLyricsLine: _firstNotEmpty([
            segmentNextLyricsLine,
            _nextLyricLineForSegment(
              lyricTimeline,
              lyricLines,
              index,
              (segment['endSec'] as num?)?.toDouble() ?? 0,
            ),
          ]),
          currentAssigneeId: assignee?['id']?.toString(),
          currentAssigneeName: assignee?['name']?.toString(),
          missionGroupId: missionGroupId,
          missionTotalSegments: segments.length,
          segmentId: segmentId,
          segmentOrder: (segment['order'] as num?)?.toInt() ?? index + 1,
          segmentStartSec: (segment['startSec'] as num?)?.toDouble() ?? 0,
          segmentEndSec: (segment['endSec'] as num?)?.toDouble() ?? 0,
          segmentDurationSec: (segment['durationSec'] as num?)?.toDouble() ?? 0,
        );
        createdIds.add(relayId);
        final assigneeId = assignee?['id']?.toString() ?? '';
        if (assigneeId.isNotEmpty && notifiedUsers.add(assigneeId)) {
          await _createRelayNotification(
            toUserId: assigneeId,
            relayId: relayId,
            title: '하모니 릴레이 미션이 열렸어요',
            body: '$title $label을 이어서 불러주세요.',
          );
        }
        if (assignee != null) handoffSeeded = true;
      }
      if (createdIds.isNotEmpty) return createdIds.first;
    }

    if (sourceId.isNotEmpty) {
      final existing = await _db
          .collection('harmony_relays')
          .where('churchId', isEqualTo: churchId)
          .where('part', isEqualTo: part)
          .where('sourceSheetMusicId', isEqualTo: sourceId)
          .get();
      for (final doc in existing.docs) {
        final data = doc.data();
        if (data['churchId'] == churchId && data['part'] == part) {
          final currentAssigneeId = data['currentAssigneeId']?.toString() ?? '';
          final assignee =
              currentAssigneeId.isEmpty && !_harmonyRelayDataCompleted(data)
              ? await _pickHarmonyAssignee(
                  part: part,
                  sourcePollId: sourcePollId,
                  excludeUserIds: {uid},
                )
              : null;
          await doc.reference.update({
            'guideAudioUrl': guide['guideAudioUrl']?.toString() ?? '',
            'guideAudioFileName': guide['guideAudioFileName']?.toString() ?? '',
            'mrAudioUrl': guide['mrAudioUrl']?.toString() ?? '',
            'mrAudioFileName': guide['mrAudioFileName']?.toString() ?? '',
            'sourceSheetUrl': guide['sheetUrl']?.toString() ?? '',
            'sourcePollId': sourcePollId,
            'lyricsText': guide['lyricsText']?.toString() ?? '',
            'lyricsTimeline': lyricTimeline,
            'lyricsLine': _lyricLineForSegment(
              lyricTimeline,
              lyricLines,
              0,
              0,
              0,
            ),
            'nextLyricsLine': _nextLyricLineForSegment(
              lyricTimeline,
              lyricLines,
              0,
              0,
            ),
            if (assignee != null) ...{
              'currentAssigneeId': assignee['id']?.toString() ?? '',
              'currentAssigneeName': assignee['name']?.toString() ?? '',
              'assignedAt': FieldValue.serverTimestamp(),
            },
            'updatedAt': FieldValue.serverTimestamp(),
          });
          if (assignee != null) {
            await _createRelayNotification(
              toUserId: assignee['id'].toString(),
              relayId: doc.id,
              title: '파트 릴레이가 도착했어요',
              body: '$title 한 소절을 이어서 불러주세요.',
            );
          }
          return doc.id;
        }
      }
    }

    if (sourceEventId.isNotEmpty) {
      final existing = await _db
          .collection('harmony_relays')
          .where('churchId', isEqualTo: churchId)
          .where('part', isEqualTo: part)
          .where('sourceEventId', isEqualTo: sourceEventId)
          .get();
      for (final doc in existing.docs) {
        final data = doc.data();
        if (data['churchId'] == churchId && data['part'] == part) {
          final currentAssigneeId = data['currentAssigneeId']?.toString() ?? '';
          final assignee =
              currentAssigneeId.isEmpty && !_harmonyRelayDataCompleted(data)
              ? await _pickHarmonyAssignee(
                  part: part,
                  sourcePollId: sourcePollId,
                  excludeUserIds: {uid},
                )
              : null;
          await doc.reference.update({
            'guide': guide['guide']?.toString() ?? '',
            'sourcePollId': sourcePollId,
            'sourceEventId': sourceEventId,
            'lyricsText': guide['lyricsText']?.toString() ?? '',
            'lyricsTimeline': lyricTimeline,
            'lyricsLine': _lyricLineForSegment(
              lyricTimeline,
              lyricLines,
              0,
              0,
              0,
            ),
            'nextLyricsLine': _nextLyricLineForSegment(
              lyricTimeline,
              lyricLines,
              0,
              0,
            ),
            if (assignee != null) ...{
              'currentAssigneeId': assignee['id']?.toString() ?? '',
              'currentAssigneeName': assignee['name']?.toString() ?? '',
              'assignedAt': FieldValue.serverTimestamp(),
            },
            'updatedAt': FieldValue.serverTimestamp(),
          });
          if (assignee != null) {
            await _createRelayNotification(
              toUserId: assignee['id'].toString(),
              relayId: doc.id,
              title: '파트 릴레이가 도착했어요',
              body: '$title 한 소절을 이어서 불러주세요.',
            );
          }
          return doc.id;
        }
      }
    }

    final segmentLabel = sheetDate.isNotEmpty ? '$sheetDate 1소절' : '오늘의 1소절';
    final assignee = await _pickHarmonyAssignee(
      part: part,
      sourcePollId: sourcePollId,
      excludeUserIds: {uid},
    );

    final relayId = await createHarmonyRelay(
      part: part,
      title: '$title 릴레이',
      segmentLabel: segmentLabel,
      guide: guide['guide']?.toString(),
      guideAudioUrl: guide['guideAudioUrl']?.toString(),
      guideAudioFileName: guide['guideAudioFileName']?.toString(),
      mrAudioUrl: guide['mrAudioUrl']?.toString(),
      mrAudioFileName: guide['mrAudioFileName']?.toString(),
      sourceSheetMusicId: guide['sheetMusicId']?.toString(),
      sourceTitle: title,
      sourceDate: sheetDate,
      sourceSheetUrl: guide['sheetUrl']?.toString(),
      sourcePollId: sourcePollId,
      sourceEventId: sourceEventId,
      lyricsText: guide['lyricsText']?.toString(),
      lyricsTimeline: lyricTimeline,
      lyricsLine: _lyricLineForSegment(lyricTimeline, lyricLines, 0, 0, 0),
      nextLyricsLine: _nextLyricLineForSegment(lyricTimeline, lyricLines, 0, 0),
      currentAssigneeId: assignee?['id']?.toString(),
      currentAssigneeName: assignee?['name']?.toString(),
      missionGroupId: sourceId.isNotEmpty
          ? '${sourceId}_$part'
          : (sourceEventId.isNotEmpty ? '${sourceEventId}_$part' : null),
      missionTotalSegments: 1,
      segmentId: 'seg-01',
      segmentOrder: 1,
    );

    if (assignee != null) {
      await _createRelayNotification(
        toUserId: assignee['id'].toString(),
        relayId: relayId,
        title: '파트 릴레이가 도착했어요',
        body: '$title 한 소절을 이어서 불러주세요.',
      );
    }
    return relayId;
  }

  static Future<String> createHarmonyRelay({
    required String part,
    required String title,
    required String segmentLabel,
    String? guide,
    String? guideAudioUrl,
    String? guideAudioFileName,
    String? mrAudioUrl,
    String? mrAudioFileName,
    String? sourceSheetMusicId,
    String? sourceTitle,
    String? sourceDate,
    String? sourceSheetUrl,
    String? sourcePollId,
    String? sourceEventId,
    String? lyricsText,
    List<Map<String, dynamic>> lyricsTimeline = const [],
    String? lyricsLine,
    String? nextLyricsLine,
    String? currentAssigneeId,
    String? currentAssigneeName,
    String? missionGroupId,
    int? missionTotalSegments,
    String? segmentId,
    int? segmentOrder,
    double? segmentStartSec,
    double? segmentEndSec,
    double? segmentDurationSec,
  }) async {
    if (uid == null) throw Exception('로그인이 필요합니다');
    final userData = await _safeUserData(uid);
    final data = {
      'churchId': _requireChurchId(),
      'userId': uid,
      'part': part,
      'title': title.trim(),
      'segmentLabel': segmentLabel.trim(),
      'guide': guide?.trim() ?? '',
      'guideAudioUrl': guideAudioUrl?.trim() ?? '',
      'guideAudioFileName': guideAudioFileName?.trim() ?? '',
      'mrAudioUrl': mrAudioUrl?.trim() ?? '',
      'mrAudioFileName': mrAudioFileName?.trim() ?? '',
      'sourceSheetMusicId': sourceSheetMusicId?.trim() ?? '',
      'sourceTitle': sourceTitle?.trim() ?? '',
      'sourceDate': sourceDate?.trim() ?? '',
      'sourceSheetUrl': sourceSheetUrl?.trim() ?? '',
      'sourcePollId': sourcePollId?.trim() ?? '',
      'sourceEventId': sourceEventId?.trim() ?? '',
      'lyricsText': lyricsText?.trim() ?? '',
      'lyricsTimeline': lyricsTimeline,
      'lyricsLine': lyricsLine?.trim() ?? '',
      'nextLyricsLine': nextLyricsLine?.trim() ?? '',
      'missionGroupId': missionGroupId?.trim() ?? '',
      'missionTotalSegments': missionTotalSegments ?? 1,
      'segmentId': segmentId?.trim() ?? '',
      'segmentOrder': segmentOrder ?? 1,
      'segmentStartSec': segmentStartSec ?? 0,
      'segmentEndSec': segmentEndSec ?? 0,
      'segmentDurationSec': segmentDurationSec ?? 0,
      'status': 'open',
      'currentAssigneeId': currentAssigneeId?.trim() ?? '',
      'currentAssigneeName': currentAssigneeName?.trim() ?? '',
      'assignedAt': currentAssigneeId?.trim().isNotEmpty == true
          ? FieldValue.serverTimestamp()
          : null,
      'clipCount': 0,
      ..._authorFields({
        'userId': uid,
        'userName': currentUser?.displayName,
      }, userData),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final doc = await _db.collection('harmony_relays').add(data);
    return doc.id;
  }

  static Future<String> addHarmonyRelayClip({
    required String relayId,
    required String part,
    required String audioUrl,
    required String audioFileName,
    required int durationSeconds,
    String? note,
  }) async {
    if (uid == null) throw Exception('로그인이 필요합니다');
    final churchId = _requireChurchId();
    final userData = await _safeUserData(uid);
    final relayRef = _db.collection('harmony_relays').doc(relayId);
    final relayDoc = await relayRef.get();
    final relayData = relayDoc.data();
    _ensureHarmonyRelayCanReceiveClip(
      relayData: relayData,
      churchId: churchId,
      userData: userData,
    );
    final score = _relayScore(durationSeconds);
    final feedback = _relayFeedback(durationSeconds);
    final clipData = {
      'churchId': churchId,
      'relayId': relayId,
      'userId': uid,
      'part': part,
      'audioUrl': audioUrl,
      'audioFileName': audioFileName,
      'durationSeconds': durationSeconds,
      'note': note?.trim() ?? '',
      'autoScore': score,
      'autoFeedback': feedback,
      ..._authorFields({
        'userId': uid,
        'userName': currentUser?.displayName,
      }, userData),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final clipRef = _db.collection('harmony_relay_clips').doc();
    final isSegmentMission =
        (relayData?['missionGroupId']?.toString() ?? '').isNotEmpty;
    final sourcePollId = relayData?['sourcePollId']?.toString() ?? '';
    final previousAssigneeId =
        relayData?['currentAssigneeId']?.toString() ?? '';
    final handoffExcludeUserIds = {
      uid,
      if (previousAssigneeId.isNotEmpty) previousAssigneeId,
    };
    final assignee = isSegmentMission
        ? null
        : await _pickHarmonyAssignee(
            part: part,
            sourcePollId: sourcePollId,
            excludeUserIds: handoffExcludeUserIds,
          );
    final completedRelayDoc = await _db
        .runTransaction<DocumentSnapshot<Map<String, dynamic>>>((
          transaction,
        ) async {
          final latestRelayDoc = await transaction.get(relayRef);
          _ensureHarmonyRelayCanReceiveClip(
            relayData: latestRelayDoc.data(),
            churchId: churchId,
            userData: userData,
          );
          transaction.set(clipRef, clipData);
          transaction.update(relayRef, {
            'clipCount': FieldValue.increment(1),
            'lastClipAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'status': 'completed',
            'completedBy': uid,
            'completedByName':
                userData?['name'] ?? currentUser?.displayName ?? '파트원',
            'completedAt': FieldValue.serverTimestamp(),
            if (!isSegmentMission) ...{
              'currentAssigneeId': assignee?['id'] ?? '',
              'currentAssigneeName': assignee?['name'] ?? '',
              'assignedAt': assignee == null
                  ? null
                  : FieldValue.serverTimestamp(),
            },
          });
          return latestRelayDoc;
        });
    if (isSegmentMission) {
      try {
        await _advanceHarmonyMissionAssignee(
          completedRelayDoc: completedRelayDoc,
          part: part,
          sourcePollId: sourcePollId,
          excludeUserIds: handoffExcludeUserIds,
        );
      } catch (_) {
        // Saving the recording is the primary action. Handoff can recover later.
      }
    } else if (assignee != null) {
      try {
        await _createRelayNotification(
          toUserId: assignee['id'].toString(),
          relayId: relayId,
          title: '다음 릴레이 차례예요',
          body:
              '${userData?['name'] ?? currentUser?.displayName ?? '파트원'}님이 소절을 이어 불렀어요.',
        );
      } catch (_) {
        // Notification failure should not make the upload look unsaved.
      }
    }
    return clipRef.id;
  }

  static Future<void> _advanceHarmonyMissionAssignee({
    required DocumentSnapshot<Map<String, dynamic>> completedRelayDoc,
    required String part,
    required String sourcePollId,
    required Set<String?> excludeUserIds,
  }) async {
    final completedData = completedRelayDoc.data() ?? {};
    final missionGroupId = completedData['missionGroupId']?.toString() ?? '';
    if (missionGroupId.isEmpty) return;

    final churchId = _requireChurchId();
    final snapshot = await _db
        .collection('harmony_relays')
        .where('churchId', isEqualTo: churchId)
        .where('part', isEqualTo: part)
        .where('missionGroupId', isEqualTo: missionGroupId)
        .get();
    final relays =
        snapshot.docs
            .where((doc) => doc.data()['churchId'] == churchId)
            .toList()
          ..sort((a, b) {
            final aOrder = (a.data()['segmentOrder'] as num?)?.toInt() ?? 0;
            final bOrder = (b.data()['segmentOrder'] as num?)?.toInt() ?? 0;
            return aOrder.compareTo(bOrder);
          });
    final currentIndex = relays.indexWhere(
      (doc) => doc.id == completedRelayDoc.id,
    );
    if (currentIndex < 0) return;

    QueryDocumentSnapshot<Map<String, dynamic>>? nextDoc;
    for (var index = currentIndex + 1; index < relays.length; index += 1) {
      final candidate = relays[index];
      if (!_harmonyRelayDataCompleted(candidate.data())) {
        nextDoc = candidate;
        break;
      }
    }
    if (nextDoc == null) return;

    final nextData = nextDoc.data();
    final existingAssigneeId =
        nextData['currentAssigneeId']?.toString().trim() ?? '';
    final existingAssigneeName =
        nextData['currentAssigneeName']?.toString().trim() ?? '';
    if (existingAssigneeId.isNotEmpty) {
      try {
        await _createRelayNotification(
          toUserId: existingAssigneeId,
          relayId: nextDoc.id,
          title: '다음 릴레이 차례예요',
          body:
              '${nextData['segmentLabel'] ?? '다음 소절'}을 이어서 불러주세요.${existingAssigneeName.isEmpty ? '' : ' ($existingAssigneeName)'}',
        );
      } catch (_) {
        // Notification failure should not block the completed recording.
      }
      return;
    }

    final alreadyRecordedUserIds = <String?>{...excludeUserIds};
    for (final relay in relays.take(currentIndex + 1)) {
      final relayData = relay.data();
      final completedBy = relayData['completedBy']?.toString() ?? '';
      if (completedBy.isNotEmpty) alreadyRecordedUserIds.add(completedBy);
    }
    final assignee = await _pickHarmonyAssignee(
      part: part,
      sourcePollId: (nextData['sourcePollId']?.toString() ?? '').isNotEmpty
          ? nextData['sourcePollId']?.toString()
          : sourcePollId,
      excludeUserIds: alreadyRecordedUserIds,
    );
    if (assignee == null) return;

    await nextDoc.reference.update({
      'currentAssigneeId': assignee['id']?.toString() ?? '',
      'currentAssigneeName': assignee['name']?.toString() ?? '',
      'assignedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    try {
      await _createRelayNotification(
        toUserId: assignee['id'].toString(),
        relayId: nextDoc.id,
        title: '다음 릴레이 차례예요',
        body: '${nextData['segmentLabel'] ?? '다음 소절'}을 이어서 불러주세요.',
      );
    } catch (_) {
      // Notification failure should not block the next assignee update.
    }
  }

  static Stream<Map<String, int>> watchHarmonyMvpVotes({
    required String missionGroupId,
    required String part,
  }) {
    if (missionGroupId.trim().isEmpty) return Stream.value(const {});
    return _db
        .collection('harmony_relay_votes')
        .where('churchId', isEqualTo: _requireChurchId())
        .where('missionGroupId', isEqualTo: missionGroupId)
        .where('part', isEqualTo: part)
        .snapshots()
        .map((snapshot) {
          final counts = <String, int>{};
          for (final doc in snapshot.docs) {
            final nomineeId = doc.data()['nomineeUserId']?.toString() ?? '';
            if (nomineeId.isEmpty) continue;
            counts[nomineeId] = (counts[nomineeId] ?? 0) + 1;
          }
          return counts;
        });
  }

  static Future<void> voteHarmonyMvp({
    required String missionGroupId,
    required String part,
    required String nomineeUserId,
    required String nomineeName,
  }) async {
    if (uid == null) throw Exception('로그인이 필요합니다');
    if (missionGroupId.trim().isEmpty || nomineeUserId.trim().isEmpty) {
      throw Exception('투표할 단원을 선택해주세요');
    }
    final churchId = _requireChurchId();
    await _db
        .collection('harmony_relay_votes')
        .doc('${missionGroupId}_$uid')
        .set({
          'churchId': churchId,
          'missionGroupId': missionGroupId,
          'part': part,
          'voterId': uid,
          'nomineeUserId': nomineeUserId,
          'nomineeName': nomineeName,
          'updatedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  static bool _harmonyRelayDataCompleted(Map<String, dynamic> data) {
    final clips = ((data['clips'] as List?) ?? const []);
    return clips.isNotEmpty || data['status']?.toString() == 'completed';
  }

  static bool _canAdminModifyHarmonyRelay(Map<String, dynamic>? userData) {
    final role = userData?['role']?.toString() ?? '';
    final email = currentUser?.email?.toLowerCase() ?? '';
    return userData?['isPlatformAdmin'] == true ||
        email == 'sinbun001@gmail.com' ||
        role == 'admin' ||
        role == 'church_admin';
  }

  static void _ensureHarmonyRelayCanReceiveClip({
    required Map<String, dynamic>? relayData,
    required String churchId,
    required Map<String, dynamic>? userData,
  }) {
    if (relayData == null) {
      throw Exception('릴레이 정보를 찾을 수 없습니다.');
    }
    final relayChurchId = relayData['churchId']?.toString() ?? '';
    if (relayChurchId.isNotEmpty && relayChurchId != churchId) {
      throw Exception('릴레이 교회 정보가 맞지 않습니다.');
    }
    if (_harmonyRelayDataCompleted(relayData) &&
        !_canAdminModifyHarmonyRelay(userData)) {
      throw Exception('완료된 릴레이 녹음은 관리자만 수정할 수 있어요.');
    }
  }

  static Future<Map<String, dynamic>?> _pickHarmonyAssignee({
    required String part,
    String? sourcePollId,
    Set<String?> excludeUserIds = const {},
  }) async {
    final churchId = _requireChurchId();
    Set<String>? attendeeIds;
    final pollId = sourcePollId?.trim() ?? '';
    if (pollId.isNotEmpty) {
      final votesSnapshot = await _db
          .collection('poll_votes')
          .where('churchId', isEqualTo: churchId)
          .where('pollId', isEqualTo: pollId)
          .get();
      attendeeIds = votesSnapshot.docs
          .where((doc) {
            final data = doc.data();
            final userId =
                data['userId']?.toString() ?? data['voterId']?.toString() ?? '';
            return data['churchId'] == churchId &&
                data['choice'] == 'attend' &&
                userId.isNotEmpty &&
                !excludeUserIds.contains(userId);
          })
          .map(
            (doc) =>
                doc.data()['userId']?.toString() ??
                doc.data()['voterId']?.toString() ??
                '',
          )
          .where((userId) => userId.isNotEmpty)
          .toSet();
      if (attendeeIds.isEmpty) return null;
    }
    final snapshot = await _db
        .collection('users')
        .where('churchId', isEqualTo: churchId)
        .get();
    final candidates = snapshot.docs
        .where((doc) {
          final data = doc.data();
          return data['part'] == part &&
              data['approvalStatus'] == 'approved' &&
              !excludeUserIds.contains(doc.id) &&
              (attendeeIds == null || attendeeIds.contains(doc.id));
        })
        .map((doc) => {'id': doc.id, ...doc.data()})
        .toList();
    if (candidates.isEmpty) return null;
    return candidates[Random().nextInt(candidates.length)];
  }

  static Future<void> _createRelayNotification({
    required String toUserId,
    required String relayId,
    required String title,
    required String body,
  }) async {
    await _db.collection('notifications').add({
      'churchId': _requireChurchId(),
      'toUserId': toUserId,
      'title': title,
      'body': body,
      'type': 'harmony_relay',
      'relayId': relayId,
      'sentAt': FieldValue.serverTimestamp(),
      'sentBy': uid,
    });
  }

  static DateTime _dateSortValue(dynamic value, {dynamic fallback}) {
    if (value is Timestamp) return value.toDate();
    final text = value?.toString() ?? '';
    final parsed = DateTime.tryParse(text);
    if (parsed != null) return parsed;
    if (fallback is Timestamp) return fallback.toDate();
    return DateTime.tryParse(fallback?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  static Map<String, dynamic> _asStringMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  static List<Map<String, dynamic>> _harmonySegmentsForPart(
    Map<String, dynamic> sheet,
    String part,
  ) {
    final harmonySegments = _asStringMap(sheet['harmonySegments']);
    final partSegments = _asStringMap(harmonySegments['parts']);
    final raw = partSegments[part] ?? partSegments['all'];
    if (raw is! List) {
      for (final value in partSegments.values) {
        if (value is List && value.isNotEmpty) {
          return value
              .whereType<Map>()
              .map((segment) => Map<String, dynamic>.from(segment))
              .toList()
            ..sort((a, b) {
              final aOrder = (a['order'] as num?)?.toInt() ?? 0;
              final bOrder = (b['order'] as num?)?.toInt() ?? 0;
              return aOrder.compareTo(bOrder);
            });
        }
      }
      return const [];
    }
    return raw
        .whereType<Map>()
        .map((segment) => Map<String, dynamic>.from(segment))
        .toList()
      ..sort((a, b) {
        final aOrder = (a['order'] as num?)?.toInt() ?? 0;
        final bOrder = (b['order'] as num?)?.toInt() ?? 0;
        return aOrder.compareTo(bOrder);
      });
  }

  static bool _harmonyRelayNeedsGuideFallback(Map<String, dynamic> relay) {
    final lyricsText = relay['lyricsText']?.toString().trim() ?? '';
    final lyricsLine = relay['lyricsLine']?.toString().trim() ?? '';
    final timeline = _lyricsTimelineFromValue(relay['lyricsTimeline']);
    final guideAudioUrl = relay['guideAudioUrl']?.toString().trim() ?? '';
    final mrAudioUrl = relay['mrAudioUrl']?.toString().trim() ?? '';
    return lyricsText.isEmpty ||
        lyricsLine.isEmpty ||
        timeline.isEmpty ||
        guideAudioUrl.isEmpty ||
        mrAudioUrl.isEmpty ||
        _isGenericHarmonySegmentLabel(relay['segmentLabel']?.toString() ?? '');
  }

  static Map<String, dynamic> _mergeHarmonyRelayGuideFallback(
    Map<String, dynamic> relay,
    List<Map<String, dynamic>> sheets,
    String part,
  ) {
    final sheet = _sheetForHarmonyRelay(relay, sheets);
    if (sheet == null) return relay;

    final partFiles = _asStringMap(sheet['partFiles']);
    final partFile = _asStringMap(partFiles[part]);
    final lyricsText = _firstNotEmpty([
      partFile['lyricsText']?.toString(),
      sheet['lyricsText']?.toString(),
    ]);
    final partTimeline = _lyricsTimelineFromValue(partFile['lyricsTimeline']);
    final sheetTimeline = _lyricsTimelineFromValue(sheet['lyricsTimeline']);
    final timeline = partTimeline.isNotEmpty ? partTimeline : sheetTimeline;
    final lyricLines = _lyricLinesFromText(lyricsText);
    final segments = _harmonySegmentsForPart(sheet, part);
    final segment = _matchingHarmonySegment(relay, segments);
    final order =
        (relay['segmentOrder'] as num?)?.toInt() ??
        (segment?['order'] as num?)?.toInt() ??
        1;
    final index = (order - 1).clamp(0, 10000);
    final startSec =
        (relay['segmentStartSec'] as num?)?.toDouble() ??
        (segment?['startSec'] as num?)?.toDouble() ??
        0;
    final endSec =
        (relay['segmentEndSec'] as num?)?.toDouble() ??
        (segment?['endSec'] as num?)?.toDouble() ??
        0;
    final lyricLine = _lyricLineForSegment(
      timeline,
      lyricLines,
      index,
      startSec,
      endSec,
    );
    final nextLyricLine = _nextLyricLineForSegment(
      timeline,
      lyricLines,
      index,
      endSec,
    );

    final merged = Map<String, dynamic>.from(relay);
    void putIfEmpty(String key, dynamic value) {
      final current = merged[key]?.toString().trim() ?? '';
      final next = value?.toString().trim() ?? '';
      if (current.isEmpty && next.isNotEmpty) merged[key] = value;
    }

    putIfEmpty(
      'guideAudioUrl',
      _firstNotEmpty([
        partFile['guideAudioUrl']?.toString(),
        sheet['audioUrl']?.toString(),
      ]),
    );
    putIfEmpty(
      'guideAudioFileName',
      _firstNotEmpty([
        partFile['guideAudioFileName']?.toString(),
        sheet['audioFileName']?.toString(),
      ]),
    );
    putIfEmpty(
      'mrAudioUrl',
      _firstNotEmpty([
        partFile['mrAudioUrl']?.toString(),
        sheet['mrAudioUrl']?.toString(),
      ]),
    );
    putIfEmpty(
      'mrAudioFileName',
      _firstNotEmpty([
        partFile['mrAudioFileName']?.toString(),
        sheet['mrAudioFileName']?.toString(),
      ]),
    );
    putIfEmpty('sourceSheetMusicId', sheet['id']?.toString());
    putIfEmpty('sourceTitle', sheet['songTitle']?.toString());
    putIfEmpty('sourceDate', sheet['sheetDate']?.toString());
    putIfEmpty(
      'sourceSheetUrl',
      _firstNotEmpty([
        partFile['sheetUrl']?.toString(),
        sheet['fileUrl']?.toString(),
      ]),
    );
    putIfEmpty('lyricsText', lyricsText);
    if (_lyricsTimelineFromValue(merged['lyricsTimeline']).isEmpty &&
        timeline.isNotEmpty) {
      merged['lyricsTimeline'] = timeline;
    }
    putIfEmpty('lyricsLine', lyricLine);
    putIfEmpty('nextLyricsLine', nextLyricLine);
    if (((merged['segmentStartSec'] as num?)?.toDouble() ?? 0) == 0 &&
        startSec > 0) {
      merged['segmentStartSec'] = startSec;
    }
    if (((merged['segmentEndSec'] as num?)?.toDouble() ?? 0) == 0 &&
        endSec > 0) {
      merged['segmentEndSec'] = endSec;
    }
    if (((merged['segmentDurationSec'] as num?)?.toDouble() ?? 0) == 0 &&
        endSec > startSec) {
      merged['segmentDurationSec'] = endSec - startSec;
    }
    final segmentLabel = merged['segmentLabel']?.toString() ?? '';
    if (_isGenericHarmonySegmentLabel(segmentLabel) && lyricLine.isNotEmpty) {
      merged['segmentLabel'] = '$order소절 · $lyricLine';
    }
    return merged;
  }

  static Map<String, dynamic>? _sheetForHarmonyRelay(
    Map<String, dynamic> relay,
    List<Map<String, dynamic>> sheets,
  ) {
    final sourceSheetId = relay['sourceSheetMusicId']?.toString().trim() ?? '';
    if (sourceSheetId.isNotEmpty) {
      for (final sheet in sheets) {
        if (sheet['id']?.toString() == sourceSheetId) return sheet;
      }
    }

    final sourcePollId = relay['sourcePollId']?.toString().trim() ?? '';
    if (sourcePollId.isNotEmpty) {
      for (final sheet in sheets) {
        if (sheet['sourcePollId']?.toString() == sourcePollId) return sheet;
      }
    }

    final title = _normalHarmonyTitle(
      _firstNotEmpty([
        relay['sourceTitle']?.toString(),
        relay['title']?.toString(),
      ]),
    );
    if (title.isEmpty) return null;
    for (final sheet in sheets) {
      final sheetTitle = _normalHarmonyTitle(
        _firstNotEmpty([
          sheet['songTitle']?.toString(),
          sheet['title']?.toString(),
        ]),
      );
      if (sheetTitle.isEmpty) continue;
      if (sheetTitle == title ||
          sheetTitle.contains(title) ||
          title.contains(sheetTitle)) {
        return sheet;
      }
    }
    return null;
  }

  static Map<String, dynamic>? _matchingHarmonySegment(
    Map<String, dynamic> relay,
    List<Map<String, dynamic>> segments,
  ) {
    if (segments.isEmpty) return null;
    final segmentId = relay['segmentId']?.toString().trim() ?? '';
    if (segmentId.isNotEmpty) {
      for (final segment in segments) {
        if (segment['id']?.toString() == segmentId) return segment;
      }
    }
    final order = (relay['segmentOrder'] as num?)?.toInt() ?? 0;
    if (order > 0) {
      for (final segment in segments) {
        if ((segment['order'] as num?)?.toInt() == order) return segment;
      }
      final index = order - 1;
      if (index >= 0 && index < segments.length) return segments[index];
    }
    return segments.first;
  }

  static bool _isGenericHarmonySegmentLabel(String label) {
    final trimmed = label.trim();
    if (trimmed.isEmpty || trimmed == '소절') return true;
    return RegExp(r'^\d+\s*소절$').hasMatch(trimmed);
  }

  static String _normalHarmonyTitle(String title) {
    return title
        .replaceAll('릴레이', '')
        .replaceAll(RegExp(r'\s+'), '')
        .trim()
        .toLowerCase();
  }

  static List<String> _lyricLinesFromText(String text) {
    return text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  static String _lyricLineForIndex(List<String> lines, int index) {
    if (index < 0 || index >= lines.length) return '';
    return lines[index];
  }

  static List<Map<String, dynamic>> _lyricsTimelineFromValue(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((entry) {
          return {
            'timeSec': (entry['timeSec'] as num?)?.toDouble() ?? 0,
            'text': entry['text']?.toString() ?? '',
          };
        })
        .where((entry) => (entry['text']?.toString() ?? '').trim().isNotEmpty)
        .toList()
      ..sort((a, b) {
        final at = (a['timeSec'] as num?)?.toDouble() ?? 0;
        final bt = (b['timeSec'] as num?)?.toDouble() ?? 0;
        return at.compareTo(bt);
      });
  }

  static String _lyricLineForSegment(
    List<Map<String, dynamic>> timeline,
    List<String> lines,
    int index,
    double startSec,
    double endSec,
  ) {
    if (timeline.isNotEmpty) {
      final inside = timeline.where((entry) {
        final time = (entry['timeSec'] as num?)?.toDouble() ?? 0;
        return time >= startSec && (endSec <= startSec || time < endSec);
      }).toList();
      if (inside.isNotEmpty) return inside.first['text']?.toString() ?? '';
      final previous = timeline.where((entry) {
        final time = (entry['timeSec'] as num?)?.toDouble() ?? 0;
        return time <= startSec;
      }).toList();
      if (previous.isNotEmpty) return previous.last['text']?.toString() ?? '';
    }
    return _lyricLineForIndex(lines, index);
  }

  static String _nextLyricLineForSegment(
    List<Map<String, dynamic>> timeline,
    List<String> lines,
    int index,
    double afterSec,
  ) {
    if (timeline.isNotEmpty) {
      final next = timeline.where((entry) {
        final time = (entry['timeSec'] as num?)?.toDouble() ?? 0;
        return time > afterSec;
      }).toList();
      if (next.isNotEmpty) return next.first['text']?.toString() ?? '';
    }
    return _lyricLineForIndex(lines, index + 1);
  }

  static String _firstNotEmpty(List<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isNotEmpty) return trimmed;
    }
    return '';
  }

  static int _relayScore(int durationSeconds) {
    if (durationSeconds <= 0) return 70;
    if (durationSeconds < 4) return 74;
    if (durationSeconds < 8) return 82;
    if (durationSeconds < 18) return 90;
    return 86;
  }

  static String _relayFeedback(int durationSeconds) {
    if (durationSeconds < 4) return '조금 짧아요. 다음에는 소절 끝까지 더 길게 이어보세요.';
    if (durationSeconds < 8) return '진입이 좋아요. 끝 음을 조금만 더 붙잡으면 안정적입니다.';
    if (durationSeconds < 18) return '호흡 길이와 연결감이 좋습니다. 다음 사람이 받기 편해요.';
    return '충분히 길게 불렀어요. 핵심 소절만 더 또렷하게 잘라보면 좋아요.';
  }

  static Future<String> createPost({
    required String title,
    String? content,
    String? imageUrl,
    String mediaType = 'photo',
    String? videoStatus,
    String? videoSourcePath,
    String? videoSourceUrl,
    String? videoUrl,
    int? videoTrimStartSec,
    int? videoTrimEndSec,
  }) async {
    final author = _authorFields({
      'userId': uid,
      'userName': currentUser?.displayName,
    }, await _safeUserData(uid));
    final postData = <String, dynamic>{
      'churchId': _requireChurchId(),
      'userId': uid,
      ...author,
      'title': title,
      'content': content,
      'imageUrl': imageUrl,
      'mediaType': mediaType,
      'reactionCounts': <String, int>{'like': 0, 'sad': 0, 'pray': 0},
      'commentCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (videoStatus != null) postData['videoStatus'] = videoStatus;
    if (videoSourcePath != null) postData['videoSourcePath'] = videoSourcePath;
    if (videoSourceUrl != null) postData['videoSourceUrl'] = videoSourceUrl;
    if (videoUrl != null) postData['videoUrl'] = videoUrl;
    if (videoTrimStartSec != null) {
      postData['videoTrimStartSec'] = videoTrimStartSec;
    }
    if (videoTrimEndSec != null) {
      postData['videoTrimEndSec'] = videoTrimEndSec;
    }
    final docRef = await _db.collection('posts').add(postData);
    return docRef.id;
  }

  static Future<void> markPostVideoProcessing(
    String postId, {
    required String sourcePath,
    String? sourceUrl,
  }) async {
    await _db.collection('posts').doc(postId).update({
      'videoSourcePath': sourcePath,
      if (sourceUrl != null && sourceUrl.trim().isNotEmpty) ...{
        'videoSourceUrl': sourceUrl,
        'videoUrl': sourceUrl,
      },
      'videoStatus': 'processing',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> markPostVideoReady(
    String postId, {
    required String sourcePath,
    String? sourceUrl,
  }) async {
    await _db.collection('posts').doc(postId).update({
      'videoSourcePath': sourcePath,
      if (sourceUrl != null && sourceUrl.trim().isNotEmpty) ...{
        'videoSourceUrl': sourceUrl,
        'videoUrl': sourceUrl,
      },
      'videoStatus': 'ready',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> deletePost(String postId) async {
    await _db.collection('posts').doc(postId).delete();
  }

  /// Toggle the current user's reaction of [type] on [postId]. Atomic.
  static Future<void> toggleReaction(String postId, String type) async {
    final userId = uid;
    if (userId == null) return;
    if (!{'like', 'sad', 'pray'}.contains(type)) return;
    final ref = _db.collection('posts').doc(postId);
    final reactionRef = ref.collection('reactions').doc(userId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final data = snap.data() ?? {};
      final churchId = data['churchId']?.toString();
      if (churchId == null || churchId != _requireChurchId()) return;

      final reactionSnap = await tx.get(reactionRef);
      final previousType =
          reactionSnap.data()?['type']?.toString() ??
          _legacyReactionType(data, userId);
      final counts = _reactionCountsFrom(data);
      final nextType = previousType == type ? null : type;

      if (previousType != null && counts.containsKey(previousType)) {
        counts[previousType] = (counts[previousType]! - 1)
            .clamp(0, 1 << 30)
            .toInt();
      }
      if (nextType != null) {
        counts[nextType] = (counts[nextType] ?? 0) + 1;
        tx.set(reactionRef, {
          'churchId': churchId,
          'postId': postId,
          'userId': userId,
          'type': nextType,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else if (reactionSnap.exists) {
        tx.delete(reactionRef);
      }

      tx.update(ref, {
        'reactionCounts': counts,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  // ============ Post Comments ============
  static Future<List<Map<String, dynamic>>> getComments(String postId) async {
    final snapshot = await _db
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .orderBy('createdAt')
        .limit(100)
        .get();
    final comments = <Map<String, dynamic>>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final userData = await _safeUserData(data['userId']);
      comments.add({
        'id': doc.id,
        ...data,
        ..._authorFields(data, userData),
        'createdAt': _timestampIso(data['createdAt']),
      });
    }
    comments.sort((a, b) => _timestampFieldAsc('createdAt', a, b));
    return comments;
  }

  static Future<void> addComment(String postId, String content) async {
    if (uid == null) return;
    final postRef = _db.collection('posts').doc(postId);
    final commentRef = postRef.collection('comments').doc();
    final batch = _db.batch();
    batch.set(commentRef, {
      'churchId': _requireChurchId(),
      'postId': postId,
      'userId': uid,
      ..._authorFields({
        'userId': uid,
        'userName': currentUser?.displayName,
      }, await _safeUserData(uid)),
      'content': content,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(postRef, {'commentCount': FieldValue.increment(1)});
    await batch.commit();
  }

  static Future<void> deleteComment(String postId, String commentId) async {
    final postRef = _db.collection('posts').doc(postId);
    final batch = _db.batch();
    batch.delete(postRef.collection('comments').doc(commentId));
    batch.update(postRef, {'commentCount': FieldValue.increment(-1)});
    await batch.commit();
  }

  // ============ Announcements ============
  static Future<List<Map<String, dynamic>>> getAnnouncements() async {
    final snapshot = await _db
        .collection('announcements')
        .where('churchId', isEqualTo: _requireChurchId())
        .orderBy('createdAt', descending: true)
        .get();
    return snapshot.docs
        .map(
          (d) => {
            'id': d.id,
            ...d.data(),
            'createdAt':
                (d.data()['createdAt'] as Timestamp?)
                    ?.toDate()
                    .toIso8601String() ??
                '',
          },
        )
        .toList();
  }

  // ============ Sheet Music ============
  static Future<List<Map<String, dynamic>>> getSheetMusic({int? limit}) async {
    Query<Map<String, dynamic>> query = _db
        .collection('sheet_music')
        .where('churchId', isEqualTo: _requireChurchId())
        .orderBy('createdAt', descending: true);
    if (limit != null) query = query.limit(limit);
    final snapshot = await query.get();
    return snapshot.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  // ============ Events ============
  static Future<List<Map<String, dynamic>>> getEvents() async {
    final snapshot = await _db
        .collection('events')
        .where('churchId', isEqualTo: _requireChurchId())
        .get();
    final events = snapshot.docs.map((d) => {'id': d.id, ...d.data()}).toList()
      ..sort(_createdAtDesc);
    return events;
  }

  static Stream<List<Map<String, dynamic>>> watchEvents() {
    return _db
        .collection('events')
        .where('churchId', isEqualTo: _requireChurchId())
        .snapshots()
        .map((snapshot) {
          final events =
              snapshot.docs.map((d) => {'id': d.id, ...d.data()}).toList()
                ..sort(_createdAtDesc);
          return events;
        });
  }

  static Future<String> createEvent({
    required String title,
    required String eventDate,
    String? time,
    String? location,
    String? description,
    String type = 'event',
    bool needsAttendance = false,
    bool needsSeating = false,
    bool harmonyEnabled = false,
    String? harmonyTitle,
    String? harmonyGuide,
    String? harmonyLyricsText,
    List<Map<String, dynamic>> harmonyLyricsTimeline = const [],
  }) async {
    final enabledHarmony = harmonyEnabled;
    final normalizedHarmonyTitle = enabledHarmony
        ? harmonyTitle?.trim() ?? ''
        : '';
    final normalizedHarmonyGuide = enabledHarmony
        ? harmonyGuide?.trim() ?? ''
        : '';
    final normalizedHarmonyLyrics = enabledHarmony
        ? harmonyLyricsText?.trim() ?? ''
        : '';
    final normalizedHarmonyTimeline = enabledHarmony
        ? harmonyLyricsTimeline
        : const <Map<String, dynamic>>[];
    final doc = await _db.collection('events').add({
      'churchId': _requireChurchId(),
      'title': title.trim(),
      'eventDate': eventDate.trim(),
      'date': eventDate.trim(),
      'time': time?.trim() ?? '',
      'location': location?.trim() ?? '',
      'description': description?.trim() ?? '',
      'type': type,
      'needsAttendance': needsAttendance,
      'needsSeating': needsSeating,
      'harmonyEnabled': enabledHarmony,
      'harmonyTitle': normalizedHarmonyTitle,
      'harmonyGuide': normalizedHarmonyGuide,
      'harmonyLyricsText': normalizedHarmonyLyrics,
      'harmonyLyricsTimeline': normalizedHarmonyTimeline,
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  static Future<void> updateEventHarmonyGuide({
    required String eventId,
    required String harmonyTitle,
    required String harmonyGuide,
    required String harmonyLyricsText,
    List<Map<String, dynamic>> harmonyLyricsTimeline = const [],
    Map<String, dynamic> harmonySegments = const {},
  }) async {
    final normalizedEventId = eventId.trim();
    if (normalizedEventId.isEmpty) throw Exception('일정 ID가 없습니다');
    final guide = harmonyGuide.trim();
    final lyricsText = harmonyLyricsText.trim();
    if (guide.isEmpty && lyricsText.isEmpty) {
      throw Exception('하모니챗 안내 문구나 가사를 입력해주세요');
    }
    await _db.collection('events').doc(normalizedEventId).update({
      'harmonyEnabled': true,
      'harmonyTitle': harmonyTitle.trim(),
      'harmonyGuide': guide,
      'harmonyLyricsText': lyricsText,
      'harmonyLyricsTimeline': harmonyLyricsTimeline,
      'harmonySegments': harmonySegments,
      'harmonyGuideUpdatedAt': FieldValue.serverTimestamp(),
      'harmonyLyricsSyncedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ============ Admin: Announcements ============
  static Future<void> createAnnouncement(
    String title, {
    String? content,
  }) async {
    await _db.collection('announcements').add({
      'churchId': _requireChurchId(),
      'title': title,
      'content': content,
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> deleteAnnouncement(String id) async {
    await _db.collection('announcements').doc(id).delete();
  }

  // ============ Admin: Videos ============
  static Future<void> addVideo(
    String title,
    String youtubeUrl, {
    String? description,
  }) async {
    await _db.collection('videos').add({
      'churchId': _requireChurchId(),
      'title': title,
      'youtubeUrl': youtubeUrl,
      'description': description,
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> deleteVideo(String id) async {
    await _db.collection('videos').doc(id).delete();
  }

  // ============ Admin: Sheet Music ============
  static Future<void> addSheetMusic(
    String title, {
    String? composer,
    String? conductorComment,
    String? lyricsText,
    List<Map<String, dynamic>> lyricsTimeline = const [],
    String? fileUrl,
    String? audioUrl,
  }) async {
    await _db.collection('sheet_music').add({
      'churchId': _requireChurchId(),
      'title': title,
      'composer': composer,
      'conductorComment': conductorComment,
      'lyricsText': lyricsText,
      'lyricsTimeline': lyricsTimeline,
      'fileUrl': fileUrl,
      'audioUrl': audioUrl,
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> deleteSheetMusic(String id) async {
    await _db.collection('sheet_music').doc(id).delete();
  }

  // ============ Part Leader ============
  static Future<void> setPartLeader(String userId, String? part) async {
    if (part == null) {
      await _db.collection('users').doc(userId).update({
        'role': 'member',
        'partLeaderFor': FieldValue.delete(),
        'partLeaderTitle': FieldValue.delete(),
      });
    } else {
      await _db.collection('users').doc(userId).update({
        'role': 'part_leader',
        'partLeaderFor': part,
        'partLeaderTitle': 'leader',
      });
    }
  }

  // ============ Admin QR Check-in ============
  static Future<Map<String, dynamic>> adminCheckIn(
    String userId, {
    String? allowedPart,
    String scannerMode = 'mobile_admin',
  }) async {
    final churchId = _requireChurchId();
    final session = await getActiveSession();
    if (session == null) throw Exception('열린 출석 세션이 없습니다');
    final sessionId = session['id']?.toString();
    if (sessionId == null || sessionId.isEmpty) {
      throw Exception('출석 세션 정보가 올바르지 않습니다');
    }

    try {
      final callable = _functions.httpsCallable('scanAttendanceQr');
      final payload = <String, dynamic>{
        'churchId': churchId,
        'sessionId': sessionId,
        'userId': userId,
        'scannerMode': scannerMode,
      };
      if (allowedPart != null) payload['allowedPart'] = allowedPart;

      final response = await callable.call<Map<String, dynamic>>(payload);
      return Map<String, dynamic>.from(response.data);
    } on FirebaseFunctionsException catch (e) {
      throw Exception(_attendanceScanErrorMessage(e));
    }
  }

  static String _attendanceScanErrorMessage(FirebaseFunctionsException e) {
    final message = e.message?.trim();
    if (message != null && message.isNotEmpty) return message;

    switch (e.code) {
      case 'permission-denied':
        return '이 단원을 출석 처리할 권한이 없습니다';
      case 'not-found':
        return '출석 QR 정보를 찾을 수 없습니다';
      case 'failed-precondition':
        return '마감된 출석 세션입니다';
      case 'unauthenticated':
        return '로그인이 필요합니다';
      default:
        return '출석 처리 중 오류가 발생했습니다';
    }
  }

  // ============ Polls (참석 투표) ============
  static Future<String> createPoll({
    required String title,
    required String targetDate,
    String? scopePart,
  }) async {
    final docRef = await _db.collection('polls').add({
      'churchId': _requireChurchId(),
      'title': title,
      'targetDate': targetDate,
      'createdBy': uid,
      'scopePart': scopePart,
      'isOpen': true,
      'closedAt': null,
      'closedBy': null,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  static Future<void> closePoll(String pollId) async {
    await _db.collection('polls').doc(pollId).update({
      'isOpen': false,
      'closedAt': FieldValue.serverTimestamp(),
      'closedBy': uid,
    });
  }

  static Future<List<Map<String, dynamic>>> getPolls() async {
    final snapshot = await _db
        .collection('polls')
        .where('churchId', isEqualTo: _requireChurchId())
        .orderBy('createdAt', descending: true)
        .get();
    return snapshot.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  static Stream<List<Map<String, dynamic>>> watchPolls() {
    return _db
        .collection('polls')
        .where('churchId', isEqualTo: _requireChurchId())
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((d) => {'id': d.id, ...d.data()}).toList();
        });
  }

  static Future<void> vote(String pollId, String choice) async {
    if (uid == null) throw Exception('로그인이 필요합니다');
    final churchId = _requireChurchId();
    final voteRef = _db.collection('poll_votes').doc('${pollId}_$uid');
    final userData = await _safeUserData(uid);
    await _db.runTransaction((tx) async {
      final poll = await tx.get(_db.collection('polls').doc(pollId));
      if (!poll.exists) throw Exception('투표를 찾을 수 없습니다');
      final pollData = poll.data() ?? {};
      if (pollData['churchId'] != churchId) throw Exception('다른 교회 투표입니다');
      tx.set(voteRef, {
        'churchId': churchId,
        'pollId': pollId,
        'userId': uid,
        ..._authorFields({'userId': uid}, userData),
        'choice': choice,
        'votedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  static Future<List<Map<String, dynamic>>> getPollVotes(String pollId) async {
    final snapshot = await _db
        .collection('poll_votes')
        .where('churchId', isEqualTo: _requireChurchId())
        .where('pollId', isEqualTo: pollId)
        .get();
    return Future.wait(
      snapshot.docs.map((doc) async {
        final data = doc.data();
        final userData = (data['userName'] == null || data['userPart'] == null)
            ? await _safeUserData(data['userId'])
            : null;
        final author = _authorFields(data, userData);
        return {
          'id': doc.id,
          ...data,
          'userName': author['userName'] ?? '',
          'userPart': author['userPart'] ?? '',
        };
      }),
    );
  }

  // ============ Seating Charts (배치판) ============
  static Future<String> createSeatingChart({
    required String label,
    required String eventDate,
    String? sourcePollId,
    String? sourcePollTitle,
  }) async {
    final docRef = await _db.collection('seating_charts').add({
      'churchId': _requireChurchId(),
      'label': label,
      'eventDate': eventDate,
      'sourcePollId': sourcePollId,
      'sourcePollTitle': sourcePollTitle,
      'createdBy': uid,
      'isPublished': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  static Future<void> publishSeatingChart(
    String chartId,
    bool isPublished,
  ) async {
    await _db.collection('seating_charts').doc(chartId).update({
      'isPublished': isPublished,
    });
  }

  static Future<void> deleteSeatingChart(String chartId) async {
    final assignments = await _db
        .collection('seat_assignments')
        .where('churchId', isEqualTo: _requireChurchId())
        .where('chartId', isEqualTo: chartId)
        .get();
    for (final doc in assignments.docs) {
      await doc.reference.delete();
    }
    await _db.collection('seating_charts').doc(chartId).delete();
  }

  static Future<List<Map<String, dynamic>>> getSeatingCharts({
    bool publishedOnly = false,
  }) async {
    var query = _db
        .collection('seating_charts')
        .where('churchId', isEqualTo: _requireChurchId())
        .orderBy('createdAt', descending: true);
    if (publishedOnly) {
      query = query.where('isPublished', isEqualTo: true);
    }
    final snapshot = await query.get();
    return snapshot.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  static Future<List<Map<String, dynamic>>> getSeatAssignments(
    String chartId,
  ) async {
    final snapshot = await _db
        .collection('seat_assignments')
        .where('churchId', isEqualTo: _requireChurchId())
        .where('chartId', isEqualTo: chartId)
        .get();
    return Future.wait(
      snapshot.docs.map((doc) async {
        final data = doc.data();
        final hasUserFields =
            data['userName'] != null && data['userGeneration'] != null;
        final userData = hasUserFields
            ? null
            : await _safeUserData(data['userId']);
        return {
          'id': doc.id,
          ...data,
          'userName': data['userName'] ?? userData?['name'] ?? '',
          'userGeneration':
              data['userGeneration'] ?? userData?['generation'] ?? '',
        };
      }),
    );
  }

  static Future<void> assignSeat({
    required String chartId,
    required String part,
    required int row,
    required int col,
    required String userId,
  }) async {
    final churchId = _requireChurchId();
    final existingUser = await _db
        .collection('seat_assignments')
        .where('churchId', isEqualTo: churchId)
        .where('chartId', isEqualTo: chartId)
        .where('userId', isEqualTo: userId)
        .get();
    for (final doc in existingUser.docs) {
      await doc.reference.delete();
    }
    final existingCell = await _db
        .collection('seat_assignments')
        .where('churchId', isEqualTo: churchId)
        .where('chartId', isEqualTo: chartId)
        .where('part', isEqualTo: part)
        .where('row', isEqualTo: row)
        .where('col', isEqualTo: col)
        .get();
    for (final doc in existingCell.docs) {
      await doc.reference.delete();
    }
    final userData = await _safeUserData(userId);
    await _db.collection('seat_assignments').add({
      'churchId': churchId,
      'chartId': chartId,
      'part': part,
      'row': row,
      'col': col,
      'userId': userId,
      'userName': userData?['name'] ?? '',
      'userGeneration': userData?['generation'] ?? '',
      'assignedBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> clearSeat({
    required String chartId,
    required String part,
    required int row,
    required int col,
  }) async {
    final existing = await _db
        .collection('seat_assignments')
        .where('churchId', isEqualTo: _requireChurchId())
        .where('chartId', isEqualTo: chartId)
        .where('part', isEqualTo: part)
        .where('row', isEqualTo: row)
        .where('col', isEqualTo: col)
        .get();
    for (final doc in existing.docs) {
      await doc.reference.delete();
    }
  }

  static Future<List<Map<String, dynamic>>> getSeatingPresets() async {
    final snapshot = await _db
        .collection('seating_presets')
        .where('churchId', isEqualTo: _requireChurchId())
        .get();
    final presets = snapshot.docs.map((d) => {'id': d.id, ...d.data()}).toList()
      ..sort(_createdAtDesc);
    return presets;
  }

  static Future<String> saveSeatingPreset({
    required String label,
    required List<Map<String, dynamic>> assignments,
  }) async {
    final sanitized = assignments
        .map(
          (seat) => {
            'part': seat['part'],
            'row': seat['row'],
            'col': seat['col'],
            'userId': seat['userId'],
          },
        )
        .toList();
    final docRef = await _db.collection('seating_presets').add({
      'churchId': _requireChurchId(),
      'label': label,
      'assignments': sanitized,
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  static Future<void> applySeatingPreset({
    required String chartId,
    required String presetId,
    required Set<String> attendingUserIds,
  }) async {
    final churchId = _requireChurchId();
    final presetDoc = await _db
        .collection('seating_presets')
        .doc(presetId)
        .get();
    final preset = presetDoc.data();
    if (preset == null) return;

    final current = await _db
        .collection('seat_assignments')
        .where('churchId', isEqualTo: churchId)
        .where('chartId', isEqualTo: chartId)
        .get();
    for (final doc in current.docs) {
      await doc.reference.delete();
    }

    final assignments = (preset['assignments'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((seat) => Map<String, dynamic>.from(seat))
        .toList();
    for (final seat in assignments) {
      final userId = seat['userId']?.toString();
      if (userId == null || !attendingUserIds.contains(userId)) continue;
      await _db.collection('seat_assignments').add({
        'churchId': churchId,
        'chartId': chartId,
        'part': seat['part'],
        'row': seat['row'],
        'col': seat['col'],
        'userId': userId,
        'assignedBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // ============ Church (Multi-tenant) ============

  /// 승인된 교회를 이름(nameLower) prefix로 검색. query가 비어있으면 상위 20건.
  static Future<List<Map<String, dynamic>>> searchApprovedChurches(
    String query,
  ) async {
    final q = query.trim().toLowerCase();
    Query<Map<String, dynamic>> ref = _db
        .collection('churches')
        .where('status', isEqualTo: 'approved')
        .orderBy('nameLower');
    if (q.isNotEmpty) {
      ref = ref.startAt([q]).endAt(['$q']);
    }
    final snap = await ref.limit(20).get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  /// 교회 단건 조회
  static Future<Map<String, dynamic>?> getChurch(String id) async {
    final doc = await _db.collection('churches').doc(id).get();
    return doc.exists ? {'id': id, ...doc.data()!} : null;
  }

  /// 교회명 중복 체크 (pending/approved 상태에 동일 nameLower 존재하면 true)
  static Future<bool> isChurchNameTaken(String name) async {
    final nameLower = name.trim().toLowerCase();
    if (nameLower.isEmpty) return false;
    final snap = await _db
        .collection('churches')
        .where('nameLower', isEqualTo: nameLower)
        .where('status', whereIn: ['pending', 'approved'])
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  /// 새 교회 등록 신청 (+ 동시에 유저 프로필 생성). 플랫폼 관리자 승인 대기 상태가 됨.
  /// 승인 시 어드민이 해당 유저를 이 교회의 admin으로 승격시킴.
  /// 반환값: 생성된 churchId
  static Future<String> requestChurchRegistration({
    required String name,
    String? address,
    String? contactPhone,
    String? contactEmail,
    required Map<String, dynamic> profileData,
  }) async {
    if (uid == null) throw Exception('로그인이 필요합니다');
    final email = currentUser?.email;
    final batch = _db.batch();
    final churchRef = _db.collection('churches').doc();
    final churchData = <String, dynamic>{
      'name': name.trim(),
      'nameLower': name.trim().toLowerCase(),
      'status': 'pending',
      'requestedBy': uid,
      'adminUids': <String>[],
      'createdAt': FieldValue.serverTimestamp(),
    };
    final choirName = profileData['choirName']?.toString().trim();
    if (choirName != null && choirName.isNotEmpty) {
      churchData['choirName'] = choirName;
    }
    if (address != null && address.trim().isNotEmpty) {
      churchData['address'] = address.trim();
    }
    if (contactPhone != null && contactPhone.trim().isNotEmpty) {
      churchData['contactPhone'] = contactPhone.trim();
    }
    if (contactEmail != null && contactEmail.trim().isNotEmpty) {
      churchData['contactEmail'] = contactEmail.trim();
    }
    batch.set(churchRef, churchData);

    final userRef = _db.collection('users').doc(uid);
    // 신규 필드는 set으로, rejectionReason 삭제는 update로 별도 처리 (merge set에서는 delete 무시됨)
    batch.set(userRef, {
      ...profileData,
      'email': email,
      'profileCompleted': true,
      'churchId': null,
      'approvalStatus': 'pending',
      'approvalScope': 'platform',
      'requestedRole': 'church_admin',
      'requestedChurchId': churchRef.id,
      'rejectionReason': FieldValue.delete(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();
    return churchRef.id;
  }

  /// 기존 승인된 교회에 가입 신청 (찬양대원 또는 파트장)
  /// [requestedRole]: 'member' | 'part_leader'
  static Future<void> requestChurchJoin({
    required String churchId,
    required String requestedRole,
    String? requestedPart,
    String? requestedPartLeaderTitle,
    required Map<String, dynamic> profileData,
  }) async {
    if (uid == null) throw Exception('로그인이 필요합니다');
    final email = currentUser?.email;
    final isWhitelisted =
        email != null && adminEmails.contains(email.toLowerCase());
    await _db.collection('users').doc(uid).set({
      ...profileData,
      'email': email,
      'profileCompleted': true,
      'churchId': churchId,
      'approvalStatus': isWhitelisted ? 'approved' : 'pending',
      'approvalScope': 'church',
      'requestedRole': requestedRole,
      if (isWhitelisted) 'role': 'admin',
      if (requestedPart != null && requestedPart.isNotEmpty)
        'requestedPart': requestedPart,
      if (requestedPartLeaderTitle != null &&
          requestedPartLeaderTitle.isNotEmpty)
        'requestedPartLeaderTitle': requestedPartLeaderTitle,
      'rejectionReason': FieldValue.delete(),
      'createdAt': FieldValue.serverTimestamp(),
      if (isWhitelisted) 'approvedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
