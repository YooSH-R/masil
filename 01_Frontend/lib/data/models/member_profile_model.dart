import '../../core/utils/json_parse.dart';
import '../../domain/entities/member_profile.dart';

/// GET /users/me 응답 파싱.
class MemberProfileModel extends MemberProfile {
  const MemberProfileModel({
    required super.memberId,
    required super.nickname,
    super.email,
    super.phoneNumber,
    super.phoneVerified,
    super.loginProviders,
    super.createdAt,
  });

  factory MemberProfileModel.fromJson(Map<String, dynamic> json) {
    return MemberProfileModel(
      // 명세서는 memberId 지만 다른 응답들이 userId 를 쓰기도 해 둘 다 받는다.
      memberId: Json.asInt(json['memberId'] ?? json['userId'] ?? json['id']),
      nickname: Json.asString(json['nickname']),
      email: Json.asStringOrNull(json['email']),
      phoneNumber: Json.asStringOrNull(json['phoneNumber']),
      phoneVerified: Json.asBool(json['phoneVerified']),
      loginProviders: _asStringList(json['loginProviders']),
      createdAt: Json.asDateTime(json['createdAt']),
    );
  }

  static List<String> _asStringList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((e) => e?.toString())
        .whereType<String>()
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }
}
