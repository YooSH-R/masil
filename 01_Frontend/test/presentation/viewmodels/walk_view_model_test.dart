import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mysil_project_new/core/services/walk_route_source.dart';
import 'package:mysil_project_new/domain/entities/walk.dart';
import 'package:mysil_project_new/domain/entities/walk_diary.dart';
import 'package:mysil_project_new/domain/repositories/walk_repository.dart';
import 'package:mysil_project_new/presentation/viewmodels/walk_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('종료 후 새 산책을 시작하면 이전 경로를 비우고 산책 중 상태를 표시한다', () async {
    SharedPreferences.setMockInitialValues({});
    final source = _TestRouteSource();
    final viewModel =
        WalkViewModel(_UnusedWalkRepository(), routeSource: source);

    viewModel.startRouteTracking();
    expect(viewModel.isWalking, isTrue);

    final startedAt = DateTime.utc(2026, 8, 5, 1);
    source.add(WalkLocationPoint(
      latitude: 37.0,
      longitude: 127.0,
      sequence: 1,
      recordedAt: startedAt,
      accuracy: 5,
    ));
    source.add(WalkLocationPoint(
      latitude: 37.00004,
      longitude: 127.0,
      sequence: 2,
      recordedAt: startedAt.add(const Duration(seconds: 1)),
      accuracy: 5,
    ));
    await Future<void>.delayed(Duration.zero);

    // 두 번째 좌표는 아직 후보점이다. 다음 좌표가 와야 튐인지 코너인지 직선인지
    // 판단할 수 있어서 바로 확정하지 않는다. 그래도 현재 위치는 갱신된다 —
    // 이 분리가 마커를 멈추지 않게 하는 핵심이다.
    expect(viewModel.routePoints, hasLength(1));
    expect(viewModel.livePosition, isNotNull);

    // 종료 시 남은 후보점을 확정하므로 마지막 구간이 잘리지 않는다.
    await viewModel.endWalk();
    expect(viewModel.isWalking, isFalse);
    expect(viewModel.routePoints, hasLength(2));

    viewModel.startRouteTracking();
    expect(viewModel.isWalking, isTrue);
    expect(viewModel.routePoints, isEmpty);

    await viewModel.endWalk();
    viewModel.dispose();
  });

  // 뷰모델은 산책 하나 분량의 요약만 들고 있다. 앞서 본 산책의 값이 남으면
  // 방금 끝낸 산책의 경로를 보려는데 며칠 전 지도가 뜬다.
  test('다른 산책을 조회하면 이전 요약을 먼저 비운다', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = _SummaryRepository();
    final viewModel = WalkViewModel(repository);

    await viewModel.loadSummary(1);
    expect(viewModel.summary?.walkId, 1);

    // 2번 조회가 실패해도 1번 요약이 남으면 안 된다. 남으면 화면이 남의 경로를
    // 그린 채 굳는다.
    repository.fails = true;
    await viewModel.loadSummary(2);
    expect(viewModel.summary, isNull);

    viewModel.dispose();
  });

  // 목록에서 여러 산책을 빠르게 눌러 들어가면 조회가 겹친다. 먼저 시작한
  // 조회가 나중에 끝나면, 화면은 최신 산책을 보고 있는데 값만 이전 것으로
  // 덮인다.
  test('늦게 도착한 옛 조회가 최신 요약을 덮지 않는다', () async {
    SharedPreferences.setMockInitialValues({});
    final viewModel = WalkViewModel(_SummaryRepository(delays: {
      1: const Duration(milliseconds: 60), // 먼저 요청했지만 늦게 온다
      2: const Duration(milliseconds: 5),
    }));

    final stale = viewModel.loadSummary(1);
    final latest = viewModel.loadSummary(2);
    await Future.wait([stale, latest]);

    expect(viewModel.summary?.walkId, 2);

    viewModel.dispose();
  });

  test('새 산책을 시작하면 지난 산책의 요약을 버린다', () async {
    SharedPreferences.setMockInitialValues({});
    final source = _TestRouteSource();
    final viewModel = WalkViewModel(_SummaryRepository(), routeSource: source);

    await viewModel.loadSummary(1);
    expect(viewModel.summary, isNotNull);

    // 남겨 두면 요약 화면이 "이미 있다"고 보고 새 산책을 안 불러온다.
    viewModel.startRouteTracking();
    expect(viewModel.summary, isNull);

    await viewModel.endWalk();
    viewModel.dispose();
  });

  test('서버 업로드 버퍼에는 확정된 경로점만 들어간다', () async {
    SharedPreferences.setMockInitialValues({});
    final source = _TestRouteSource();
    final viewModel =
        WalkViewModel(_UnusedWalkRepository(), routeSource: source);
    viewModel.startRouteTracking();

    // 1초 간격으로 북쪽으로 곧게 걷는다 (1초에 약 1.4m).
    final startedAt = DateTime.utc(2026, 8, 5, 1);
    for (var i = 0; i < 20; i++) {
      source.add(WalkLocationPoint(
        latitude: 37.0 + i * 1.4 / 111320,
        longitude: 127.0,
        sequence: i + 1,
        recordedAt: startedAt.add(Duration(seconds: i)),
        accuracy: 5,
      ));
    }
    await Future<void>.delayed(Duration.zero);

    // 마커용 현재 위치는 좌표마다 갱신되지만, 버퍼에는 확정점만 쌓인다.
    expect(viewModel.livePosition, isNotNull);
    expect(viewModel.pendingPointCount, viewModel.routePoints.length);
    expect(viewModel.routePoints.length, lessThan(20),
        reason: '직선 구간의 중간점은 솎여야 한다');

    await viewModel.endWalk();
    viewModel.dispose();
  });

  test('튄 좌표는 경로에도 업로드 버퍼에도 남지 않는다', () async {
    SharedPreferences.setMockInitialValues({});
    final source = _TestRouteSource();
    final viewModel =
        WalkViewModel(_UnusedWalkRepository(), routeSource: source);
    viewModel.startRouteTracking();

    final startedAt = DateTime.utc(2026, 8, 5, 1);
    // 정상 → 동쪽으로 크게 튐 → 원래 경로 복귀
    const offsets = <(double, double)>[
      (0, 0),
      (0, 2),
      (18, 4), // 튐
      (0, 6),
      (0, 8),
    ];
    for (var i = 0; i < offsets.length; i++) {
      final (dx, dy) = offsets[i];
      source.add(WalkLocationPoint(
        latitude: 37.0 + dy / 111320,
        longitude: 127.0 + dx / (111320 * 0.7934),
        sequence: i + 1,
        recordedAt: startedAt.add(Duration(seconds: i * 2)),
        accuracy: 5,
      ));
    }
    await Future<void>.delayed(Duration.zero);
    await viewModel.endWalk();

    // 튄 좌표는 동쪽으로 18m 다. 경로점 중 그쪽으로 간 것이 없어야 한다.
    for (final point in viewModel.routePoints) {
      final eastMeters = (point.longitude - 127.0) * 111320 * 0.7934;
      expect(eastMeters, lessThan(8),
          reason: '튄 좌표가 경로에 남았다 (동쪽 ${eastMeters.round()}m)');
    }

    viewModel.dispose();
  });
}

