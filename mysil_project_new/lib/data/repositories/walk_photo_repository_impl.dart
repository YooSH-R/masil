import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/config/api_config.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/json_parse.dart';
import '../../domain/entities/walk_photo.dart';
import '../../domain/repositories/walk_photo_repository.dart';
import '../models/walk_photo_model.dart';

class WalkPhotoRepositoryImpl implements WalkPhotoRepository {
  WalkPhotoRepositoryImpl({required ApiClient client}) : _client = client;

  final ApiClient _client;

  @override
  Future<WalkPhoto> uploadPhoto({
    required int walkId,
    required String filePath,
    required int sequence,
    DateTime? capturedAt,
    String? checksum,
    void Function(int sent, int total)? onProgress,
  }) async {
    final formData = FormData.fromMap({
      'photo': await MultipartFile.fromFile(filePath),
      'capturedAt': (capturedAt ?? DateTime.now()).toUtc().toIso8601String(),
      'sequence': sequence,
      if (checksum != null) 'checksum': checksum,
    });

    final data = await _client.upload(
      ApiEndpoints.walkPhotos(walkId),
      formData: formData,
      idempotencyKey: 'walk-photo-$walkId-$sequence',
      timeout: ApiConfig.uploadTimeout,
      onSendProgress: onProgress == null
          ? null
          : (sent, total) => onProgress(sent, total),
    );
    return WalkPhotoModel.fromJson(Json.asMap(data), fallbackWalkId: walkId);
  }

  @override
  Future<WalkPhoto> getPhoto({
    required int walkId,
    required int photoId,
  }) async {
    final data = await _client.get(ApiEndpoints.walkPhoto(walkId, photoId));
    return WalkPhotoModel.fromJson(Json.asMap(data), fallbackWalkId: walkId);
  }

  @override
  Future<WalkPhoto> retryProcessing({
    required int walkId,
    required int photoId,
  }) async {
    final data = await _client.post(
      ApiEndpoints.walkPhotoRetry(walkId, photoId),
      idempotencyKey: 'retry-photo-$photoId-${DateTime.now().millisecondsSinceEpoch}',
    );
    return WalkPhotoModel.fromJson(Json.asMap(data), fallbackWalkId: walkId);
  }

  @override
  Future<void> deletePhoto({
    required int walkId,
    required int photoId,
  }) async {
    await _client.delete(ApiEndpoints.walkPhoto(walkId, photoId));
  }

  @override
  Stream<WalkPhoto> watchProcessing({
    required int walkId,
    required int photoId,
    Duration interval = const Duration(seconds: 3),
  }) async* {
    while (true) {
      try {
        final photo = await getPhoto(walkId: walkId, photoId: photoId);
        yield photo;
        if (!photo.processingStatus.isPending) return;
      } on ApiException {
        // 폴링 중 일시적 실패는 무시하고 다음 주기에 재시도.
      }
      await Future<void>.delayed(interval);
    }
  }

  @override
  String contentUrl(int photoId) =>
      '${ApiConfig.baseUrl}${ApiEndpoints.photoContent(photoId)}';

  @override
  Future<Uint8List> photoBytes(int photoId) async {
    final bytes = await _client.getBytes(ApiEndpoints.photoContent(photoId));
    return Uint8List.fromList(bytes);
  }
}
