import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;

typedef UploadProgress = void Function(double progress);

class FirebaseService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final fb.FirebaseAuth _auth = fb.FirebaseAuth.instance;

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
  }) async {
    await _db.collection('users').doc(userId).update({
      'approvalStatus': 'approved',
      'role': role,
      'partLeaderFor': partLeaderFor,
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
        .limit(limit)
        .get();
    final sessions =
        snapshot.docs.map((d) => {'id': d.id, ...d.data()}).toList()
          ..sort((a, b) => _timestampFieldDesc('openedAt', a, b));
    return sessions.take(limit).toList();
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

    // Check if already checked in
    final existing = await _db
        .collection('attendance')
        .where('churchId', isEqualTo: churchId)
        .where('userId', isEqualTo: uid)
        .where('sessionId', isEqualTo: sessionId)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      return {'alreadyCheckedIn': true};
    }

    await _db.collection('attendance').add({
      'churchId': churchId,
      'userId': uid,
      'sessionId': sessionId,
      'checkedInAt': FieldValue.serverTimestamp(),
    });

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
      final userDoc = await _db.collection('users').doc(data['userId']).get();
      attendees.add({
        'id': doc.id,
        'userName': userDoc.data()?['name'] ?? '',
        'userPart': userDoc.data()?['part'] ?? '',
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
        .get();
    final videos = snapshot.docs.map((d) => {'id': d.id, ...d.data()}).toList()
      ..sort(_createdAtDesc);
    return videos;
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
        .get();
    final posts = snapshot.docs.map((d) {
      final data = d.data();
      return {
        'id': d.id,
        'userId': data['userId'],
        'reactions': data['reactions'] ?? {},
        'createdAt': (data['createdAt'] as Timestamp?)?.toDate(),
      };
    }).toList();
    posts.sort(_createdAtDesc);
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
        .limit(50)
        .get();
    final posts = <Map<String, dynamic>>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final userData = await _safeUserData(data['userId']);
      posts.add({
        'id': doc.id,
        ...data,
        ..._authorFields(data, userData),
        'createdAt': _timestampIso(data['createdAt']),
      });
    }
    posts.sort(_createdAtDesc);
    return posts;
  }

  static Stream<List<Map<String, dynamic>>> watchPosts() {
    return _db
        .collection('posts')
        .where('churchId', isEqualTo: _requireChurchId())
        .limit(50)
        .snapshots()
        .asyncMap((snapshot) async {
          final posts = <Map<String, dynamic>>[];
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final userData = await _safeUserData(data['userId']);
            posts.add({
              'id': doc.id,
              ...data,
              ..._authorFields(data, userData),
              'createdAt': _timestampIso(data['createdAt']),
            });
          }
          posts.sort(_createdAtDesc);
          return posts;
        });
  }

  static Future<Map<String, dynamic>?> getPost(String postId) async {
    final doc = await _db.collection('posts').doc(postId).get();
    if (!doc.exists) return null;
    final data = doc.data()!;
    final userData = await _safeUserData(data['userId']);
    return {
      'id': doc.id,
      ...data,
      ..._authorFields(data, userData),
      'createdAt': _timestampIso(data['createdAt']),
    };
  }

  static Stream<Map<String, dynamic>?> watchPost(String postId) {
    return _db.collection('posts').doc(postId).snapshots().asyncMap((
      doc,
    ) async {
      if (!doc.exists) return null;
      final data = doc.data()!;
      final userData = await _safeUserData(data['userId']);
      return {
        'id': doc.id,
        ...data,
        ..._authorFields(data, userData),
        'createdAt': _timestampIso(data['createdAt']),
      };
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

  /// 게시물 영상 원본 업로드 → 서버 압축 함수가 처리할 Storage path 반환
  static Future<String?> uploadPostVideoSource(
    Uint8List bytes, {
    required String postId,
    required int trimStartSec,
    required int trimEndSec,
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
          'trimStartSec': '$trimStartSec',
          'trimEndSec': '$trimEndSec',
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

  static Future<String> createPost({
    required String title,
    String? content,
    String? imageUrl,
    String mediaType = 'photo',
    String? videoStatus,
    String? videoSourcePath,
    int? videoTrimStartSec,
    int? videoTrimEndSec,
  }) async {
    final docRef = await _db.collection('posts').add({
      'churchId': _requireChurchId(),
      'userId': uid,
      'title': title,
      'content': content,
      'imageUrl': imageUrl,
      'mediaType': mediaType,
      if (videoStatus != null) 'videoStatus': videoStatus,
      if (videoSourcePath != null) 'videoSourcePath': videoSourcePath,
      if (videoTrimStartSec != null) 'videoTrimStartSec': videoTrimStartSec,
      if (videoTrimEndSec != null) 'videoTrimEndSec': videoTrimEndSec,
      'reactions': <String, List<String>>{'like': [], 'sad': [], 'pray': []},
      'commentCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
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

  static Future<void> deletePost(String postId) async {
    await _db.collection('posts').doc(postId).delete();
  }

  /// Toggle the current user's reaction of [type] on [postId]. Atomic.
  static Future<void> toggleReaction(String postId, String type) async {
    if (uid == null) return;
    final ref = _db.collection('posts').doc(postId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final reactionsRaw =
          (snap.data()?['reactions'] as Map<String, dynamic>?) ?? {};
      final list = List<String>.from(
        (reactionsRaw[type] as List<dynamic>?) ?? [],
      );
      if (list.contains(uid)) {
        list.remove(uid);
      } else {
        list.add(uid!);
      }
      tx.update(ref, {'reactions.$type': list});
    });
  }

  // ============ Post Comments ============
  static Future<List<Map<String, dynamic>>> getComments(String postId) async {
    final snapshot = await _db
        .collection('posts')
        .doc(postId)
        .collection('comments')
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
    await postRef.collection('comments').add({
      'churchId': _requireChurchId(),
      'postId': postId,
      'userId': uid,
      'content': content,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await postRef.update({'commentCount': FieldValue.increment(1)});
  }

  static Future<void> deleteComment(String postId, String commentId) async {
    final postRef = _db.collection('posts').doc(postId);
    await postRef.collection('comments').doc(commentId).delete();
    await postRef.update({'commentCount': FieldValue.increment(-1)});
  }

  // ============ Announcements ============
  static Future<List<Map<String, dynamic>>> getAnnouncements() async {
    final snapshot = await _db
        .collection('announcements')
        .where('churchId', isEqualTo: _requireChurchId())
        .get();
    final announcements = snapshot.docs
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
    announcements.sort(_createdAtDesc);
    return announcements;
  }

  // ============ Sheet Music ============
  static Future<List<Map<String, dynamic>>> getSheetMusic() async {
    final snapshot = await _db
        .collection('sheet_music')
        .where('churchId', isEqualTo: _requireChurchId())
        .get();
    final items = snapshot.docs.map((d) => {'id': d.id, ...d.data()}).toList()
      ..sort(_createdAtDesc);
    return items;
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
    String? fileUrl,
    String? audioUrl,
  }) async {
    await _db.collection('sheet_music').add({
      'churchId': _requireChurchId(),
      'title': title,
      'composer': composer,
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
      });
    } else {
      await _db.collection('users').doc(userId).update({
        'role': 'part_leader',
        'partLeaderFor': part,
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

    final userDoc = await _db.collection('users').doc(userId).get();
    if (!userDoc.exists) throw Exception('해당 단원을 찾을 수 없습니다');
    final userData = userDoc.data() ?? {};
    if (userData['churchId'] != churchId) {
      throw Exception('다른 교회 단원 QR입니다');
    }
    if (allowedPart != null && userData['part'] != allowedPart) {
      throw Exception('담당 파트 단원만 출석 처리할 수 있습니다');
    }

    final existing = await _db
        .collection('attendance')
        .where('churchId', isEqualTo: churchId)
        .where('userId', isEqualTo: userId)
        .where('sessionId', isEqualTo: session['id'])
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      return {'alreadyCheckedIn': true, 'userName': userData['name'] ?? ''};
    }

    await _db.collection('attendance').add({
      'churchId': churchId,
      'userId': userId,
      'sessionId': session['id'],
      'checkedInAt': FieldValue.serverTimestamp(),
      'checkedInBy': uid,
      'scannerMode': scannerMode,
    });

    return {'alreadyCheckedIn': false, 'userName': userData['name'] ?? ''};
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
        .get();
    final polls = snapshot.docs.map((d) => {'id': d.id, ...d.data()}).toList()
      ..sort(_createdAtDesc);
    return polls;
  }

  static Stream<List<Map<String, dynamic>>> watchPolls() {
    return _db
        .collection('polls')
        .where('churchId', isEqualTo: _requireChurchId())
        .snapshots()
        .map((snapshot) {
          final polls =
              snapshot.docs.map((d) => {'id': d.id, ...d.data()}).toList()
                ..sort(_createdAtDesc);
          return polls;
        });
  }

  static Future<void> vote(String pollId, String choice) async {
    if (uid == null) throw Exception('로그인이 필요합니다');
    final churchId = _requireChurchId();
    final existing = await _db
        .collection('poll_votes')
        .where('churchId', isEqualTo: churchId)
        .where('pollId', isEqualTo: pollId)
        .where('userId', isEqualTo: uid)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      await existing.docs.first.reference.update({
        'choice': choice,
        'votedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await _db.collection('poll_votes').add({
        'churchId': churchId,
        'pollId': pollId,
        'userId': uid,
        'choice': choice,
        'votedAt': FieldValue.serverTimestamp(),
      });
    }
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
      final userDoc = await _db.collection('users').doc(data['userId']).get();
      votes.add({
        'id': doc.id,
        ...data,
        'userName': userDoc.data()?['name'] ?? '',
        'userPart': userDoc.data()?['part'] ?? '',
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
        .where('churchId', isEqualTo: _requireChurchId());
    if (publishedOnly) {
      query = query.where('isPublished', isEqualTo: true);
    }
    final snapshot = await query.get();
    final charts = snapshot.docs.map((d) => {'id': d.id, ...d.data()}).toList()
      ..sort(_createdAtDesc);
    return charts;
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
      'rejectionReason': FieldValue.delete(),
      'createdAt': FieldValue.serverTimestamp(),
      if (isWhitelisted) 'approvedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
