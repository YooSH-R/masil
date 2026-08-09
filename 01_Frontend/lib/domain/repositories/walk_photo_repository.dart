import 'dart:typed_data';

import '../entities/walk_photo.dart';

/// 명세서 2.5 사진·GPT 처리 API.
abstract class WalkPhotoRepository {
  /// POST /walks/{walkId}/photos — 사진 업로드 (multipart/form-data)
  Future<WalkPhoto> uploadPhoto({
    required int walkId,
    required String filePath,
    required int sequence,
    DateTime? capturedAt,
    String? checksum,
    void Function(int sent, int total)? onProgress,
  });

  /// GET /walks/{walkId}/photos/{photoId} — GPT 처리 상태·문구 조회
  Future<WalkPhoto> getPhoto({required int walkId, required int photoId});

  /// POST /walks/{walkId}/photos/{photoId}/retry — GPT 처리 재시도
  Future<WalkPhoto> retryProcessing({
    required int walkId,
    required int photoId,
  });

  /// DELETE /walks/{walkId}/photos/{photoId} — 사진 삭제
  Future<void> deletePhoto({required int walkId, required int photoId});

  /// 처리가 끝날 때까지 상태를 폴링한다 (PROCESSING → COMPLETED/FAILED).
  Stream<WalkPhoto> watchProcessing({
    required int walkId,
    required int photoId,
    Duration interval,
  });

  /// GET /photos/{photoId}/content — 화면에서 바로 쓸 절대 URL
  String contentUrl(int photoId);

  /// GET /photos/{photoId}/content — 사진 원본 바이트.
  ///
  /// 갤러리 저장처럼 URL 이 아니라 실제 바이트가 필요할 때 쓴다. [contentUrl] 은
  /// 인증 헤더가 붙지 않아 `Image.network` 로는 못 받는 경우가 있는데, 이 쪽은
  /// ApiClient(=dio + AuthInterceptor)를 지나므로 토큰이 함께 나간다.
  Future<Uint8List> photoBytes(int photoId);
}
