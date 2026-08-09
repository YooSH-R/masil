import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kakao_map_plugin/kakao_map_plugin.dart';

import '../../core/config/map_config.dart';
import '../../core/utils/geo.dart';
import '../../domain/entities/walk.dart';

/// 산책 경로를 카카오맵 위에 굵은 선으로 그리는 공용 위젯.
///
/// 산책 중 화면(실시간)과 경로 상세 화면(지난 기록)이 함께 쓴다. 두 화면의
/// 차이는 생성자 옵션으로만 표현한다.
///
/// **확정 경로와 현재 위치를 따로 받는다.** 예전에는 좌표 목록 하나만 받아서
/// 마지막 좌표를 현재 위치로 겸해 썼는데, 그 목록은 저장 기준(최소 5~8m 이동)을
/// 통과한 것만 들어 있어서 마커가 4~6초씩 멈춰 있다가 순간이동했다. 지금은
/// [points] 가 확정 경로, [livePosition] 이 현재 위치다.
///
/// 주의: 이 위젯을 감싸는 쪽에서 `clipBehavior`/`borderRadius` 로 잘라내면
/// 안 된다. 내부가 WebView(안드로이드 플랫폼 뷰)라서 클리핑을 걸면 지도가
/// 렌더링되지 않고 배경색만 보인다.
class WalkRouteMap extends StatefulWidget {
  const WalkRouteMap({
    super.key,
    required this.points,
    this.livePosition,
    this.centerHint,
    this.followLast = false,
    this.fitWholeRoute = false,
    this.initialLevel = 3,
  });

  /// 확정된 경로점. 순서대로 이어서 선이 된다.
  final List<WalkLocationPoint> points;

  /// 실시간 현재 위치. 산책 중에만 준다. 주면 마커가 이걸 부드럽게 따라가고,
  /// 마지막 확정점부터 여기까지 임시 선분이 그려진다.
  final WalkLocationPoint? livePosition;

  /// 좌표가 하나도 없을 때 지도를 띄울 위치. 없으면 기본 좌표를 쓴다.
  final WalkLocationPoint? centerHint;

  /// 현재 위치를 따라 지도 중심을 옮긴다. (산책 중)
  final bool followLast;

  /// 경로 전체가 화면에 들어오도록 줌을 맞춘다. (경로 상세)
  final bool fitWholeRoute;

  final int initialLevel;

  @override
  State<WalkRouteMap> createState() => _WalkRouteMapState();
}

class _WalkRouteMapState extends State<WalkRouteMap> {
  static const Color _brand = Color(0xFFC67C4E);
  static const String _routeId = 'walk-route';
  static const String _tailId = 'walk-route-tail';
  static const String _startId = 'walk-start';
  static const String _endId = 'walk-end';

  /// 지도에 표시할 핀 크기. 에셋은 4배(120x160)로 그려져 있고 여기서 줄여
  /// 표시하므로 테두리가 깨끗하게 나온다.
  static const int _pinWidth = 30;
  static const int _pinHeight = 40;

  /// 마커가 새 좌표까지 이동하는 데 걸리는 시간.
  ///
  /// GPS 수신 간격(1초)보다 짧아야 다음 좌표가 오기 전에 도착한다. 더 길게
  /// 잡으면 EMA 지연 위에 애니메이션 지연이 겹쳐 마커가 눈에 띄게 뒤처진다.
  static const Duration _markerAnimation = Duration(milliseconds: 300);

  /// 애니메이션 갱신 주기.
  ///
  /// 지도가 WebView 라서 프레임마다(60fps) 마커를 옮기면 버벅인다. 100ms 면
  /// 한 번 이동에 3단계 — 사람 눈에는 이어져 보이면서 호출은 1/6 로 준다.
  static const Duration _frameInterval = Duration(milliseconds: 100);

