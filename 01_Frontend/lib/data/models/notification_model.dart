import '../../core/utils/json_parse.dart';
import '../../domain/entities/app_notification.dart';

const _typeMapping = <String, NotificationType>{
  'PHOTO_PROCESSED': NotificationType.photoProcessed,
  'WALK_PROPOSAL': NotificationType.walkProposal,
  'WALK_ENDED': NotificationType.walkEnded,
  'AFFINITY_CHANGED': NotificationType.affinityChanged,
};

class AppNotificationModel extends AppNotification {
  const AppNotificationModel({
    required super.type,
    required super.title,
    required super.body,
    super.id,
    super.deepLink,
    super.data,
    super.createdAt,
    super.readAt,
  });

  factory AppNotificationModel.fromJson(Map<String, dynamic> json) {
    final data = Json.asMap(json['data']);
    return AppNotificationModel(
      type: Json.asEnum(json['type'], _typeMapping, NotificationType.unknown),
      title: Json.asString(json['title']),
      body: Json.asString(json['body'] ?? json['message']),
      id: Json.asIntOrNull(json['notificationId'] ?? json['id']),
      deepLink: Json.asStringOrNull(data['deepLink'] ?? json['deepLink']),
      data: data,
      createdAt: Json.asDateTime(json['createdAt'] ?? json['sentAt']),
      readAt: Json.asDateTime(json['readAt']),
    );
  }
}
