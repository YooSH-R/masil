import '../../core/utils/json_parse.dart';
import '../../domain/entities/walk_diary.dart';
import 'walk_model.dart';
import 'walk_photo_model.dart';

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
