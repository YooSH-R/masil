import '../../../domain/entities/walk.dart';
import '../../utils/geo.dart';
import 'gps_track_config.dart';

/// 원본 좌표 한 개에 대한 판정.
enum GpsVerdict {
  /// 정상. 화면에도 쓰고 경로점으로 확정해도 된다.
  accept,

  /// 정확도가 애매하다. 화면에는 반영하되 이것만 보고 경로점을 확정하지 않는다.
  candidate,

  /// 버린다.
  reject,
}

class GpsSanitizeResult {
  const GpsSanitizeResult(this.verdict, [this.reason]);

  final GpsVerdict verdict;

  /// 버리거나 후보로 내린 이유. 화면 진단 문구에 그대로 쓴다.
  final String? reason;

  bool get isRejected => verdict == GpsVerdict.reject;
  bool get isCandidateOnly => verdict == GpsVerdict.candidate;
}

/// 정확도·시각·속도만 보고 명백히 잘못된 좌표를 걸러낸다.
///
/// **여기서 거리 기준(최소 몇 m 이동)은 보지 않는다.** 예전 구조는 "5m 이상
/// 움직여야 저장"을 이 단계에서 함께 처리했는데, 그러면 화면에 찍을 좌표까지
/// 같이 사라져서 마커가 멈춘 것처럼 보였다. 간격을 솎아내는 일은 경로점을
/// 고르는 [RouteAnchorTracker] 몫이고, 여기는 '믿을 수 있는 좌표인가'만 본다.
///
/// 속도 판정의 기준점은 **직전에 통과시킨 좌표**다. 버린 좌표를 기준으로 삼으면
/// 튄 좌표 하나 때문에 이후 정상 좌표가 전부 "너무 빠름"으로 걸려 경로가 영영
/// 멈춘다.
class GpsSanitizer {
  GpsSanitizer({this.config = GpsTrackConfig.defaults});

  final GpsTrackConfig config;

  WalkLocationPoint? _lastPassed;

  void reset() => _lastPassed = null;

  GpsSanitizeResult evaluate(WalkLocationPoint point) {
    final accuracy = point.accuracy;
    if (accuracy != null && accuracy > config.maxAccuracyMeters) {
      return GpsSanitizeResult(
        GpsVerdict.reject,
        '정확도 ${accuracy.round()}m 로 낮아 제외',
      );
    }

    final last = _lastPassed;
    if (last != null) {
      final moved = Geo.distanceMeters(
        lat1: last.latitude,
        lng1: last.longitude,
        lat2: point.latitude,
        lng2: point.longitude,
      );
      final seconds =
          point.recordedAt.difference(last.recordedAt).inMilliseconds / 1000;

      if (seconds <= 0) {
        // 시각이 같거나 거꾸로 왔다. 속도를 낼 수 없으니 거리로만 본다.
        // 시각이 뒤집혔다고 좌표까지 버리지는 않는다 — 기기 시계가 잠깐 튀는
        // 일은 흔하고, 위치 자체는 멀쩡한 경우가 많다.
        if (moved > config.maxJumpMeters) {
          return GpsSanitizeResult(
            GpsVerdict.reject,
            '${moved.round()}m 순간이동으로 보여 제외',
          );
        }
      } else if (moved / seconds > config.maxSpeedMetersPerSecond) {
        return GpsSanitizeResult(
          GpsVerdict.reject,
          '${(moved / seconds).round()}m/s 로 너무 빨라 제외',
        );
      }
    }

    _lastPassed = point;

    if (accuracy != null && accuracy > config.goodAccuracyMeters) {
      return GpsSanitizeResult(
        GpsVerdict.candidate,
        '정확도 ${accuracy.round()}m — 후보로만 사용',
      );
    }
    return const GpsSanitizeResult(GpsVerdict.accept);
  }
}
