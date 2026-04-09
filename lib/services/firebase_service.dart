import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;

class FirebaseService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final fb.FirebaseAuth _auth = fb.FirebaseAuth.instance;

  // ============ Auth ============
  static fb.User? get currentUser => _auth.currentUser;
  static String? get uid => _auth.currentUser?.uid;
  static Stream<fb.User?> get authStateChanges => _auth.authStateChanges();

  static Future<void> signOut() => _auth.signOut();

  // ============ User Profile ============
  static Future<Map<String, dynamic>?> getProfile() async {
    if (uid == null) return null;
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return {'id': uid, ...doc.data()!};
  }

  static Future<void> createProfile(Map<String, dynamic> data) async {
    if (uid == null) return;
    await _db.collection('users').doc(uid).set({
      ...data,
      'email': currentUser?.email,
      'role': 'user',
      'profileCompleted': true,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> updateProfile(Map<String, dynamic> data) async {
    if (uid == null) return;
    await _db.collection('users').doc(uid).update(data);
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
        'createdAt': (data['createdAt'] as Timestamp?)?.toDate().toIso8601String() ?? '',
      });
    }
    return posts;
  }

  static Future<void> createPost(String content, {String? imageUrl}) async {
    await _db.collection('posts').add({
      'userId': uid,
      'content': content,
      'imageUrl': imageUrl,
      'createdAt': FieldValue.serverTimestamp(),
    });
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
}
