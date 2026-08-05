import '../../core/utils/json_parse.dart';
import '../../domain/entities/walk_diary.dart';
import 'walk_model.dart';
import 'walk_photo_model.dart';

/// 일지 생성 상태 문자열 → enum.
///
/// 백엔드가 아직 개발 중이라 어떤 낱말을 쓸지 확정되지 않았다. 흔히 쓰는 값을
/// 모두 받아둬서, 서버가 붙었을 때 값이 조금 달라도 화면이 그대로 동작한다.
/// (여기에 없는 값이면 [DiaryGenerationStatus.unknown] 이 되고, 그때는 사진
/// 유무로 판단한다 — [WalkDiary.isGenerating] 참고)
const _diaryStatusMapping = <String, DiaryGenerationStatus>{
  'PENDING': DiaryGenerationStatus.generating,
  'PROCESSING': DiaryGenerationStatus.generating,
  'GENERATING': DiaryGenerationStatus.generating,
  'IN_PROGRESS': DiaryGenerationStatus.generating,
  'RECEIVED': DiaryGenerationStatus.generating,
  'COMPLETED': DiaryGenerationStatus.completed,
  'DONE': DiaryGenerationStatus.completed,
  'SUCCESS': DiaryGenerationStatus.completed,
  'FAILED': DiaryGenerationStatus.failed,
  'FAILURE': DiaryGenerationStatus.failed,
  'ERROR': DiaryGenerationStatus.failed,
  'TIMEOUT': DiaryGenerationStatus.failed,
};

class WalkDiaryModel extends WalkDiary {
  const WalkDiaryModel({
    required super.walkId,
    super.petId,
    super.petName,
    super.walkedAt,
    super.durationSeconds,
    super.distanceMeters,
    super.route,
    super.photos,
    super.status,
  });

  factory WalkDiaryModel.fromJson(Map<String, dynamic> json) {
    final walkId = Json.asInt(json['walkId']);
    final pet = Json.asMapOrNull(json['pet']);
    return WalkDiaryModel(
      walkId: walkId,
      petId: pet == null ? null : Json.asIntOrNull(pet['petId']),
      petName: pet == null ? null : Json.asStringOrNull(pet['name']),
      walkedAt: Json.asDateTime(json['walkedAt']),
      durationSeconds: Json.asIntOrNull(json['durationSeconds']),
      distanceMeters: Json.asIntOrNull(json['distanceMeters']),
      route: Json.asMapList(json['route'])
          .map(WalkLocationPointModel.fromJson)
          .toList(growable: false),
      photos: Json.asMapList(json['photos'])
          .map((p) => WalkPhotoModel.fromJson(p, fallbackWalkId: walkId))
          .toList(growable: false),
      // 필드 이름도 확정되지 않아 후보를 순서대로 본다.
      status: Json.asEnum(
        json['status'] ?? json['diaryStatus'] ?? json['generationStatus'],
        _diaryStatusMapping,
        DiaryGenerationStatus.unknown,
      ),
    );
  }
}

class WalkDiaryFeedItemModel extends WalkDiaryFeedItem {
  const WalkDiaryFeedItemModel({
    required super.walkId,
    super.walkedAt,
    super.durationSeconds,
    super.distanceMeters,
    super.thumbnailUrl,
    super.summary,
  });

  factory WalkDiaryFeedItemModel.fromJson(Map<String, dynamic> json) {
    return WalkDiaryFeedItemModel(
      walkId: Json.asInt(json['walkId']),
      walkedAt: Json.asDateTime(json['walkedAt']),
      durationSeconds: Json.asIntOrNull(json['durationSeconds']),
      distanceMeters: Json.asIntOrNull(json['distanceMeters']),
      thumbnailUrl: Json.asStringOrNull(json['thumbnailUrl']),
      summary: Json.asStringOrNull(json['summary']),
    );
  }
}

/// items/nextCursor/hasNext 형태의 목록 응답을 CursorPage로 변환.
CursorPage<T> parseCursorPage<T>(
  Map<String, dynamic> json,
  T Function(Map<String, dynamic>) itemParser,
) {
  return CursorPage<T>(
    items: Json.asMapList(json['items']).map(itemParser).toList(growable: false),
    nextCursor: Json.asStringOrNull(json['nextCursor']),
    hasNext: Json.asBool(json['hasNext']),
  );
}
