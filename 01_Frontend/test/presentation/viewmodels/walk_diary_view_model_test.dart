import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mysil_project_new/core/services/sample_august_routes.dart';
import 'package:mysil_project_new/core/services/walk_record_store.dart';
import 'package:mysil_project_new/domain/entities/walk.dart';
import 'package:mysil_project_new/domain/entities/walk_diary.dart';
import 'package:mysil_project_new/domain/repositories/walk_diary_repository.dart';
import 'package:mysil_project_new/domain/repositories/walk_repository.dart';
import 'package:mysil_project_new/presentation/viewmodels/walk_diary_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('같은 날짜의 여러 산책을 모두 보관하고 집계한다', () async {
    SharedPreferences.setMockInitialValues({});
    final viewModel = WalkDiaryViewModel(_MultipleWalksRepository());

    await viewModel.loadFeed(refresh: true);

    final items = viewModel.itemsOn(DateTime.utc(2026, 8, 6));
    expect(items, hasLength(2));
    expect(items.map((item) => item.session), [1, 2]);
    expect(viewModel.statsForDay(DateTime.utc(2026, 8, 6)).count, 2);

    viewModel.dispose();
  });

  // 서버에 남은 산책이 피드에 없으면, 같은 계정으로 로그인한 다른 기기에서는
  // 그 산책이 존재하지 않는 것과 같다. S3 일지 피드는 마실이 기기가 올린 것만
  // 훑으므로 앱에서 걸은 산책은 여기서만 들어온다.
  test('S3 일지가 없어도 서버에 남은 산책은 피드에 나온다', () async {
    SharedPreferences.setMockInitialValues({});
    final startedAt = DateTime.utc(2026, 8, 8, 1);
    final viewModel = WalkDiaryViewModel(
      _EmptyDiaryRepository(),
      walkRepository: _StubWalkRepository([
        Walk(
          walkId: 4242,
          status: WalkStatus.completed,
          startedAt: startedAt,
          durationSeconds: 1800,
          distanceMeters: 2300,
        ),
      ]),
    );

    await viewModel.loadFeed(refresh: true);

    final items = viewModel.itemsOn(DateTime.utc(2026, 8, 8));
    expect(items, hasLength(1));
    expect(items.single.walkId, 4242);
    expect(items.single.distanceMeters, 2300);

    viewModel.dispose();
  });

  test('진행 중인 산책은 아직 피드에 넣지 않는다', () async {
    SharedPreferences.setMockInitialValues({});
    final viewModel = WalkDiaryViewModel(
      _EmptyDiaryRepository(),
      walkRepository: _StubWalkRepository([
        Walk(
          walkId: 4243,
          status: WalkStatus.active,
          startedAt: DateTime.utc(2026, 8, 8, 1),
        ),
      ]),
    );

    await viewModel.loadFeed(refresh: true);

    expect(viewModel.itemsOn(DateTime.utc(2026, 8, 8)), isEmpty);
    viewModel.dispose();
  });

  // 마실이를 데리고 나간 산책은 앱이 경로·거리·시간을, 기기가 사진·본문을
  // 만든다. 둘을 따로 넣으면 한 번 걸은 산책이 두 줄로 보이고 통계도 두 배가
  // 된다. 짝은 날짜 + 그날의 순서로 맞춘다(S3 일지에는 시각이 없다).
  test('같은 날 앱 산책과 S3 일지를 회차 순으로 한 줄로 합친다', () async {
    SharedPreferences.setMockInitialValues({});
    final day = DateTime.utc(2026, 8, 8);
    final viewModel = WalkDiaryViewModel(
      _DiaryOnlyRepository([
        WalkDiaryFeedItem(
          walkId: -100002,
          walkedAt: day,
          deviceId: 'device-001',
          session: 2,
        ),
        WalkDiaryFeedItem(
          walkId: -100001,
          walkedAt: day,
          deviceId: 'device-001',
          session: 1,
        ),
      ]),
      walkRepository: _StubWalkRepository([
        Walk(
          walkId: 501,
          status: WalkStatus.completed,
          startedAt: DateTime.utc(2026, 8, 8, 1),
          durationSeconds: 1200,
          distanceMeters: 1500,
        ),
        Walk(
          walkId: 502,
          status: WalkStatus.completed,
          startedAt: DateTime.utc(2026, 8, 8, 9),
          durationSeconds: 1800,
          distanceMeters: 2300,
        ),
      ]),
    );

    await viewModel.loadFeed(refresh: true);

    final items = viewModel.itemsOn(day);
    expect(items, hasLength(2), reason: '두 번 걸었으면 두 줄이다');
    // 아침 산책이 1회차, 저녁 산책이 2회차와 짝지어진다.
    expect(items.map((item) => item.walkId), [501, 502]);
    expect(items.map((item) => item.distanceMeters), [1500, 2300]);
    // 사진·본문을 부르는 데 쓰는 값은 그대로 남아 있어야 한다.
    expect(items.map((item) => item.session), [1, 2]);
    expect(items.every((item) => item.deviceId == 'device-001'), isTrue);
    expect(viewModel.statsForDay(day).count, 2);

    viewModel.dispose();
  });

  // 피드 날짜는 **한국 벽시계 값을 UTC 객체에 담은 것**이라는 규약이 있다.
  // 날짜 계산(byDate·statsForDay·WalkProgress)이 전부 이걸 전제로 한다.
  // isUtc 가 섞이면 .toUtc()·difference() 가 기기 시간대만큼 어긋나서, 해외로
  // 맞춰진 기기에서 날짜가 하루 밀린다.
  //
  // 서버 응답을 파싱하는 쪽은 walk_diary_model_test 가 지킨다(DateTime 의 == 는
  // isUtc 까지 비교해서 local 이 되면 바로 깨진다). 여기서는 **피드를 합치는
  // 쪽**을 지킨다 — 출처가 넷이라 한 곳만 규약을 어겨도 그 항목만 조용히 밀린다.
  test('피드에 합쳐지는 모든 날짜는 UTC 객체다', () async {
    SharedPreferences.setMockInitialValues({});
    const store = WalkRecordStore();
    final localStartedAt = DateTime.utc(2026, 8, 11, 1);
    await store.save(
      startedAt: localStartedAt,
      endedAt: localStartedAt.add(const Duration(minutes: 20)),
      route: [
        WalkLocationPoint(
          latitude: 37.0,
          longitude: 127.0,
          sequence: 1,
          recordedAt: localStartedAt,
        ),
        WalkLocationPoint(
          latitude: 37.001,
          longitude: 127.0,
          sequence: 2,
          recordedAt: localStartedAt.add(const Duration(minutes: 1)),
        ),
      ],
    );

    final viewModel = WalkDiaryViewModel(
      // S3 일지 — 서버가 주는 `yyyy-MM-dd` 를 파싱하는 경로
      _DiaryOnlyRepository([
        WalkDiaryFeedItem(
          walkId: -100006,
          walkedAt: DateTime.utc(2026, 8, 5),
          deviceId: 'device-001',
          session: 1,
        ),
      ]),
      // 서버 산책 — 절대 시각을 한국 시각으로 바꾸는 경로
      walkRepository: _StubWalkRepository([
        Walk(
          walkId: 901,
          status: WalkStatus.completed,
          startedAt: DateTime.utc(2026, 8, 12, 10),
          durationSeconds: 900,
          distanceMeters: 1200,
        ),
      ]),
    );

    await viewModel.loadFeed(refresh: true);

    // 비어 있으면 아무것도 검증하지 못한다. 네 출처(S3·서버·기기·7월 예시)가
    // 모두 들어왔는지 먼저 확인한다.
    expect(viewModel.feed.length, greaterThan(3));

    for (final item in viewModel.feed) {
      expect(
        item.walkedAt?.isUtc,
        isTrue,
        reason: 'walkId ${item.walkId} 의 날짜가 local 이다 — '
            'DateTime.utc 로 만들거나 KoreaTime 을 거쳐야 한다',
      );
    }

    viewModel.dispose();
  });

  // 앞에서부터 순서대로 짝지으면 일지 하나가 누락됐을 때 그 뒤가 한 칸씩
  // 밀린다. 오전·오후를 걸었는데 오전 일지만 없으면 오후 일지가 오전 산책에
  // 붙고, 오후 산책은 일지 없이 남는다. 회차 번호로 찾아야 제자리에 붙는다.
  test('회차가 빠진 날에도 일지가 제 산책에 붙는다', () async {
    SharedPreferences.setMockInitialValues({});
    final day = DateTime.utc(2026, 8, 10);
    final viewModel = WalkDiaryViewModel(
      _DiaryOnlyRepository([
        // 2회차 일지만 올라왔다. 1회차 일지는 없다.
        WalkDiaryFeedItem(
          walkId: -100005,
          walkedAt: day,
          deviceId: 'device-001',
          session: 2,
        ),
      ]),
      walkRepository: _StubWalkRepository([
        Walk(
          walkId: 801,
          status: WalkStatus.completed,
          startedAt: DateTime.utc(2026, 8, 10, 0), // 오전 9시(KST)
          durationSeconds: 1200,
          distanceMeters: 1500,
        ),
        Walk(
          walkId: 802,
          status: WalkStatus.completed,
          startedAt: DateTime.utc(2026, 8, 10, 10), // 저녁 7시(KST)
          durationSeconds: 1800,
          distanceMeters: 2300,
        ),
      ]),
    );

    await viewModel.loadFeed(refresh: true);

    final items = viewModel.itemsOn(day);
    expect(items, hasLength(2));

    final morning = items.firstWhere((item) => item.walkId == 801);
    final evening = items.firstWhere((item) => item.walkId == 802);

    // 오전 산책은 일지가 없다. 사진·본문 조회에 쓰는 값이 붙으면 안 된다.
    expect(morning.session, isNull);
    expect(morning.deviceId, isNull);
    expect(morning.distanceMeters, 1500);

    // 2회차 일지는 오후 산책에 붙어야 한다.
    expect(evening.session, 2);
    expect(evening.deviceId, 'device-001');
    expect(evening.distanceMeters, 2300);

    viewModel.dispose();
  });

  // 산책 없이 S3에만 올린 8/3~8/7 테스트 일지는 짝지을 산책이 없다. 그래도
  // 시연에서 거리·시간이 비어 보이면 안 되므로 만들어 둔 값을 채운다.
  test('짝지을 산책이 없는 8월 일지는 그대로 남고 시연용 거리·시간이 붙는다', () async {
    SharedPreferences.setMockInitialValues({});
    final day = DateTime.utc(2026, 8, 5);
    final viewModel = WalkDiaryViewModel(
      _DiaryOnlyRepository([
        WalkDiaryFeedItem(
          walkId: -100003,
          walkedAt: day,
          deviceId: 'device-001',
          session: 1,
        ),
      ]),
      walkRepository: _StubWalkRepository(const []),
    );

    await viewModel.loadFeed(refresh: true);

    final items = viewModel.itemsOn(day);
    expect(items, hasLength(1), reason: '줄이 늘어나면 안 된다');
    expect(items.single.walkId, -100003, reason: '사진·본문 조회에 쓰는 id 는 그대로');
    expect(items.single.session, 1);
    expect(items.single.distanceMeters, isNotNull);
    expect(items.single.durationSeconds, isNotNull);
    // 경로 상세가 walkId 만으로 좌표를 찾을 수 있어야 한다.
    final summary = SampleAugustRoutes.summaryFor(-100003);
    expect(summary, isNotNull);
    expect(summary!.route.length, greaterThan(10));
    expect(summary.distanceMeters, items.single.distanceMeters);

    viewModel.dispose();
  });

  // 실제로 걸어서 서버에 남은 산책이 있으면 그 값이 진짜다. 만들어 둔 값으로
  // 덮으면 걸은 거리가 엉뚱하게 바뀐다.
  test('서버 산책과 짝지어진 8월 일지는 시연용 값으로 덮지 않는다', () async {
    SharedPreferences.setMockInitialValues({});
    final day = DateTime.utc(2026, 8, 5);
    final viewModel = WalkDiaryViewModel(
      _DiaryOnlyRepository([
        WalkDiaryFeedItem(
          walkId: -100004,
          walkedAt: day,
          deviceId: 'device-001',
          session: 1,
        ),
      ]),
      walkRepository: _StubWalkRepository([
        Walk(
          walkId: 777,
          status: WalkStatus.completed,
          startedAt: DateTime.utc(2026, 8, 5, 2),
          durationSeconds: 900,
          distanceMeters: 3333,
        ),
      ]),
    );

    await viewModel.loadFeed(refresh: true);

    final items = viewModel.itemsOn(day);
    expect(items, hasLength(1));
    expect(items.single.walkId, 777);
    expect(items.single.distanceMeters, 3333);

    viewModel.dispose();
  });

  // 서버 종료가 늦게 성공하거나 예전에 남은 기록이면 같은 산책이 양쪽에 있다.
  // 로컬 기록은 walkId 를 직접 만들어 쓰므로 id 로는 겹침을 알 수 없다.
  test('같은 산책이 서버와 기기 양쪽에 있으면 한 줄만 보여준다', () async {
    SharedPreferences.setMockInitialValues({});
    const store = WalkRecordStore();
    final startedAt = DateTime.utc(2026, 8, 8, 1);
    await store.save(
      startedAt: startedAt,
      endedAt: startedAt.add(const Duration(minutes: 30)),
      route: [
        WalkLocationPoint(
          latitude: 37.0,
          longitude: 127.0,
          sequence: 1,
          recordedAt: startedAt,
        ),
        WalkLocationPoint(
          latitude: 37.001,
          longitude: 127.0,
          sequence: 2,
          recordedAt: startedAt.add(const Duration(minutes: 1)),
        ),
      ],
    );

    final viewModel = WalkDiaryViewModel(
      _EmptyDiaryRepository(),
      walkRepository: _StubWalkRepository([
        Walk(
          // 서버 세션 생성이 위치 추적보다 2분 늦게 잡힌 경우.
          walkId: 4244,
          status: WalkStatus.completed,
          startedAt: startedAt.add(const Duration(minutes: 2)),
          durationSeconds: 1800,
          distanceMeters: 2300,
        ),
      ]),
    );

    await viewModel.loadFeed(refresh: true);

    final items = viewModel.itemsOn(DateTime.utc(2026, 8, 8));
    expect(items, hasLength(1));
    expect(items.single.walkId, 4244, reason: '서버 기록을 우선한다');

    viewModel.dispose();
  });
}

