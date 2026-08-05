/// GET /users/me 응답. (명세서 "회원 목록 추가" 2. 회원정보 조회)
///
/// 로그인 응답의 [User] 는 `{userId, nickname}` 만 담고 있어 마이페이지에
/// 필요한 이메일·전화번호·가입경로가 없다. 그래서 별도 엔티티로 둔다.
class MemberProfile {
  const MemberProfile({
    required this.memberId,
    required this.nickname,
    this.email,
    this.phoneNumber,
    this.phoneVerified = false,
    this.loginProviders = const [],
    this.createdAt,
  });

  final int memberId;
  final String nickname;
  final String? email;
  final String? phoneNumber;
  final bool phoneVerified;

  /// `LOCAL`, `GOOGLE`, `KAKAO` 조합. (명세서 12.2 소셜 공급자)
  final List<String> loginProviders;

  final DateTime? createdAt;

  /// 비밀번호로 로그인할 수 있는 계정인지.
  ///
  /// 소셜 전용 회원은 비밀번호가 없어서 비밀번호 변경을 시도하면 서버가
  /// PASSWORD_NOT_CONFIGURED 를 반환한다. 회원탈퇴 요청 본문도 달라진다
  /// (일반 회원만 currentPassword 를 함께 보낸다).
  bool get hasPassword =>
      loginProviders.any((p) => p.toUpperCase() == 'LOCAL');

  /// 전화번호를 하이픈 넣어 보여준다. 없으면 null.
  String? get formattedPhoneNumber {
    final raw = phoneNumber;
    if (raw == null || raw.length < 10) return raw;
    if (raw.length == 11) {
      return '${raw.substring(0, 3)}-${raw.substring(3, 7)}-${raw.substring(7)}';
    }
    return '${raw.substring(0, 3)}-${raw.substring(3, 6)}-${raw.substring(6)}';
  }
}
