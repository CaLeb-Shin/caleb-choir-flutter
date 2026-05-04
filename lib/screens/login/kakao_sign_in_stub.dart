// Web Kakao login bridge. The JavaScript helper lives in web/index.html.

import 'dart:async';
import 'dart:js_interop';

@JS('CCNoteKakao.login')
external void _kakaoLogin(JSFunction success, JSFunction fail);

@JS('CCNoteKakao.logout')
external void _kakaoLogout(JSFunction callback);

Future<String?> signInWithKakao() async {
  final completer = Completer<String?>();
  try {
    _kakaoLogin(
      ((JSString token) {
        if (completer.isCompleted) return;
        final accessToken = token.toDart.trim();
        completer.complete(accessToken.isEmpty ? null : accessToken);
      }).toJS,
      ((JSString message) {
        if (!completer.isCompleted) {
          completer.completeError(StateError(message.toDart));
        }
      }).toJS,
    );
  } catch (error) {
    if (!completer.isCompleted) {
      completer.completeError(StateError(error.toString()));
    }
  }
  return completer.future.timeout(
    const Duration(minutes: 2),
    onTimeout: () => throw StateError('카카오 로그인 창 응답이 없습니다. 팝업 차단 여부를 확인해주세요.'),
  );
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
