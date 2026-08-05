import 'dart:async';

import '../../core/services/sample_walk_diaries.dart';
import '../../core/services/walk_record_store.dart';
import '../../core/services/walk_route_source.dart';
import '../../core/utils/geo.dart';
import '../../domain/entities/walk.dart';
import '../../domain/repositories/walk_repository.dart';
import 'base_view_model.dart';

class WalkViewModel extends BaseViewModel {
  WalkViewModel(this._walkRepository, {WalkRouteSource? routeSource})
      : _routeSource = routeSource;

  final WalkRepository _walkRepository;

  /// 이동경로가 들어오는 입구.
  ///
  /// 지금은 휴대폰 자체 GPS([DeviceGpsWalkRouteSource])를 쓴다. 마실이 기기의
  /// GPS 푸시로 바꾸려면 이 구현만 갈아끼우면 된다.
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

  /// 서버 산책 API가 없어도 사용자가 시작 버튼을 누른 뒤 종료할 때까지 유지되는
  /// 로컬 산책 상태. GPS 권한 문제로 스트림이 닫혀도 산책 중 표시는 유지한다.
  bool _localWalkActive = false;

  /// 화면에 흐르는 경과 시간. 1초마다 갱신된다.
  Timer? _elapsedTimer;
  DateTime? _trackingStartedAt;
  Duration _elapsed = Duration.zero;

  /// 모아둔 좌표를 서버에 일괄 업로드하는 주기.
  ///
  /// 명세서 2.4 "배치 처리 속도" 권장값을 따른다:
  ///   측정 5초 / 최소 이동 5m / **서버 전송 20~30초마다 묶어서**
  /// 좌표 하나마다 보내면 요청이 너무 잦고, 너무 길면 앱이 죽을 때 손실이 크다.
  static const Duration _uploadInterval = Duration(seconds: 30);
  Timer? _uploadTimer;

  /// 한 번에 보낼 좌표 수 상한.
  ///
  /// 버퍼를 통째로 보내면, 네트워크가 한동안 끊겼다 돌아왔을 때 수백 개가 한
  /// 요청에 실린다. 서버가 배치 크기를 제한하면 그 요청은 **영구히 실패**하고
  /// 버퍼가 계속 불어난다. 그래서 잘라 보내고, 남으면 이어서 보낸다.
  static const int _maxBatchSize = 100;

  /// 전송이 겹치지 않게 하는 잠금.
  ///
  /// 30초 타이머·산책 종료·화면 내려감(lifecycle)에서 각각 flush 를 부르므로
  /// 겹칠 수 있다. 겹치면 같은 좌표를 두 번 보내게 된다.
  bool _isUploading = false;

  /// 좌표를 저장할지 판단하는 기준. 명세서 2.4 "배치 처리 속도" 개정판이다.
  ///
  ///   일반 산책: 측정 3초 간격 / accuracy 기반 최소 이동거리 3~8m
  ///   accuracy 가 30~50m 보다 큰 부정확한 좌표는 제외
  ///
  /// **측정 간격(3초)은 좌표를 만들어 보내는 쪽([WalkRouteSource])이 지킨다.**
  /// 여기서는 이미 들어온 좌표를 "저장할지" 만 판단한다. 측정 주기와 서버 전송
  /// 주기는 서로 별개다(3초 측정 / 30초 전송).
  ///
  /// GPS가 정확할 때 적용하는 최소 이동거리. 3초 보행 시 약 3~5m 이동하므로
  /// 경로 반응성을 유지하면서 제자리의 작은 흔들림은 제외한다.
  static const double _minMoveMeters = 3;

  /// 정확도가 낮다고 임계값을 무한히 키우면 정상 경로까지 끊기므로 상한을 둔다.
  static const double _maxAdaptiveMoveMeters = 8;

