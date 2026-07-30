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
  });

  final int walkId;
  final int? petId;
  final String? petName;
  final DateTime? walkedAt;
  final int? durationSeconds;
  final int? distanceMeters;
  final List<WalkLocationPoint> route;
  final List<WalkPhoto> photos;

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
  });

  final int walkId;
  final DateTime? walkedAt;
  final int? durationSeconds;
  final int? distanceMeters;
  final String? thumbnailUrl;
  final String? summary;

  String get durationLabel {
    final seconds = durationSeconds;
    if (seconds == null) return '-';
    return '${seconds ~/ 60}분';
  }
}
