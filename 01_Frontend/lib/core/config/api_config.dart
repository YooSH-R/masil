/// API 공통 설정. 명세서 v1.0 "1. 공통 규칙" 참고.
class ApiConfig {
  ApiConfig._();

  /// 운영 서버. 인증 API 만 올라가 있다.
  static const String prodBaseUrl = 'https://i15a203.p.ssafy.io/api/v1';

  /// 개발 서버. 경로 접두사가 `/dev/api` 로 **다르다.**
  ///
  /// `/api` 만 보고 "dev 배포가 안 됐다"고 오판하기 쉽다. ingress 설정에는
  /// `/api` 만 적혀 있어서 소스만 봐서는 알 수 없다. dev 에 올라온 것을 확인할
  /// 때는 `https://i15a203.p.ssafy.io/dev/api/v3/api-docs` 를 볼 것.
  ///
  /// 2026-07-31 기준 dev 에만 있는 것: `/robots/pairings`(QR 기기 등록),
  /// 이미지 업로드(presigned-url) 관련 4개.
  static const String devBaseUrl = 'https://i15a203.p.ssafy.io/dev/api/v1';

  /// 실제로 쓰는 주소. 기본값은 개발 서버다.
  ///
  /// 서버를 바꿀 때 코드를 고치지 않도록 주입받는다:
  ///   flutter run --dart-define=API_BASE_URL=https://.../api/v1
  /// 또는 dart_defines.json 의 `API_BASE_URL` 값을 바꾼다.
  ///
  /// 주의: http 로 보내면 308 Permanent Redirect 가 오고 dio 가 이를 에러로
  /// 처리해 로그인이 전부 실패한다. 반드시 https 로 둘 것.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: devBaseUrl,
  );

  /// 지금 개발 서버를 보고 있는지. 화면에 환경 배지를 띄울 때 쓸 수 있다.
  static bool get isDev => baseUrl == devBaseUrl;

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 15);
  static const Duration sendTimeout = Duration(seconds: 30);

  /// 사진 업로드는 응답이 느릴 수 있어 별도로 길게 잡는다.
  static const Duration uploadTimeout = Duration(seconds: 60);

  /// 인증 헤더를 붙이지 않는 경로 (로그인 이전 단계).
  static const List<String> publicPaths = [
    '/auth/verifications',
    '/auth/signup',
    '/auth/login',
    '/auth/refresh',
  ];
}
