import '../../core/services/google_sign_in_service.dart';
import '../../core/services/kakao_sign_in_service.dart';
import '../../data/models/auth_model.dart';
import '../../data/models/social_auth_model.dart';
import '../../domain/entities/member_profile.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';
import 'base_view_model.dart';

/// 소셜 로그인(구글·카카오) 시도 결과.
enum SocialSignInOutcome {
  /// 기존 회원 → 곧바로 홈으로.
  loggedIn,

  /// 신규 회원 → 닉네임 입력 화면으로.
  needsNickname,

  /// 사용자가 취소.
  cancelled,

  failed,
}

class AuthViewModel extends BaseViewModel {
  AuthViewModel(
    this._authRepository, {
    GoogleSignInService? googleSignInService,
    KakaoSignInService? kakaoSignInService,
  })  : _google = googleSignInService ?? GoogleSignInService(),
        _kakao = kakaoSignInService ?? KakaoSignInService();

  final AuthRepository _authRepository;
  final GoogleSignInService _google;
  final KakaoSignInService _kakao;

  User? _user;
  User? get user => _user;
  bool get isAuthenticated => _user != null;

  // --- 회원가입 휴대전화 인증 진행 상태 ---
  String? _verificationId;
  bool _isPhoneVerified = false;
  String? _verificationToken;

  String? get verificationId => _verificationId;
  bool get isPhoneVerified => _isPhoneVerified;
  bool get isVerificationRequested => _verificationId != null;

  /// 재전송 버튼을 다시 누를 수 있는 시각까지 남은 초.
  int _resendCooldown = 0;
  int get resendCooldown => _resendCooldown;

  /// 인증번호 유효 만료 시각. 입력칸의 남은 시간 표시에 쓴다.
  DateTime? _codeExpiresAt;
  DateTime? get codeExpiresAt => _codeExpiresAt;

  /// POST /auth/verifications — 휴대전화로 인증번호 발송
  Future<bool> requestPhoneVerification(
    String phoneNumber, {
    VerificationPurpose purpose = VerificationPurpose.signUp,
  }) async {
    final result = await guard(
      () => _authRepository.requestVerification(
        phoneNumber: phoneNumber,
        purpose: purpose,
      ),
    );
    if (result == null) return false;

    _verificationId = result.verificationId;
    _isPhoneVerified = false;
    _verificationToken = null;
    _resendCooldown = result.resendCooldownSeconds;
    _codeExpiresAt = result.expiresAt;
    safeNotify();
    return true;
  }

  /// POST /auth/verifications/{verificationId}/confirm
  Future<bool> confirmPhoneVerification(String code) async {
    final id = _verificationId;
    if (id == null) return false;

    final result = await guard(() => _authRepository.confirmVerification(
          verificationId: id,
          code: code,
        ));
    if (result == null) return false;

    _isPhoneVerified = result.verified;
    _verificationToken = result.verificationToken;
    safeNotify();
    return result.verified;
  }

  /// 휴대전화 번호를 고치면 인증 단계를 처음부터 다시 밟게 한다.
  void resetPhoneVerification() {
    if (_verificationId == null && !_isPhoneVerified) return;
    _verificationId = null;
    _isPhoneVerified = false;
    _verificationToken = null;
    _resendCooldown = 0;
    _codeExpiresAt = null;
    safeNotify();
  }

  /// POST /auth/signup
  ///
  /// 휴대전화 인증을 거친 경우에는 phoneNumber/verificationToken이 함께 전송된다.
  /// 가입 후 로그인 화면으로 보내기 위해 세션은 여기서 유지하지 않는다.
  Future<bool> signup({
    required String email,
    required String password,
    required String nickname,
    String? phoneNumber,
  }) async {
    final user = await guard(() => _authRepository.signup(
          email: email,
          password: password,
          nickname: nickname,
          phoneNumber: phoneNumber,
          verificationToken: _verificationToken,
        ));
    if (user == null) return false;

    _resetVerification();
    safeNotify();
    return true;
  }

  // --- 소셜 로그인 (구글·카카오) ---
  String? _signupToken;
  String? _suggestedNickname;
  String? get suggestedNickname => _suggestedNickname;

  /// 구글 계정 선택 → POST /auth/oauth/google
  Future<SocialSignInOutcome> signInWithGoogle() => _socialSignIn(
        getIdToken: _google.getIdToken,
        authenticate: (idToken) =>
            _authRepository.signInWithGoogle(idToken: idToken),
      );

  /// 카카오 로그인 → POST /auth/oauth/kakao
  /// 서버 응답과 이후 흐름(신규 회원 → 닉네임 화면)은 구글과 완전히 같다.
  Future<SocialSignInOutcome> signInWithKakao() => _socialSignIn(
        getIdToken: _kakao.getIdToken,
        authenticate: (idToken) =>
            _authRepository.signInWithKakao(idToken: idToken),
      );

  /// 소셜 로그인 공통 흐름: idToken 획득 → 서버 인증 → 기존/신규 회원 분기.
  Future<SocialSignInOutcome> _socialSignIn({
    required Future<String?> Function() getIdToken,
    required Future<SocialAuthResult> Function(String idToken) authenticate,
  }) async {
    clearError();

    final idToken = await guard<String?>(getIdToken);
    if (idToken == null) {
      // 오류 없이 null이면 사용자가 취소한 것.
      return hasError
          ? SocialSignInOutcome.failed
          : SocialSignInOutcome.cancelled;
    }

    final result = await guard(() => authenticate(idToken));
    if (result == null) return SocialSignInOutcome.failed;

    if (result.isAuthenticated) {
      _user = result.user;
      safeNotify();
      return SocialSignInOutcome.loggedIn;
    }

    if (result.needsSignup) {
      _signupToken = result.signupToken;
      _suggestedNickname = result.profile?.suggestedNickname;
      safeNotify();
      return SocialSignInOutcome.needsNickname;
    }
    return SocialSignInOutcome.failed;
  }

