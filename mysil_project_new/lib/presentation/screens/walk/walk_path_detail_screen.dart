import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../viewmodels/walk_view_model.dart';
import '../../widgets/walk_route_map.dart';

/// 지난 산책의 경로 상세. GET /walks/{walkId}/summary 의 route 를
/// 카카오맵 위에 굵은 선으로 그린다.
class WalkPathDetailScreen extends StatefulWidget {
  const WalkPathDetailScreen({super.key, this.walkId});

  /// 볼 산책의 id. null 이면 진행/최근 산책을 보여준다.
  final int? walkId;

  @override
  State<WalkPathDetailScreen> createState() => _WalkPathDetailScreenState();
}

class _WalkPathDetailScreenState extends State<WalkPathDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final walkVm = context.read<WalkViewModel>();
      final id = widget.walkId ?? walkVm.currentWalk?.walkId;
      if (id != null) walkVm.loadSummary(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final walkVm = context.watch<WalkViewModel>();
    final summary = walkVm.summary;

    // 저장된 경로가 있으면 그걸 쓰고, 없으면(방금 끝낸 산책 등) 메모리의 좌표를 쓴다.
    final route =
        (summary?.route.isNotEmpty ?? false) ? summary!.route : walkVm.routePoints;

    final distanceMeters = summary?.distanceMeters ?? walkVm.distanceMeters;
    final durationSeconds =
        summary?.durationSeconds ?? walkVm.elapsed.inSeconds;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F3E7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Color(0xFF5D4037)),
          onPressed: () => context.pop(),
        ),
        title: const Text('산책 경로 상세', style: TextStyle(color: Color(0xFF5D4037), fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
        child: Column(
          children: [
            // Map Area
            // 주의: borderRadius/clipBehavior 로 감싸지 않는다. 내부가 WebView
            // (플랫폼 뷰)라서 클리핑하면 지도가 렌더링되지 않는다.
            Container(
              height: 350,
              width: double.infinity,
              color: const Color(0xFFE8F6F3),
              child: Stack(
                children: [
                  // 경로 전체가 보이도록 줌을 맞추고, 출발·도착에 마커를 찍는다.
                  Positioned.fill(
                    child: WalkRouteMap(
                      points: route,
                      fitWholeRoute: true,
                      showStartEndMarkers: true,
                    ),
                  ),
                  if (route.isEmpty)
                    const Positioned(
                      bottom: 16,
                      left: 16,
                      right: 16,
                      child: _NoRouteBadge(),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Stats Row
            _buildWhiteCard(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildMiniStat(
                      '${(distanceMeters / 1000).toStringAsFixed(2)} km', '산책 거리'),
                  Container(width: 1, height: 30, color: Colors.grey.shade100),
                  _buildMiniStat('${durationSeconds ~/ 60} 분', '산책 시간'),
                  Container(width: 1, height: 30, color: Colors.grey.shade100),
                  _buildMiniStat(_paceLabel(distanceMeters, durationSeconds),
                      '평균 페이스'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Badges
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(color: const Color(0xFFE8F6F3).withValues(alpha: 0.6), borderRadius: BorderRadius.circular(15)),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.circle, color: Colors.green, size: 8),
                  SizedBox(width: 8),
                  Text('위치 권한 허용됨 · GPS 정확도 높음 · 카카오맵 연동', style: TextStyle(color: Color(0xFF16A085), fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Info Note
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
              child: const Row(
                children: [
                  Icon(Icons.location_on, color: Colors.redAccent, size: 18),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '경로가 안 보이나요? 실내 산책이거나 GPS가 약했을 수 있어요. 그래도 기록엔 저장돼요.',
                      style: TextStyle(color: Color(0xFF8D6E63), fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 40),
            
            // AI Action Section
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('이 산책의 감성 사진', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF5D4037))),
            ),
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('산책 중 찍은 사진을 감성 스타일로 바꿔 보세요', style: TextStyle(color: Color(0xFF8D6E63))),
            ),
            const SizedBox(height: 20),
            
            // Style Card
            _buildWhiteCard(
              child: Column(
                children: [
                  Container(
                    height: 180,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFDF7F0),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: const Color(0xFFF0E0D0)),
                    ),
                    child: const Center(child: Icon(Icons.image_outlined, size: 40, color: Color(0xFFD7CCC8))),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton(
                      onPressed: () => context.push('/walk/ai-photo'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFC67C4E),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.auto_awesome, size: 20),
                          SizedBox(width: 12),
                          Text('AI 감성 사진 만들기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  /// 1km 당 분'초". 거리·시간이 없으면 --'--".
  static String _paceLabel(int meters, int seconds) {
    if (meters < 10 || seconds == 0) return '--\'--"';
    final secondsPerKm = seconds / (meters / 1000);
    final m = secondsPerKm ~/ 60;
    final s = (secondsPerKm % 60).round();
    return '$m\'${s.toString().padLeft(2, '0')}"';
  }

  // ignore: unused_element
  Widget _buildMarker(String label, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(10)),
          child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        Icon(Icons.location_on, color: color, size: 30),
      ],
    );
  }

  Widget _buildMiniStat(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF5D4037))),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }

  Widget _buildWhiteCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
      child: child,
    );
  }
}

class MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.5)..strokeWidth = 1;
    for (double i = 0; i < size.width; i += 50) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += 50) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }

    final pathPaint = Paint()..color = const Color(0xFFC67C4E)..strokeWidth = 5..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    final path = Path()..moveTo(size.width * 0.2, size.height * 0.8)..quadraticBezierTo(size.width * 0.5, size.height * 0.4, size.width * 0.8, size.height * 0.2);
    canvas.drawPath(path, pathPaint);
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 저장된 경로가 없을 때 지도 위에 띄우는 안내.
class _NoRouteBadge extends StatelessWidget {
  const _NoRouteBadge();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_off_outlined, color: Color(0xFFC67C4E), size: 16),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                '저장된 경로가 없어요',
                style: TextStyle(
                    color: Color(0xFF5D4037),
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
