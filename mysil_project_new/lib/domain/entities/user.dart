class User {
  final String id;
  final String email;
  final String nickname;
  final String? profileImageUrl;

  User({
    required this.id,
    required this.email,
    required this.nickname,
    this.profileImageUrl,
  });
}
