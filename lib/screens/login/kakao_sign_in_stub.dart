// Web 환경용 Kakao 로그인 — Kakao JavaScript SDK (v2)를 dart:js_interop으로 호출한다.
// SDK 초기화(Kakao.init)는 web/index.html에서 수행된다.

import 'dart:async';
import 'dart:js_interop';

extension type _KakaoAuthObj(JSObject _) implements JSObject {
  // ignore: non_constant_identifier_names
  external String get access_token;
}

extension type _KakaoLoginOptions._(JSObject _) implements JSObject {
  external factory _KakaoLoginOptions({
    JSFunction success,
    JSFunction fail,
  });
}

@JS('Kakao.Auth.login')
external void _kakaoAuthLogin(_KakaoLoginOptions options);

@JS('Kakao.Auth.logout')
external void _kakaoAuthLogout(JSFunction callback);

@JS('Kakao.isInitialized')
external bool _kakaoIsInitialized();

Future<String?> signInWithKakao() async {
  if (!_kakaoIsInitialized()) return null;
  final completer = Completer<String?>();
  try {
    _kakaoAuthLogin(
      _KakaoLoginOptions(
        success: ((_KakaoAuthObj authObj) {
          if (!completer.isCompleted) completer.complete(authObj.access_token);
        }).toJS,
        fail: ((JSObject _) {
          if (!completer.isCompleted) completer.complete(null);
        }).toJS,
      ),
    );
  } catch (_) {
    if (!completer.isCompleted) completer.complete(null);
  }
  return completer.future;
}

Future<void> signOutKakao() async {
  if (!_kakaoIsInitialized()) return;
  final completer = Completer<void>();
  try {
    _kakaoAuthLogout((() {
      if (!completer.isCompleted) completer.complete();
    }).toJS);
  } catch (_) {
    if (!completer.isCompleted) completer.complete();
  }
  return completer.future;
}
