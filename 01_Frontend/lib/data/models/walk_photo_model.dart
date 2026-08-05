import '../../core/utils/json_parse.dart';
import '../../domain/entities/walk_photo.dart';

const _photoStatusMapping = <String, PhotoProcessingStatus>{
  'RECEIVED': PhotoProcessingStatus.received,
  'PROCESSING': PhotoProcessingStatus.processing,
  'COMPLETED': PhotoProcessingStatus.completed,
  'FAILED': PhotoProcessingStatus.failed,
};

class WalkPhotoModel extends WalkPhoto {
  const WalkPhotoModel({
    required super.photoId,
    required super.walkId,
    required super.processingStatus,
    super.caption,
    super.contentUrl,
    super.capturedAt,
    super.retryCount,
  });

  /// [fallbackWalkId]: 산책일지 응답의 photos 항목에는 walkId가 없어서 상위에서 받아온다.
  factory WalkPhotoModel.fromJson(
    Map<String, dynamic> json, {
    int fallbackWalkId = 0,
  }) {
    return WalkPhotoModel(
      photoId: Json.asInt(json['photoId'] ?? json['id']),
      walkId: Json.asInt(json['walkId'], fallback: fallbackWalkId),
      processingStatus: Json.asEnum(
        json['processingStatus'],
        _photoStatusMapping,
        // 일지 응답처럼 상태 없이 caption만 오면 완료로 본다.
        json['caption'] == null
            ? PhotoProcessingStatus.unknown
            : PhotoProcessingStatus.completed,
      ),
      caption: Json.asStringOrNull(json['caption']),
      contentUrl: Json.asStringOrNull(json['contentUrl'] ?? json['thumbnailUrl']),
      capturedAt: Json.asDateTime(json['capturedAt']),
      retryCount: Json.asIntOrNull(json['retryCount']),
    );
  }
}
