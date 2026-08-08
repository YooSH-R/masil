import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../../domain/entities/walk.dart';
import 'walk_route_source.dart';

/// 위치 수집을 시작할 수 없는 이유.
enum GpsUnavailableReason {
  /// 기기의 위치 서비스(GPS)가 꺼져 있다.
  serviceDisabled,

  /// 사용자가 위치 권한을 거절했다. 다시 물어볼 수 있다.
  permissionDenied,

  /// "다시 묻지 않기"로 거절했다. 설정 화면에서 직접 켜야 한다.
  permissionDeniedForever,
}

/// **휴대폰 자체 GPS** 로 산책 경로를 기록하는 [WalkRouteSource].
///
/// 마실이 기기의 GPS 를 받아오는 게 아니라 이 휴대폰의 위치를 쓴다. 그래서
/// 거리·평균 페이스·발자국 수가 모두 사용자가 실제로 걸은 값이 된다.
///
/// 역할을 나눠 두었다.
/// - **여기**: OS 에게 1초 간격으로 원본 좌표를 요청하기만 한다. 거르지 않는다.
/// - **[WalkTrackProcessor]**: 이상치를 걷어내고 EMA 를 걸어 화면용 위치와
///   저장용 경로점을 따로 만든다.
///
/// 예전에는 여기서도 3초·2m 로 미리 줄였다. 그러면 화면에 찍을 좌표까지 같이
/// 사라져서 마커가 멈춰 있다가 순간이동한다. 무엇을 버릴지는 판단에 필요한
/// 재료를 다 본 뒤에 정하는 편이 낫다. 서버 전송은 이것과 별개로 뷰모델이
/// 30초마다 묶어서 한다.
class DeviceGpsWalkRouteSource implements WalkRouteSource {
  DeviceGpsWalkRouteSource();

  /// 원본을 촘촘히 받는다. 솎아내는 일은 [WalkTrackProcessor] 가 한다.
  ///
  /// 예전에는 3초였다. OS 단계에서 미리 줄여 두면 배터리는 아끼지만, 화면에
  /// 찍을 좌표까지 같이 사라져서 마커가 3초씩 멈춰 있었다. 판단에 필요한
  /// 재료는 다 받아 놓고 무엇을 버릴지는 위에서 정하는 편이 낫다.
  static const Duration interval = Duration(seconds: 1);

  /// 0 이면 거리와 무관하게 [interval] 마다 준다.
  ///
  /// 제자리 흔들림은 EMA 와 A-B-C 확정이 걸러낸다. 여기서 미리 자르면 아주
  /// 천천히 걸을 때 좌표가 아예 안 와서 경로가 멈춘다.
  static const int distanceFilterMeters = 0;

  /// 좌표가 이만큼 안 오면 멈춘 것으로 보고 직접 물어본다.
  /// 측정 간격(1초)보다 넉넉히 잡아, 정상 지연을 실패로 오인하지 않는다.
  static const Duration _stallThreshold = Duration(seconds: 6);

  /// 요청할 정확도. 산책 경로는 보행자 단위 정밀도가 필요하다.
  static const LocationAccuracy _accuracy = LocationAccuracy.best;

  StreamController<WalkLocationPoint>? _controller;
  StreamSubscription<Position>? _positionSub;

  /// 좌표가 멈췄는지 지켜보는 타이머.
  Timer? _watchdog;

  /// 마지막으로 좌표를 받은 시각. 멈춤 판정에 쓴다.
  DateTime? _lastStreamAt;

  /// Foreground Service 를 쓰는 중인지. 실패하면 false 로 떨어진다.
  bool _usingForegroundService = true;

  /// 스트림이 끝내 실패한 이유. 화면이 안내에 쓴다.
  String? _streamError;

  /// 화면이 꺼져도 기록되는 상태인지. false 면 앱을 보고 있어야 기록된다.
  bool get isBackgroundCapable => _usingForegroundService;

  /// 좌표 순번. 서버·뷰모델이 중복을 걸러내는 데 쓴다.
  int _sequence = 0;