class _DiaryOnlyRepository implements WalkDiaryRepository {
  _DiaryOnlyRepository(this.items);

  final List<WalkDiaryFeedItem> items;

  @override
  Future<CursorPage<WalkDiaryFeedItem>> getFeed({
    String? cursor,
    int limit = 20,
  }) async =>
      CursorPage<WalkDiaryFeedItem>(items: items);

  @override
  Future<WalkDiary> getDiary(int walkId) => throw UnimplementedError();

  @override
  Future<WalkDiaryContent> getS3Diary({
    required String deviceId,
    required DateTime walkDate,
    required int session,
  }) =>
      throw UnimplementedError();

  @override
  Future<WalkDiary> updateCaption({
    required int walkId,
    required int photoId,
    required String caption,
  }) =>
      throw UnimplementedError();
}

class _EmptyDiaryRepository implements WalkDiaryRepository {
  @override
  Future<CursorPage<WalkDiaryFeedItem>> getFeed({
    String? cursor,
    int limit = 20,
  }) async =>
      const CursorPage<WalkDiaryFeedItem>(items: []);

  @override
  Future<WalkDiary> getDiary(int walkId) => throw UnimplementedError();

  @override
  Future<WalkDiaryContent> getS3Diary({
    required String deviceId,
    required DateTime walkDate,
    required int session,
  }) =>
      throw UnimplementedError();

