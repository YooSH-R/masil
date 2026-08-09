import 'local_projection.dart';

/// 지수이동평균(EMA)으로 좌표 흔들림을 완화한다.
///
///     보정값 = alpha x 새좌표 + (1 - alpha) x 이전보정값
///
/// **이상치를 없애는 필터가 아니라 줄이는 필터다.** 100m 튄 좌표를 넣으면
/// alpha 만큼(0.45 면 45m) 끌려간다. 그래서 [GpsSanitizer] 로 명백한 튐을 먼저
/// 걷어낸 뒤에 써야 한다.
///
/// 위경도가 아니라 [LocalProjection] 이 만든 미터 좌표에 적용한다. 이유는
/// [LocalProjection] 주석 참고.
class EmaSmoother {
  EmaSmoother({required this.alpha})
      : assert(alpha > 0 && alpha <= 1, 'alpha 는 0 초과 1 이하여야 한다');

  final double alpha;

  Vec2? _state;

  Vec2? get value => _state;

  void reset() => _state = null;

  /// 첫 좌표는 섞을 이전 값이 없으므로 그대로 통과시킨다. 0 에서 출발하면
  /// 첫 몇 초 동안 원점에서 실제 위치로 끌려오는 이상한 궤적이 생긴다.
  Vec2 add(Vec2 raw) {
    final previous = _state;
    if (previous == null) return _state = raw;
    return _state = raw * alpha + previous * (1 - alpha);
  }
}
