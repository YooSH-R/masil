import '../../core/utils/json_parse.dart';
import '../../core/utils/korea_time.dart';
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
      walkedAt: KoreaTime.fromNullableInstant(
        Json.asDateTime(json['walkedAt']),
      ),
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
    super.deviceId,
    super.session,
  });

  factory WalkDiaryFeedItemModel.fromJson(Map<String, dynamic> json) {
    return WalkDiaryFeedItemModel(
      walkId: Json.asInt(json['walkId']),
      walkedAt: KoreaTime.fromNullableInstant(
        Json.asDateTime(json['walkedAt']),
      ),
      durationSeconds: Json.asIntOrNull(json['durationSeconds']),
      distanceMeters: Json.asIntOrNull(json['distanceMeters']),
      thumbnailUrl: Json.asStringOrNull(json['thumbnailUrl']),
      summary: Json.asStringOrNull(json['summary']),
      deviceId: Json.asStringOrNull(json['deviceId']),
      session: Json.asIntOrNull(json['session']),
    );
  }

  /// 새 S3 피드의 날짜별 묶음을 화면이 쓰는 일지 목록으로 펼친다.
  static List<WalkDiaryFeedItem> fromS3Day(Map<String, dynamic> json) {
    final walkDate = _parseDateOnly(json['walkDate']);
    if (walkDate == null) return const [];

    return Json.asMapList(json['diaries']).map((diary) {
      final deviceId = Json.asString(diary['deviceId']);
      final session = Json.asInt(diary['session']);
      return WalkDiaryFeedItem(
        walkId: _s3DiaryId(deviceId, walkDate, session),
        walkedAt: walkDate,
        deviceId: deviceId,
        session: session,
      );
    }).toList(growable: false);
  }
}

int _s3DiaryId(String deviceId, DateTime date, int session) {
  final hash = Object.hash(deviceId, date.year, date.month, date.day, session);
  // 예시 ID(-1~-10) 및 로컬 산책 ID(-10억 이하)와 겹치지 않는 범위다.
  return -100000 - (hash & 0x1fffffff);
}

class WalkDiaryContentModel extends WalkDiaryContent {
  const WalkDiaryContentModel({
    required super.deviceId,
    required super.walkDate,
    required super.session,
    required super.imageUrls,
    required super.markdown,
    super.imageUrlExpiresAt,
  });

  factory WalkDiaryContentModel.fromJson(Map<String, dynamic> json) {
    return WalkDiaryContentModel(
      deviceId: Json.asString(json['deviceId']),
      walkDate: _parseDateOnly(json['walkDate']) ?? DateTime.utc(1970),
      session: Json.asInt(json['session']),
      imageUrls: _parseImageUrls(json),
      markdown: Json.asString(json['markdown']),
      imageUrlExpiresAt: Json.asDateTime(json['imageUrlExpiresAt']),
    );
  }

  /// `imageUrls` 를 쓰고, 없으면 옛 응답의 `imageUrl` 한 장으로 받아준다.
  /// 서버가 아직 배포되지 않은 동안에도 화면이 비지 않게 한다.
  static List<String> _parseImageUrls(Map<String, dynamic> json) {
    final raw = json['imageUrls'];
    if (raw is List) {
      final urls = raw
          .map((entry) => entry?.toString() ?? '')
          .where((url) => url.isNotEmpty)
          .toList(growable: false);
      if (urls.isNotEmpty) return urls;
    }
    final single = Json.asStringOrNull(json['imageUrl']);
    return single == null || single.isEmpty ? const [] : [single];
  }
}

/// 서버의 LocalDate(`yyyy-MM-dd`)는 순간 시각이 아니다. 문자열의 연·월·일을
/// UTC DateTime에 담아 어느 기기에서도 같은 달력 날짜로 비교되게 한다.
DateTime? _parseDateOnly(Object? raw) {
  final value = raw?.toString();
  if (value == null) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return null;
  return DateTime.utc(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
}

/// items/nextCursor/hasNext 형태의 목록 응답을 CursorPage로 변환.
CursorPage<T> parseCursorPage<T>(
  Map<String, dynamic> json,
  T Function(Map<String, dynamic>) itemParser,
) {
  return CursorPage<T>(
    items:
        Json.asMapList(json['items']).map(itemParser).toList(growable: false),
    nextCursor: Json.asStringOrNull(json['nextCursor']),
    hasNext: Json.asBool(json['hasNext']),
  );
}
