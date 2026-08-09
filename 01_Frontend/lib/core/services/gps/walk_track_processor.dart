import '../../../domain/entities/walk.dart';
import 'ema_smoother.dart';
import 'gps_sanitizer.dart';
import 'gps_track_config.dart';
import 'local_projection.dart';
import 'route_anchor_tracker.dart';

/// 좌표 하나를 처리한 결과.
class WalkTrackUpdate {
  const WalkTrackUpdate({
    this.livePosition,
    this.committedAnchors = const [],
    this.rejectReason,
  });

  /// EMA 까지 적용한 현재 위치. 마커가 이걸 따라간다. **서버에 보내지 않는다.**
  /// 좌표가 버려졌으면 null.
  final WalkLocationPoint? livePosition;

  /// 이번에 확정된 경로점. 폴리라인과 업로드 버퍼가 이것만 받는다.
  final List<WalkLocationPoint> committedAnchors;

  /// 좌표를 버린 이유. 화면 진단용.
  final String? rejectReason;

  bool get isRejected => livePosition == null;
}

/// GPS 원본 좌표를 화면용 위치와 서버 저장용 경로점으로 갈라 주는 입구.
///
/// 처리 순서는 다음과 같고, 순서를 바꾸면 안 된다.
///
///     원본 -> 정확도·시각·속도로 이상치 제거 -> EMA 보정 -> A-B-C 확정
///
/// EMA 를 먼저 걸면 튄 좌표가 필터에 섞여 들어가 이후 좌표까지 끌고 간다.
/// 확정을 먼저 하면 흔들리는 좌표가 그대로 경로점이 된다.
///
/// **왜 화면용과 저장용을 나누는가**: 예전에는 하나였다. 그래서 흔들림을 잡으려고
/// 저장 기준을 올리면(최소 5~8m 이동) 마커가 그만큼 멈춰 있다가 순간이동했고,
/// 기준을 내리면 경로가 지그재그가 됐다. 둘은 목적이 다르니 따로 조절해야 한다.
///
/// Flutter 에 의존하지 않는 순수 Dart 다. 단위 테스트에서 좌표만 넣어 검증한다.
class WalkTrackProcessor {
  WalkTrackProcessor({this.config = GpsTrackConfig.defaults})
      : _sanitizer = GpsSanitizer(config: config),
        _ema = EmaSmoother(alpha: config.emaAlpha),
        _tracker = RouteAnchorTracker<WalkLocationPoint>(config: config);

  final GpsTrackConfig config;

  final GpsSanitizer _sanitizer;
  final EmaSmoother _ema;
  final RouteAnchorTracker<WalkLocationPoint> _tracker;

  /// 미터 좌표 변환 기준점. 첫 좌표가 정해 준다.
  LocalProjection? _projection;

  WalkLocationPoint? _livePosition;
  final List<WalkLocationPoint> _anchors = [];

  /// EMA 가 적용된 현재 위치.
  WalkLocationPoint? get livePosition => _livePosition;

  /// 확정된 경로점 전체.
  List<WalkLocationPoint> get anchors =>
      List<WalkLocationPoint>.unmodifiable(_anchors);

  WalkTrackUpdate add(WalkLocationPoint raw) {
    final verdict = _sanitizer.evaluate(raw);
    if (verdict.isRejected) {
      return WalkTrackUpdate(rejectReason: verdict.reason);
    }

    final projection = _projection ??= LocalProjection(
      originLatitude: raw.latitude,
      originLongitude: raw.longitude,
    );

    final measured = projection.toMeters(raw.latitude, raw.longitude);
    final smoothed = _ema.add(measured);
    final live = _toPoint(projection, smoothed, raw);
    _livePosition = live;

    final committed = _tracker.add(AnchorSample<WalkLocationPoint>(
      position: smoothed,
      // 튐 판정은 EMA 를 거치지 않은 값으로 해야 한다. 이유는 AnchorSample 참고.
      rawPosition: measured,
      recordedAt: raw.recordedAt,
      payload: live,
      candidateOnly: verdict.isCandidateOnly,
    ));

    final points = committed.map((s) => s.payload).toList(growable: false);
    _anchors.addAll(points);

    return WalkTrackUpdate(
      livePosition: live,
      committedAnchors: points,
      rejectReason: verdict.reason,
    );
  }

  /// 산책 종료 시 남은 후보점을 확정한다. 이걸 부르지 않으면 마지막 구간이
  /// 경로에서 잘리고 서버에도 안 올라간다.
  List<WalkLocationPoint> finish() {
    final points =
        _tracker.flush().map((s) => s.payload).toList(growable: false);
    _anchors.addAll(points);
    return points;
  }

  void reset() {
    _sanitizer.reset();
    _ema.reset();
    _tracker.reset();
    _projection = null;
    _livePosition = null;
    _anchors.clear();
  }

  /// 보정된 미터 좌표를 위경도로 되돌리되, sequence·정확도·시각은 원본을 지킨다.
  /// sequence 는 서버의 중복 제거 키라서 우리가 새로 만들면 안 된다.
  WalkLocationPoint _toPoint(
    LocalProjection projection,
    Vec2 position,
    WalkLocationPoint raw,
  ) {
    final (latitude, longitude) = projection.toLatLng(position);
    return WalkLocationPoint(
      latitude: latitude,
      longitude: longitude,
      accuracy: raw.accuracy,
      sequence: raw.sequence,
      recordedAt: raw.recordedAt,
    );
  }
}
