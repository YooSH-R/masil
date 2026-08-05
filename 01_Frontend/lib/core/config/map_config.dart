/// 카카오맵 설정.
///
/// 로그인에 쓰는 **네이티브 앱 키**와 다른 값이다. kakao_map_plugin 은 내부에서
/// WebView 로 Kakao Maps **JavaScript API** 를 띄우므로 JavaScript 키가 필요하다.
///
/// Kakao Developers 콘솔에서 두 가지를 해줘야 지도가 뜬다:
///   1. 내 애플리케이션 → 앱 키 → **JavaScript 키** 복사
///   2. 플랫폼 → **Web** 플랫폼 등록 → 사이트 도메인에 `http://localhost` 추가
///      (WebView 가 localhost 로 문서를 올리기 때문에 이 등록이 없으면
///       지도가 회색으로만 보이고 타일이 내려오지 않는다)
///
/// 실행 시 주입:
///   flutter run --dart-define=KAKAO_JS_APP_KEY=xxxxxxxxxxxxxxxx
/// 또는 dart_defines.json 에 `"KAKAO_JS_APP_KEY": "..."` 추가.
class MapConfig {
  MapConfig._();

  static const String kakaoJsAppKey =
      String.fromEnvironment('KAKAO_JS_APP_KEY');

  static bool get isKakaoMapConfigured => kakaoJsAppKey.isNotEmpty;

  /// WebView 문서의 origin. kakao_map_plugin 은 지도 HTML을
  /// `loadHtmlString(html, baseUrl: ...)` 으로 올리는데, 이 값을 주지 않으면
  /// origin 이 `about:blank` 가 되어 카카오의 도메인 검사를 통과하지 못한다.
  /// 여기 값과 콘솔의 Web 플랫폼 사이트 도메인이 **정확히 같아야** 한다.
  static const String kakaoMapBaseUrl = 'http://localhost';

  /// 좌표가 아직 하나도 없을 때 지도를 띄울 기준점 (광화문).
  static const double fallbackLatitude = 37.5759;
  static const double fallbackLongitude = 126.9768;

  /// 카카오 로컬 REST API 키. 좌표 → 장소명 변환(역지오코딩)에만 쓴다.
  ///
  /// 주의: REST 키는 원래 서버용이라 앱에 심으면 APK 를 뜯으면 노출된다.
  /// 백엔드에 산책 API 가 생기면 서버가 장소명을 계산해 내려주도록 옮기고,
  /// 이 키는 앱에서 빼는 것이 옳다.
  ///
  /// 실행 시 주입:
  ///   flutter run --dart-define=KAKAO_REST_API_KEY=xxxxxxxx
  static const String kakaoRestApiKey =
      String.fromEnvironment('KAKAO_REST_API_KEY');

  /// 키가 없으면 장소명 조회를 건너뛰고 화면은 `-` 를 보여준다.
  static bool get isPlaceLookupConfigured => kakaoRestApiKey.isNotEmpty;
}
