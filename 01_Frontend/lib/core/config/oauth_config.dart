/// 소셜 로그인 설정.
///
/// 구글: Android에서 서버에 넘길 idToken을 받으려면 **웹 클라이언트 ID**를
/// serverClientId로 넘겨야 한다(안드로이드 클라이언트 ID가 아님).
/// 백엔드가 idToken 검증에 쓰는 것과 같은 값이어야 한다.
///
/// 카카오: 개발자 콘솔의 **네이티브 앱 키**. 안드로이드 리다이렉트 스킴
/// (`kakao{네이티브앱키}://oauth`)에도 같은 값이 필요해서
/// android/local.properties 의 `kakao.nativeAppKey` 에도 함께 넣어야 한다.
///
/// 실행 시 주입:
///   flutter run \
///     --dart-define=GOOGLE_SERVER_CLIENT_ID=xxxx.apps.googleusercontent.com \
///     --dart-define=KAKAO_NATIVE_APP_KEY=xxxxxxxxxxxxxxxx
class OAuthConfig {
  OAuthConfig._();

  static const String googleServerClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  static bool get isGoogleConfigured => googleServerClientId.isNotEmpty;

  static const String kakaoNativeAppKey =
      String.fromEnvironment('KAKAO_NATIVE_APP_KEY');

  static bool get isKakaoConfigured => kakaoNativeAppKey.isNotEmpty;
}
