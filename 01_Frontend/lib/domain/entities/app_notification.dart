/// 푸시 알림 종류 (명세서 9.2의 type).
enum NotificationType {
  photoProcessed,
  walkProposal,
  walkEnded,
  affinityChanged,
  unknown,
}

extension NotificationTypeX on NotificationType {
  String get label => switch (this) {
        NotificationType.photoProcessed => '사진 처리 완료',
        NotificationType.walkProposal => '산책 제안',
        NotificationType.walkEnded => '산책 종료',
        NotificationType.affinityChanged => '친밀도 변화',
        NotificationType.unknown => '알림',
      };
}

/// 명세서 2.6 GET /notifications 항목 + 9.2 푸시 페이로드 공용.
class AppNotification {
  const AppNotification({
    required this.type,
    required this.title,
    required this.body,
    this.id,
    this.deepLink,
    this.data = const {},
    this.createdAt,
    this.readAt,
  });

  final NotificationType type;
  final String title;
  final String body;
  final int? id;
  final String? deepLink;
  final Map<String, dynamic> data;
  final DateTime? createdAt;
  final DateTime? readAt;

  bool get isRead => readAt != null;
}

/// 푸시 토큰 플랫폼 (명세서 9.1).
enum PushPlatform { android, ios }

extension PushPlatformX on PushPlatform {
  String get apiValue => switch (this) {
        PushPlatform.android => 'ANDROID',
        PushPlatform.ios => 'IOS',
      };
}
