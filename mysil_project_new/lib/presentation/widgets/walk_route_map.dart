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
    this.showStartEndMarkers = false,
    this.initialLevel = 3,
  });

  /// 그릴 좌표. 순서대로 이어서 선이 된다.
  final List<WalkLocationPoint> points;

  /// 새 좌표가 들어올 때마다 지도 중심을 마지막 좌표로 옮긴다. (산책 중)
  final bool followLast;

  /// 경로 전체가 화면에 들어오도록 줌을 맞춘다. (경로 상세)
  final bool fitWholeRoute;

  /// 출발·도착 지점에 마커를 찍는다. (경로 상세)
  final bool showStartEndMarkers;

  final int initialLevel;

  @override
  State<WalkRouteMap> createState() => _WalkRouteMapState();
}

class _WalkRouteMapState extends State<WalkRouteMap> {
  static const Color _brand = Color(0xFFC67C4E);
  static const String _routeId = 'walk-route';
  static const String _currentId = 'walk-current';
  static const String _startId = 'walk-start';
  static const String _endId = 'walk-end';

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
    if (controller == null || points.isEmpty || !mounted) return;

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

    if (widget.showStartEndMarkers) {
      await controller.addMarker(markers: [
        Marker(markerId: _startId, latLng: path.first),
        if (path.length >= 2) Marker(markerId: _endId, latLng: path.last),
      ]);
    } else {
      await controller.addMarker(markers: [
        Marker(markerId: _currentId, latLng: path.last),
      ]);
    }

    if (widget.fitWholeRoute && path.length >= 2) {
      await controller.fitBounds(path);
    } else if (widget.followLast) {
      await controller.setCenter(path.last);
    }
  }

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