  /// 지도 중심을 다시 잡는 최소 이동거리.
  ///
  /// 좌표마다 setCenter 를 부르면 GPS 가 조금만 흔들려도 지도가 자글자글
  /// 떨린다. 마커는 매번 움직이되 카메라는 이만큼 벗어났을 때만 따라간다.
  static const double _cameraFollowMeters = 5;

  /// 선을 다시 그리는 최소 간격.
  ///
  /// 마커는 100ms 마다 옮겨야 부드럽지만 선까지 그렇게 자주 그릴 필요는 없다.
  /// 아래 '그리기 규칙' 때문에 선을 하나만 고칠 수 없어서 **매번 경로 전체를
  /// 다시 보낸다.** 오래 걸으면 좌표가 수백 개가 되는데 그걸 100ms 마다 보내면
  /// WebView 가 버벅인다. 꼬리 선분이 0.3초 늦게 따라오는 건 눈에 안 띈다.
  ///
  /// 경로점이 늘어난 경우는 이 간격을 기다리지 않고 바로 그린다.
  static const Duration _polylineInterval = Duration(milliseconds: 300);

  KakaoMapController? _controller;

  /// 지도에 이미 반영한 확정점 개수. 폴리라인을 다시 그릴지 판단하는 기준.
  int _drawnAnchorCount = 0;

  /// 마지막으로 선을 그린 시각. [_polylineInterval] 을 재는 기준.
  DateTime? _polylineDrawnAt;

  /// 지금 마커가 있는 자리. 애니메이션 중에는 중간값이다.
  LatLng? _markerAt;

  /// 마지막으로 지도 중심을 맞춘 자리.
  LatLng? _centeredAt;

  Timer? _animTimer;

  // --- 지도 그리기 직렬화 ---
  //
  // 지도에 무언가 그리는 일은 전부 WebView 로 가는 비동기 호출이다
  // (`addMarker` 는 마커마다 `await runJavaScript(...)` 를 돈다). 한 번 그리는
  // 데 100ms 를 넘길 수 있는데 마커 애니메이션 타이머는 100ms 마다 돌므로,
  // 그냥 두면 이전 그리기가 끝나기 전에 다음 그리기가 시작된다. 그러면
  // 명령이 순서를 잃고 마커가 앞뒤로 튀거나, 채널에 그리기 명령이 쌓인다.
  //
  // **그냥 "실행 중이면 무시"하면 안 된다.** 애니메이션의 마지막 프레임(도착
  // 지점)이 버려지면 마커가 중간 지점에 멈춘 채 다음 GPS 좌표를 기다린다 —
  // 이번 작업에서 고치려던 바로 그 증상이 약한 형태로 돌아온다.
  //
  // 그래서 '무시'가 아니라 '미뤄 두고 끝나면 한 번 더'다. 요청이 몰리면
  // 중간 것들은 합쳐지고 **마지막 상태는 반드시 그려진다.**
  //
  // 선과 마커가 같은 잠금을 쓴다. 따로 두면, 새 산책이 시작돼 경로를 지우는
  // 사이에 진행 중이던 마커 그리기가 이전 산책의 핀을 다시 찍는다.
  bool _drawing = false;
  bool _polylinePending = false;
  bool _markerPending = false;

  // --- 그리기 규칙 (kakao_map_plugin 0.4.0) ---
  //
  // 이 플러그인의 `clearMarker(ids)` / `clearPolyline(ids)` 는 이름과 뜻이
  // 반대다. **"넘긴 id 만 남기고 나머지를 전부 지운다."**
  //
  //   markers = markers.filter(m => {
  //     if (!ids.includes(m.id)) { m.setMap(null); return false; }  // 없는 걸 지움
  //     return true;                                                // 있는 걸 남김
  //   });
  //
  // 그리고 `addMarker(list)` 는 내부에서 그 clear 를 먼저 부른다. 그래서
  // **일부만 넘겨 그리면 나머지가 지워진다.** 예전에는 경로 그리기가
  // `addMarker([출발핀])`, 실시간 그리기가 `addMarker([현재위치])` 를 따로
  // 불러서 서로를 지웠고, 100ms 마다 도는 실시간 쪽이 이겨 출발핀과 경로선이
  // 사라졌다.
  //
  // 게다가 JS 쪽 `addMarker`/`addPolyline` 은 같은 id 가 이미 있으면 그냥
  // 돌아간다. 그래서 위치를 옮기려면 **먼저 지워야** 한다.
  //
  // 두 규칙을 합치면 방법은 하나다: 지울 때는 id 를 주지 않아 전부 지우고,
  // 그릴 때는 **화면에 있어야 할 것 전부**를 한 번에 넘긴다.

