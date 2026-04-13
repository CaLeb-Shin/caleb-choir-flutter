import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;

class FirebaseService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final fb.FirebaseAuth _auth = fb.FirebaseAuth.instance;

  /// 자동 관리자 이메일 화이트리스트
  static const adminEmails = {'sinbun001@gmail.com'};

  // ============ Auth ============
  static fb.User? get currentUser => _auth.currentUser;
  static String? get uid => _auth.currentUser?.uid;
  static Stream<fb.User?> get authStateChanges => _auth.authStateChanges();

  static Future<void> signOut() async {
    // 카카오 로그아웃 시도 (카카오로 로그인한 경우)
    try {
      await kakao.UserApi.instance.logout();
    } catch (_) {}
    await _auth.signOut();
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
    final autoRole = (email != null && adminEmails.contains(email.toLowerCase())) ? 'admin' : 'member';
    await _db.collection('users').doc(uid).set({
      ...data,
      'email': email,
      'role': autoRole,
      'profileCompleted': true,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// 관리자 이메일이면 기존 프로필도 admin으로 승격 (로그인 시 자동 실행)
  static Future<void> ensureAdminRole() async {
    final email = currentUser?.email?.toLowerCase();
    if (email == null || !adminEmails.contains(email) || uid == null) return;
    final doc = await _db.collection('users').doc(uid).get();
    if (doc.exists && doc.data()?['role'] != 'admin') {
      await _db.collection('users').doc(uid).update({'role': 'admin'});
    }
  }

  /// 관리자 전용: 다른 사용자 등급 변경
  static Future<void> updateUserRole(String userId, String role) async {
    await _db.collection('users').doc(userId).update({'role': role});
  }

  static Future<void> updateProfile(Map<String, dynamic> data) async {
    if (uid == null) return;
    await _db.collection('users').doc(uid).update(data);
  }

  /// 프로필 이미지 업로드 → downloadUrl 반환
  static Future<String?> uploadProfileImage(Uint8List bytes, {String contentType = 'image/jpeg'}) async {
    if (uid == null) return null;
    final ref = FirebaseStorage.instance.ref().child('profile_images').child('$uid.jpg');
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    return await ref.getDownloadURL();
  }

  static Future<List<Map<String, dynamic>>> getAllMembers() async {
    final snapshot = await _db.collection('users')
        .where('profileCompleted', isEqualTo: true)
        .get();
    return snapshot.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  // ============ Attendance Sessions ============
  static Future<Map<String, dynamic>?> getActiveSession() async {
    final snapshot = await _db.collection('attendance_sessions')
        .where('isOpen', isEqualTo: true)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    final doc = snapshot.docs.first;
    return {'id': doc.id, ...doc.data()};
  }

  static Future<List<Map<String, dynamic>>> getRecentSessions({int limit = 20}) async {
    final snapshot = await _db.collection('attendance_sessions')
        .orderBy('openedAt', descending: true)
        .limit(limit)
        .get();
    return snapshot.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  static Future<void> openSession(String title) async {
    await _db.collection('attendance_sessions').add({
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

    // Check if already checked in
    final existing = await _db.collection('attendance')
        .where('userId', isEqualTo: uid)
        .where('sessionId', isEqualTo: sessionId)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      return {'alreadyCheckedIn': true};
    }

    await _db.collection('attendance').add({
      'userId': uid,
      'sessionId': sessionId,
      'checkedInAt': FieldValue.serverTimestamp(),
    });

    return {'alreadyCheckedIn': false};
  }

  static Future<List<Map<String, dynamic>>> getMyHistory() async {
    if (uid == null) return [];
    final snapshot = await _db.collection('attendance')
        .where('userId', isEqualTo: uid)
        .orderBy('checkedInAt', descending: true)
        .get();

    final records = <Map<String, dynamic>>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      // Get session title
      final sessionDoc = await _db.collection('attendance_sessions').doc(data['sessionId']).get();
      records.add({
        'id': doc.id,
        'sessionTitle': sessionDoc.data()?['title'] ?? '',
        'checkedInAt': (data['checkedInAt'] as Timestamp?)?.toDate().toIso8601String() ?? '',
      });
    }
    return records;
  }

  static Future<List<Map<String, dynamic>>> getSessionAttendees(String sessionId) async {
    final snapshot = await _db.collection('attendance')
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
        'checkedInAt': (data['checkedInAt'] as Timestamp?)?.toDate().toIso8601String() ?? '',
      });
    }
    return attendees;
  }

  // ============ Videos ============
  static Future<List<Map<String, dynamic>>> getVideos() async {
    final snapshot = await _db.collection('videos').orderBy('createdAt', descending: true).get();
    return snapshot.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  // ============ Awards data ============
  /// Posts created on/after [since], with userId+reactions intact (light shape).
  static Future<List<Map<String, dynamic>>> getPostsSince(DateTime since) async {
    final snapshot = await _db
        .collection('posts')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .orderBy('createdAt', descending: true)
        .get();
    return snapshot.docs.map((d) {
      final data = d.data();
      return {
        'id': d.id,
        'userId': data['userId'],
        'reactions': data['reactions'] ?? {},
        'createdAt': (data['createdAt'] as Timestamp?)?.toDate(),
      };
    }).toList();
  }

  /// Attendance records on/after [since].
  static Future<List<Map<String, dynamic>>> getAttendanceSince(DateTime since) async {
    final snapshot = await _db
        .collection('attendance')
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
  static Future<List<Map<String, dynamic>>> getSessionsSince(DateTime since) async {
    final snapshot = await _db
        .collection('attendance_sessions')
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
  static Future<List<Map<String, dynamic>>> getCommentsSince(DateTime since) async {
    final snapshot = await _db
        .collectionGroup('comments')
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
    final snapshot = await _db.collection('posts').orderBy('createdAt', descending: true).limit(50).get();
    final posts = <Map<String, dynamic>>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final userDoc = await _db.collection('users').doc(data['userId']).get();
      posts.add({
        'id': doc.id,
        ...data,
        'userName': userDoc.data()?['name'] ?? '',
        'userPart': userDoc.data()?['part'] ?? '',
        'userGeneration': userDoc.data()?['generation'] ?? '',
        'userImageUrl': userDoc.data()?['imageUrl'],
        'createdAt': (data['createdAt'] as Timestamp?)?.toDate().toIso8601String() ?? '',
      });
    }
    return posts;
  }

  static Future<Map<String, dynamic>?> getPost(String postId) async {
    final doc = await _db.collection('posts').doc(postId).get();
    if (!doc.exists) return null;
    final data = doc.data()!;
    final userDoc = await _db.collection('users').doc(data['userId']).get();
    return {
      'id': doc.id,
      ...data,
      'userName': userDoc.data()?['name'] ?? '',
      'userPart': userDoc.data()?['part'] ?? '',
      'userGeneration': userDoc.data()?['generation'] ?? '',
      'userImageUrl': userDoc.data()?['imageUrl'],
      'createdAt': (data['createdAt'] as Timestamp?)?.toDate().toIso8601String() ?? '',
    };
  }

  /// 게시물 이미지 업로드 → downloadUrl 반환
  static Future<String?> uploadPostImage(Uint8List bytes, {String contentType = 'image/jpeg'}) async {
    if (uid == null) return null;
    final filename = '${DateTime.now().millisecondsSinceEpoch}_$uid.jpg';
    final ref = FirebaseStorage.instance.ref().child('post_images').child(filename);
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    return await ref.getDownloadURL();
  }

  static Future<String> createPost({
    required String title,
    String? content,
    String? imageUrl,
  }) async {
    final docRef = await _db.collection('posts').add({
      'userId': uid,
      'title': title,
      'content': content,
      'imageUrl': imageUrl,
      'reactions': <String, List<String>>{
        'like': [],
        'sad': [],
        'pray': [],
      },
      'commentCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
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
      final reactionsRaw = (snap.data()?['reactions'] as Map<String, dynamic>?) ?? {};
      final list = List<String>.from((reactionsRaw[type] as List<dynamic>?) ?? []);
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
        .collection('posts').doc(postId)
        .collection('comments').orderBy('createdAt', descending: false).get();
    final comments = <Map<String, dynamic>>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final userDoc = await _db.collection('users').doc(data['userId']).get();
      comments.add({
        'id': doc.id,
        ...data,
        'userName': userDoc.data()?['name'] ?? '',
        'userPart': userDoc.data()?['part'] ?? '',
        'userImageUrl': userDoc.data()?['imageUrl'],
        'createdAt': (data['createdAt'] as Timestamp?)?.toDate().toIso8601String() ?? '',
      });
    }
    return comments;
  }

  static Future<void> addComment(String postId, String content) async {
    if (uid == null) return;
    final postRef = _db.collection('posts').doc(postId);
    await postRef.collection('comments').add({
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
    final snapshot = await _db.collection('announcements').orderBy('createdAt', descending: true).get();
    return snapshot.docs.map((d) => {'id': d.id, ...d.data(),
      'createdAt': (d.data()['createdAt'] as Timestamp?)?.toDate().toIso8601String() ?? '',
    }).toList();
  }

  // ============ Sheet Music ============
  static Future<List<Map<String, dynamic>>> getSheetMusic() async {
    final snapshot = await _db.collection('sheet_music').orderBy('createdAt', descending: true).get();
    return snapshot.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  // ============ Events ============
  static Future<List<Map<String, dynamic>>> getEvents() async {
    final snapshot = await _db.collection('events').orderBy('createdAt', descending: true).get();
    return snapshot.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  // ============ Admin: Announcements ============
  static Future<void> createAnnouncement(String title, {String? content}) async {
    await _db.collection('announcements').add({
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
  static Future<void> addVideo(String title, String youtubeUrl, {String? description}) async {
    await _db.collection('videos').add({
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
  static Future<void> addSheetMusic(String title, {String? composer, String? fileUrl}) async {
    await _db.collection('sheet_music').add({
      'title': title,
      'composer': composer,
      'fileUrl': fileUrl,
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> deleteSheetMusic(String id) async {
    await _db.collection('sheet_music').doc(id).delete();
  }
}