  /// 위치를 못 켠 이유. 화면이 안내 문구를 고르는 데 쓴다.
  GpsUnavailableReason? _unavailableReason;
  GpsUnavailableReason? get unavailableReason => _unavailableReason;

  @override
  String? get unavailableMessage => switch (_unavailableReason) {
        GpsUnavailableReason.serviceDisabled => '위치 서비스가 꺼져 있어요. 설정에서 켜 주세요',
        GpsUnavailableReason.permissionDenied => '위치 권한이 필요해요. 허용하면 경로가 그려져요',
        GpsUnavailableReason.permissionDeniedForever =>
          '위치 권한이 차단돼 있어요. 앱 설정에서 허용해 주세요',
        // 권한은 있는데 스트림이 끝내 실패한 경우. 예전에는 이 상황이 화면에
        // 아무 표시도 남기지 않아, 첫 좌표에 멈춘 채 원인을 알 수 없었다.
        null => _streamError == null
            ? null
            : '위치를 계속 받지 못했어요. 위치 권한을 "정확한 위치"로 허용했는지 확인해 주세요',
      };

  @override
  Stream<WalkLocationPoint> points(int? walkId) {
    // walkId 는 쓰지 않는다. 서버에 산책 세션이 없어도 휴대폰 GPS 는 찍힌다.
    _controller?.close();
    final controller = StreamController<WalkLocationPoint>();
    _controller = controller;
    _sequence = 0;
    _unavailableReason = null;

    // 권한 확인은 비동기라서, 스트림을 먼저 돌려주고 준비되면 흘려보낸다.
    _start(controller);

    return controller.stream;
  }

