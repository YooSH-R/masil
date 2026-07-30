import 'dart:async';

import '../../domain/entities/walk_photo.dart';
import '../../domain/repositories/walk_photo_repository.dart';
import 'base_view_model.dart';

class WalkPhotoViewModel extends BaseViewModel {
  WalkPhotoViewModel(this._photoRepository);

  final WalkPhotoRepository _photoRepository;

  final List<WalkPhoto> _photos = [];
  double _uploadProgress = 0;
  StreamSubscription<WalkPhoto>? _watchSub;

  List<WalkPhoto> get photos => List.unmodifiable(_photos);
  double get uploadProgress => _uploadProgress;
  bool get isUploading => isLoading && _uploadProgress > 0;

  /// POST /walks/{walkId}/photos — 업로드 후 처리 상태 폴링까지 시작.
  Future<WalkPhoto?> uploadPhoto({
    required int walkId,
    required String filePath,
    DateTime? capturedAt,
  }) async {
    _uploadProgress = 0;
    final sequence = _photos.length + 1;

    final photo = await guard(() => _photoRepository.uploadPhoto(
          walkId: walkId,
          filePath: filePath,
          sequence: sequence,
          capturedAt: capturedAt,
          onProgress: (sent, total) {
            if (total <= 0) return;
            _uploadProgress = sent / total;
            safeNotify();
          },
        ));

    _uploadProgress = 0;
    if (photo == null) return null;

    _photos.add(photo);
    safeNotify();

    // 업로드 응답은 PROCESSING이므로 문구가 생길 때까지 지켜본다.
    if (photo.processingStatus.isPending) {
      watchProcessing(walkId: walkId, photoId: photo.photoId);
    }
    return photo;
  }

  /// GET /walks/{walkId}/photos/{photoId} 폴링.
  void watchProcessing({required int walkId, required int photoId}) {
    _watchSub?.cancel();
    _watchSub = _photoRepository
        .watchProcessing(walkId: walkId, photoId: photoId)
        .listen(_replacePhoto);
  }

  /// POST /walks/{walkId}/photos/{photoId}/retry — 실패한 사진 재처리.
  Future<bool> retry({required int walkId, required int photoId}) async {
    final photo = await guard(() => _photoRepository.retryProcessing(
          walkId: walkId,
          photoId: photoId,
        ));
    if (photo == null) return false;

    _replacePhoto(photo);
    watchProcessing(walkId: walkId, photoId: photoId);
    return true;
  }

  /// DELETE /walks/{walkId}/photos/{photoId}
  Future<bool> deletePhoto({required int walkId, required int photoId}) async {
    await guard(() => _photoRepository.deletePhoto(
          walkId: walkId,
          photoId: photoId,
        ));
    if (hasError) return false;

    _photos.removeWhere((p) => p.photoId == photoId);
    safeNotify();
    return true;
  }

  String contentUrl(int photoId) => _photoRepository.contentUrl(photoId);

  /// 산책일지 상세에서 가져온 사진 목록을 그대로 표시할 때 사용.
  void setPhotos(List<WalkPhoto> photos) {
    _photos
      ..clear()
      ..addAll(photos);
    safeNotify();
  }

  void _replacePhoto(WalkPhoto photo) {
    final index = _photos.indexWhere((p) => p.photoId == photo.photoId);
    if (index >= 0) {
      _photos[index] = photo;
    } else {
      _photos.add(photo);
    }
    safeNotify();
  }

  @override
  void dispose() {
    _watchSub?.cancel();
    super.dispose();
  }
}
