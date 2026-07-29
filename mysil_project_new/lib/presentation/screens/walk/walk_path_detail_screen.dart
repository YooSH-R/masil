import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class WalkPathDetailScreen extends StatelessWidget {
  const WalkPathDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
            Container(
              height: 350,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F6F3),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white, width: 4),
              ),
              child: Stack(
                children: [
                  CustomPaint(painter: MapGridPainter(), size: Size.infinite),
                  // Markers
                  Positioned(top: 60, left: 100, child: _buildMarker('출발', Colors.green)),
                  Positioned(bottom: 80, right: 80, child: _buildMarker('도착', Colors.redAccent)),
                  // Kakao Button
                  Positioned(
                    bottom: 20,
                    right: 20,
                    child: ElevatedButton(
                      onPressed: () => context.push('/walk/path-detail/exception'), // Link to D11 for testing
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFE812),
                        foregroundColor: Colors.black87,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                      child: const Text('카카오맵으로 열기', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
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
                  _buildMiniStat('2.3 km', '산책 거리'),
                  Container(width: 1, height: 30, color: Colors.grey.shade100),
                  _buildMiniStat('45 분', '산책 시간'),
                  Container(width: 1, height: 30, color: Colors.grey.shade100),
                  _buildMiniStat('142 kcal', '소모 칼로리'),
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
