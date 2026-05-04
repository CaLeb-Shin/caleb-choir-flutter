// Web Kakao login bridge. The JavaScript helper lives in web/index.html.

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

@JS('CCNoteKakao.start')
external void _startKakaoLogin();

@JS('CCNoteKakao.consumeCallback')
external JSString? _consumeKakaoCallback();

@JS('CCNoteKakao.logout')
external void _kakaoLogout(JSFunction callback);

Future<String?> signInWithKakao() async {
  _startKakaoLogin();
  return null;
}

Map<String, String>? consumeKakaoRedirectResult() {
  final raw = _consumeKakaoCallback();
  if (raw == null) return null;
  final decoded = jsonDecode(raw.toDart) as Map<String, dynamic>;
  final error = decoded['error'] as String?;
  if (error != null && error.isNotEmpty) {
    throw StateError(error);
  }
  final code = decoded['code'] as String?;
  final state = decoded['state'] as String?;
  final redirectUri = decoded['redirectUri'] as String?;
  if (code == null || state == null || redirectUri == null) return null;
  return {'code': code, 'state': state, 'redirectUri': redirectUri};
}

Future<void> signOutKakao() async {
  final completer = Completer<void>();
  try {
    _kakaoLogout(
      (() {
        if (!completer.isCompleted) completer.complete();
      }).toJS,
    );
  } catch (_) {
    if (!completer.isCompleted) completer.complete();
  }
  return completer.future;
}
