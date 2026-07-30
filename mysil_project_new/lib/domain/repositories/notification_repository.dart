import '../entities/app_notification.dart';
import '../entities/walk_diary.dart';

/// 명세서 2.6 알림 API.
abstract class NotificationRepository {
  /// PUT /users/me/push-tokens/{deviceId} — 푸시 토큰 등록·갱신
  Future<void> registerPushToken({
    required String token,
    PushPlatform platform,
  });

  /// DELETE /users/me/push-tokens/{deviceId} — 푸시 토큰 삭제
  Future<void> deletePushToken();

  /// GET /notifications — 알림 내역 조회
  Future<CursorPage<AppNotification>> getNotifications({
    String? cursor,
    int limit,
  });
}
