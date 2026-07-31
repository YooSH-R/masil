import '../../core/services/google_sign_in_service.dart';
import '../../core/services/kakao_sign_in_service.dart';
import '../../data/models/social_auth_model.dart';
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

  // --- 닉네임 중복 확인 상태 ---
  bool _isNicknameChecked = false;
  bool _isNicknameAvailable = false;
  bool get isNicknameChecked => _isNicknameChecked;
  bool get isNicknameAvailable => _isNicknameAvailable;

  /// POST /auth/verifications — 휴대전화로 인증번호 발송
  Future<bool> requestPhoneVerification(String phoneNumber) async {
    final result = await guard(
      () => _authRepository.requestVerification(phoneNumber: phoneNumber),
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

  /// GET /users/nickname-availability
  Future<bool> checkNickname(String nickname) async {
    final result = await guard(
      () => _authRepository.checkNicknameAvailability(nickname),
    );

    _isNicknameChecked = result != null;
    _isNicknameAvailable = result?.available ?? false;
    safeNotify();
    return _isNicknameAvailable;
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

  void resetNicknameCheck() {
    if (!_isNicknameChecked) return;
    _isNicknameChecked = false;
    _isNicknameAvailable = false;
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
      return hasError ? SocialSignInOutcome.failed : SocialSignInOutcome.cancelled;
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

  void _resetVerification() {
    _verificationId = null;
    _isPhoneVerified = false;
    _verificationToken = null;
    _resendCooldown = 0;
    _codeExpiresAt = null;
    _isNicknameChecked = false;
    _isNicknameAvailable = false;
  }
}
