import 'gps_track_config.dart';
import 'local_projection.dart';

/// 확정 판단을 기다리는 좌표 한 개.
class AnchorSample<T> {
  const AnchorSample({
    required this.position,
    required this.recordedAt,
    required this.payload,
    Vec2? rawPosition,
    this.candidateOnly = false,
  }) : rawPosition = rawPosition ?? position;

  /// EMA 를 거친 좌표. 경로 모양 판단과 실제로 기록되는 값이 모두 이것이다.
  final Vec2 position;

  /// EMA 를 거치기 **전** 좌표. 튐 판정에만 쓴다.
  ///
  /// **왜 따로 필요한가**: EMA 는 튄 좌표를 없애지 않고 alpha 만큼 줄여서 이후
  /// 좌표에 번지게 한다. 18m 튄 값이 alpha 0.45 를 지나면 약 8m 로 줄고, 그
  /// 8m 가 다음 좌표에도 섞인다. 보정된 좌표만 보면 "크게 튀었다가 제자리로
  /// 돌아왔다"는 모양이 무너져서 튐을 못 잡는다. 원본으로 보면 그대로 보인다.
  final Vec2 rawPosition;

  final DateTime recordedAt;

  /// 호출자가 들고 다니는 원본 정보. 뷰모델은 여기에 원본 좌표를 넣어 sequence
  /// 와 accuracy 를 잃지 않는다. 테스트는 그냥 정수를 넣는다.
  final T payload;

  /// 정확도가 애매해서 '후보로만' 쓰기로 한 좌표인지.
  final bool candidateOnly;
}

/// A-B-C 방식으로 경로점을 확정한다.
///
/// - **A**: 마지막으로 확정한 경로점
/// - **B**: 아직 확정하지 않은 후보점
/// - **C**: 새로 들어온 좌표
///
/// B 를 바로 확정하지 않고 C 가 올 때까지 미루는 게 핵심이다. C 를 봐야 B 가
/// 튄 좌표인지, 직선 위의 불필요한 중간점인지, 진짜 코너인지 구분할 수 있다.
///
/// 판정 순서와 이유:
/// 1. **튐**: A-B 가 확 벌어졌는데 C 가 다시 A 근처면 B 는 GPS 가 튄 것이다.
/// 2. **코너**: B 가 A-C 직선에서 벗어났거나 방향이 크게 꺾였으면 지켜야 할
///    점이다. 이걸 버리면 경로가 코너를 가로질러 잘린다.
/// 3. **강제 확정**: 직선이어도 너무 오래/멀리 미루면 경로가 안 그려진다.
/// 4. **직선**: 위 어디에도 안 걸리면 B 는 없어도 되는 중간점이다. C 로 바꾼다.
class RouteAnchorTracker<T> {
  RouteAnchorTracker({this.config = GpsTrackConfig.defaults});

  final GpsTrackConfig config;

  AnchorSample<T>? _anchor;
  AnchorSample<T>? _pending;
  DateTime? _lastCommitAt;

  /// 마지막 확정점. 화면이 임시 선분을 그릴 때 시작점으로 쓴다.
  AnchorSample<T>? get anchor => _anchor;

  /// 아직 확정되지 않은 후보점.
  AnchorSample<T>? get pending => _pending;

  void reset() {
    _anchor = null;
    _pending = null;
    _lastCommitAt = null;
  }

  /// 좌표 하나를 넣고, 이번에 확정된 경로점들을 돌려준다. 보통 0개 또는 1개다.
  List<AnchorSample<T>> add(AnchorSample<T> c) {
    final a = _anchor;
    if (a == null) {
      // 첫 좌표는 비교 대상이 없다. 그대로 출발점으로 확정한다.
      _anchor = c;
      _lastCommitAt = c.recordedAt;
      return [c];
    }

    final b = _pending;
    if (b == null) {
      _pending = c;
      return const [];
    }

    final ab = a.position.distanceTo(b.position);

    // 1) 튐: B 만 멀리 떨어졌다가 C 가 제자리로 돌아왔다. B 를 버린다.
    //
    // 여기서만 원본 좌표를 본다. 보정된 좌표는 EMA 가 튐을 이미 절반쯤 깎고
    // 다음 좌표에도 번뜨려 놔서, 튐 특유의 '갔다가 돌아옴' 모양이 남지 않는다.
    final rawAb = a.rawPosition.distanceTo(b.rawPosition);
    final rawAc = a.rawPosition.distanceTo(c.rawPosition);
    if (rawAb >= config.spikeMinMeters &&
        rawAc <= rawAb * config.spikeReturnRatio) {
      _pending = c;
      return const [];
    }

    // 정확도가 애매한 좌표는 그것 하나만 보고 경로를 확정하지 않는다.
    // 확정은 미루되 후보 자리는 계속 지킨다.
    if (b.candidateOnly) {
      _pending = c;
      return const [];
    }

    // 2) 코너: A-C 직선에서 벗어났거나 진행 방향이 꺾였다.
    //
    // 단, A 에서 충분히 벗어난 뒤에만 본다. 제자리에 서 있으면 GPS 가 2~5m 를
    // 오가는데 그 점들끼리는 서로 크게 꺾여 보여서, 걷지도 않았는데 경로점이
    // 계속 쌓인다. 이 조건이 노이즈와 진짜 코너를 가른다.
    if (ab >= config.cornerMinMeters) {
      final perpendicular =
          b.position.perpendicularDistance(a.position, c.position);
      final turned = _bearingDelta(
        a.position.bearingTo(b.position),
        b.position.bearingTo(c.position),
      );
      if (perpendicular >= config.straightToleranceMeters ||
          turned >= config.turnBearingDegrees) {
        return _commit(b, c);
      }
    }

    // 3) 강제 확정: 직선이어도 경로가 멈춰 보이면 안 된다.
    //
    // 시간 조건에 최소 이동거리를 함께 건다. 제자리에 서 있으면 C 가 계속 B 를
    // 같은 자리로 갈아치우는데, 시간만 보면 5초마다 같은 자리에 점이 쌓인다.
    final held = _lastCommitAt == null
        ? Duration.zero
        : c.recordedAt.difference(_lastCommitAt!);
    final movedEnough = ab >= config.straightToleranceMeters;
    if (ab >= config.forceCommitMeters ||
        (movedEnough && held >= config.forceCommitInterval)) {
      return _commit(b, c);
    }

    // 4) 직선 위의 중간점. 없어도 경로 모양이 같으니 버린다.
    _pending = c;
    return const [];
  }

  /// 산책을 끝낼 때 남아 있는 후보점을 확정한다.
  ///
  /// 이게 없으면 마지막 몇 m 가 경로에서 잘리고 서버에도 안 올라간다.
  List<AnchorSample<T>> flush() {
    final b = _pending;
    final a = _anchor;
    _pending = null;
    if (b == null) return const [];
    // 출발점과 같은 자리면 점을 하나 더 만들 이유가 없다.
    if (a != null && a.position.distanceTo(b.position) == 0) return const [];
    _anchor = b;
    _lastCommitAt = b.recordedAt;
    return [b];
  }

  List<AnchorSample<T>> _commit(AnchorSample<T> b, AnchorSample<T> next) {
    _anchor = b;
    _pending = next;
    _lastCommitAt = b.recordedAt;
    return [b];
  }

  /// 두 방위각의 차이(0~180도).
  static double _bearingDelta(double from, double to) {
    final diff = (to - from).abs() % 360;
    return diff > 180 ? 360 - diff : diff;
  }
}
