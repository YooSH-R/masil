import 'dart:async';

import '../../core/services/gps/walk_track_processor.dart';
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

  /// GPS 원본을 화면용 위치와 저장용 경로점으로 갈라 주는 처리기.
  ///
  /// 좌표를 거를지 말지 판단하는 규칙은 전부 여기 있다. 예전에는 뷰모델이
  /// 직접 `_shouldKeep()` 으로 걸렀는데, 그 하나의 기준이 지도 표시와 서버
  /// 저장을 동시에 결정해 버려서 둘을 따로 조절할 수 없었다.
  final WalkTrackProcessor _track = WalkTrackProcessor();

  /// EMA 가 적용된 현재 위치. 마커가 이걸 따라간다. **서버에 보내지 않는다.**
  WalkLocationPoint? _livePosition;

  /// 좌표가 아직 없을 때 지도 중심으로 쓸 마지막 알려진 위치.
  /// 경로에도 업로드 버퍼에도 넣지 않는다.
  WalkLocationPoint? _cameraHint;

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

  /// 끝낸 산책을 기기에 남기는 저장소.
  ///
  /// 서버에 산책 API 가 배포되기 전까지, 산책일지가 날짜별 경로를 보여줄 수 있는
  /// 유일한 출처다([WalkRecordStore] 주석 참고).
  final WalkRecordStore _recordStore = const WalkRecordStore();

  /// 방금 저장한 기록의 walkId. 종료 직후 경로 상세로 바로 갈 때 쓴다.
  int? _lastSavedRecordId;
  int? get lastSavedRecordId => _lastSavedRecordId;

  WalkProposal? get proposal => _proposal;
  Walk? get currentWalk => _currentWalk;
  WalkSummary? get summary => _summary;
  bool get hasProposal => _proposal != null && !_proposal!.isExpired;
  bool get isWalking =>
      _localWalkActive || _currentWalk?.status == WalkStatus.active;
  int get pendingPointCount => _pendingPoints.length;

  /// 지금 서버로 좌표를 보내는 중인지.
  bool get isUploadingLocations => _isUploading;

  /// 확정된 경로점. 폴리라인과 거리 계산이 이걸 쓴다.
  List<WalkLocationPoint> get routePoints => _track.anchors;
  WalkLocationPoint? get lastPoint {
    final anchors = _track.anchors;
    return anchors.isEmpty ? null : anchors.last;
  }

  bool get hasRoute => _track.anchors.isNotEmpty;
  bool get isTracking => _routeSub != null;

  /// EMA 가 적용된 현재 위치. 마커가 이걸 따라간다.
  ///
  /// 확정 경로점([routePoints])보다 훨씬 자주 바뀐다. 걸러지지 않은 좌표마다
  /// 갱신되므로 1초 간격이면 1초마다 움직인다.
  WalkLocationPoint? get livePosition => _livePosition;

  /// 지도의 첫 중심으로 쓸 좌표.
  ///
  /// 현재 위치 → 확정 경로 시작점 → OS 캐시 순으로 고른다. 셋 다 없을 때만
  /// 화면이 기본 좌표(광화문)를 쓴다.
  WalkLocationPoint? get mapCenterHint {
    if (_livePosition != null) return _livePosition;
    final anchors = _track.anchors;
    if (anchors.isNotEmpty) return anchors.first;
    return _cameraHint;
  }

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
    return Geo.routeDistanceMeters(_track.anchors).round();
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

    // 첫 측위는 실외에서도 수 초 걸린다. 그동안 지도가 기본 좌표(광화문)에
    // 머무르지 않도록, OS 캐시에 남은 위치를 먼저 받아 중심만 옮겨 둔다.
    // 경로·업로드에는 넣지 않는다.
    source.lastKnownPosition().then((position) {
      if (position == null || _livePosition != null) return;
      _cameraHint = position;
      safeNotify();
    });

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

    // 아직 확정을 기다리던 후보점을 경로에 넣는다. 이게 없으면 마지막 몇 m 가
    // 지도에서도 잘리고 서버에도 안 올라간다.
    _enqueueForUpload(_track.finish());

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
    _seenSequences.add(point.sequence);
    _receivedCount += 1;

    final update = _track.add(point);
    _lastRejectReason = update.rejectReason;
    if (update.isRejected) {
      safeNotify();
      return false;
    }

    // 화면용 위치는 좌표마다 갱신한다. 확정 경로점과 달리 서버에 가지 않는다.
    _livePosition = update.livePosition;
    _enqueueForUpload(update.committedAnchors);
    safeNotify();
    return update.committedAnchors.isNotEmpty;
  }

  /// 확정된 경로점만 업로드 버퍼에 넣는다.
  ///
  /// 마커를 부드럽게 하려고 만든 보간 좌표나 EMA 중간값은 여기 오지 않는다.
  /// 서버에는 검증이 끝난 기록 좌표만 남아야 한다.
  void _enqueueForUpload(List<WalkLocationPoint> anchors) {
    if (anchors.isEmpty) return;
    for (final anchor in anchors) {
      _sequence = anchor.sequence > _sequence ? anchor.sequence : _sequence;
      _pendingPoints.add(anchor);
    }

    // 상한까지 찼으면 30초를 기다리지 않고 바로 보낸다. 오래 걸으면 주기보다
    // 버퍼가 먼저 차는데, 그때까지 쌓아두면 한 요청이 너무 커진다.
    // 결과를 기다리지 않는다 — 좌표 수신을 막지 않아야 한다.
    if (_pendingPoints.length >= _maxBatchSize) {
      flushLocations();
    }
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
    if (_track.anchors.length >= 2) return null; // 정상 동작 중
    if (_receivedCount == 0) return null; // 아직 아무것도 안 옴 → 별도 안내가 있다
    final reason = _lastRejectReason;
    if (reason == null) return null;
    return 'GPS $_receivedCount개 받음 · $reason';
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
    if (_track.anchors.length < 2) return;

    final startedAt =
        _trackingStartedAt ?? _track.anchors.first.recordedAt.toLocal();

    _lastSavedRecordId = await _recordStore.save(
      startedAt: startedAt,
      endedAt: DateTime.now(),
      route: _track.anchors,
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
    _track.reset();
    _livePosition = null;
    _seenSequences.clear();
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
