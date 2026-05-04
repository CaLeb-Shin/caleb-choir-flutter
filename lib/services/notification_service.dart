import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'firebase_service.dart';

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static StreamSubscription<User?>? _authSubscription;
  static StreamSubscription<String>? _tokenSubscription;
  static bool _initialized = false;

  /// 알림 권한 요청 + FCM 토큰 저장
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // 웹은 service worker + VAPID 설정이 필요하므로 일단 건너뜀
    if (kIsWeb) {
      debugPrint('FCM: web initialization skipped (requires VAPID key setup)');
      return;
    }

    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        await _saveToken();
      }

      _authSubscription?.cancel();
      _authSubscription = FirebaseAuth.instance.authStateChanges().listen((
        user,
      ) {
        if (user != null) {
          _saveToken();
        }
      });

      _tokenSubscription?.cancel();
      _tokenSubscription = _messaging.onTokenRefresh.listen(_saveToken);

      FirebaseMessaging.onMessage.listen((message) {
        debugPrint('FCM foreground: ${message.notification?.title}');
      });
    } catch (e) {
      debugPrint('FCM init error: $e');
    }
  }

  /// FCM 토큰을 Firestore users/{uid} 에 저장
  static Future<void> _saveToken([String? refreshedToken]) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final token = refreshedToken ?? await _messaging.getToken();
      if (token != null) {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'fcmToken': token,
          'fcmTokens': {
            token: {
              'enabled': true,
              'platform': defaultTargetPlatform.name,
              'updatedAt': FieldValue.serverTimestamp(),
            },
          },
          'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        debugPrint('FCM token saved: ${token.substring(0, 20)}...');
      }
    } catch (e) {
      debugPrint('FCM token save error: $e');
    }
  }

  /// 전체 멤버에게 알림 전송 (Cloud Function으로 위임)
  /// Cloud Function 'sendNotification' 호출
  static Future<void> sendToAll(String title, String body) async {
    final churchId = FirebaseService.currentChurchId;
    if (churchId == null) {
      throw Exception('교회가 선택되지 않았거나 승인 대기 중입니다');
    }

    // Cloud Function에서 처리 — 클라이언트에서는 Firestore에 알림 기록만 저장
    await FirebaseFirestore.instance.collection('notifications').add({
      'churchId': churchId,
      'title': title,
      'body': body,
      'sentAt': FieldValue.serverTimestamp(),
      'sentBy': FirebaseAuth.instance.currentUser?.uid,
    });
  }
}
