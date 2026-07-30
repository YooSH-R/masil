/// 명세서 3.3/3.4 응답의 user 정보.
/// 로그인 응답은 {userId, nickname}만 주므로 email은 nullable.
class User {
  const User({
    required this.id,
    required this.nickname,
    this.email,
    this.profileImageUrl,
    this.createdAt,
  });

  final int id;
  final String nickname;
  final String? email;
  final String? profileImageUrl;
  final DateTime? createdAt;

  User copyWith({
    int? id,
    String? nickname,
    String? email,
    String? profileImageUrl,
    DateTime? createdAt,
  }) {
    return User(
      id: id ?? this.id,
      nickname: nickname ?? this.nickname,
      email: email ?? this.email,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