  /// 이보다 부정확한 좌표는 버린다. 명세서의 30~50m 구간에서 느슨한 쪽을 잡았다.
  /// 시연은 실외 안드로이드 휴대폰이라 보통 5~20m 로 들어오지만, 건물 사이나
  /// 지하도에서 수백 m 튄 좌표가 한 개라도 섞이면 경로선이 지도를 가로지르고
  /// 거리·페이스까지 같이 망가진다.
  static const double _maxAccuracyMeters = 50;

  /// 걷는 중에는 나올 수 없는 속도(m/s). 이보다 빠르면 튀는 좌표로 본다.
  /// 10m/s = 36km/h — 뛰어도 못 넘는 값이라 정상 보행은 걸리지 않는다.
  ///
  /// **왜 "몇 m 이상 이동"이 아니라 속도로 보는가**: 거리만 보면(예: 200m 초과
  /// 배제) 터널·지하도·백그라운드 제약으로 좌표가 한동안 끊겼다가 멀리서 다시
  /// 잡히는 정상 상황을 버린다. 그러면 기준점([_lastKeptPoint])이 갱신되지 않아
  /// 이후 좌표도 계속 멀다고 판정되고 **경로가 영구히 멈춘다.** 시간 간격을 함께
  /// 보면 200m 를 100초에 걸쳐 온 것은 통과하고, 1초에 온 것만 걸러낸다.
  static const double _maxSpeedMetersPerSecond = 10;

  /// 시각을 믿을 수 없을 때(같거나 거꾸로) 쓰는 절대 거리 상한.
  static const double _maxJumpMeters = 200;

  /// 끝낸 산책을 기기에 남기는 저장소.
  ///
  /// 서버에 산책 API 가 배포되기 전까지, 산책일지가 날짜별 경로를 보여줄 수 있는
  /// 유일한 출처다([WalkRecordStore] 주석 참고).
  final WalkRecordStore _recordStore = const WalkRecordStore();

  /// 방금 저장한 기록의 walkId. 종료 직후 경로 상세로 바로 갈 때 쓴다.
  int? _lastSavedRecordId;
  int? get lastSavedRecordId => _lastSavedRecordId;

  /// 마지막으로 저장한 좌표. [_minMoveMeters] 비교 기준점이다.
  /// 버려진 좌표는 기준점을 갱신하지 않는다(그래야 조금씩 흔들리며 누적되는
  /// 좌표가 5m 를 넘길 때까지 계속 걸러진다).
  WalkLocationPoint? _lastKeptPoint;

  WalkProposal? get proposal => _proposal;
  Walk? get currentWalk => _currentWalk;
  WalkSummary? get summary => _summary;
  bool get hasProposal => _proposal != null && !_proposal!.isExpired;
  bool get isWalking =>
      _localWalkActive || _currentWalk?.status == WalkStatus.active;
  int get pendingPointCount => _pendingPoints.length;

  /// 지금 서버로 좌표를 보내는 중인지.
  bool get isUploadingLocations => _isUploading;

  List<WalkLocationPoint> get routePoints =>
      List<WalkLocationPoint>.unmodifiable(_routePoints);
  WalkLocationPoint? get lastPoint =>
      _routePoints.isEmpty ? null : _routePoints.last;
  bool get hasRoute => _routePoints.isNotEmpty;
  bool get isTracking => _routeSub != null;

  /// 위치를 못 받는 이유(권한 거부 등). 받을 수 있으면 null.
  /// 사용자가 직접 풀어줘야 하는 상황이라 화면이 그대로 보여준다.
  String? get routeUnavailableMessage => _routeSource?.unavailableMessage;

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
    if (_routeSub != null) return;

    // 종료한 산책의 경로는 요약 화면에서 쓸 수 있게 남겨 두고, 다음 산책이
    // 실제로 시작되는 이 시점에 비운다. 화면을 잠깐 나갔다 돌아온 경우에는
    // _localWalkActive가 true라서 현재 산책 경로가 그대로 이어진다.
    if (!_localWalkActive) {
      _resetPoints();
      _localWalkActive = true;
    }

    _trackingStartedAt ??= DateTime.now();

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

    if (source == null) {
      safeNotify();
      return;
    }