  @override
  void didUpdateWidget(WalkRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.points.length != _drawnAnchorCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // 경로점이 바뀌면 선도 출발핀도 다시 그려야 한다.
        _polylinePending = true;
        _markerPending = true;
        _drain();
      });
    }

    final live = widget.livePosition;
    if (live != null && live != oldWidget.livePosition) {
      _animateMarkerTo(LatLng(live.latitude, live.longitude));
    }
  }

  @override
  void dispose() {
    _animTimer?.cancel();
    super.dispose();
  }

  /// 마커를 옮긴다. 선은 [_polylineInterval] 이 지났을 때만 같이 그린다.
  ///
  /// [force] 는 애니메이션의 마지막 프레임에서 준다. 그걸 건너뛰면 꼬리 선분이
  /// 마커에 못 미친 자리에 멈춘 채 다음 좌표를 기다린다.
  void _requestDraw({bool force = false}) {
    _markerPending = true;

    final drawnAt = _polylineDrawnAt;
    if (force ||
        drawnAt == null ||
        DateTime.now().difference(drawnAt) >= _polylineInterval) {
      _polylinePending = true;
    }
    _drain();
  }

  /// 밀린 그리기 요청을 하나씩 순서대로 처리한다.
  ///
  /// 선을 먼저 그린다. 마커가 선 위에 얹혀 보여야 하기 때문이다.
  Future<void> _drain() async {
    if (_drawing) return;
    _drawing = true;
    try {
      while (mounted && (_polylinePending || _markerPending)) {
        if (_polylinePending) {
          _polylinePending = false;
          await _drawPolylines();
        } else {
          _markerPending = false;
          await _drawMarkers();
        }
      }
    } finally {
      _drawing = false;
    }
  }

  /// 확정 경로선 + 마지막 확정점에서 현재 위치까지 잇는 꼬리 선분.
  ///
  /// 꼬리가 필요한 이유: 확정점은 몇 미터마다, 그것도 다음 좌표를 봐야 확정되기
  /// 때문에 현재 위치보다 늘 조금 뒤에 있다. 꼬리가 없으면 마커와 선 사이가
  /// 비어 경로가 끊겨 보인다.
  ///
  /// [_drain] 만 부른다. 직접 부르면 직렬화가 깨진다.
  Future<void> _drawPolylines() async {
    final controller = _controller;
    if (controller == null || !mounted) return;

    _polylineDrawnAt = DateTime.now();
    _drawnAnchorCount = widget.points.length;

    final path = widget.points
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList(growable: false);

    // 새 산책이 시작되면 points 가 빈다. 위젯만 갱신해서는 WebView 안에 남은
    // 이전 산책의 선이 없어지지 않으므로 여기서 직접 지운다.
    if (path.isEmpty) {
      _markerAt = null;
      controller.clearPolyline();
      return;
    }

    final tailTo = _markerAt;
    final polylines = <Polyline>[
      // 점이 하나뿐이면 선을 그릴 수 없다.
      if (path.length >= 2)
        Polyline(
          polylineId: _routeId,
          points: path,
          strokeWidth: 12,
          strokeColor: _brand,
          strokeOpacity: 0.9,
          strokeStyle: StrokeStyle.solid,
        ),
      if (tailTo != null)
        Polyline(
          polylineId: _tailId,
          points: [path.last, tailTo],
          strokeWidth: 12,
          strokeColor: _brand,
          strokeOpacity: 0.9,
          strokeStyle: StrokeStyle.solid,
        ),
    ];

    // 전부 지우고 전부 다시 그린다(위 '그리기 규칙').
    controller.clearPolyline();
    if (polylines.isNotEmpty) {
      await controller.addPolyline(polylines: polylines);
    }

    if (widget.fitWholeRoute && path.length >= 2) {
      await controller.fitBounds(path);
    }
  }

  /// 마커를 [target] 까지 [_markerAnimation] 동안 나눠서 옮긴다.
  ///
  /// 좌표가 올 때마다 순간이동시키면 1초마다 툭툭 끊겨 보인다.
  void _animateMarkerTo(LatLng target) {
    final from = _markerAt;
    _animTimer?.cancel();

    // 첫 좌표는 비교할 이전 자리가 없다. 그냥 그 자리에 찍는다.
    if (from == null) {
      _markerAt = target;
      _requestDraw(force: true);
      return;
    }

    final startedAt = DateTime.now();
    _animTimer = Timer.periodic(_frameInterval, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
      final t =
          (elapsed / _markerAnimation.inMilliseconds).clamp(0.0, 1.0).toDouble();
      _markerAt = LatLng(
        from.latitude + (target.latitude - from.latitude) * t,
        from.longitude + (target.longitude - from.longitude) * t,
      );
      // 도착 프레임은 선까지 반드시 맞춘다.
      _requestDraw(force: t >= 1);
      if (t >= 1) timer.cancel();
    });
  }

  /// 출발 핀과 도착 핀을 **한 번에** 찍는다.
  ///
  /// 시작은 민트 발바닥, 끝은 오렌지 하트로 서로 다르게 보이게 한다.
  /// 산책 중에는 도착 핀이 현재 위치를 따라 움직이고, 지난 기록에서는 경로의
  /// 마지막 점에 고정된다.
  ///
  /// 둘을 따로 그리면 안 된다 — 위 '그리기 규칙' 참고. 한쪽만 넘기는 순간
  /// 다른 쪽이 지도에서 사라진다.
  ///
  /// [_drain] 만 부른다. 직접 부르면 직렬화가 깨진다.
  Future<void> _drawMarkers() async {
    final controller = _controller;
    if (controller == null || !mounted) return;

    final points = widget.points;
    final live = _markerAt;

    final start = points.isEmpty
        ? null
        : LatLng(points.first.latitude, points.first.longitude);

    // 지난 기록에는 현재 위치가 없다. 경로의 끝을 도착 지점으로 쓴다.
    // 점이 하나뿐이면 출발 핀과 같은 자리라 찍지 않는다 — 겹치면 뒤에 찍힌
    // 것만 보여서 시작 지점이 사라진 것처럼 된다.
    final end = live ??
        (points.length >= 2
            ? LatLng(points.last.latitude, points.last.longitude)
            : null);

    if (start == null && end == null) {
      controller.clearMarker();
      return;
    }

    // 캐시가 차 있으면 await 없이 바로 쓴다. 프레임마다 마이크로태스크로
    // 한 번 끊기는 것도 그리기 순서가 뒤섞일 틈이 된다.
    final startIcon = start == null ? null : (_cachedStart ?? await _startIcon());
    final endIcon = end == null ? null : (_cachedEnd ?? await _endIcon());
    if (!mounted) return;

    // 전부 지우고 전부 다시 그린다(위 '그리기 규칙').
    controller.clearMarker();
    await controller.addMarker(markers: [
      if (start != null)
        Marker(
          markerId: _startId,
          latLng: start,
          width: _pinWidth,
          height: _pinHeight,
          // 핀 끝(아래 꼭지점)이 좌표를 가리키게 맞춘다. 기본값이면 이미지
          // 가운데가 좌표에 놓여 실제 위치보다 아래에 찍힌 것처럼 보인다.
          offsetX: _pinWidth ~/ 2,
          offsetY: _pinHeight,
          icon: startIcon,
          zIndex: 1,
        ),
      if (end != null)
        Marker(
          markerId: _endId,
          latLng: end,
          width: _pinWidth,
          height: _pinHeight,
          offsetX: _pinWidth ~/ 2,
          offsetY: _pinHeight,
          icon: endIcon,
          zIndex: 2,
        ),
    ]);

    if (live != null) _maybeFollowCamera(live);
  }

  /// 카메라는 마커와 따로 움직인다. 매번 따라가면 지도가 떨린다.
  void _maybeFollowCamera(LatLng at) {
    if (!widget.followLast) return;
    final controller = _controller;
    if (controller == null) return;

    final centered = _centeredAt;
    if (centered != null) {
      final moved = Geo.distanceMeters(
        lat1: centered.latitude,
        lng1: centered.longitude,
        lat2: at.latitude,
        lng2: at.longitude,
      );
      if (moved < _cameraFollowMeters) return;
    }
    _centeredAt = at;
    controller.setCenter(at);
  }

  /// 핀 이미지는 한 번만 읽어 재사용한다. 좌표마다 다시 읽으면 산책 중에
  /// 1초마다 에셋을 디코딩하게 된다.
  static MarkerIcon? _cachedStart;
  static MarkerIcon? _cachedEnd;

  Future<MarkerIcon> _startIcon() async => _cachedStart ??=
      await MarkerIcon.fromAsset('assets/images/pin_start.png');

  Future<MarkerIcon> _endIcon() async =>
      _cachedEnd ??= await MarkerIcon.fromAsset('assets/images/pin_end.png');

  @override
  Widget build(BuildContext context) {
    // JavaScript 키가 없으면 WebView 가 빈 화면만 보여줘 원인을 알기 어렵다.
    // 무엇이 빠졌는지 적어준다.
    if (!MapConfig.isKakaoMapConfigured) {
      return const _MapKeyMissingNotice();
    }

    // 첫 중심: 확정 경로 → 현재 위치 → 캐시된 위치 → 기본 좌표(광화문).
    // 캐시된 위치까지 없을 때만 광화문이 뜬다.
    final anchor = widget.points.isEmpty ? null : widget.points.first;
    final center = anchor ?? widget.livePosition ?? widget.centerHint;

    return KakaoMap(
      onMapCreated: (controller) {
        _controller = controller;
        // 지도가 늦게 준비될 수 있어, 이미 쌓인 좌표를 즉시 반영한다.
        _drawnAnchorCount = 0;
        final live = widget.livePosition;
        if (live != null) {
          _markerAt = LatLng(live.latitude, live.longitude);
        }
        _requestDraw(force: true);
      },
      center: LatLng(
        center?.latitude ?? MapConfig.fallbackLatitude,
        center?.longitude ?? MapConfig.fallbackLongitude,
      ),
      currentLevel: widget.initialLevel,
    );
  }
}

/// JavaScript 앱키가 주입되지 않았을 때의 안내. 빈 WebView 대신 이유를 보여준다.
class _MapKeyMissingNotice extends StatelessWidget {
  const _MapKeyMissingNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFDF7F0),
      padding: const EdgeInsets.all(24),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map_outlined, color: Color(0xFFC67C4E), size: 40),
            SizedBox(height: 12),
            Text(
              '카카오맵 JavaScript 키가 없어요',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: Color(0xFF5D4037)),
            ),
            SizedBox(height: 8),
            Text(
              'dart_defines.json 에 KAKAO_JS_APP_KEY 를 넣고\n'
              'Kakao Developers 에서 JavaScript SDK 도메인에\n'
              'http://localhost 를 등록해 주세요.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
