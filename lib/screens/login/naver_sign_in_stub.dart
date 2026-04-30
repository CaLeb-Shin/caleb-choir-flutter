// Web Naver login bridge. The JavaScript helper lives in web/index.html.

import 'dart:convert';
import 'dart:js_interop';

@JS('CCNoteNaver.start')
external void _startNaverLogin();

@JS('CCNoteNaver.consumeCallback')
external JSString? _consumeNaverCallback();

Future<void> startSignInWithNaver() async {
  _startNaverLogin();
}

Map<String, String>? consumeNaverRedirectResult() {
  final raw = _consumeNaverCallback();
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
