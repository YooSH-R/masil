import '../../domain/entities/walk_diary.dart';
import '../../domain/repositories/walk_diary_repository.dart';
import 'base_view_model.dart';

class WalkDiaryViewModel extends BaseViewModel {
  WalkDiaryViewModel(this._diaryRepository);

  final WalkDiaryRepository _diaryRepository;

  final List<WalkDiaryFeedItem> _feed = [];
  String? _nextCursor;
  bool _hasNext = true;
  bool _isLoadingMore = false;
  WalkDiary? _detail;

  List<WalkDiaryFeedItem> get feed => List.unmodifiable(_feed);
  bool get hasNext => _hasNext;
  bool get isLoadingMore => _isLoadingMore;
  bool get isEmpty => _feed.isEmpty && !isLoading;
  WalkDiary? get detail => _detail;

  /// GET /walk-diaries — 첫 페이지 (당겨서 새로고침 포함).
  Future<void> loadFeed({bool refresh = false}) async {
    if (refresh) {
      _feed.clear();
      _nextCursor = null;
      _hasNext = true;
    }

    final page = await guard(() => _diaryRepository.getFeed(limit: 20));
    if (page == null) return;

    _feed
      ..clear()
      ..addAll(page.items);
    _nextCursor = page.nextCursor;
    _hasNext = page.hasNext;
    safeNotify();
  }

  /// 다음 커서 페이지 추가 로드.
  Future<void> loadMore() async {
    if (!_hasNext || _isLoadingMore || _nextCursor == null) return;

    _isLoadingMore = true;
    safeNotify();

    final page = await guard(
      () => _diaryRepository.getFeed(cursor: _nextCursor, limit: 20),
      silent: true,
    );

    _isLoadingMore = false;
    if (page == null) {
      safeNotify();
      return;
    }

    _feed.addAll(page.items);
    _nextCursor = page.nextCursor;
    _hasNext = page.hasNext;
    safeNotify();
  }

  /// GET /walks/{walkId}/diary — 상세.
  Future<void> loadDetail(int walkId) async {
    final diary = await guard(() => _diaryRepository.getDiary(walkId));
    if (diary == null) return;

    _detail = diary;
    safeNotify();
  }

  /// PATCH /walks/{walkId}/diary — 사진 문구 수정.
  Future<bool> updateCaption({
    required int walkId,
    required int photoId,
    required String caption,
  }) async {
    final diary = await guard(() => _diaryRepository.updateCaption(
          walkId: walkId,
          photoId: photoId,
          caption: caption,
        ));
    if (diary == null) return false;

    _detail = diary;
    safeNotify();
    return true;
  }
}
