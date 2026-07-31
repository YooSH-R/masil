/// API 공통 설정. 명세서 v1.0 "1. 공통 규칙" 참고.
class ApiConfig {
  ApiConfig._();

  /// 배포 서버 주소 + 명세서의 /v1 버전 경로.
  ///
  /// 서버가 HTTPS로 전환되면서 http 로 보내면 308 Permanent Redirect 가 온다.
  /// (dio 는 이를 에러로 처리해 로그인·소셜로그인이 전부 실패했다)
  /// https 로 직접 보내야 하고, 덕분에 Android 평문 트래픽 허용도 필요 없다.
  static const String baseUrl = 'https://i15a203.p.ssafy.io/api/v1';

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
