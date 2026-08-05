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
      latitude: 37.00002,
      longitude: 127.0,
      sequence: 2,
      recordedAt: startedAt.add(const Duration(seconds: 1)),
      accuracy: 5,
    ));
    await Future<void>.delayed(Duration.zero);
    expect(viewModel.routePoints, hasLength(2));

    await viewModel.endWalk();
    expect(viewModel.isWalking, isFalse);
    expect(viewModel.routePoints, hasLength(2));

    viewModel.startRouteTracking();
    expect(viewModel.isWalking, isTrue);
    expect(viewModel.routePoints, isEmpty);

    await viewModel.endWalk();
    viewModel.dispose();
  });
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
}

class _UnusedWalkRepository implements WalkRepository {
  @override
  Future<Walk> createWalk({
    required int proposalId,
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
