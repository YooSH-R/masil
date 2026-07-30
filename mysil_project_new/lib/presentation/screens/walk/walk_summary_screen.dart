import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class WalkSummaryScreen extends StatelessWidget {
  const WalkSummaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F3E7),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
          child: Column(
            children: [
              // Top Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(20)),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.home_outlined, color: Colors.green, size: 16),
                    SizedBox(width: 8),
                    Text('도킹 감지 · 산책 종료', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              
              // Character
              Image.asset('assets/images/mysil_character.png', height: 180),
              const SizedBox(height: 24),
              const Text(
                '오늘 산책 완료!',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF5D4037)),
              ),
              const SizedBox(height: 8),
              const Text('2026.07.27 (월) 오후 2:00 ~ 2:45', style: TextStyle(color: Colors.grey, fontSize: 14)),
              
              const SizedBox(height: 40),
              
              // Stats Row
              _buildWhiteCard(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildSummaryStat('2.3', '거리 (km)'),
                    Container(width: 1, height: 40, color: Colors.grey.shade200),
                    _buildSummaryStat('45', '시간 (분)'),
                    Container(width: 1, height: 40, color: Colors.grey.shade200),
                    _buildSummaryStat('142', 'kcal'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              // Intimacy Bonus Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(20)),
                child: Row(
                  children: [
                    const Icon(Icons.favorite, color: Colors.redAccent, size: 24),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('친밀도 +5 · 78% → 83%', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2E7D32))),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text('목표 30분을 넘겨서 보너스를 받았어요', style: TextStyle(color: const Color(0xFF2E7D32).withValues(alpha: 0.8), fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              // Checklist Card
              _buildWhiteCard(
                child: Column(
                  children: [
                    _buildCheckRow(Icons.check_circle_outline, Colors.green, 'GPS 경로 저장', '312 포인트'),
                    const SizedBox(height: 12),
                    _buildCheckRow(Icons.refresh, const Color(0xFFC67C4E), '산책 사진 정리', '3장 추천 중'),
                    const SizedBox(height: 12),
                    _buildCheckRow(Icons.auto_awesome_outlined, const Color(0xFFC67C4E), '감성 일지 생성', '만들고 있어요'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              // Note
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(15)),
                child: const Row(
                  children: [
                    Icon(Icons.network_wifi, color: Colors.blue, size: 18),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text('영상 동기화는 Wi-Fi에 연결되면 자동으로 이어서 진행돼요.', style: TextStyle(color: Color(0xFF8D6E63), fontSize: 12)),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 40),
              
              // Buttons
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  onPressed: () => context.push('/walk'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC67C4E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  child: const Text('감성 일지 보러 가기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 60,
                child: TextButton(
                  onPressed: () => context.push('/walk/path-detail'),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF5D4037),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  child: const Text('경로 상세 보기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWhiteCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: child,
    );
  }

  Widget _buildSummaryStat(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF5D4037))),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
      ],
    );
  }

  Widget _buildCheckRow(IconData icon, Color color, String label, String status) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
          ],
        ),
        Text(status, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }
}
