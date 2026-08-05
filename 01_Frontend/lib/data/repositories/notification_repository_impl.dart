import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/storage/token_storage.dart';
import '../../core/utils/json_parse.dart';
import '../../domain/entities/app_notification.dart';
import '../../domain/entities/walk_diary.dart';
import '../../domain/repositories/notification_repository.dart';
import '../models/notification_model.dart';
import '../models/walk_diary_model.dart';

class NotificationRepositoryImpl implements NotificationRepository {
  NotificationRepositoryImpl({
    required ApiClient client,
    required TokenStorage tokenStorage,
  })  : _client = client,
        _tokenStorage = tokenStorage;

  final ApiClient _client;
  final TokenStorage _tokenStorage;

  @override
  Future<void> registerPushToken({
    required String token,
    PushPlatform platform = PushPlatform.android,
  }) async {
    final deviceId = await _tokenStorage.deviceId();
    await _client.put(
      ApiEndpoints.pushToken(deviceId),
      data: {'token': token, 'platform': platform.apiValue},
    );
  }

  @override
  Future<void> deletePushToken() async {
    final deviceId = await _tokenStorage.deviceId();
    await _client.delete(ApiEndpoints.pushToken(deviceId));
  }

  @override
  Future<CursorPage<AppNotification>> getNotifications({
    String? cursor,
    int limit = 20,
  }) async {
    final data = await _client.get(
      ApiEndpoints.notifications,
      query: {'limit': limit, if (cursor != null) 'cursor': cursor},
    );
    if (data is List) {
      return CursorPage<AppNotification>(
        items: Json.asMapList(data)
            .map(AppNotificationModel.fromJson)
            .toList(growable: false),
      );
    }
    return parseCursorPage<AppNotification>(
      Json.asMap(data),
      AppNotificationModel.fromJson,
    );
  }
}