  Future<void> _start(StreamController<WalkLocationPoint> controller) async {
    final ready = await _ensurePermission();
    if (!ready) {
      // 이유는 [unavailableReason] 으로 남기고 스트림은 조용히 닫는다.
      // 에러를 던지면 화면이 빨간 오류로 덮이는데, 여기서 필요한 건
      // "권한을 켜 주세요" 안내다.
      await controller.close();
      return;
    }

    // 첫 좌표를 바로 하나 찍어 준다. 그러지 않으면 스트림 첫 이벤트가 올 때까지
    // 지도가 빈 채로 남아서 고장난 것처럼 보인다.
    try {
      final first = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: _accuracy),
      );
      if (!controller.isClosed) controller.add(_toPoint(first));
    } catch (_) {
      // 첫 좌표를 못 받아도 이어지는 스트림은 그대로 시도한다.
    }

    // 위치 스트림을 연다. 실패하면 Foreground Service 를 빼고 한 번 더 시도한다.
    _listen(controller, withForegroundService: true);

    // 스트림이 살아 있어도 좌표가 한동안 안 오는 경우가 있다(기기·전원 설정에
    // 따라 배치가 지연되거나 서비스가 조용히 죽는다). 그때 화면이 첫 좌표에
    // 멈춰 보이므로, 주기적으로 직접 물어봐서 메운다.
    _startWatchdog(controller);
  }

  /// 위치 스트림 구독. [withForegroundService] 가 false 면 화면이 켜져 있는
  /// 동안만 동작하는 대신 알림 권한에 의존하지 않는다.
  void _listen(
    StreamController<WalkLocationPoint> controller, {
    required bool withForegroundService,
  }) {
    _positionSub?.cancel();
    _usingForegroundService = withForegroundService;

    _positionSub = Geolocator.getPositionStream(
      locationSettings: _settings(foreground: withForegroundService),
    ).listen(
      (position) {
        if (controller.isClosed) return;
        _lastStreamAt = DateTime.now();
        _streamError = null;
        controller.add(_toPoint(position));
      },
      onError: (Object error) {
        // **오류를 삼키지 않는다.** 예전에는 조용히 무시해서, Foreground Service
        // 가 알림 권한 때문에 시작하지 못한 경우에도 화면에는 아무 표시가 없었다.
        if (withForegroundService) {
          // 알림 권한이 없거나 서비스 시작이 막힌 경우가 대부분이다.
          // 서비스를 빼고 다시 시도하면 최소한 화면이 켜져 있는 동안은 기록된다.
          _listen(controller, withForegroundService: false);
          return;
        }
        _streamError = error.toString();
      },
      cancelOnError: false,
    );
  }

  /// 좌표가 [_stallThreshold] 동안 안 오면 직접 한 번 물어본다.
  void _startWatchdog(StreamController<WalkLocationPoint> controller) {
    _watchdog?.cancel();
    _watchdog = Timer.periodic(_stallThreshold, (_) async {
      if (controller.isClosed) return;

      final last = _lastStreamAt;
      if (last != null && DateTime.now().difference(last) < _stallThreshold) {
        return; // 잘 들어오고 있다.
      }

      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: _accuracy),
        );
        if (controller.isClosed) return;
        _lastStreamAt = DateTime.now();
        controller.add(_toPoint(position));
      } catch (_) {
        // 이번 주기는 실패. 다음 주기에 다시 시도한다.
      }
    });
  }

  /// 안드로이드에서는 산책 중 화면이 꺼져도 좌표가 끊기지 않게 Foreground
  /// Service 알림을 함께 띄운다. 안드로이드가 요구하는 방식이다.
  /// [foreground] 가 false 면 Foreground Service 를 붙이지 않는다.
  ///
  /// 서비스는 알림을 띄워야 하고 안드로이드 13+ 는 알림에 권한이 필요하다.
  /// 권한이 없으면 서비스 시작이 막혀 **스트림 자체가 안 열리므로**, 그때는
  /// 서비스를 포기하고라도 좌표를 받는 쪽을 택한다(화면이 켜져 있는 동안 기록).
  LocationSettings _settings({required bool foreground}) {
    return AndroidSettings(
      accuracy: _accuracy,
      distanceFilter: distanceFilterMeters,
      intervalDuration: interval,
      foregroundNotificationConfig: foreground
          ? const ForegroundNotificationConfig(
              notificationTitle: '산책 기록 중',
              notificationText: '마실이와 걷는 길을 지도에 그리고 있어요',
              notificationChannelName: '산책 위치 기록',
              enableWakeLock: true,
            )
          : null,
    );
  }

  /// 위치 서비스와 권한을 확인하고, 필요하면 요청한다.
  Future<bool> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      _unavailableReason = GpsUnavailableReason.serviceDisabled;
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    switch (permission) {
      case LocationPermission.denied:
        _unavailableReason = GpsUnavailableReason.permissionDenied;
        return false;
      case LocationPermission.deniedForever:
        _unavailableReason = GpsUnavailableReason.permissionDeniedForever;
        return false;
      case LocationPermission.whileInUse:
      case LocationPermission.always:
        return true;
      case LocationPermission.unableToDetermine:
        // 판단이 안 되면 일단 시도한다. 실제로 막히면 스트림이 조용히 끝난다.
        return true;
    }
  }

  /// OS 캐시에 남아 있는 마지막 위치. 측위를 기다리지 않고 즉시 돌아온다.
  ///
  /// 지도 첫 중심에만 쓴다. sequence 를 0 으로 두어 경로용 좌표와 구분한다 —
  /// 실수로 경로에 섞이면 몇 시간 전 위치까지 선이 그어진다.
  @override
  Future<WalkLocationPoint?> lastKnownPosition() async {
    try {
      final position = await Geolocator.getLastKnownPosition();
      if (position == null) return null;
      return WalkLocationPoint(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        sequence: 0,
        recordedAt: position.timestamp.toUtc(),
      );
    } catch (_) {
      // 권한이 없거나 캐시가 비었다. 지도는 기본 좌표로 뜬다.
      return null;
    }
  }

  WalkLocationPoint _toPoint(Position position) {
    _sequence += 1;
    return WalkLocationPoint(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      sequence: _sequence,
      recordedAt: position.timestamp.toUtc(),
    );
  }

  @override
  Future<void> stop() async {
    _watchdog?.cancel();
    _watchdog = null;
    _lastStreamAt = null;
    await _positionSub?.cancel();
    _positionSub = null;
    await _controller?.close();
    _controller = null;
  }
}
