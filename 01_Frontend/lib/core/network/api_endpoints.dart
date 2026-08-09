/// 명세서 v1.0 "2. API 목록"의 엔드포인트 모음.
/// 경로 조립을 한 곳에 모아 화면·리포지토리에서 문자열을 직접 쓰지 않게 한다.
class ApiEndpoints {
  ApiEndpoints._();

  // 2.1 인증
  static const String verifications = '/auth/verifications';
  static String verificationConfirm(String verificationId) =>
      '/auth/verifications/$verificationId/confirm';
  static const String signup = '/auth/signup';
  static const String login = '/auth/login';
  static const String refresh = '/auth/refresh';
  static const String logout = '/auth/logout';

  // --- 회원정보 (명세서 "회원 목록 추가") ---
  /// GET 조회 / PATCH 수정(닉네임·전화번호) / DELETE 회원탈퇴
  static const String me = '/users/me';

  /// PATCH — 로그인 상태에서 비밀번호 변경
  static const String mePassword = '/users/me/password';

  /// POST — 비밀번호 분실 시 재설정 (VerificationToken 필요)
  static const String passwordReset = '/auth/password/reset';

  // 소셜 로그인 (서버 구현에만 있음)
  static const String googleOAuth = '/auth/oauth/google';
  static const String kakaoOAuth = '/auth/oauth/kakao';
  static const String oauthSignup = '/auth/oauth/signup';

  // 2.2 펫·로봇
  static const String pets = '/pets';
  static String pet(int petId) => '/pets/$petId';
  static const String robotPairings = '/robots/pairings';
  static const String robotRegistrationValidation =
      '/robots/registrations/validate';
  static const String robotRegistrations = '/robots/registrations';
  static String robotStatus(int robotId) => '/robots/$robotId/status';
  static String robotPairing(int robotId) => '/robots/$robotId/pairing';

  // 2.3 교감·친밀도
  static String robotInteractions(int robotId) =>
      '/robots/$robotId/interactions';
  static String petAffinity(int petId) => '/pets/$petId/affinity';

  /// 친밀도 실시간 구독(SSE). 연결되면 `affinity-snapshot` 이 한 번 오고,
  /// 이후 변경은 `affinity-changed` 로 온다.
  static String petAffinityStream(int petId) =>
      '/pets/$petId/affinity/stream';
  static String petAffinityHistory(int petId) =>
      '/pets/$petId/affinity/history';

  // 2.4 산책
  static const String currentWalkProposal = '/walk-proposals/current';
  static String walkProposalResponses(int proposalId) =>
      '/walk-proposals/$proposalId/responses';
  static const String walks = '/walks';
  static String walk(int walkId) => '/walks/$walkId';
  static String walkStart(int walkId) => '/walks/$walkId/start';
  static String walkLocationsBatch(int walkId) =>
      '/walks/$walkId/locations/batch';
  /// 마실이 기기가 도킹을 감지해 부르는 종료. 앱은 기기 토큰이 없어 못 부른다.
  static String walkEnd(int walkId) => '/walks/$walkId/end';

  /// 앱에서 바로 시작한 산책의 종료. `산책 종료` 버튼이 이걸 부른다.
  static String walkComplete(int walkId) => '/walks/$walkId/complete';
  static String walkSummary(int walkId) => '/walks/$walkId/summary';

  // 2.5 사진·GPT 처리
  static String walkPhotos(int walkId) => '/walks/$walkId/photos';
  static String walkPhoto(int walkId, int photoId) =>
      '/walks/$walkId/photos/$photoId';
  static String photoContent(int photoId) => '/photos/$photoId/content';
  static String walkPhotoRetry(int walkId, int photoId) =>
      '/walks/$walkId/photos/$photoId/retry';

  // 2.6 산책일지·알림
  static String walkDiary(int walkId) => '/walks/$walkId/diary';
  static const String walkDiaries = '/walk-diaries';
  static String s3WalkDiary(String deviceId, String walkDate, int session) =>
      '/walk-diaries/${Uri.encodeComponent(deviceId)}/$walkDate/$session';
  static String pushToken(String deviceId) => '/users/me/push-tokens/$deviceId';
  static const String notifications = '/notifications';
}
