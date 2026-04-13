import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

Future<String?> signInWithKakao() async {
  OAuthToken token;
  if (await isKakaoTalkInstalled()) {
    token = await UserApi.instance.loginWithKakaoTalk();
  } else {
    token = await UserApi.instance.loginWithKakaoAccount();
  }
  return token.accessToken;
}
