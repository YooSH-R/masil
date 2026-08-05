import 'walk.dart';
import 'walk_photo.dart';

/// 커서 기반 목록 (명세서 8.3 응답의 items/nextCursor/hasNext).
class CursorPage<T> {
  const CursorPage({
    required this.items,
    this.nextCursor,
    this.hasNext = false,
  });

  final List<T> items;
  final String? nextCursor;
  final bool hasNext;

  static CursorPage<T> empty<T>() => CursorPage<T>(items: const []);
}

/// 산책일지 생성 상태.
///
/// 마실이가 산책 내내 찍은 영상에서 괜찮은 장면을 골라 사진으로 만들고 문구까지
/// 붙이는 데 시간이 걸린다. **그래서 산책이 끝난 직후에는 일지가 아직 없다.**
/// 화면은 이 값으로 "만들고 있어요"를 띄울지, 사진을 보여줄지, 실패 안내를
/// 띄울지 정한다.
enum DiaryGenerationStatus {
  /// 아직 만드는 중. 일지 자체가 없어서 404 가 온 경우도 여기로 본다.
  generating,

  completed,

  /// 생성 실패 또는 시간 초과.
  failed,

  /// 서버가 상태를 안 알려줬다. 사진이 있으면 완성으로, 없으면 만드는 중으로 본다.
  unknown,
}

/// 명세서 8.2 산책일지 상세.
class WalkDiary {
  const WalkDiary({
    required this.walkId,
    this.petId,
    this.petName,
    this.walkedAt,
    this.durationSeconds,
    this.distanceMeters,
    this.route = const [],
    this.photos = const [],
    this.status = DiaryGenerationStatus.unknown,
  });

  /// 일지가 아직 만들어지지 않았을 때(서버가 404) 쓰는 껍데기.
  ///
  /// 화면이 "없음"과 "만드는 중"을 구분할 수 있게 한다. null 을 돌려주면
  /// 그 둘이 똑같아 보여서 사용자에게 그냥 오류처럼 보인다.
  factory WalkDiary.generating(int walkId) => WalkDiary(
        walkId: walkId,
        status: DiaryGenerationStatus.generating,
      );

  final int walkId;
  final int? petId;
  final String? petName;
  final DateTime? walkedAt;
  final int? durationSeconds;
  final int? distanceMeters;
  final List<WalkLocationPoint> route;
  final List<WalkPhoto> photos;
  final DiaryGenerationStatus status;

  /// 아직 만들어지는 중인지. 폴링을 계속할지 판단하는 기준이다.
  ///
  /// 서버가 상태를 안 주는 동안에는(=[DiaryGenerationStatus.unknown]) 사진
  /// 유무로 판단한다. 사진이 한 장이라도 있으면 완성된 것으로 본다.
  bool get isGenerating => switch (status) {
        DiaryGenerationStatus.generating => true,
        DiaryGenerationStatus.unknown => photos.isEmpty,
        _ => false,
      };

  bool get hasFailed => status == DiaryGenerationStatus.failed;

  /// 상태만 바꾼 사본. 기다리다 시간이 초과됐을 때 실패로 넘기는 데 쓴다.
  WalkDiary copyWithStatus(DiaryGenerationStatus status) => WalkDiary(
        walkId: walkId,
        petId: petId,
        petName: petName,
        walkedAt: walkedAt,
        durationSeconds: durationSeconds,
        distanceMeters: distanceMeters,
        route: route,
        photos: photos,
        status: status,
      );

  String get durationLabel {
    final seconds = durationSeconds;
    if (seconds == null) return '-';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '$minutes분';
    return '${minutes ~/ 60}시간 ${minutes % 60}분';
  }

  String get distanceLabel {
    final meters = distanceMeters;
    if (meters == null) return '-';
    if (meters < 1000) return '${meters}m';
    return '${(meters / 1000).toStringAsFixed(2)}km';
  }
}

/// 명세서 8.3 산책일지 피드 항목.
class WalkDiaryFeedItem {
  const WalkDiaryFeedItem({
    required this.walkId,
    this.walkedAt,
    this.durationSeconds,
    this.distanceMeters,
    this.thumbnailUrl,
    this.summary,
    this.deviceId,
    this.session,
  });

  final int walkId;
  final DateTime? walkedAt;
  final int? durationSeconds;
  final int? distanceMeters;
  final String? thumbnailUrl;
  final String? summary;
  final String? deviceId;
  final int? session;

  bool get isS3Diary => deviceId != null && session != null && walkedAt != null;

  WalkDiaryFeedItem copyWith({
    String? thumbnailUrl,
    String? summary,
  }) =>
      WalkDiaryFeedItem(
        walkId: walkId,
        walkedAt: walkedAt,
        durationSeconds: durationSeconds,
        distanceMeters: distanceMeters,
        thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
        summary: summary ?? this.summary,
        deviceId: deviceId,
        session: session,
      );

  String get durationLabel {
    final seconds = durationSeconds;
    if (seconds == null) return '-';
    return '${seconds ~/ 60}분';
  }
}

/// S3 고정 경로에서 조회한 산책일지 본문과 이미지.
class WalkDiaryContent {
  const WalkDiaryContent({
    required this.deviceId,
    required this.walkDate,
    required this.session,
    required this.imageUrl,
    required this.markdown,
    this.imageUrlExpiresAt,
  });

  final String deviceId;
  final DateTime walkDate;
  final int session;
  final String imageUrl;
  final String markdown;
  final DateTime? imageUrlExpiresAt;
}
