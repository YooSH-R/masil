/// GPS 경로 처리에 쓰는 임계값 모음.
///
/// 값을 코드 곳곳에 흩어 두면 현장에서 튜닝할 때마다 여러 파일을 고쳐야 한다.
/// 전부 여기 모아 두고 [WalkTrackProcessor] 생성자로 주입한다. 테스트도 극단적인
/// 값을 넣어 경계 동작을 확인할 수 있다.
class GpsTrackConfig {
  const GpsTrackConfig({
    this.goodAccuracyMeters = 20,
    this.maxAccuracyMeters = 35,
    this.maxSpeedMetersPerSecond = 10,
    this.maxJumpMeters = 200,
    this.emaAlpha = 0.45,
    this.straightToleranceMeters = 1.5,
    this.turnBearingDegrees = 30,
    this.cornerMinMeters = 2,
    this.forceCommitMeters = 3,
    this.forceCommitInterval = const Duration(seconds: 5),
    this.spikeMinMeters = 15,
    this.spikeReturnRatio = 0.4,
  });

  /// 이 정확도 이하면 정상 좌표로 본다.
  final double goodAccuracyMeters;

  /// [goodAccuracyMeters] 초과 ~ 이 값 이하는 '후보 전용'. 화면에는 반영하되
  /// 이것만 보고 경로점을 확정하지는 않는다. 이 값을 넘으면 아예 버린다.
  final double maxAccuracyMeters;

  /// 걷는 중에 나올 수 없는 속도(m/s). 10m/s = 36km/h.
  final double maxSpeedMetersPerSecond;

  /// 시각을 믿을 수 없을 때(같거나 거꾸로) 쓰는 절대 거리 상한.
  final double maxJumpMeters;

  /// EMA 반영 비율. 클수록 반응이 빠르고 작을수록 부드럽다.
  ///
  /// 지연은 대략 `수신간격 x (1-alpha) / alpha` 다. 1초 간격에서 0.45 면 약
  /// 1.2초 — 보행 속도로 1.7m 뒤처진다. 마커 보간(300ms)까지 더해지므로 더
  /// 낮추면 "위치를 안 따라온다"는 체감이 다시 생긴다.
  final double emaAlpha;

  /// 후보점 B 가 A-C 직선에서 이만큼 안쪽이면 직선으로 보고 B 를 버린다.
  final double straightToleranceMeters;

  /// 진행 방향이 이만큼 꺾이면 코너로 보고 B 를 확정한다.
  final double turnBearingDegrees;

  /// 코너 판정을 시작하는 최소 이동거리(A-B).
  ///
  /// **없으면 제자리 흔들림이 전부 코너가 된다.** 서 있어도 GPS 는 2~5m 를
  /// 오가는데, 그 점들은 서로에 대해 크게 꺾인 것처럼 보인다. 수직거리나
  /// 방위각만 보면 걷지도 않았는데 경로점이 계속 쌓인다. A 에서 이만큼은
  /// 벗어나야 '꺾였다'는 판단에 의미가 생긴다.
  final double cornerMinMeters;

  /// 직선이어도 마지막 확정점에서 이만큼 멀어지면 확정한다.
  ///
  /// 이 값을 키우면 직선 구간의 점이 더 줄지만 경로가 늦게 그려진다. 1.4m/s
  /// 보행 기준 3m 는 약 2초마다 한 점이다.
  final double forceCommitMeters;

  /// 아주 천천히 걸어도 경로가 멈추지 않도록, 마지막 확정 후 이 시간이 지나면
  /// 확정한다.
  final Duration forceCommitInterval;

  /// A-B 가 이만큼 떨어져 있어야 '튐'을 의심한다.
  final double spikeMinMeters;

  /// 튐 판정: A-C 거리가 A-B 거리의 이 비율 이하로 돌아오면 B 를 버린다.
  final double spikeReturnRatio;

  static const GpsTrackConfig defaults = GpsTrackConfig();
}
