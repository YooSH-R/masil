import 'dart:math' as math;

/// 평면 위의 한 점(m).
class Vec2 {
  const Vec2(this.x, this.y);

  final double x;
  final double y;

  Vec2 operator +(Vec2 other) => Vec2(x + other.x, y + other.y);
  Vec2 operator -(Vec2 other) => Vec2(x - other.x, y - other.y);
  Vec2 operator *(double k) => Vec2(x * k, y * k);

  double get length => math.sqrt(x * x + y * y);

  double distanceTo(Vec2 other) => (this - other).length;

  /// 정북을 0도로 하고 시계방향으로 커지는 방위각(0~360).
  double bearingTo(Vec2 other) {
    final d = other - this;
    if (d.x == 0 && d.y == 0) return 0;
    final deg = math.atan2(d.x, d.y) * 180 / math.pi;
    return deg < 0 ? deg + 360 : deg;
  }

  /// [a]-[b] 직선에서 이 점까지의 수직 거리(m).
  ///
  /// a 와 b 가 같은 자리면 그냥 a 까지의 거리를 준다.
  double perpendicularDistance(Vec2 a, Vec2 b) {
    final ab = b - a;
    final len = ab.length;
    if (len == 0) return distanceTo(a);
    final ap = this - a;
    return (ap.x * ab.y - ap.y * ab.x).abs() / len;
  }

  @override
  String toString() => 'Vec2(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)})';
}

/// 위경도를 기준점 중심의 미터 좌표로 바꾸는 평면 근사.
///
/// **왜 필요한가**: 위도 1도와 경도 1도의 실거리가 다르다(한국 기준 경도가 약
/// 0.79배). 위경도 값에 그대로 EMA 를 걸면 동서 방향이 남북 방향보다 더 세게
/// 눌려서 진행 방향이 미세하게 틀어진다. 거리·수직거리·방위각 계산도 마찬가지다.
///
/// 산책 한 번은 길어야 수 km 라, 기준점 부근을 평면으로 근사해도 오차가 무시할
/// 수준이다. 지구 곡률까지 볼 필요가 없다.
class LocalProjection {
  LocalProjection({required this.originLatitude, required this.originLongitude})
      : _metersPerLngDegree =
            _metersPerLatDegree * math.cos(originLatitude * math.pi / 180);

  /// 위도 1도의 거리(m). 위도에 따라 조금 변하지만 산책 범위에서는 상수로 본다.
  static const double _metersPerLatDegree = 111320;

  final double originLatitude;
  final double originLongitude;
  final double _metersPerLngDegree;

  Vec2 toMeters(double latitude, double longitude) => Vec2(
        (longitude - originLongitude) * _metersPerLngDegree,
        (latitude - originLatitude) * _metersPerLatDegree,
      );

  /// 미터 좌표를 다시 위경도로. (위도, 경도) 순서로 돌려준다.
  (double, double) toLatLng(Vec2 point) => (
        originLatitude + point.y / _metersPerLatDegree,
        originLongitude + point.x / _metersPerLngDegree,
      );
}
