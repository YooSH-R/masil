import '../../core/utils/json_parse.dart';
import '../../domain/entities/user.dart';

/// 서버는 userId를 쓰고 화면은 User.id를 쓴다. 그 변환을 여기서만 처리한다.
/// (기존 json_serializable 대신 수동 파싱 — 명세서의 필드명/타입을 그대로 따라가기 위함)
class UserModel extends User {
  const UserModel({
    required super.id,
    required super.nickname,
    super.email,
    super.profileImageUrl,
    super.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      // 서버는 memberId를 쓰고(OpenAPI: MemberResponse), 명세서 PDF는 userId로
      // 적혀 있어 둘 다 받아준다.
      id: Json.asInt(json['memberId'] ?? json['userId'] ?? json['id']),
      nickname: Json.asString(json['nickname']),
      email: Json.asStringOrNull(json['email']),
      profileImageUrl: Json.asStringOrNull(
        json['profileImageUrl'] ?? json['profileImage'],
      ),
      createdAt: Json.asDateTime(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        'userId': id,
        'nickname': nickname,
        if (email != null) 'email': email,
        if (profileImageUrl != null) 'profileImageUrl': profileImageUrl,
        if (createdAt != null) 'createdAt': createdAt!.toUtc().toIso8601String(),
      };
}
