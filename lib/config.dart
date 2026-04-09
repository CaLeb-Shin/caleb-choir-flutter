/// 앱 설정 - 배포 전에 실제 서버 URL로 변경하세요
class AppConfig {
  // API 서버 URL (Express/tRPC 백엔드)
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://caleb-choir-app.vercel.app',
  );

  // OAuth 포털 URL
  static const String oauthPortalUrl = String.fromEnvironment(
    'OAUTH_PORTAL_URL',
    defaultValue: '',
  );

  // OAuth App ID
  static const String appId = String.fromEnvironment(
    'APP_ID',
    defaultValue: '',
  );

  // Deep link scheme
  static const String deepLinkScheme = 'calebchoir';

  // OAuth redirect URI (서버의 Flutter 전용 콜백)
  static String get oauthRedirectUri => '$apiBaseUrl/api/oauth/flutter-callback';

  // OAuth login URL 생성
  static String? getLoginUrl() {
    if (oauthPortalUrl.isEmpty) return null;

    final redirectUri = oauthRedirectUri;
    final state = Uri.encodeComponent(redirectUri);

    return Uri.parse('$oauthPortalUrl/app-auth').replace(queryParameters: {
      'appId': appId,
      'redirectUri': redirectUri,
      'state': state,
      'type': 'signIn',
    }).toString();
  }
}
