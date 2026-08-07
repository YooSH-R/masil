import '../../core/utils/json_parse.dart';
import 'user_model.dart';

/// 인증번호 발송 목적. 명세서 4.1 / 5. 비밀번호 재설정.
///
/// 서버는 목적별로 발급한 verificationToken 을 구분해 검증한다.
/// 목적이 다르면 VERIFICATION_PURPOSE_MISMATCH 오류가 온다.
///
/// **[wireValue] 는 서버 enum 과 글자까지 같아야 한다.**
/// `VerificationSendRequest.purpose` 의 허용값은 `SIGNUP`, `PASSWORD_RESET`
/// 두 개뿐이다. 다른 값을 보내면 Jackson 이 역직렬화에 실패해 400
/// `INVALID_REQUEST` 가 온다(어느 필드가 틀렸는지는 알려주지 않는다).
///
/// prod 배포에는 `purpose` 필드가 아예 없어서 틀린 값을 보내도 무시된다.
/// 그래서 prod 를 보고 있으면 이 오류가 드러나지 않는다 — 2026-08-03 에
/// 기본 서버를 dev 로 바꾸고 나서야 `SIGN_UP` 오타가 발견됐다.
enum VerificationPurpose {
  /// 회원가입 휴대전화 인증. 서버 값은 밑줄 없는 `SIGNUP` 이다.
  signUp('SIGNUP'),

  /// 비밀번호 분실 시 재설정.
  passwordReset('PASSWORD_RESET'),

  /// 로그인 상태에서 전화번호 변경.
  ///
  /// 서버 enum 에는 이 값이 **없다.** 전화번호 변경도 회원가입과 같은
  /// `SIGNUP` 인증을 쓴다. 서버에 전용 목적이 생기면 이 값을 바꾼다.
  phoneChange('SIGNUP');

  const VerificationPurpose(this.wireValue);

  /// 서버에 보내는 값.
  final String wireValue;
}

/// 인증번호 발송 응답. (서버 OpenAPI: VerificationSendResponse)
class VerificationRequestResult {
  const VerificationRequestResult({
    required this.verificationId,
    this.expiresAt,
    this.resendAvailableAt,
  });

  final String verificationId;
  final DateTime? expiresAt;
  final DateTime? resendAvailableAt;

  factory VerificationRequestResult.fromJson(Map<String, dynamic> json) {
    return VerificationRequestResult(
      verificationId: Json.asString(json['verificationId']),
      expiresAt: Json.asDateTime(json['expiresAt']),
      resendAvailableAt: Json.asDateTime(json['resendAvailableAt']),
    );
  }

  /// 재전송 버튼 활성화까지 남은 초.
  int get resendCooldownSeconds {
    final target = resendAvailableAt;
    if (target == null) return 0;
    final diff = target.difference(DateTime.now().toUtc()).inSeconds;
    return diff > 0 ? diff : 0;
  }
}

/// 인증번호 확인 응답. (서버 OpenAPI: VerificationConfirmResponse)
/// 서버는 {verificationToken, expiresAt}만 주고 verified 플래그는 없다.
class VerificationConfirmResult {
  const VerificationConfirmResult({
    required this.verified,
    this.verificationToken,
    this.expiresAt,
  });

  final bool verified;

  /// 회원가입 요청에 그대로 넣어야 하는 토큰.
  final String? verificationToken;
  final DateTime? expiresAt;

  factory VerificationConfirmResult.fromJson(Map<String, dynamic> json) {
    final token = Json.asStringOrNull(json['verificationToken']);
    return VerificationConfirmResult(
      // 토큰이 내려왔으면 인증 성공으로 본다.
      verified: json['verified'] == null
          ? token != null
          : Json.asBool(json['verified']),
      verificationToken: token,
      expiresAt: Json.asDateTime(json['expiresAt']),
    );
  }
}

/// 로그인 / 회원가입 / 토큰 재발급 공통 응답. (서버 OpenAPI: AuthResponse)
///
/// 주의: 서버는 사용자 정보를 `member: {memberId, email, nickname}` 으로 내려준다.
/// (명세서 PDF의 `user: {userId, nickname}` 와 다름 — 둘 다 받아준다)
class AuthSession {
  const AuthSession({
    required this.accessToken,
    this.refreshToken,
    this.accessTokenExpiresAt,
    this.refreshTokenExpiresAt,
    this.tokenType,
    this.user,
  });

  final String accessToken;
  final String? refreshToken;
  final String? accessTokenExpiresAt;
  final String? refreshTokenExpiresAt;
  final String? tokenType;
  final UserModel? user;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final userJson =
        Json.asMapOrNull(json['member']) ?? Json.asMapOrNull(json['user']);
    return AuthSession(
      accessToken: Json.asString(json['accessToken']),
      refreshToken: Json.asStringOrNull(json['refreshToken']),
      accessTokenExpiresAt: Json.asStringOrNull(json['accessTokenExpiresAt']),
      refreshTokenExpiresAt: Json.asStringOrNull(json['refreshTokenExpiresAt']),
      tokenType: Json.asStringOrNull(json['tokenType']),
      user: userJson == null ? null : UserModel.fromJson(userJson),
    );
  }
}

/// 서버 검증 규칙. OpenAPI 스키마의 pattern/minLength를 그대로 옮긴 것.
class AuthValidation {
  AuthValidation._();

  /// 8~72자, 영문과 숫자를 각각 최소 1개 포함.
  static final RegExp password = RegExp(r'^(?=.*[A-Za-z])(?=.*\d).{8,72}$');

  /// 01로 시작하는 휴대폰 번호 (하이픈 없이).
  static final RegExp phoneNumber = RegExp(r'^01[016789][0-9]{7,8}$');

  /// 6자리 인증번호.
  static final RegExp verificationCode = RegExp(r'^[0-9]{6}$');

  /// 한글·영문·숫자·_- 2~20자.
  static final RegExp nickname = RegExp(r'^[가-힣a-zA-Z0-9_-]{2,20}$');

  static final RegExp email = RegExp(r'^[\w.\-+]+@[\w\-]+\.[\w.\-]+$');
}
