import 'dart:async';

import '../../core/services/place_name_resolver.dart';
import '../../core/services/sample_august_routes.dart';
import '../../core/services/sample_walk_diaries.dart';
import '../../core/services/walk_record_store.dart';
import '../../core/utils/walk_log_markdown.dart';
import '../../core/utils/korea_time.dart';
import '../../domain/entities/walk.dart';
import '../../domain/entities/walk_diary.dart';
import '../../domain/entities/walk_progress.dart';
import '../../domain/repositories/walk_diary_repository.dart';
import '../../domain/repositories/walk_repository.dart';
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

/// 서버 산책과 그 시작 시각(KST). 같은 날 산책을 순서대로 세울 때 쓴다.
class _DatedWalk {
  const _DatedWalk(this.at, this.walk);

  final DateTime at;
  final Walk walk;
}

class WalkDiaryViewModel extends BaseViewModel {
  WalkDiaryViewModel(
    this._diaryRepository, {
    WalkRepository? walkRepository,
    PlaceNameResolver? placeResolver,
  })  : _walkRepository = walkRepository,
        _placeResolver = placeResolver ?? PlaceNameResolver();

  final WalkDiaryRepository _diaryRepository;

  /// 서버에 남은 산책 목록의 출처.
  ///
  /// **일지 피드(GET /walk-diaries)만으로는 부족하다.** 그 피드는 마실이 기기가
  /// S3에 올린 사진·일지만 훑는다. 앱에서 걸은 산책은 S3에 아무것도 올리지
  /// 않으므로 거기 나오지 않고, 그러면 같은 계정으로 로그인한 다른 기기에서
  /// 그 산책이 영영 보이지 않는다.
  final WalkRepository? _walkRepository;

  final PlaceNameResolver _placeResolver;

  /// 기기에 저장한 산책 기록. 서버에 못 올린 산책의 마지막 보루다
  /// ([WalkRecordStore] 주석 참고).
  final WalkRecordStore _recordStore = const WalkRecordStore();

  final List<WalkDiaryFeedItem> _feed = [];
  String? _nextCursor;
  bool _hasNext = true;
  bool _isLoadingMore = false;
  WalkDiary? _detail;

  /// walkId → 장소명. 역지오코딩 결과를 담아둔다.
  final Map<int, String?> _placeNames = {};

  /// 마지막으로 계산한 산책 진행 상황. [safeNotify] 에서 비운다.
  WalkProgress? _progress;

  // --- 일지 생성 대기 ---

  Timer? _diaryPollTimer;
  int? _watchedWalkId;
  DateTime? _watchStartedAt;

  /// 일지가 완성됐는지 다시 물어보는 주기.
  static const Duration _diaryPollInterval = Duration(seconds: 5);

  /// 이만큼 기다려도 안 끝나면 실패로 본다.
  /// 영상에서 사진을 뽑고 문구까지 붙이는 시간을 넉넉히 잡았다.
  static const Duration _generationTimeout = Duration(minutes: 3);

  List<WalkDiaryFeedItem> get feed => List.unmodifiable(_feed);

  /// 오늘 산책 횟수·누적 횟수·받은 리본. 홈과 친밀도 화면이 함께 쓴다.
  ///
  /// **화면의 build 안에서 계산하지 않는다.** 산책 중에는
  /// [WalkViewModel] 의 경과 시간 타이머가 1초마다 알림을 보내고, `loadMore`
  /// 는 피드를 계속 누적하므로 화면마다 매번 다시 정렬·집계하게 된다. 여기서
  /// 한 번 계산해 두면 알림 1회당 최대 한 번만 돌고, 두 화면이 같은 값을
  /// 본다는 것도 구조로 보장된다.
  WalkProgress get progress => _progress ??= WalkProgress.from(
        _feed.map((item) => item.walkedAt).whereType<DateTime>(),
      );

  /// 피드를 고치는 지점이 여러 곳(`loadFeed`·`loadMore`·`_mergeLocalRecords`·
  /// `_mergeSamples`·항목 갱신)인데 전부 이 알림을 거친다. 그래서 무효화를
  /// 여기 한 곳에만 두면 나중에 변경 지점이 늘어도 빠뜨릴 수 없다. 각 메서드
  /// 끝에서 다시 계산하는 방식은 한 곳을 잊으면 낡은 값을 조용히 보여준다.
  @override
  void safeNotify() {
    _progress = null;
    super.safeNotify();
  }
  bool get hasNext => _hasNext;
  bool get isLoadingMore => _isLoadingMore;
  bool get isEmpty => _feed.isEmpty && !isLoading;
  WalkDiary? get detail => _detail;

