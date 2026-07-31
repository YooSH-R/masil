import 'dart:async';

import '../../core/services/walk_route_source.dart';
import '../../core/utils/geo.dart';
import '../../domain/entities/walk.dart';
import '../../domain/repositories/walk_repository.dart';
import 'base_view_model.dart';

class WalkViewModel extends BaseViewModel {
  WalkViewModel(this._walkRepository, {WalkRouteSource? routeSource})
      : _routeSource = routeSource;

  final WalkRepository _walkRepository;

  /// 이동경로가 들어오는 입구. 백엔드 GPS 푸시가 준비되면 이 구현만 바꾼다.
  final WalkRouteSource? _routeSource;

  WalkProposal? _proposal;
  Walk? _currentWalk;
  WalkSummary? _summary;
  StreamSubscription<Walk>? _watchSub;

  /// 아직 서버에 올리지 못한 GPS 좌표 버퍼.
  final List<WalkLocationPoint> _pendingPoints = [];
  int _sequence = 0;

  // --- 지도에 그릴 경로 ---

  /// 지금까지 받은 좌표 전체. 지도의 폴리라인이 이걸 그린다.
  /// (_pendingPoints 는 전송 후 비워지므로 그리기용으로 따로 보관한다)
  final List<WalkLocationPoint> _routePoints = [];
  final Set<int> _seenSequences = {};
  StreamSubscription<WalkLocationPoint>? _routeSub;

  /// 화면에 흐르는 경과 시간. 1초마다 갱신된다.
  Timer? _elapsedTimer;
  DateTime? _trackingStartedAt;
  Duration _elapsed = Duration.zero;

  /// 모아둔 좌표를 서버에 일괄 업로드하는 주기.
  /// 좌표 하나마다 보내면 요청이 너무 잦고, 너무 길면 앱이 죽을 때 손실이 크다.
  static const Duration _uploadInterval = Duration(seconds: 15);
  Timer? _uploadTimer;

  WalkProposal? get proposal => _proposal;
  Walk? get currentWalk => _currentWalk;
  WalkSummary? get summary => _summary;
  bool get hasProposal => _proposal != null && !_proposal!.isExpired;
  bool get isWalking => _currentWalk?.status == WalkStatus.active;
  int get pendingPointCount => _pendingPoints.length;

  List<WalkLocationPoint> get routePoints =>
      List<WalkLocationPoint>.unmodifiable(_routePoints);
  WalkLocationPoint? get lastPoint =>
      _routePoints.isEmpty ? null : _routePoints.last;
  bool get hasRoute => _routePoints.isNotEmpty;
  bool get isTracking => _routeSub != null;

  /// 경과 시간. 우선순위는 아래 순서다.
  ///
  /// 1. 진행 중이고 서버가 startedAt 을 줬으면 `지금 - startedAt`.
  ///    durationSeconds 는 폴링 간격(기본 5초)마다만 갱신돼 숫자가 툭툭 뛰는데,
  ///    startedAt 기준으로 계산하면 서버 시각에 맞춰 매초 부드럽게 흐른다.
  /// 2. 끝난 산책이면 서버가 확정한 durationSeconds.
  /// 3. 서버 데이터가 없으면 이 화면에서 재는 로컬 시간.
  Duration get elapsed {
    final walk = _currentWalk;
    final startedAt = walk?.startedAt;
    if (walk != null && startedAt != null && !walk.status.isFinished) {
      final fromServer = DateTime.now().toUtc().difference(startedAt.toUtc());
      if (!fromServer.isNegative) return fromServer;
    }

    final serverSeconds = walk?.durationSeconds;
    if (serverSeconds != null) return Duration(seconds: serverSeconds);
    return _elapsed;
  }

  /// 이동 거리(m). 서버가 distanceMeters 를 주면 그 값을 우선하고,
  /// 없으면 받은 좌표로 직접 계산한다.
  int get distanceMeters {
    final serverMeters = _currentWalk?.distanceMeters;
    if (serverMeters != null) return serverMeters;
    return Geo.routeDistanceMeters(_routePoints).round();
  }

  /// 이동경로 수신 시작. [WalkRouteSource] 가 주입되지 않았으면 아무것도 하지 않는다.
  ///
  /// 백엔드 GPS 푸시가 붙으면 이 메서드는 그대로 두고 소스만 교체하면 된다.
  void startRouteTracking({int? walkId}) {
    final source = _routeSource;
    // walkId 는 서버에 산책 세션이 없으면 null 이다(산책 API 미구현).
    // null 이라고 추적을 막으면 화면이 0:00 에서 멈춰버리므로 그대로 넘긴다.
    // 판단은 소스 구현이 한다.
    final id = walkId ?? _currentWalk?.walkId;
    if (source == null || _routeSub != null) return;

    _trackingStartedAt = DateTime.now();
    _elapsed = Duration.zero;

    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final startedAt = _trackingStartedAt;
      if (startedAt == null) return;
      _elapsed = DateTime.now().difference(startedAt);
      safeNotify();
    });

    // 모아둔 좌표를 주기적으로 서버에 올린다.
    // 산책 세션(walkId)이 없으면 flushLocations 내부에서 그냥 넘어간다.
    _uploadTimer?.cancel();
    _uploadTimer = Timer.periodic(_uploadInterval, (_) => flushLocations());

    _routeSub = source.points(id).listen(
      _onPointReceived,
      onError: (_) {},
    );
    safeNotify();
  }

  Future<void> stopRouteTracking() async {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    _uploadTimer?.cancel();
    _uploadTimer = null;
    await _routeSub?.cancel();
    _routeSub = null;
    await _routeSource?.stop();
    // 남은 좌표를 마지막으로 올린다. 실패해도 버퍼에 남아 다음 기회에 재시도된다.
    await flushLocations();
    safeNotify();
  }

  /// 좌표 하나 수신. sequence 로 중복을 걸러내므로 소스가 재전송해도 안전하다.
  void _onPointReceived(WalkLocationPoint point) {
    if (!_seenSequences.add(point.sequence)) return;

    _routePoints.add(point);
    // 그리기용 목록과 별개로, 서버 업로드 버퍼에도 쌓아둔다.
    _sequence = point.sequence > _sequence ? point.sequence : _sequence;
    _pendingPoints.add(point);
    safeNotify();
  }

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
    _routePoints.clear();
    _seenSequences.clear();
    _sequence = 0;
    _elapsed = Duration.zero;
    _trackingStartedAt = null;
  }

  @override
  void dispose() {
    stopWatchingWalk();
    _elapsedTimer?.cancel();
    _uploadTimer?.cancel();
    _routeSub?.cancel();
    _routeSource?.stop();
    super.dispose();
  }
}
