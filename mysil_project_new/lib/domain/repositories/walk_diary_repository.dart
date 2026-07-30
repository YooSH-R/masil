import '../entities/walk_diary.dart';

/// 명세서 2.6 산책일지 API.
abstract class WalkDiaryRepository {
  /// GET /walks/{walkId}/diary — 산책일지 상세 조회
  Future<WalkDiary> getDiary(int walkId);

  /// GET /walk-diaries — 산책일지 피드 조회 (커서 페이지네이션)
  Future<CursorPage<WalkDiaryFeedItem>> getFeed({String? cursor, int limit});

  /// PATCH /walks/{walkId}/diary — 사진 문구 수정
  Future<WalkDiary> updateCaption({
    required int walkId,
    required int photoId,
    required String caption,
  });
}