  /// 일지를 아직 만들고 있는지. 화면이 "만들고 있어요"를 띄우는 기준.
  bool get isDiaryGenerating => _detail?.isGenerating ?? false;

  /// 생성이 실패했거나 시간을 초과했는지.
  bool get hasDiaryFailed => _detail?.hasFailed ?? false;

  /// 해당 산책의 장소명. 아직 못 구했으면 null.
  String? placeNameOf(int walkId) => _placeNames[walkId];

  /// 날짜(시각 제거) → 그 날의 산책들. 캘린더에 점을 찍는 데 쓴다.
  Map<DateTime, List<WalkDiaryFeedItem>> get byDate {
    final map = <DateTime, List<WalkDiaryFeedItem>>{};
    for (final item in _feed) {
      final at = item.walkedAt;
      if (at == null) continue;
      final key = DateTime.utc(at.year, at.month, at.day);
      map.putIfAbsent(key, () => []).add(item);
    }
    return map;
  }

  /// 특정 날짜의 첫 산책. 없으면 null.
  WalkDiaryFeedItem? itemOn(DateTime date) {
    final items = itemsOn(date);
    return items.isEmpty ? null : items.first;
  }

  /// 특정 날짜의 모든 산책. 하루에 여러 번 걸어도 세션을 잃지 않는다.
  ///
  /// S3 일지는 session 순서로, 앱에서 저장한 기록은 시작 시각 순서로 보여준다.
  List<WalkDiaryFeedItem> itemsOn(DateTime date) {
    final key = DateTime.utc(date.year, date.month, date.day);
    final items = List<WalkDiaryFeedItem>.of(
      byDate[key] ?? const <WalkDiaryFeedItem>[],
    );
    items.sort((a, b) {
      final aSession = a.session;
      final bSession = b.session;
      if (aSession != null && bSession != null) {
        return aSession.compareTo(bSession);
      }
      final aAt = a.walkedAt;
      final bAt = b.walkedAt;
      if (aAt == null || bAt == null) return 0;
      return aAt.compareTo(bAt);
    });
    return List.unmodifiable(items);
  }

  /// [anchor] 날 하루의 집계.
  WalkStats statsForDay(DateTime anchor) {
    final day = DateTime.utc(anchor.year, anchor.month, anchor.day);
    final next = day.add(const Duration(days: 1));
    return _aggregate((at) => !at.isBefore(day) && at.isBefore(next));
  }

  /// [anchor] 가 속한 주의 **요일별 이동거리(m)**. 월요일부터 7칸.
  /// 막대그래프가 쓴다. 기록이 없는 요일은 0 이다.
  List<int> weekdayMeters(DateTime anchor) {
    final monday = DateTime.utc(anchor.year, anchor.month, anchor.day)
        .subtract(Duration(days: anchor.weekday - 1));
    return [
      for (var i = 0; i < 7; i++)
        statsForDay(monday.add(Duration(days: i))).totalMeters,
    ];
  }

  /// [anchor] 가 속한 주(월요일 시작)의 집계.
  WalkStats statsForWeek(DateTime anchor) {
    final start = DateTime.utc(anchor.year, anchor.month, anchor.day)
        .subtract(Duration(days: anchor.weekday - 1));
    final end = start.add(const Duration(days: 7));
    return _aggregate((at) => !at.isBefore(start) && at.isBefore(end));
  }