class _SummaryRepository extends _UnusedWalkRepository {
  _SummaryRepository({this.delays = const {}});

  bool fails = false;

  /// walkId → 응답이 늦게 오는 정도. 경합을 만들 때 쓴다.
  final Map<int, Duration> delays;

  @override
  Future<WalkSummary> getSummary(int walkId) async {
    final delay = delays[walkId];
    if (delay != null) await Future<void>.delayed(delay);
    if (fails) throw StateError('조회 실패');
    return WalkSummary(
      walkId: walkId,
      durationSeconds: 600,
      distanceMeters: 900,
      route: const [],
    );
  }
}

class _TestRouteSource implements WalkRouteSource {
  StreamController<WalkLocationPoint>? _controller;

  void add(WalkLocationPoint point) => _controller!.add(point);

  @override
  Stream<WalkLocationPoint> points(int? walkId) {
    _controller = StreamController<WalkLocationPoint>();
    return _controller!.stream;
  }

  @override
  Future<void> stop() async {
    await _controller?.close();
    _controller = null;
  }

  @override
  String? get unavailableMessage => null;

  @override
  Future<WalkLocationPoint?> lastKnownPosition() async => null;
}

class _UnusedWalkRepository implements WalkRepository {
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
  Future<CursorPage<Walk>> getWalks({String? cursor, int limit = 20}) =>
      throw UnimplementedError();

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
