import '../../data/models/auth_model.dart';
import '../../data/models/social_auth_model.dart';
import '../entities/member_profile.dart';
import '../entities/user.dart';

/// 인증 API. 필드·필수값은 서버 OpenAPI(`/api/v3/api-docs`) 기준.
abstract class AuthRepository {
  /// POST /auth/verifications — 휴대전화 인증번호 발송
  /// body: {phoneNumber} — 하이픈 없는 01xxxxxxxxx 형식
  /// [purpose] 에 따라 서버가 다른 목적의 verificationToken 을 발급한다.
  /// 회원가입은 signUp, 비밀번호 재설정은 passwordReset 을 넘겨야 한다.
  Future<VerificationRequestResult> requestVerification({
    required String phoneNumber,
    VerificationPurpose purpose = VerificationPurpose.signUp,
  });

  /// POST /auth/verifications/{verificationId}/confirm — 인증번호 확인
  /// 성공 시 회원가입에 쓸 verificationToken을 받는다.
  Future<VerificationConfirmResult> confirmVerification({
    required String verificationId,
    required String code,
  });

  /// GET /users/nickname-availability?nickname= — 닉네임 중복 확인
  Future<NicknameAvailability> checkNicknameAvailability(String nickname);

  /// POST /auth/signup — 회원가입
  ///
  /// 서버 필수값: deviceId, email, nickname, password, phoneNumber, verificationToken
  /// 휴대폰 인증 단계를 쓰지 않는 화면에서도 호출할 수 있게 phoneNumber와
  /// verificationToken은 선택 인자로 두고, 있을 때만 함께 보낸다.
  Future<User> signup({
    required String email,
    required String password,
    required String nickname,
    String? phoneNumber,
    String? verificationToken,
  });

  /// POST /auth/oauth/google — 구글 idToken으로 인증
  /// 기존 회원이면 토큰이 저장되고, 신규 회원이면 signupToken이 담겨 온다.
  Future<SocialAuthResult> signInWithGoogle({required String idToken});

  /// POST /auth/oauth/kakao — 카카오 idToken으로 인증
  /// 응답 형태와 후속 흐름(signupToken → completeSocialSignup)은 구글과 같다.
  Future<SocialAuthResult> signInWithKakao({required String idToken});

  /// POST /auth/oauth/signup — 신규 소셜 회원 가입 완료 (닉네임 지정)
  Future<User> completeSocialSignup({
    required String signupToken,
    required String nickname,
  });

  /// POST /auth/login — 로그인 (토큰 저장까지 수행)
  Future<User> login({
    required String email,
    required String password,
  });

  /// POST /auth/logout — 로그아웃 (실패해도 로컬 토큰은 정리)
  Future<void> logout();

  /// 저장된 refreshToken으로 세션 복구. 자동 로그인 화면에서 사용.
  Future<User?> restoreSession();

  /// 캐시된 로그인 사용자.
  Future<User?> currentUser();

  // --- 회원정보 (명세서 "회원 목록 추가") ---

  /// GET /users/me — 내 회원정보 조회
  Future<MemberProfile> getMyProfile();

  /// PATCH /users/me — 닉네임·휴대전화 번호 수정
  ///
  /// 전달한 필드만 변경된다. 전화번호를 바꿀 때는 휴대전화 인증을 먼저 받고
  /// [verificationToken] 을 함께 넘겨야 한다.
  Future<MemberProfile> updateMyProfile({
    String? nickname,
    String? phoneNumber,
    String? verificationToken,
  });

  /// PATCH /users/me/password — 로그인 상태에서 비밀번호 변경
  ///
  /// 성공 시 204. 현재 세션을 제외한 다른 로그인 세션이 서버에서 폐기된다.
  /// 소셜 전용 회원은 PASSWORD_NOT_CONFIGURED 오류가 온다.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });

  /// DELETE /users/me — 회원탈퇴
  ///
  /// 일반 회원은 [currentPassword] 가 필요하고, 소셜 전용 회원은 생략한다.
  /// 서버는 confirmation 값으로 'WITHDRAW' 를 요구한다.
  Future<void> withdraw({String? currentPassword});

  /// POST /auth/password/reset — 비밀번호 분실 시 재설정
  ///
  /// [verificationToken] 은 purpose=PASSWORD_RESET 으로 발급받은 것이어야 한다.
  /// 성공 후 모든 Refresh Token 이 폐기되므로 다시 로그인해야 한다.
  Future<void> resetPassword({
    required String phoneNumber,
    required String verificationToken,
    required String newPassword,
  });
}
