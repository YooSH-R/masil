/// 명세서 "11. 상태값 - 사진 처리 상태".
enum PhotoProcessingStatus { received, processing, completed, failed, unknown }

extension PhotoProcessingStatusX on PhotoProcessingStatus {
  String get label => switch (this) {
        PhotoProcessingStatus.received => '업로드 완료',
        PhotoProcessingStatus.processing => 'AI가 문구를 쓰고 있어요',
        PhotoProcessingStatus.completed => '완료',
        PhotoProcessingStatus.failed => '처리 실패',
        PhotoProcessingStatus.unknown => '알 수 없음',
      };

  bool get isPending =>
      this == PhotoProcessingStatus.received ||
      this == PhotoProcessingStatus.processing;

  bool get canRetry => this == PhotoProcessingStatus.failed;
}

/// 명세서 7.1/7.3의 산책 사진.
class WalkPhoto {
  const WalkPhoto({
    required this.photoId,
    required this.walkId,
    required this.processingStatus,
    this.caption,
    this.contentUrl,
    this.capturedAt,
    this.retryCount,
  });

  final int photoId;
  final int walkId;
  final PhotoProcessingStatus processingStatus;
  final String? caption;

  /// "/api/v1/photos/601/content" 형태의 상대 경로.
  final String? contentUrl;
  final DateTime? capturedAt;
  final int? retryCount;
}
