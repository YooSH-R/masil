import 'dart:async';

import '../../domain/entities/walk.dart';
import '../../domain/repositories/walk_repository.dart';
import 'base_view_model.dart';

class WalkViewModel extends BaseViewModel {
  WalkViewModel(this._walkRepository);

  final WalkRepository _walkRepository;

  WalkProposal? _proposal;
  Walk? _currentWalk;
  WalkSummary? _summary;
  StreamSubscription<Walk>? _watchSub;

  /// 아직 서버에 올리지 못한 GPS 좌표 버퍼.
  final List<WalkLocationPoint> _pendingPoints = [];
  int _sequence = 0;

  WalkProposal? get proposal => _proposal;
  Walk? get currentWalk => _currentWalk;
  WalkSummary? get summary => _summary;
  bool get hasProposal => _proposal != null && !_proposal!.isExpired;
  bool get isWalking => _currentWalk?.status == WalkStatus.active;
  int get pendingPointCount => _pendingPoints.length;

  /// GET /walk-proposals/current — 제안이 없으면 proposal은 null로 유지된다.
  Future<void> loadCurrentProposal({bool silent = false}) async {
    _proposal = await guard<WalkProposal?>(
      () => _walkRepository.getCurrentProposal(),
      silent: silent,
    );
    safeNotify();
  }

  /// POST /walk-proposals/{proposalId}/responses — 수락
  /// 수락 후 곧바로 POST /walks 로 세션을 만든다(명세서 6.2 → 6.3).
  Future<Walk?> acceptProposal({required int petId, required int robotId}) async {
    final proposal = _proposal;
    if (proposal == null) return null;

    final walk = await guard(() async {
      await _walkRepository.respondToProposal(
        proposalId: proposal.proposalId,
        accepted: true,
      );
      return _walkRepository.createWalk(
        proposalId: proposal.proposalId,
        petId: petId,
        robotId: robotId,
      );
    });
    if (walk == null) return null;

    _currentWalk = walk;
    _proposal = null;
    _resetPoints();
    safeNotify();
    return walk;
  }

  /// POST /walk-proposals/{proposalId}/responses — 거절
  Future<bool> declineProposal() async {
    final proposal = _proposal;
    if (proposal == null) return false;

    await guard(() => _walkRepository.respondToProposal(
          proposalId: proposal.proposalId,
          accepted: false,
        ));
    if (hasError) return false;

    _proposal = null;
    safeNotify();
    return true;
  }

  /// 산책 중 수집한 좌표를 버퍼에 쌓는다.
  /// 실제 위치 수집(geolocator 등)은 화면/서비스에서 담당한다.
  void addLocation({
    required double latitude,
    required double longitude,
    double? accuracy,
    DateTime? recordedAt,
  }) {
    _sequence += 1;
    _pendingPoints.add(WalkLocationPoint(
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      sequence: _sequence,
      recordedAt: recordedAt ?? DateTime.now().toUtc(),
    ));
    safeNotify();
  }

  /// POST /walks/{walkId}/locations/batch — 버퍼를 비우며 일괄 전송.
  Future<bool> flushLocations() async {
    final walkId = _currentWalk?.walkId;
    if (walkId == null || _pendingPoints.isEmpty) return true;

    final batch = List<WalkLocationPoint>.unmodifiable(_pendingPoints);
    final result = await guard(
      () => _walkRepository.uploadLocations(walkId: walkId, points: batch),
      silent: true,
    );
    if (result == null) return false;

    // 전송에 성공한 만큼만 버퍼에서 제거한다.
    _pendingPoints.removeRange(0, batch.length);
    safeNotify();
    return true;
  }

  /// GET /walks/{walkId} — 상태 새로고침.
  Future<void> refreshWalk({bool silent = true}) async {
    final walkId = _currentWalk?.walkId;
    if (walkId == null) return;

    final walk = await guard(
      () => _walkRepository.getWalk(walkId),
      silent: silent,
    );
    if (walk == null) return;

    _currentWalk = walk;
    safeNotify();
  }

  /// Jetson이 산책을 시작/종료할 때까지 상태를 지켜본다.
  void startWatchingWalk({Duration interval = const Duration(seconds: 5)}) {
    final walkId = _currentWalk?.walkId;
    if (walkId == null || _watchSub != null) return;

    _watchSub = _walkRepository
        .watchWalk(walkId, interval: interval)
        .listen((walk) async {
      _currentWalk = walk;
      safeNotify();
      if (walk.status.isFinished) {
        await flushLocations();
        await loadSummary(walk.walkId);
        stopWatchingWalk();
      }
    });
  }

  void stopWatchingWalk() {
    _watchSub?.cancel();
    _watchSub = null;
  }

  /// GET /walks/{walkId}/summary
  Future<void> loadSummary(int walkId) async {
    final summary = await guard(() => _walkRepository.getSummary(walkId));
    if (summary == null) return;

    _summary = summary;
    safeNotify();
  }

  void attachWalk(Walk walk) {
    _currentWalk = walk;
    safeNotify();
  }

  void _resetPoints() {
    _pendingPoints.clear();
    _sequence = 0;
  }

  @override
  void dispose() {
    stopWatchingWalk();
    super.dispose();
  }
}
