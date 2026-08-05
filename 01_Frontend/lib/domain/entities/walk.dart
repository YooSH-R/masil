/// 명세서 "11. 상태값 - 산책 상태".
enum WalkStatus { ready, active, processing, completed, cancelled, unknown }

extension WalkStatusX on WalkStatus {
  String get label => switch (this) {
        WalkStatus.ready => '준비됨',
        WalkStatus.active => '산책 중',
        WalkStatus.processing => '기록 정리 중',
        WalkStatus.completed => '완료',
        WalkStatus.cancelled => '취소됨',
        WalkStatus.unknown => '알 수 없음',
      };

  bool get isFinished =>
      this == WalkStatus.completed || this == WalkStatus.cancelled;
}

/// 명세서 6.1 현재 산책 제안.
class WalkProposal {
  const WalkProposal({
    required this.proposalId,
    required this.petId,
    required this.message,
    this.reason,
    this.expiresAt,
  });

  final int proposalId;
  final int petId;
  final String message;
  final String? reason;
  final DateTime? expiresAt;

  bool get isExpired =>
      expiresAt != null && DateTime.now().toUtc().isAfter(expiresAt!);
}

/// 명세서 6.3~8.1의 산책 세션.
class Walk {
  const Walk({
    required this.walkId,
    required this.status,
    this.createdAt,
    this.startedAt,
    this.endedAt,
    this.durationSeconds,
    this.distanceMeters,
  });

  final int walkId;
  final WalkStatus status;
  final DateTime? createdAt;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int? durationSeconds;
  final int? distanceMeters;

  /// "30분" 같은 표시용 문자열.
  String get durationLabel {
    final seconds = durationSeconds;
    if (seconds == null) return '-';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '$minutes분';
    return '${minutes ~/ 60}시간 ${minutes % 60}분';
  }

  /// "2.15km" 같은 표시용 문자열.
  String get distanceLabel {
    final meters = distanceMeters;
    if (meters == null) return '-';
    if (meters < 1000) return '${meters}m';
    return '${(meters / 1000).toStringAsFixed(2)}km';
  }
}

/// GPS 좌표 한 점 (명세서 6.5).
class WalkLocationPoint {
  const WalkLocationPoint({
    required this.latitude,
    required this.longitude,
    required this.sequence,
    required this.recordedAt,
    this.accuracy,
  });

  final double latitude;
  final double longitude;
  final int sequence;
  final DateTime recordedAt;
  final double? accuracy;

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        if (accuracy != null) 'accuracy': accuracy,
        'sequence': sequence,
        'recordedAt': recordedAt.toUtc().toIso8601String(),
      };
}

/// 좌표 일괄 저장 결과 (명세서 6.5 응답).
class WalkLocationBatchResult {
  const WalkLocationBatchResult({
    required this.walkId,
    required this.receivedCount,
    required this.savedCount,
    required this.rejectedCount,
  });

  final int walkId;
  final int receivedCount;
  final int savedCount;
  final int rejectedCount;
}

/// 명세서 2.4 GET /walks/{walkId}/summary.
class WalkSummary {
  const WalkSummary({
    required this.walkId,
    this.durationSeconds,
    this.distanceMeters,
    this.route = const [],
    this.startedAt,
    this.endedAt,
  });

  final int walkId;
  final int? durationSeconds;
  final int? distanceMeters;
  final List<WalkLocationPoint> route;
  final DateTime? startedAt;
  final DateTime? endedAt;
}
