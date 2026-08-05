import '../../domain/entities/app_notification.dart';
import '../../domain/repositories/notification_repository.dart';
import 'base_view_model.dart';

class NotificationViewModel extends BaseViewModel {
  NotificationViewModel(this._notificationRepository);

  final NotificationRepository _notificationRepository;

  final List<AppNotification> _notifications = [];
  String? _nextCursor;
  bool _hasNext = true;
  bool _pushEnabled = false;

  List<AppNotification> get notifications => List.unmodifiable(_notifications);
  bool get hasNext => _hasNext;
  bool get pushEnabled => _pushEnabled;
  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  /// GET /notifications
  Future<void> loadNotifications({bool refresh = false}) async {
    if (refresh) {
      _notifications.clear();
      _nextCursor = null;
      _hasNext = true;
    }

    final page = await guard(
      () => _notificationRepository.getNotifications(cursor: _nextCursor),
    );
    if (page == null) return;

    _notifications.addAll(page.items);
    _nextCursor = page.nextCursor;
    _hasNext = page.hasNext;
    safeNotify();
  }

  /// PUT /users/me/push-tokens/{deviceId}
  /// [token]은 FCM 토큰. FCM 연동 전에는 화면에서 토글만 저장한다.
  Future<bool> enablePush({
    required String token,
    PushPlatform platform = PushPlatform.android,
  }) async {
    await guard(() => _notificationRepository.registerPushToken(
          token: token,
          platform: platform,
        ));
    if (hasError) return false;

    _pushEnabled = true;
    safeNotify();
    return true;
  }

  /// DELETE /users/me/push-tokens/{deviceId}
  Future<bool> disablePush() async {
    await guard(() => _notificationRepository.deletePushToken());
    if (hasError) return false;

    _pushEnabled = false;
    safeNotify();
    return true;
  }
}