  /// POST /auth/oauth/signup — 닉네임 정하고 가입 완료
  Future<bool> completeSocialSignup(String nickname) async {
    final token = _signupToken;
    if (token == null) return false;

    final user = await guard(() => _authRepository.completeSocialSignup(
          signupToken: token,
          nickname: nickname,
        ));
    if (user == null) return false;

    _user = user;
    _signupToken = null;
    _suggestedNickname = null;
    safeNotify();
    return true;
  }

  /// POST /auth/login
  Future<bool> login(String email, String password) async {
    final user = await guard(() => _authRepository.login(
          email: email,
          password: password,
        ));
    if (user == null) return false;

    _user = user;
    _resetVerification();
    safeNotify();
    return true;
  }

  /// POST /auth/logout
  Future<void> logout() async {
    await guard(() => _authRepository.logout());
    // 소셜 계정 선택 상태도 함께 초기화해 다음 로그인 때 계정을 다시 고를 수 있게 한다.
    await _google.signOut();
    await _kakao.signOut();
    _user = null;
    _signupToken = null;
    _suggestedNickname = null;
    _resetVerification();
    safeNotify();
  }

  /// 저장된 refreshToken으로 세션 복구 (자동 로그인).
  Future<bool> restoreSession() async {
    final user = await guard<User?>(() => _authRepository.restoreSession());
    _user = user;
    safeNotify();
    return user != null;
  }

  /// 앱 시작 시 캐시된 사용자만 먼저 읽어 화면을 그린다.
  Future<void> loadCachedUser() async {
    _user = await _authRepository.currentUser();
    safeNotify();
  }

  /// 토큰이 완전히 만료돼 재발급까지 실패한 경우 호출된다.
  void onSessionExpired() {
    _user = null;
    safeNotify();
  }

  // --- 회원정보 (명세서 "회원 목록 추가") ---

  MemberProfile? _profile;
  MemberProfile? get profile => _profile;

  /// GET /users/me — 마이페이지 진입 시 호출.
  Future<void> loadMyProfile({bool silent = false}) async {
    final profile = await guard(
      () => _authRepository.getMyProfile(),
      silent: silent,
    );
    if (profile == null) return;

    _profile = profile;
    safeNotify();
  }

  /// PATCH /users/me — 닉네임·전화번호 수정. 전달한 값만 변경된다.
  ///
  /// 전화번호를 바꿀 때는 휴대전화 인증을 먼저 받아야 한다. 인증이 끝나 있으면
  /// 뷰모델이 보관 중인 verificationToken 을 자동으로 함께 보낸다.
  Future<bool> updateMyProfile({
    String? nickname,
    String? phoneNumber,
  }) async {
    final profile = await guard(() => _authRepository.updateMyProfile(
          nickname: nickname,
          phoneNumber: phoneNumber,
          // 전화번호를 바꿀 때만 인증 토큰이 필요하다.
          verificationToken: phoneNumber == null ? null : _verificationToken,
        ));
    if (profile == null) return false;

    _profile = profile;
    // 닉네임이 바뀌면 화면이 참조하는 user 도 맞춰준다.
    final current = _user;
    if (current != null) {
      _user = current.copyWith(nickname: profile.nickname);
    }
    _resetVerification();
    safeNotify();
    return true;
  }

  /// PATCH /users/me/password — 로그인 상태에서 비밀번호 변경.
  ///
  /// 성공해도 이 기기의 세션은 유지된다(서버가 현재 세션만 남긴다).
  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await guard(() => _authRepository.changePassword(
          currentPassword: currentPassword,
          newPassword: newPassword,
        ));
    return !hasError;
  }

  /// DELETE /users/me — 회원탈퇴.
  ///
  /// 일반 회원은 [currentPassword] 가 필요하고 소셜 전용 회원은 생략한다.
  /// ([MemberProfile.hasPassword] 로 판단할 수 있다)
  Future<bool> withdraw({String? currentPassword}) async {
    await guard(() => _authRepository.withdraw(
          currentPassword: currentPassword,
        ));
    if (hasError) return false;

    // 탈퇴가 끝나면 로그인 상태를 완전히 비운다.
    await _google.signOut();
    await _kakao.signOut();
    _user = null;
    _profile = null;
    _signupToken = null;
    _suggestedNickname = null;
    _resetVerification();
    safeNotify();
    return true;
  }

  /// POST /auth/password/reset — 비밀번호 분실 시 재설정.
  ///
  /// 먼저 [requestPhoneVerification] 을 `purpose: passwordReset` 으로 호출하고
  /// [confirmPhoneVerification] 까지 마쳐야 한다. 그 과정에서 받은
  /// verificationToken 을 뷰모델이 보관하고 있어 따로 넘기지 않아도 된다.
  Future<bool> resetPassword({
    required String phoneNumber,
    required String newPassword,
  }) async {
    final token = _verificationToken;
    if (token == null) {
      setError('휴대전화 인증을 먼저 완료해 주세요.');
      return false;
    }

    await guard(() => _authRepository.resetPassword(
          phoneNumber: phoneNumber,
          verificationToken: token,
          newPassword: newPassword,
        ));
    if (hasError) return false;

    // 서버가 모든 세션을 폐기했다. 다시 로그인해야 한다.
    _user = null;
    _profile = null;
    _resetVerification();
    safeNotify();
    return true;
  }

  void _resetVerification() {
    _verificationId = null;
    _isPhoneVerified = false;
    _verificationToken = null;
    _resendCooldown = 0;
    _codeExpiresAt = null;
  }
}
