import 'dart:math';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;

typedef UploadProgress = void Function(double progress);

class FirebaseService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final fb.FirebaseAuth _auth = fb.FirebaseAuth.instance;
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;

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

  static Future<void> signOut() async {
    _currentChurchIdCache = null;
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
    return {'id': uid, ...doc.data()!};
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
  static Stream<Map<String, dynamic>?> watchMyProfile() {
    if (uid == null) return const Stream.empty();
    return _db.collection('users').doc(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      return {'id': doc.id, ...doc.data()!};
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

  static Future<Map<String, dynamic>?> _safeUserData(dynamic userId) async {
    final id = userId?.toString();
    if (id == null || id.isEmpty) return null;
    try {
      final doc = await _db.collection('users').doc(id).get();
      return doc.data();
    } catch (_) {
      return null;
    }
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

  static Future<Map<String, dynamic>> _postWithAuthorAndReaction(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();
    final userData = await _safeUserData(data['userId']);
    final myReaction = await _myReactionForPost(doc.id, data);
    return {
      'id': doc.id,
      ...data,
      ..._authorFields(data, userData),
      'reactionCounts': _reactionCountsFrom(data),
      'myReaction': myReaction,
      'createdAt': _timestampIso(data['createdAt']),
    };
  }

  static Future<Map<String, dynamic>> _postSnapshotWithAuthorAndReaction(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data()!;
    final userData = await _safeUserData(data['userId']);
    final myReaction = await _myReactionForPost(doc.id, data);
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

    final records = <Map<String, dynamic>>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final sessionDoc = await _db
          .collection('attendance_sessions')
          .doc(data['sessionId'])
          .get();
      records.add({
        'id': doc.id,
        'sessionTitle': sessionDoc.data()?['title'] ?? '',
        'checkedInAt':
            (data['checkedInAt'] as Timestamp?)?.toDate().toIso8601String() ??
            '',
      });
    }
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
  static Future<List<Map<String, dynamic>>> getVideos() async {
    final snapshot = await _db
        .collection('videos')
        .where('churchId', isEqualTo: _requireChurchId())
        .orderBy('createdAt', descending: true)
        .get();
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
    final posts = <Map<String, dynamic>>[];
    for (final doc in snapshot.docs) {
      posts.add(await _postWithAuthorAndReaction(doc));
    }
    return posts;
  }

  static Stream<List<Map<String, dynamic>>> watchPosts() {
    return _db
        .collection('posts')
        .where('churchId', isEqualTo: _requireChurchId())
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .asyncMap((snapshot) async {
          final posts = <Map<String, dynamic>>[];
          for (final doc in snapshot.docs) {
            posts.add(await _postWithAuthorAndReaction(doc));
          }
          return posts;
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
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final clipsSnapshot = await _db
                .collection('harmony_relay_clips')
                .where('churchId', isEqualTo: _requireChurchId())
                .where('relayId', isEqualTo: doc.id)
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

      if (sheetPart == part) {
        final guideUrl = sheet['audioUrl']?.toString() ?? '';
        if (guideUrl.isNotEmpty) {
          return {
            'sheetMusicId': sheet['id'],
            'title': songTitle,
            'songTitle': songTitle,
            'sheetDate': sheetDate,
            'part': part,
            'guideAudioUrl': guideUrl,
            'guideAudioFileName': sheet['audioFileName']?.toString() ?? '',
            'guide': conductorComment,
            'composer': sheet['composer']?.toString() ?? '',
            'sheetUrl': sheet['fileUrl']?.toString() ?? '',
          };
        }
      }

      final partFiles = _asStringMap(sheet['partFiles']);
      final partFile = _asStringMap(partFiles[part]);
      final guideUrl = partFile['guideAudioUrl']?.toString() ?? '';
      if (guideUrl.isNotEmpty) {
        final mainSheetUrl = sheet['fileUrl']?.toString() ?? '';
        final partSheetUrl = partFile['sheetUrl']?.toString() ?? '';
        return {
          'sheetMusicId': sheet['id'],
          'title': songTitle,
          'songTitle': songTitle,
          'sheetDate': sheetDate,
          'part': part,
          'guideAudioUrl': guideUrl,
          'guideAudioFileName': partFile['guideAudioName']?.toString() ?? '',
          'guide': conductorComment,
          'composer': sheet['composer']?.toString() ?? '',
          'sheetUrl': partSheetUrl.isNotEmpty ? partSheetUrl : mainSheetUrl,
        };
      }
    }
    return null;
  }

  static Future<String> createHarmonyRelayFromGuide({
    required String part,
    required Map<String, dynamic> guide,
  }) async {
    final sourceId = guide['sheetMusicId']?.toString() ?? '';
    if (sourceId.isNotEmpty) {
      final existing = await _db
          .collection('harmony_relays')
          .where('sourceSheetMusicId', isEqualTo: sourceId)
          .get();
      for (final doc in existing.docs) {
        final data = doc.data();
        if (data['churchId'] == _requireChurchId() && data['part'] == part) {
          return doc.id;
        }
      }
    }
    final title = _firstNotEmpty([
      guide['songTitle']?.toString(),
      guide['title']?.toString(),
      '오늘의 가이드',
    ]);
    final sheetDate = guide['sheetDate']?.toString() ?? '';
    final segmentLabel = sheetDate.isNotEmpty ? '$sheetDate 1소절' : '오늘의 1소절';
    final assignee = await _pickHarmonyAssignee(
      part: part,
      excludeUserIds: {uid},
    );

    final relayId = await createHarmonyRelay(
      part: part,
      title: '$title 릴레이',
      segmentLabel: segmentLabel,
      guide: guide['guide']?.toString(),
      guideAudioUrl: guide['guideAudioUrl']?.toString(),
      guideAudioFileName: guide['guideAudioFileName']?.toString(),
      sourceSheetMusicId: guide['sheetMusicId']?.toString(),
      sourceTitle: title,
      sourceDate: sheetDate,
      sourceSheetUrl: guide['sheetUrl']?.toString(),
      currentAssigneeId: assignee?['id']?.toString(),
      currentAssigneeName: assignee?['name']?.toString(),
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
    String? sourceSheetMusicId,
    String? sourceTitle,
    String? sourceDate,
    String? sourceSheetUrl,
    String? currentAssigneeId,
    String? currentAssigneeName,
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
      'sourceSheetMusicId': sourceSheetMusicId?.trim() ?? '',
      'sourceTitle': sourceTitle?.trim() ?? '',
      'sourceDate': sourceDate?.trim() ?? '',
      'sourceSheetUrl': sourceSheetUrl?.trim() ?? '',
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
    final userData = await _safeUserData(uid);
    final score = _relayScore(durationSeconds);
    final feedback = _relayFeedback(durationSeconds);
    final clipData = {
      'churchId': _requireChurchId(),
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
    final doc = await _db.collection('harmony_relay_clips').add(clipData);
    final assignee = await _pickHarmonyAssignee(
      part: part,
      excludeUserIds: {uid},
    );
    await _db.collection('harmony_relays').doc(relayId).update({
      'clipCount': FieldValue.increment(1),
      'lastClipAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'currentAssigneeId': assignee?['id'] ?? '',
      'currentAssigneeName': assignee?['name'] ?? '',
      'assignedAt': assignee == null ? null : FieldValue.serverTimestamp(),
    });
    if (assignee != null) {
      await _createRelayNotification(
        toUserId: assignee['id'].toString(),
        relayId: relayId,
        title: '다음 릴레이 차례예요',
        body:
            '${userData?['name'] ?? currentUser?.displayName ?? '파트원'}님이 소절을 이어 불렀어요.',
      );
    }
    return doc.id;
  }

  static Future<Map<String, dynamic>?> _pickHarmonyAssignee({
    required String part,
    Set<String?> excludeUserIds = const {},
  }) async {
    final churchId = _requireChurchId();
    final snapshot = await _db
        .collection('users')
        .where('churchId', isEqualTo: churchId)
        .get();
    final candidates = snapshot.docs
        .where((doc) {
          final data = doc.data();
          return data['part'] == part &&
              data['approvalStatus'] == 'approved' &&
              !excludeUserIds.contains(doc.id);
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
    final postData = <String, dynamic>{
      'churchId': _requireChurchId(),
      'userId': uid,
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
  static Future<List<Map<String, dynamic>>> getSheetMusic() async {
    final snapshot = await _db
        .collection('sheet_music')
        .where('churchId', isEqualTo: _requireChurchId())
        .orderBy('createdAt', descending: true)
        .get();
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
    String? fileUrl,
    String? audioUrl,
  }) async {
    await _db.collection('sheet_music').add({
      'churchId': _requireChurchId(),
      'title': title,
      'composer': composer,
      'conductorComment': conductorComment,
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
    final votes = <Map<String, dynamic>>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final userData = (data['userName'] == null || data['userPart'] == null)
          ? await _safeUserData(data['userId'])
          : null;
      final author = _authorFields(data, userData);
      votes.add({
        'id': doc.id,
        ...data,
        'userName': author['userName'] ?? '',
        'userPart': author['userPart'] ?? '',
      });
    }
    return votes;
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
    final assignments = <Map<String, dynamic>>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final userDoc = await _db.collection('users').doc(data['userId']).get();
      assignments.add({
        'id': doc.id,
        ...data,
        'userName': userDoc.data()?['name'] ?? '',
        'userGeneration': userDoc.data()?['generation'] ?? '',
      });
    }
    return assignments;
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
    await _db.collection('seat_assignments').add({
      'churchId': churchId,
      'chartId': chartId,
      'part': part,
      'row': row,
      'col': col,
      'userId': userId,
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
