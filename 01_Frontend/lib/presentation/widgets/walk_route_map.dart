import 'package:flutter/material.dart';
import 'package:kakao_map_plugin/kakao_map_plugin.dart';

import '../../core/config/map_config.dart';
import '../../domain/entities/walk.dart';

/// 산책 경로를 카카오맵 위에 굵은 선으로 그리는 공용 위젯.
///
/// 산책 중 화면(실시간)과 경로 상세 화면(지난 기록)이 함께 쓴다. 두 화면의
/// 차이는 생성자 옵션으로만 표현한다.
///
/// 주의: 이 위젯을 감싸는 쪽에서 `clipBehavior`/`borderRadius` 로 잘라내면
/// 안 된다. 내부가 WebView(안드로이드 플랫폼 뷰)라서 클리핑을 걸면 지도가
/// 렌더링되지 않고 배경색만 보인다.
class WalkRouteMap extends StatefulWidget {
  const WalkRouteMap({
    super.key,
    required this.points,
    this.followLast = false,
    this.fitWholeRoute = false,
    this.initialLevel = 3,
  });

  /// 그릴 좌표. 순서대로 이어서 선이 된다.
  final List<WalkLocationPoint> points;

  /// 새 좌표가 들어올 때마다 지도 중심을 마지막 좌표로 옮긴다. (산책 중)
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
  static const String _startId = 'walk-start';
  static const String _endId = 'walk-end';

  /// 지도에 표시할 핀 크기. 에셋은 4배(120x160)로 그려져 있고 여기서 줄여
  /// 표시하므로 테두리가 깨끗하게 나온다.
  static const int _pinWidth = 30;
  static const int _pinHeight = 40;

  KakaoMapController? _controller;

  /// 지도에 이미 반영한 좌표 개수. 새 좌표가 들어왔는지 판단하는 기준.
  int _drawnCount = 0;

  @override
  void didUpdateWidget(WalkRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.points.length != _drawnCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    }
  }

  Future<void> _sync() async {
    final controller = _controller;
    final points = widget.points;
    if (controller == null || !mounted) return;

    // 새 산책이 시작되어 points가 비면 WebView 안에 남아 있는 이전 산책의
    // 폴리라인과 마커도 직접 지운다. Flutter 위젯만 갱신해서는 지도 오버레이가
    // 자동으로 없어지지 않는다.
    if (points.isEmpty) {
      _drawnCount = 0;
      controller.clearPolyline(polylineIds: const [_routeId]);
      controller.clearMarker(markerIds: const [_startId, _endId]);
      return;
    }

    _drawnCount = points.length;
    final path = points
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList(growable: false);

    // 점이 하나뿐이면 선을 그릴 수 없다. 마커만 찍는다.
    if (path.length >= 2) {
      await controller.addPolyline(polylines: [
        Polyline(
          polylineId: _routeId,
          points: path,
          strokeWidth: 12,
          strokeColor: _brand,
          strokeOpacity: 0.9,
          strokeStyle: StrokeStyle.solid,
        ),
      ]);
    }

    await _drawMarkers(controller, path);

    if (widget.fitWholeRoute && path.length >= 2) {
      await controller.fitBounds(path);
    } else if (widget.followLast) {
      await controller.setCenter(path.last);
    }
  }

  /// 출발·도착 핀을 찍는다.
  ///
  /// 시작은 민트 발바닥, 끝은 오렌지 하트로 **서로 다르게** 보이게 한다.
  /// 예전에는 같은 기본 마커라 어디가 시작인지 알 수 없었다.
  ///
  /// 산책 중에는 마지막 좌표가 곧 현재 위치이므로, 그 자리에 도착 핀을 찍어
  /// 걸어갈수록 따라오게 한다(멈추면 그대로 도착 지점이 된다).
  ///
  /// 좌표가 하나뿐이면 출발 핀만 찍는다 — 같은 자리에 두 핀이 겹치면
  /// 뒤에 찍힌 것만 보여서 시작 지점이 사라진 것처럼 된다.
  Future<void> _drawMarkers(
    KakaoMapController controller,
    List<LatLng> path,
  ) async {
    final start = await _startIcon();
    final end = await _endIcon();
    if (!mounted) return;

    await controller.addMarker(markers: [
      Marker(
        markerId: _startId,
        latLng: path.first,
        width: _pinWidth,
        height: _pinHeight,
        // 핀 끝(아래 꼭지점)이 좌표를 가리키게 맞춘다. 기본값이면 이미지
        // 가운데가 좌표에 놓여 실제 위치보다 아래에 찍힌 것처럼 보인다.
        offsetX: _pinWidth ~/ 2,
        offsetY: _pinHeight,
        icon: start,
        zIndex: 1,
      ),
      if (path.length >= 2)
        Marker(
          markerId: _endId,
          latLng: path.last,
          width: _pinWidth,
          height: _pinHeight,
          offsetX: _pinWidth ~/ 2,
          offsetY: _pinHeight,
          icon: end,
          zIndex: 2,
        ),
    ]);
  }

  /// 핀 이미지는 한 번만 읽어 재사용한다. 좌표마다 다시 읽으면 산책 중에
  /// 5초마다 에셋을 디코딩하게 된다.
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

    final first = widget.points.isEmpty ? null : widget.points.first;
    return KakaoMap(
      onMapCreated: (controller) {
        _controller = controller;
        // 지도가 늦게 준비될 수 있어, 이미 쌓인 좌표를 즉시 반영한다.
        _drawnCount = 0;
        _sync();
      },
      center: LatLng(
        first?.latitude ?? MapConfig.fallbackLatitude,
        first?.longitude ?? MapConfig.fallbackLongitude,
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
