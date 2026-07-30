import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/utils/json_parse.dart';
import '../../domain/entities/walk_diary.dart';
import '../../domain/repositories/walk_diary_repository.dart';
import '../models/walk_diary_model.dart';

class WalkDiaryRepositoryImpl implements WalkDiaryRepository {
  WalkDiaryRepositoryImpl({required ApiClient client}) : _client = client;

  final ApiClient _client;

  @override
  Future<WalkDiary> getDiary(int walkId) async {
    final data = await _client.get(ApiEndpoints.walkDiary(walkId));
    return WalkDiaryModel.fromJson(Json.asMap(data));
  }

  @override
  Future<CursorPage<WalkDiaryFeedItem>> getFeed({
    String? cursor,
    int limit = 20,
  }) async {
    final data = await _client.get(
      ApiEndpoints.walkDiaries,
      query: {'limit': limit, if (cursor != null) 'cursor': cursor},
    );
    if (data is List) {
      return CursorPage<WalkDiaryFeedItem>(
        items: Json.asMapList(data)
            .map(WalkDiaryFeedItemModel.fromJson)
            .toList(growable: false),
      );
    }
    return parseCursorPage<WalkDiaryFeedItem>(
      Json.asMap(data),
      WalkDiaryFeedItemModel.fromJson,
    );
  }

  @override
  Future<WalkDiary> updateCaption({
    required int walkId,
    required int photoId,
    required String caption,
  }) async {
    // 명세서에 PATCH 본문 예시가 없어 {photoId, caption} 으로 보낸다.
    // 서버 스펙이 확정되면 이 부분만 맞추면 된다.
    final data = await _client.patch(
      ApiEndpoints.walkDiary(walkId),
      data: {'photoId': photoId, 'caption': caption},
    );
    return WalkDiaryModel.fromJson(Json.asMap(data));
  }
}