    _routeSub = source.points(id).listen(
      _onPointReceived,
      onError: (_) {},
      // 권한이 막히면 소스가 스트림을 닫는다. 그때 화면이 안내 문구를 띄울 수
      // 있게 알린다([routeUnavailableMessage]).
      onDone: () {
        _routeSub = null;
        safeNotify();
      },
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
  void _onPointReceived(WalkLocationPoint point) => _ingest(point);

  /// 좌표를 걸러서 그리기 목록과 업로드 버퍼에 넣는다. 저장했으면 true.
  ///
  /// 좌표가 들어오는 길은 두 개다(마실이 기기 푸시 [_onPointReceived], 휴대폰
  /// 직접 수집 [addLocation]). 둘이 같은 기준으로 걸러지도록 여기로 모았다.
  bool _ingest(WalkLocationPoint point) {
    // 중복. 소스가 재연결 후 이미 보낸 좌표를 다시 보내는 경우다.
    if (_seenSequences.contains(point.sequence)) return false;
    if (!_shouldKeep(point)) return false;

    _seenSequences.add(point.sequence);
    _routePoints.add(point);
    // 그리기용 목록과 별개로, 서버 업로드 버퍼에도 쌓아둔다.
    _sequence = point.sequence > _sequence ? point.sequence : _sequence;
    _pendingPoints.add(point);
    _lastKeptPoint = point;
    safeNotify();

    // 상한까지 찼으면 30초를 기다리지 않고 바로 보낸다. 오래 걸으면 주기보다
    // 버퍼가 먼저 차는데, 그때까지 쌓아두면 한 요청이 너무 커진다.
    // 결과를 기다리지 않는다 — 좌표 수신을 막지 않아야 한다.
    if (_pendingPoints.length >= _maxBatchSize) {
      flushLocations();
    }
    return true;
  }

  /// 좌표를 몇 개 받았는지(걸러진 것 포함). 진단용.
  int _receivedCount = 0;

  /// 마지막으로 좌표를 버린 이유. 진단용.
  String? _lastRejectReason;

  /// 좌표가 안 쌓일 때 화면에 보여줄 진단 문구. 정상이면 null.
  ///
  /// **왜 필요한가**: 실기기에서 "위치가 안 바뀐다"는 증상이 났을 때, 좌표가
  /// 아예 안 오는 것인지 / 와도 걸러지는 것인지 구분할 방법이 없어 원인을
  /// 추측만 했다. 이 값이 있으면 화면만 보고 바로 판별된다.
  String? get gpsDiagnostic {
    if (_routePoints.length >= 2) return null; // 정상 동작 중
    if (_receivedCount == 0) return null; // 아직 아무것도 안 옴 → 별도 안내가 있다
    final reason = _lastRejectReason;
    if (reason == null) return null;
    return 'GPS $_receivedCount개 받음 · $reason';
  }

  /// 저장할 좌표인지 판단한다. 명세서 2.4 "배치 처리 속도" 참고.
  ///
  /// 첫 좌표는 비교 대상이 없으니 무조건 저장한다. 그래야 산책 시작 지점이
  /// 경로에 남고 지도가 곧바로 그쪽으로 움직인다.
  bool _shouldKeep(WalkLocationPoint point) {
    _receivedCount += 1;

    final accuracy = point.accuracy;
    if (accuracy != null && accuracy > _maxAccuracyMeters) {
      _lastRejectReason = '정확도 ${accuracy.round()}m 로 낮아 제외';
      return false;
    }

    final last = _lastKeptPoint;
    if (last == null) {
      _lastRejectReason = null;
      return true;
    }

    final moved = Geo.distanceMeters(
      lat1: last.latitude,
      lng1: last.longitude,
      lat2: point.latitude,
      lng2: point.longitude,
    );
    // accuracy는 실제 위치가 포함될 가능성이 높은 오차 반경이다. 현재 좌표나
    // 직전 좌표의 오차가 크면 최소 이동거리도 함께 키워, 정지 상태의 GPS
    // Drift가 실제 이동 거리로 누적되는 것을 줄인다.
    final effectiveAccuracy = <double>[
      point.accuracy ?? _minMoveMeters,
      last.accuracy ?? _minMoveMeters,
    ].reduce((a, b) => a > b ? a : b);
    final requiredMove = (effectiveAccuracy * 0.5).clamp(
      _minMoveMeters,
      _maxAdaptiveMoveMeters,
    );
    if (moved < requiredMove) {
      _lastRejectReason =
          '이동 ${moved.toStringAsFixed(1)}m (${requiredMove.toStringAsFixed(1)}m 이상 필요)';
      return false;
    }

    // 튀는 좌표 걸러내기. 실내·건물 사이에서 수백 m 씩 순간이동한 것처럼
    // 잡히는 경우가 있는데, 그대로 받으면 경로선이 지도를 가로지르고 거리·
    // 페이스까지 같이 망가진다.
    final seconds =
        point.recordedAt.difference(last.recordedAt).inMilliseconds / 1000;
    if (seconds <= 0) {
      // 시각이 같거나 거꾸로 왔다. 속도를 계산할 수 없으니 거리로만 본다.
      if (moved > _maxJumpMeters) {
        _lastRejectReason = '${moved.round()}m 순간이동으로 보여 제외';
        return false;
      }
      _lastRejectReason = null;
      return true;
    }
    if (moved / seconds > _maxSpeedMetersPerSecond) {
      _lastRejectReason = '${(moved / seconds).round()}m/s 로 너무 빨라 제외';
      return false;
    }
    _lastRejectReason = null;
    return true;
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
  Future<Walk?> acceptProposal(
      {required int petId, required int robotId}) async {
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

  /// 산책 중 수집한 좌표를 버퍼에 쌓는다. 저장했으면 true, 걸러졌으면 false.
  /// 실제 위치 수집(geolocator 등)은 화면/서비스에서 담당한다.
  ///
  /// 5m 미만 이동이나 부정확한 좌표는 [_ingest] 에서 걸러진다. 이때 sequence 는
  /// 소비되지 않으므로 서버로 가는 번호에 구멍이 생기지 않는다.
  bool addLocation({
    required double latitude,
    required double longitude,
    double? accuracy,
    DateTime? recordedAt,
  }) {
    return _ingest(WalkLocationPoint(
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      sequence: _sequence + 1,
      recordedAt: recordedAt ?? DateTime.now().toUtc(),
    ));
  }

  /// POST /walks/{walkId}/locations/batch — 버퍼를 비우며 일괄 전송.
  ///
  /// [_maxBatchSize] 개씩 잘라 보내고, 남아 있으면 이어서 보낸다. **성공한 만큼만**
  /// 버퍼에서 지우므로, 실패한 좌표는 그대로 남아 다음 주기에 같은 멱등키로
  /// 재전송된다(리포지토리가 시작 sequence 로 키를 만든다).
  Future<bool> flushLocations() async {
    final walkId = _currentWalk?.walkId;
    if (walkId == null || _pendingPoints.isEmpty) return true;
    // 이미 보내는 중이면 그 전송이 끝나기를 기다린다. 겹치면 중복 전송이 된다.
    if (_isUploading) return false;

    _isUploading = true;
    try {
      while (_pendingPoints.isNotEmpty) {
        final batch =
            _pendingPoints.take(_maxBatchSize).toList(growable: false);

        final result = await guard(
          () => _walkRepository.uploadLocations(walkId: walkId, points: batch),
          silent: true,
        );
        // 실패하면 여기서 멈춘다. 버퍼는 건드리지 않아 다음 기회에 재시도된다.
        if (result == null) return false;

        // 보내는 동안 들어온 좌표는 뒤에 붙으므로, 앞에서 batch 만큼만 지운다.
        _pendingPoints.removeRange(0, batch.length);
        safeNotify();
      }
      return true;
    } finally {
      _isUploading = false;
      safeNotify();
    }
  }

  /// 산책을 끝낸다. `산책 종료` 버튼이 부르는 유일한 종료 경로다.
  ///
  /// 순서가 중요하다.
  ///   1. 위치 수신을 멈추고 (더 이상 좌표가 늘지 않게)
  ///   2. **버퍼에 남은 좌표를 모두 서버에 올린 뒤**
  ///   3. POST /walks/{walkId}/end 를 부른다
  ///
  /// 2번을 건너뛰면 마지막 30초 구간이 서버에 없는 상태로 산책이 끝나고,
  /// 그 좌표들은 영원히 반영되지 않는다. 서버가 이 호출을 받고서야 감성 사진·
  /// 일지 생성을 시작하므로 순서가 뒤바뀌면 안 된다.
  ///
  /// 산책 세션이 없으면(walk API 미배포 등) 로컬 정리만 하고 조용히 끝난다.
  Future<void> endWalk() async {
    stopWatchingWalk();
    // 내부에서 남은 좌표를 마지막으로 flush 한다.
    await stopRouteTracking();

    // 걸은 경로를 기기에 남긴다. 서버에 산책 API 가 배포되기 전까지 산책일지가
    // 날짜별로 경로를 다시 보여줄 수 있는 유일한 방법이다.
    // 서버 기록이 생기면 그쪽이 우선되고 이건 캐시로 남는다.
    await _saveLocalRecord();

    _localWalkActive = false;
    safeNotify();

    final walkId = _currentWalk?.walkId;
    if (walkId == null) return;

    // 좌표가 아직 남아 있으면(전송 실패) 한 번 더 시도한다.
    if (_pendingPoints.isNotEmpty) await flushLocations();

    final walk =
        await guard(() => _walkRepository.endWalk(walkId), silent: true);
    if (walk == null) return;

    _currentWalk = walk;
    safeNotify();
  }

  /// 방금 끝낸 산책을 기기에 저장한다.
  ///
  /// 좌표가 2개 미만이면(제자리에 있었거나 GPS 를 못 잡음) 그릴 경로가 없으므로
  /// 저장하지 않는다. 저장된 id 는 [lastSavedRecordId] 로 알 수 있어, 종료 직후
  /// 경로 상세로 바로 들어갈 수 있다.
  Future<void> _saveLocalRecord() async {
    if (_routePoints.length < 2) return;

    final startedAt =
        _trackingStartedAt ?? _routePoints.first.recordedAt.toLocal();

    _lastSavedRecordId = await _recordStore.save(
      startedAt: startedAt,
      endedAt: DateTime.now(),
      route: _routePoints,
      // 서버 값이 있으면 그걸 쓰고, 없으면 좌표로 계산한 거리를 남긴다.
      distanceMeters: _currentWalk?.distanceMeters,
    );
    safeNotify();
  }

  /// 기기에 저장된 산책 경로. 산책일지·경로 상세가 이걸 읽는다.
  Future<WalkSummary?> localRecord(int walkId) => _recordStore.read(walkId);

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
    // 기기에 저장한 산책이면 그걸 쓴다. 서버에 산책 API 가 없어서 조회해도
    // 못 받는다(2026-08-04 기준 dev 에 walk 엔드포인트 0개).
    if (WalkRecordStore.isLocalId(walkId)) {
      final local = await _recordStore.read(walkId);
      if (local != null) {
        _summary = local;
        clearError();
        safeNotify();
      }
      return;
    }

    // 7월 예시 기록은 서버에 없다. 조회하면 401 만 나므로 만들어 넣은 경로를 쓴다.
    // (SampleWalkDiaries.enabled 를 false 로 하면 이 분기는 타지 않는다)
    if (SampleWalkDiaries.enabled && SampleWalkDiaries.isSampleId(walkId)) {
      final sample = SampleWalkDiaries.summaryFor(walkId);
      if (sample != null) {
        _summary = sample;
        clearError();
        safeNotify();
      }
      return;
    }

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
    _lastKeptPoint = null;
    _sequence = 0;
    _elapsed = Duration.zero;
    _trackingStartedAt = null;
    _receivedCount = 0;
    _lastRejectReason = null;
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
