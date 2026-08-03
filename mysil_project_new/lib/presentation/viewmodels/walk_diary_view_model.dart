import '../../core/services/place_name_resolver.dart';
import '../../core/services/sample_walk_diaries.dart';
import '../../domain/entities/walk_diary.dart';
import '../../domain/repositories/walk_diary_repository.dart';
import 'base_view_model.dart';

/// 기간별 산책 집계. 주간·월간 통계 카드에 쓴다.
class WalkStats {
  const WalkStats({
    this.count = 0,
    this.totalMeters = 0,
    this.totalSeconds = 0,
  });

  final int count;
  final int totalMeters;
  final int totalSeconds;

  String get distanceLabel => '${(totalMeters / 1000).toStringAsFixed(1)} km';

  /// 3시간 12분 / 45분 형태.
  String get durationLabel {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    return h > 0 ? '$h시간 $m분' : '$m분';
  }

  String get countLabel => '$count 회';

  /// 평균 1회 거리. 산책이 없으면 0.0 km.
  String get averageDistanceLabel {
    if (count == 0) return '0.0 km';
    return '${(totalMeters / count / 1000).toStringAsFixed(1)} km';
  }
}

class WalkDiaryViewModel extends BaseViewModel {
  WalkDiaryViewModel(this._diaryRepository, {PlaceNameResolver? placeResolver})
      : _placeResolver = placeResolver ?? PlaceNameResolver();

  final WalkDiaryRepository _diaryRepository;
  final PlaceNameResolver _placeResolver;

  final List<WalkDiaryFeedItem> _feed = [];
  String? _nextCursor;
  bool _hasNext = true;
  bool _isLoadingMore = false;
  WalkDiary? _detail;

  /// walkId → 장소명. 역지오코딩 결과를 담아둔다.
  final Map<int, String?> _placeNames = {};

  List<WalkDiaryFeedItem> get feed => List.unmodifiable(_feed);
  bool get hasNext => _hasNext;
  bool get isLoadingMore => _isLoadingMore;
  bool get isEmpty => _feed.isEmpty && !isLoading;
  WalkDiary? get detail => _detail;

  /// 해당 산책의 장소명. 아직 못 구했으면 null.
  String? placeNameOf(int walkId) => _placeNames[walkId];

  /// 날짜(시각 제거) → 그 날의 산책들. 캘린더에 점을 찍는 데 쓴다.
  Map<DateTime, List<WalkDiaryFeedItem>> get byDate {
    final map = <DateTime, List<WalkDiaryFeedItem>>{};
    for (final item in _feed) {
      final at = item.walkedAt;
      if (at == null) continue;
      final key = DateTime(at.year, at.month, at.day);
      map.putIfAbsent(key, () => []).add(item);
    }
    return map;
  }

  /// 특정 날짜의 첫 산책. 없으면 null.
  WalkDiaryFeedItem? itemOn(DateTime date) {
    final key = DateTime(date.year, date.month, date.day);
    final items = byDate[key];
    return (items == null || items.isEmpty) ? null : items.first;
  }

  /// [anchor] 가 속한 주(월요일 시작)의 집계.
  WalkStats statsForWeek(DateTime anchor) {
    final start = DateTime(anchor.year, anchor.month, anchor.day)
        .subtract(Duration(days: anchor.weekday - 1));
    final end = start.add(const Duration(days: 7));
    return _aggregate((at) => !at.isBefore(start) && at.isBefore(end));
  }

  /// [anchor] 가 속한 달의 집계.
  WalkStats statsForMonth(DateTime anchor) {
    return _aggregate((at) => at.year == anchor.year && at.month == anchor.month);
  }

  WalkStats _aggregate(bool Function(DateTime walkedAt) inRange) {
    var count = 0;
    var meters = 0;
    var seconds = 0;
    for (final item in _feed) {
      final at = item.walkedAt;
      if (at == null || !inRange(at)) continue;
      count += 1;
      meters += item.distanceMeters ?? 0;
      seconds += item.durationSeconds ?? 0;
    }
    return WalkStats(
        count: count, totalMeters: meters, totalSeconds: seconds);
  }

  /// 날짜를 선택했을 때: 상세(경로 포함)를 불러오고 첫 좌표로 장소명을 구한다.
  ///
  /// 장소명 필드가 서버 응답에 없어서 좌표를 역지오코딩한다. 백엔드가 장소명을
  /// 내려주게 되면 이 두 번째 단계는 지워도 된다.
  Future<void> selectWalk(int walkId) async {
    // 7월 예시 데이터는 서버에 없다. 상세를 조회하면 401 만 나므로 건너뛴다.
    // 장소명은 이미 채워져 있다.
    if (SampleWalkDiaries.isSampleId(walkId)) {
      safeNotify();
      return;
    }

    await loadDetail(walkId);

    if (_placeNames.containsKey(walkId)) return;

    final route = _detail?.route;
    if (route == null || route.isEmpty) {
      _placeNames[walkId] = null;
      return;
    }

    final name = await _placeResolver.resolve(
      latitude: route.first.latitude,
      longitude: route.first.longitude,
    );
    _placeNames[walkId] = name;
    safeNotify();
  }

  /// GET /walk-diaries — 첫 페이지 (당겨서 새로고침 포함).
  Future<void> loadFeed({bool refresh = false}) async {
    if (refresh) {
      _feed.clear();
      _nextCursor = null;
      _hasNext = true;
    }

    final page = await guard(() => _diaryRepository.getFeed(limit: 20));

    _feed.clear();
    if (page != null) {
      _feed.addAll(page.items);
      _nextCursor = page.nextCursor;
      _hasNext = page.hasNext;
    }

    // 서버 기록을 담은 뒤 7월 예시 데이터를 합친다.
    // 조회가 실패해도(현재 산책 API 미배포) 예시는 보여야 하므로 page == null
    // 인 경우에도 실행한다.
    _mergeSamples();
    safeNotify();
  }

  /// 2026년 7월 예시 데이터를 합친다. 같은 날짜에 서버 기록이 있으면 넣지 않는다.
  ///
  /// 실제 산책 기록이 쌓이면 [SampleWalkDiaries.enabled] 를 false 로 바꾸거나
  /// 이 메서드와 호출부를 지우면 된다.
  void _mergeSamples() {
    if (!SampleWalkDiaries.enabled) return;

    final serverDays = _feed
        .map((e) => e.walkedAt)
        .whereType<DateTime>()
        .map((at) => DateTime(at.year, at.month, at.day))
        .toSet();

    for (final sample in SampleWalkDiaries.items) {
      final at = sample.walkedAt;
      if (at == null) continue;
      // 서버에 그 날 기록이 있으면 실제 데이터를 우선한다.
      if (serverDays.contains(DateTime(at.year, at.month, at.day))) continue;
      _feed.add(sample);
    }

    // 예시 데이터는 좌표가 없어 역지오코딩을 못 하므로 장소명을 미리 채운다.
    _placeNames.addAll(SampleWalkDiaries.placeNames);

    // 최신순으로 맞춘다(서버 피드도 최신순이다).
    _feed.sort((a, b) {
      final at = a.walkedAt;
      final bt = b.walkedAt;
      if (at == null || bt == null) return 0;
      return bt.compareTo(at);
    });
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
