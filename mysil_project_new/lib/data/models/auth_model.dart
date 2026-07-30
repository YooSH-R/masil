import '../../core/utils/json_parse.dart';
import 'user_model.dart';

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

/// 닉네임 사용 가능 여부. (서버 OpenAPI: NicknameAvailabilityResponse)
class NicknameAvailability {
  const NicknameAvailability({required this.nickname, required this.available});

  final String nickname;
  final bool available;

  factory NicknameAvailability.fromJson(Map<String, dynamic> json) {
    return NicknameAvailability(
      nickname: Json.asString(json['nickname']),
      available: Json.asBool(json['available']),
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
