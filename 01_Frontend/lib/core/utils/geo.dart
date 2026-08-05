import 'dart:math' as math;

import '../../domain/entities/walk.dart';

/// 좌표 계산 유틸.
class Geo {
  Geo._();

  static const double _earthRadiusMeters = 6371000;

  /// 두 좌표 사이 거리(m). Haversine.
  static double distanceMeters({
    required double lat1,
    required double lng1,
    required double lat2,
    required double lng2,
  }) {
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return _earthRadiusMeters * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// 경로 전체 길이(m). 점이 2개 미만이면 0.
  static double routeDistanceMeters(List<WalkLocationPoint> points) {
    if (points.length < 2) return 0;

    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += distanceMeters(
        lat1: points[i - 1].latitude,
        lng1: points[i - 1].longitude,
        lat2: points[i].latitude,
        lng2: points[i].longitude,
      );
    }
    return total;
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180;
}
