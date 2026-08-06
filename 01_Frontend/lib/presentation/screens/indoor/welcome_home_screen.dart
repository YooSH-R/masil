import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class WelcomeHomeScreen extends StatefulWidget {
  const WelcomeHomeScreen({super.key});

  @override
  State<WelcomeHomeScreen> createState() => _WelcomeHomeScreenState();
}

class _WelcomeHomeScreenState extends State<WelcomeHomeScreen> {
  bool _isEnabled = true;
  double _radius = 120.0;
  bool _isNotificationEnabled = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F3E7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.chevron_left, color: Color(0xFF5D4037)), onPressed: () => context.pop()),
        title: const Text('귀가 마중', style: TextStyle(color: Color(0xFF5D4037), fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          Switch(value: _isEnabled, onChanged: (v) => setState(() => _isEnabled = v), activeThumbColor: const Color(0xFFC67C4E)),
          const SizedBox(width: 12),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // Map Preview with Circle
            Container(
              height: 280,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F6F3),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Stack(
                children: [
                  CustomPaint(painter: GeofencePainter(_radius), size: Size.infinite),
                  Positioned(
                    top: 20,
                    left: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
                      child: Text('우리집 · 감지 반경 ${_radius.toInt()}m', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ),
                  Positioned(
                    bottom: 20,
                    right: 20,
                    child: ElevatedButton(
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFE812),
                        foregroundColor: Colors.black87,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('카카오맵', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            const Text(
              '🏃‍♂️ 집 반경에 들어오면 마실이가 현관으로 마중 나가요',
              style: TextStyle(color: Color(0xFFC67C4E), fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 32),
            
            // Slider Card
            _buildWhiteCard(
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('감지 반경', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('${_radius.toInt()}m', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF5D4037))),
                    ],
                  ),
                  Slider(
                    value: _radius,
                    min: 50,
                    max: 300,
                    activeColor: const Color(0xFFC67C4E),
                    inactiveColor: const Color(0xFFF9F3E7),
                    onChanged: (v) => setState(() => _radius = v),
                  ),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('50m', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      Text('300m', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Home Location Card
            _buildWhiteCard(
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(color: Color(0xFFE8F5E9), shape: BoxShape.circle),
                    child: const Icon(Icons.home, color: Color(0xFF2E7D32)),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('집 위치 설정', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text('서울 마포구 · 등록됨', style: TextStyle(color: Colors.grey, fontSize: 13)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Info Note
            Container(
              padding: const EdgeInsets.all(16),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.grey, size: 16),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text('정확한 마중을 위해 위치 · 백그라운드 권한이 필요해요. 집 위치가 없으면 마중을 켤 수 없어요.', style: TextStyle(color: Color(0xFF8D6E63), fontSize: 11, height: 1.4)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Recent History
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('최근 마중 기록', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF5D4037))),
            ),
            const SizedBox(height: 16),
            _buildWhiteCard(
              child: Column(
                children: [
                  _buildHistoryItem('현관에서 마중했어요', '오늘 오후 7:20', '성공', Colors.green),
                  const Divider(height: 32),
                  _buildHistoryItem('배터리 부족으로 대기', '어제 오후 6:45', '실패', Colors.redAccent),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Arrival Notification
            _buildWhiteCard(
              child: Row(
                children: [
                  const Icon(Icons.notifications_active_outlined, color: Colors.orange, size: 24),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('도착 알림 받기', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text('마중 나갈 때 푸시로 알려드려요', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  ),
                  Switch(value: _isNotificationEnabled, onChanged: (v) => setState(() => _isNotificationEnabled = v), activeThumbColor: const Color(0xFFC67C4E)),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildWhiteCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
      child: child,
    );
  }

  Widget _buildHistoryItem(String title, String time, String status, Color statusColor) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(color: Color(0xFFF9F3E7), shape: BoxShape.circle),
          child: const Icon(Icons.pets, color: Colors.brown, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(time, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
          child: Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11)),
        ),
      ],
    );
  }
}

class GeofencePainter extends CustomPainter {
  final double radius;
  GeofencePainter(this.radius);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..color = const Color(0xFFC67C4E).withValues(alpha: 0.2)..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, paint);

    final borderPaint = Paint()..color = const Color(0xFFC67C4E)..style = PaintingStyle.stroke..strokeWidth = 2;
    // Dashed line simulation
    double dashWidth = 5, dashSpace = 5, startAngle = 0;
    while (startAngle < 2 * 3.14159) {
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, dashWidth / radius, false, borderPaint);
      startAngle += (dashWidth + dashSpace) / radius;
    }
    
    // Home icon placeholder
    final iconPaint = Paint()..color = const Color(0xFFC67C4E);
    canvas.drawCircle(center, 10, iconPaint);
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
