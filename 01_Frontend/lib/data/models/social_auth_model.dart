import '../../core/utils/json_parse.dart';
import 'user_model.dart';

/// 구글 인증 결과 상태. 서버 SocialAuthenticationResponse.status.
enum SocialAuthStatus {
  /// 기존 회원 → 토큰이 함께 온다.
  authenticated,

  /// 신규 회원 → signupToken으로 닉네임을 정해 가입을 마쳐야 한다.
  signupRequired,

  unknown,
}

/// 구글 로그인 시 서버가 제안하는 프로필 정보.
class SocialProfile {
  const SocialProfile({this.provider, this.email, this.suggestedNickname});

  final String? provider;
  final String? email;
  final String? suggestedNickname;

  factory SocialProfile.fromJson(Map<String, dynamic> json) {
    return SocialProfile(
      provider: Json.asStringOrNull(json['provider']),
      email: Json.asStringOrNull(json['email']),
      suggestedNickname: Json.asStringOrNull(json['suggestedNickname']),
    );
  }
}

/// POST /auth/oauth/google 응답 (SocialAuthenticationResponse).
class SocialAuthResult {
  const SocialAuthResult({
    required this.status,
    this.accessToken,
    this.refreshToken,
    this.accessTokenExpiresAt,
    this.user,
    this.signupToken,
    this.signupTokenExpiresAt,
    this.profile,
  });

  final SocialAuthStatus status;
  final String? accessToken;
  final String? refreshToken;
  final String? accessTokenExpiresAt;
  final UserModel? user;
  final String? signupToken;
  final DateTime? signupTokenExpiresAt;
  final SocialProfile? profile;

  bool get isAuthenticated =>
      accessToken != null && accessToken!.isNotEmpty;
  bool get needsSignup => !isAuthenticated && (signupToken?.isNotEmpty ?? false);

  factory SocialAuthResult.fromJson(Map<String, dynamic> json) {
    final userJson =
        Json.asMapOrNull(json['user']) ?? Json.asMapOrNull(json['member']);
    final profileJson = Json.asMapOrNull(json['profile']);
    final accessToken = Json.asStringOrNull(json['accessToken']);
    final signupToken = Json.asStringOrNull(json['signupToken']);

    // status 문자열이 어떤 값으로 오든, 토큰 유무로도 판단할 수 있게 한다.
    final rawStatus = json['status']?.toString().toUpperCase() ?? '';
    final status = switch (rawStatus) {
      'AUTHENTICATED' || 'LOGIN' || 'EXISTING_MEMBER' => SocialAuthStatus.authenticated,
      'SIGNUP_REQUIRED' || 'SIGNUP' || 'NEW_MEMBER' => SocialAuthStatus.signupRequired,
      _ => accessToken != null
          ? SocialAuthStatus.authenticated
          : (signupToken != null
              ? SocialAuthStatus.signupRequired
              : SocialAuthStatus.unknown),
    };

    return SocialAuthResult(
      status: status,
      accessToken: accessToken,
      refreshToken: Json.asStringOrNull(json['refreshToken']),
      accessTokenExpiresAt: Json.asStringOrNull(json['accessTokenExpiresAt']),
      user: userJson == null ? null : UserModel.fromJson(userJson),
      signupToken: signupToken,
      signupTokenExpiresAt: Json.asDateTime(json['signupTokenExpiresAt']),
      profile: profileJson == null ? null : SocialProfile.fromJson(profileJson),
    );
  }
}
