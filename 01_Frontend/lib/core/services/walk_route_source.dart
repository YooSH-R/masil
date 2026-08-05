import 'dart:async';

import '../../domain/entities/walk.dart';

/// 산책 중 이동경로(마실이 디바이스의 GPS 발자국)가 앱으로 들어오는 입구.
///
/// 화면(`WalkInProgressScreen`)과 뷰모델은 이 인터페이스만 알고 있다. 따라서
/// 백엔드가 GPS 푸시 채널을 붙이면 **이 인터페이스를 구현한 클래스 하나만
/// 새로 만들어 갈아끼우면** 지도·경로선·시간 표시는 그대로 동작한다.
///
/// 붙일 때 예시:
/// ```dart
/// class MqttWalkRouteSource implements WalkRouteSource {
///   @override
///   Stream<WalkLocationPoint> points(int walkId) =>
///       _client.subscribe('robot-pet/v1/walks/$walkId/locations')
///              .map(_parsePoint);
///   ...
/// }
/// ```
/// 그리고 [main.dart] 의 Provider 등록에서 [MockWalkRouteSource] 대신
/// 새 구현을 넘기면 끝이다.
abstract class WalkRouteSource {
  /// 해당 산책의 좌표 스트림. 새 발자국이 찍힐 때마다 하나씩 흘려보낸다.
  ///
  /// [walkId] 는 서버에 산책 세션이 아직 없으면 null 로 온다(산책 API 미구현).
  /// 실제 구현에서는 null 이면 빈 스트림을 돌려주면 된다.
  ///
  /// 구현 시 주의:
  /// - 순서가 뒤섞여 들어올 수 있으면 [WalkLocationPoint.sequence] 를 채워준다.
  /// - 재연결 시 이미 보낸 좌표를 다시 보내도 된다. 화면 쪽에서 sequence 로
  ///   중복을 걸러낸다.
  Stream<WalkLocationPoint> points(int? walkId);

  /// 구독 정리. 화면을 떠날 때 호출된다.
  Future<void> stop();

  /// 좌표를 받을 수 없는 이유를 사용자 문구로. 받을 수 있으면 null.
  ///
  /// 위치 권한 거부처럼 **사용자가 직접 풀어줘야 하는** 상황을 화면이 안내할 수
  /// 있게 한다. 이게 없으면 권한이 막혔을 때도 "위치 대기 중"만 계속 떠서
  /// 사용자가 무엇을 해야 하는지 알 수 없다.
  ///
  /// 값은 [points] 를 부른 뒤에 정해진다(권한 확인이 비동기라서).
  String? get unavailableMessage;
}

/// 백엔드 GPS 푸시가 준비되기 전까지 화면을 검증하기 위한 임시 소스.
///
/// 미리 정해둔 좌표를 [interval] 마다 하나씩 흘려보낸다. 실제 서버가 붙으면
/// 이 클래스는 지우거나 테스트용으로만 남긴다.
class MockWalkRouteSource implements WalkRouteSource {
  MockWalkRouteSource({
    this.interval = defaultInterval,
    List<({double lat, double lng})>? path,
  }) : _path = path ?? _defaultPath;

  /// 실제 GPS와 같은 3초 간격으로 흘려 화면 갱신 동작을 검증한다.
  /// 서버 전송은 이것과 별개로 [WalkViewModel]이 30초마다 묶어서 보낸다.
  static const Duration defaultInterval = Duration(seconds: 3);

  final Duration interval;
  final List<({double lat, double lng})> _path;

  StreamController<WalkLocationPoint>? _controller;
  Timer? _timer;

  /// 광화문 → 청계천 방향으로 걷는 듯한 좌표들.
  static const List<({double lat, double lng})> _defaultPath = [
    (lat: 37.5759, lng: 126.9768),
    (lat: 37.5754, lng: 126.9775),
    (lat: 37.5748, lng: 126.9781),
    (lat: 37.5741, lng: 126.9788),
    (lat: 37.5735, lng: 126.9797),
    (lat: 37.5729, lng: 126.9808),
    (lat: 37.5726, lng: 126.9820),
    (lat: 37.5722, lng: 126.9833),
    (lat: 37.5719, lng: 126.9845),
    (lat: 37.5715, lng: 126.9858),
    (lat: 37.5710, lng: 126.9869),
    (lat: 37.5704, lng: 126.9878),
  ];

  @override
  Stream<WalkLocationPoint> points(int? walkId) {
    _controller?.close();
    final controller = StreamController<WalkLocationPoint>();
    _controller = controller;

    var index = 0;
    _timer?.cancel();
    _timer = Timer.periodic(interval, (timer) {
      if (index >= _path.length) {
        timer.cancel();
        return;
      }
      final p = _path[index];
      controller.add(WalkLocationPoint(
        latitude: p.lat,
        longitude: p.lng,
        sequence: index + 1,
        recordedAt: DateTime.now().toUtc(),
      ));
      index += 1;
    });

    return controller.stream;
  }

  /// 목 소스는 항상 좌표를 흘려보내므로 막히는 경우가 없다.
  @override
  String? get unavailableMessage => null;

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _controller?.close();
    _controller = null;
  }
}