  /// [anchor] 가 속한 달의 집계.
  WalkStats statsForMonth(DateTime anchor) {
    return _aggregate(
        (at) => at.year == anchor.year && at.month == anchor.month);
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
    return WalkStats(count: count, totalMeters: meters, totalSeconds: seconds);
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

    // 기기에 저장한 산책. 서버에 일지 API 가 없으니 조회하지 않고, 저장된
    // 경로의 첫 좌표로 장소명만 구한다(산책 장소 표시에 쓴다).
    if (WalkRecordStore.isLocalId(walkId)) {
      if (_placeNames.containsKey(walkId)) return;

      final record = await _recordStore.read(walkId);
      final route = record?.route ?? const [];
      if (route.isEmpty) {
        _placeNames[walkId] = null;
        return;
      }
      _placeNames[walkId] = await _placeResolver.resolve(
        latitude: route.first.latitude,
        longitude: route.first.longitude,
      );
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

  /// 피드에서 날짜를 선택했을 때 출처에 맞는 상세를 불러온다.
  ///
  /// S3 일지는 walkId가 없으므로 deviceId/date/session 조합을 사용한다.
  /// 상세 응답의 Presigned URL과 Markdown을 피드 항목에 합쳐 기존 화면이
  /// 그대로 이미지와 본문을 표시할 수 있게 한다.
  Future<void> selectFeedItem(WalkDiaryFeedItem item) async {
    if (!item.isS3Diary) {
      await selectWalk(item.walkId);
      return;
    }

    final content = await guard(
      () => _diaryRepository.getS3Diary(
        deviceId: item.deviceId!,
        walkDate: item.walkedAt!,
        session: item.session!,
      ),
    );
    if (content == null) return;

    final index = _feed.indexWhere((entry) => entry.walkId == item.walkId);
    if (index == -1) return;
    _feed[index] = _feed[index].copyWith(
      thumbnailUrl: content.coverImageUrl,
      imageUrls: content.imageUrls,
      // 목록에는 기호를 걷어낸 한 줄만 넣는다. 원문을 그대로 넣으면 `##` 이나
      // `**` 가 화면에 그대로 보인다. 서식이 필요한 본문은 markdown 을 쓴다.
      summary: WalkLogMarkdown.summaryLine(content.markdown),
      markdown: content.markdown,
    );
    // 시연용 경로가 붙은 일지는 장소명도 같이 넣어 뒀다. 그게 없을 때만 비운다.
    _placeNames[item.walkId] = SampleAugustRoutes.placeOf(item.walkId);
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

    // 서버에 남은 산책을 합친다. 앱에서 걸은 산책은 S3 일지를 만들지 않으므로
    // 위의 피드에는 없고 여기서만 온다. 이 기록은 계정에 붙어 있어서 같은
    // 계정으로 로그인한 다른 기기에서도 그대로 보인다.
    await _mergeServerWalks();

    // 8/3~8/7 시연용 일지에는 GPS 가 없다. 짝지을 산책이 없는 항목에만 채운다.
    _fillSampleAugustRoutes();

    // 그다음 기기에만 있는 기록을 합친다. 서버에 올리지 못한 산책이다.
    await _mergeLocalRecords();

    // 마지막으로 7월 예시 데이터를 합친다.
    // 조회가 실패해도 예시는 보여야 하므로 page == null 인 경우에도 실행한다.
    _mergeSamples();
    _sortByRecent();
    safeNotify();
  }

  /// GET /walks — 서버에 남은 산책을 피드에 넣는다.
  ///
  /// **산책 하나는 두 곳에서 만들어진다.** 앱이 GPS로 경로·거리·시간을 만들어
  /// 서버에 남기고, 마실이를 거치대에 꽂으면 기기가 사진이 들어간 일지를 S3에
  /// 올린다. 둘은 같은 산책이므로 피드에서 한 줄로 합쳐야 한다. 따로 넣으면
  /// 산책 한 번이 두 번 걸은 것처럼 보이고 통계도 두 배가 된다.
  ///
  /// 짝을 맞추는 기준은 **날짜 + 그날의 순서**다. S3 일지에는 산책 시각이 없고
  /// 날짜와 회차(session)만 있어서 시각으로는 맞출 수 없다.
  ///
  /// 끝난 산책만 넣는다. 진행 중인 산책은 거리·시간이 아직 확정되지 않아
  /// 일지에 0km 로 박힌다.
  Future<void> _mergeServerWalks() async {
    final repository = _walkRepository;
    if (repository == null) return;

    final page = await guard(
      () => repository.getWalks(limit: 50),
      silent: true,
    );
    if (page == null) return;

    final byDay = <DateTime, List<_DatedWalk>>{};
    for (final walk in page.items) {
      if (!walk.status.isFinished) continue;
      final at =
          KoreaTime.fromNullableInstant(walk.startedAt ?? walk.createdAt);
      if (at == null) continue;
      byDay.putIfAbsent(_dayKey(at), () => []).add(_DatedWalk(at, walk));
    }

    for (final day in byDay.keys) {
      final walks = byDay[day]!..sort((a, b) => a.at.compareTo(b.at));

      // 그날의 S3 일지를 회차 순으로 세운다. n번째 일지가 n번째 산책이다.
      final diaryIndexes = <int>[];
      for (var i = 0; i < _feed.length; i++) {
        final item = _feed[i];
        final at = item.walkedAt;
        if (at == null || !item.isS3Diary || _dayKey(at) != day) continue;
        diaryIndexes.add(i);
      }
      diaryIndexes.sort(
        (a, b) => (_feed[a].session ?? 0).compareTo(_feed[b].session ?? 0),
      );

      for (var i = 0; i < walks.length; i++) {
        final walk = walks[i].walk;
        if (i < diaryIndexes.length) {
          final item = _feed[diaryIndexes[i]];
          // walkId 를 서버 것으로 바꾼다. 그래야 경로 상세가
          // GET /walks/{walkId}/summary 로 실제 걸은 경로를 그린다.
          // deviceId·session 은 그대로 둬서 사진·본문 조회도 계속 된다.
          _feed[diaryIndexes[i]] = WalkDiaryFeedItem(
            walkId: walk.walkId,
            walkedAt: item.walkedAt,
            durationSeconds: walk.durationSeconds ?? item.durationSeconds,
            distanceMeters: walk.distanceMeters ?? item.distanceMeters,
            thumbnailUrl: item.thumbnailUrl,
            imageUrls: item.imageUrls,
            summary: item.summary,
            markdown: item.markdown,
            deviceId: item.deviceId,
            session: item.session,
          );
          continue;
        }

        // 짝이 없는 산책 = 마실이를 아직 안 꽂았거나, 기기 없이 앱만으로 걸었다.
        // 사진·일지 없이 경로·거리·시간만 있는 한 줄로 들어간다.
        _feed.add(WalkDiaryFeedItem(
          walkId: walk.walkId,
          walkedAt: walks[i].at,
          durationSeconds: walk.durationSeconds,
          distanceMeters: walk.distanceMeters,
        ));
      }
    }
  }

  static DateTime _dayKey(DateTime at) =>
      DateTime.utc(at.year, at.month, at.day);

  /// 8/3~8/7 시연용 일지에 거리·시간·장소를 채운다([SampleAugustRoutes]).
  ///
  /// 그 일지들은 산책 없이 S3 에만 올려 만든 데이터라 GPS 가 없다. 그대로 두면
  /// 그 날짜만 거리·시간이 비고 경로 지도도 안 그려진다.
  ///
  /// **거리가 이미 있는 항목은 건드리지 않는다.** 그건 실제로 걸어서 서버에
  /// 남은 산책이 짝지어진 것이라 만든 값으로 덮으면 안 된다.
  void _fillSampleAugustRoutes() {
    if (!SampleAugustRoutes.enabled) return;

    for (var i = 0; i < _feed.length; i++) {
      final item = _feed[i];
      final at = item.walkedAt;
      final session = item.session;
      if (at == null || session == null) continue;
      if (item.distanceMeters != null) continue;

      final row = SampleAugustRoutes.rowFor(at, session);
      if (row == null) continue;

      // 경로 상세가 walkId 만으로 좌표를 찾을 수 있게 이어 둔다.
      SampleAugustRoutes.register(item.walkId, at, session);

      _feed[i] = WalkDiaryFeedItem(
        walkId: item.walkId,
        walkedAt: item.walkedAt,
        durationSeconds: row.minutes * 60,
        distanceMeters: row.meters,
        thumbnailUrl: item.thumbnailUrl,
        imageUrls: item.imageUrls,
        summary: item.summary,
        markdown: item.markdown,
        deviceId: item.deviceId,
        session: item.session,
      );
      _placeNames[item.walkId] ??= row.place;
    }
  }

  /// 2026년 7월 예시 데이터를 합친다. 같은 날짜에 서버 기록이 있으면 넣지 않는다.
  ///
  /// 실제 산책 기록이 쌓이면 [SampleWalkDiaries.enabled] 를 false 로 바꾸거나
  /// 이 메서드와 호출부를 지우면 된다.
  /// 기기에 저장한 산책을 피드에 넣는다.
  ///
  /// 같은 산책이 서버에도 있으면 넣지 않는다. 로컬 기록은 walkId 를 직접 만들어
  /// 쓰기 때문에(음수) 서버 id 와 절대 겹치지 않는다. 그래서 **시작 시각이
  /// 겹치는지**로 판단한다. 종료 요청이 늦게 성공했거나 이 변경 전에 남은
  /// 기록이면 같은 산책이 서버와 기기 양쪽에 있을 수 있다.
  Future<void> _mergeLocalRecords() async {
    final local = await _recordStore.readFeedItems();
    if (local.isEmpty) return;

    final serverIds = _feed.map((e) => e.walkId).toSet();
    final serverStarts =
        _feed.map((e) => e.walkedAt).whereType<DateTime>().toList();

    for (final item in local) {
      if (serverIds.contains(item.walkId)) continue;

      final at = item.walkedAt;
      if (at != null &&
          serverStarts.any((start) =>
              start.difference(at).abs() < _sameWalkWindow)) {
        continue;
      }
      _feed.add(item);
    }
  }

  /// 시작 시각이 이만큼 가까우면 같은 산책으로 본다.
  ///
  /// 서버는 산책 세션을 만든 시각을, 기기는 위치 추적을 시작한 시각을 쓴다.
  /// 둘은 네트워크 지연·측위 대기만큼 벌어지므로 정확히 같지 않다.
  static const Duration _sameWalkWindow = Duration(minutes: 5);

  /// 최신순으로 맞춘다(서버 피드도 최신순이다).
  void _sortByRecent() {
    _feed.sort((a, b) {
      final at = a.walkedAt;
      final bt = b.walkedAt;
      if (at == null || bt == null) return 0;
      return bt.compareTo(at);
    });
  }

  void _mergeSamples() {
    if (!SampleWalkDiaries.enabled) return;

    final serverDays = _feed
        .map((e) => e.walkedAt)
        .whereType<DateTime>()
        .map((at) => DateTime.utc(at.year, at.month, at.day))
        .toSet();

    for (final sample in SampleWalkDiaries.items) {
      final at = sample.walkedAt;
      if (at == null) continue;
      // 서버에 그 날 기록이 있으면 실제 데이터를 우선한다.
      if (serverDays.contains(DateTime.utc(at.year, at.month, at.day))) {
        continue;
      }
      _feed.add(sample);
    }

    // 예시 데이터는 좌표가 없어 역지오코딩을 못 하므로 장소명을 미리 채운다.
    _placeNames.addAll(SampleWalkDiaries.placeNames);
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
  ///
  /// 일지가 아직 만들어지지 않았으면 서버가 404 를 준다. 그건 **오류가 아니라
  /// "만드는 중"** 이므로 에러로 남기지 않고 [WalkDiary.generating] 껍데기를
  /// 넣는다. 그러지 않으면 산책이 끝난 직후 화면이 그냥 실패처럼 보인다.
  Future<void> loadDetail(int walkId, {bool silent = false}) async {
    final diary = await guard(
      () => _diaryRepository.getDiary(walkId),
      silent: silent,
    );

    if (diary == null) {
      if (error?.isNotFound ?? false) {
        _detail = WalkDiary.generating(walkId);
        clearError();
        safeNotify();
      }
      return;
    }

    _detail = diary;
    safeNotify();
  }

  /// 일지가 완성될 때까지 상세를 되풀이해 조회한다.
  ///
  /// 마실이 기기가 찍은 영상에서 사진을 뽑고 문구를 붙이는 데 시간이 걸려서,
  /// 산책이 끝난 직후에는 일지가 없다. 완성(또는 실패)이 되면 알아서 멈춘다.
  ///
  /// [_generationTimeout] 까지 안 끝나면 실패로 넘긴다. 그래야 화면이 "만들고
  /// 있어요"에 영원히 머무르지 않는다.
  void startWatchingDiary(int walkId) {
    // 7월 예시 기록은 서버에 없다. 폴링하면 401 만 쌓인다.
    if (SampleWalkDiaries.isSampleId(walkId)) return;
    if (_watchedWalkId == walkId && _diaryPollTimer != null) return;

    stopWatchingDiary();
    _watchedWalkId = walkId;
    _watchStartedAt = DateTime.now();

    // 먼저 한 번 확인한다. 이미 완성돼 있으면 폴링을 시작하지도 않는다.
    loadDetail(walkId, silent: true).then((_) {
      if (_watchedWalkId != walkId) return;
      if (!(_detail?.isGenerating ?? false)) {
        stopWatchingDiary();
        return;
      }
      _diaryPollTimer =
          Timer.periodic(_diaryPollInterval, (_) => _pollDiary(walkId));
    });
  }

  void stopWatchingDiary() {
    _diaryPollTimer?.cancel();
    _diaryPollTimer = null;
    _watchedWalkId = null;
    _watchStartedAt = null;
  }

  Future<void> _pollDiary(int walkId) async {
    final startedAt = _watchStartedAt;
    if (startedAt != null &&
        DateTime.now().difference(startedAt) > _generationTimeout) {
      // 너무 오래 걸렸다. 실패로 넘겨 화면이 안내를 띄우게 한다.
      _detail = (_detail ?? WalkDiary.generating(walkId))
          .copyWithStatus(DiaryGenerationStatus.failed);
      stopWatchingDiary();
      safeNotify();
      return;
    }

    await loadDetail(walkId, silent: true);
    if (_watchedWalkId != walkId) return;
    if (!(_detail?.isGenerating ?? false)) stopWatchingDiary();
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

  @override
  void dispose() {
    _diaryPollTimer?.cancel();
    super.dispose();
  }
}