  @override
  Future<WalkDiary> updateCaption({
    required int walkId,
    required int photoId,
    required String caption,
  }) =>
      throw UnimplementedError();
}

class _StubWalkRepository implements WalkRepository {
  _StubWalkRepository(this.walks);

  final List<Walk> walks;

  @override
  Future<CursorPage<Walk>> getWalks({String? cursor, int limit = 20}) async =>
      CursorPage<Walk>(items: walks);

  @override
  Future<Walk> createWalk({
    int? proposalId,
    required int petId,
    required int robotId,
  }) =>
      throw UnimplementedError();

  @override
  Future<Walk> endWalk(int walkId) => throw UnimplementedError();

  @override
  Future<WalkProposal?> getCurrentProposal() => throw UnimplementedError();

  @override
  Future<WalkSummary> getSummary(int walkId) => throw UnimplementedError();

  @override
  Future<Walk> getWalk(int walkId) => throw UnimplementedError();

  @override
  Future<void> respondToProposal({
    required int proposalId,
    required bool accepted,
  }) =>
      throw UnimplementedError();

  @override
  Future<WalkLocationBatchResult> uploadLocations({
    required int walkId,
    required List<WalkLocationPoint> points,
    String? idempotencyKey,
  }) =>
      throw UnimplementedError();

  @override
  Stream<Walk> watchWalk(
    int walkId, {
    Duration interval = const Duration(seconds: 5),
  }) =>
      const Stream.empty();
}

class _MultipleWalksRepository implements WalkDiaryRepository {
  @override
  Future<CursorPage<WalkDiaryFeedItem>> getFeed({
    String? cursor,
    int limit = 20,
  }) async {
    return CursorPage<WalkDiaryFeedItem>(items: [
      WalkDiaryFeedItem(
        walkId: -100002,
        walkedAt: DateTime.utc(2026, 8, 6),
        deviceId: 'device-001',
        session: 2,
      ),
      WalkDiaryFeedItem(
        walkId: -100001,
        walkedAt: DateTime.utc(2026, 8, 6),
        deviceId: 'device-001',
        session: 1,
      ),
    ]);
  }

  @override
  Future<WalkDiary> getDiary(int walkId) => throw UnimplementedError();

  @override
  Future<WalkDiaryContent> getS3Diary({
    required String deviceId,
    required DateTime walkDate,
    required int session,
  }) =>
      throw UnimplementedError();

  @override
  Future<WalkDiary> updateCaption({
    required int walkId,
    required int photoId,
    required String caption,
  }) =>
      throw UnimplementedError();
}
