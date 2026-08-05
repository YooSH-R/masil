import 'dart:async';
import 'dart:typed_data';

import '../../core/services/gallery_saver.dart';
import '../../domain/entities/walk_photo.dart';
import '../../domain/repositories/walk_photo_repository.dart';
import 'base_view_model.dart';

/// 여러 장을 한 번에 저장한 결과.
class GallerySaveSummary {
  const GallerySaveSummary({
    required this.saved,
    required this.total,
    this.firstFailure,
  });

  final int saved;
  final int total;

  /// 실패가 있었다면 그중 첫 사유. 안내 문구를 고르는 데 쓴다.
  final GallerySaveOutcome? firstFailure;

  bool get allSaved => saved == total && total > 0;
  bool get noneSaved => saved == 0;

  String get message {
    if (total == 0) return '저장할 사진을 골라 주세요';
    if (allSaved) {
      return total == 1 ? '사진을 갤러리에 저장했어요' : '사진 $total장을 갤러리에 저장했어요';
    }
    if (noneSaved) {
      return firstFailure?.message ?? '저장하지 못했어요';
    }
    return '$total장 중 $saved장만 저장했어요. ${firstFailure?.message ?? ''}'.trim();
  }
}

class WalkPhotoViewModel extends BaseViewModel {
  WalkPhotoViewModel(
    this._photoRepository, {
    GallerySaver gallerySaver = const GallerySaver(),
  }) : _gallerySaver = gallerySaver;

  final WalkPhotoRepository _photoRepository;
  final GallerySaver _gallerySaver;

  final List<WalkPhoto> _photos = [];
  double _uploadProgress = 0;
  StreamSubscription<WalkPhoto>? _watchSub;

  /// photoId → 사진 원본 바이트.
  ///
  /// `/photos/{id}/content` 는 인증이 필요해서 `Image.network` 로는 401 이 날 수
  /// 있다. 그래서 ApiClient(토큰 붙음)로 바이트를 받아 `Image.memory` 로 그린다.
  /// 갤러리 저장에도 같은 바이트를 재사용하므로 저장이 즉시 끝난다.
  final Map<int, Uint8List> _bytes = {};

  /// 지금 바이트를 받아오는 중인 photoId. 같은 사진을 두 번 요청하지 않는다.
  final Set<int> _loadingBytes = {};

  /// 바이트 받기에 실패한 photoId. 무한 재요청을 막는다.
  final Set<int> _failedBytes = {};

  bool _isSaving = false;

  List<WalkPhoto> get photos => List.unmodifiable(_photos);
  double get uploadProgress => _uploadProgress;
  bool get isUploading => isLoading && _uploadProgress > 0;

  /// 갤러리 저장이 진행 중인지. 버튼 중복 탭을 막는 데 쓴다.
  bool get isSaving => _isSaving;

  /// 이미 받아둔 바이트. 없으면 null (그 사이에는 로딩 표시를 띄운다).
  Uint8List? bytesOf(int photoId) => _bytes[photoId];
  bool isLoadingBytesOf(int photoId) => _loadingBytes.contains(photoId);
  bool didFailBytesOf(int photoId) => _failedBytes.contains(photoId);

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

  /// 사진 바이트를 받아 캐시에 담는다. 이미 있으면 아무것도 하지 않는다.
  ///
  /// 그리기용으로 build 안에서 호출해도 안전하다(중복 요청·재실패를 막는다).
  Future<void> ensureBytes(int photoId) async {
    if (_bytes.containsKey(photoId) ||
        _loadingBytes.contains(photoId) ||
        _failedBytes.contains(photoId)) {
      return;
    }

    _loadingBytes.add(photoId);
    safeNotify();

    // silent: 사진 한 장을 못 받은 것으로 화면 전체를 에러로 만들지 않는다.
    // 실패한 칸에만 표시하고 나머지는 그대로 보여준다.
    final bytes = await guard(
      () => _photoRepository.photoBytes(photoId),
      silent: true,
    );

    _loadingBytes.remove(photoId);
    if (bytes == null || bytes.isEmpty) {
      _failedBytes.add(photoId);
    } else {
      _bytes[photoId] = bytes;
    }
    safeNotify();
  }

  /// 실패한 사진을 다시 받아본다.
  Future<void> retryBytes(int photoId) async {
    _failedBytes.remove(photoId);
    await ensureBytes(photoId);
  }

  /// 고른 사진들을 이 기기 갤러리에 저장한다.
  ///
  /// 한 장이 실패해도 나머지는 계속 저장한다. 결과는 [GallerySaveSummary] 로
  /// 돌려주므로 화면이 스낵바 문구를 고르면 된다.
  Future<GallerySaveSummary> saveToGallery(Iterable<int> photoIds) async {
    final ids = photoIds.toList(growable: false);
    if (ids.isEmpty || _isSaving) {
      return const GallerySaveSummary(saved: 0, total: 0);
    }

    _isSaving = true;
    safeNotify();

    var saved = 0;
    GallerySaveOutcome? firstFailure;

    for (final id in ids) {
      // 화면에 이미 그려진 사진이면 캐시가 채워져 있어 그대로 저장된다.
      await ensureBytes(id);
      final bytes = _bytes[id];
      if (bytes == null) {
        firstFailure ??= GallerySaveOutcome.failed;
        continue;
      }

      final outcome = await _gallerySaver.saveImage(bytes, name: 'mysil-$id');
      if (outcome.isSuccess) {
        saved += 1;
      } else {
        firstFailure ??= outcome;
        // 권한 거부는 다음 장도 똑같이 막히므로 더 시도하지 않는다.
        if (outcome == GallerySaveOutcome.permissionDenied) break;
      }
    }

    _isSaving = false;
    safeNotify();
    return GallerySaveSummary(
      saved: saved,
      total: ids.length,
      firstFailure: firstFailure,
    );
  }

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
