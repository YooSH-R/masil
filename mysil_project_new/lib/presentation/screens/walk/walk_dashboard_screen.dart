import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class WalkDashboardScreen extends StatefulWidget {
  const WalkDashboardScreen({super.key});

  @override
  State<WalkDashboardScreen> createState() => _WalkDashboardScreenState();
}

class _WalkDashboardScreenState extends State<WalkDashboardScreen> {
  int _selectedTab = 1; // 0: 일, 1: 주, 2: 월

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
        title: const Text('산책 리포트', style: TextStyle(color: Color(0xFF5D4037), fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
        child: Column(
          children: [
            // Custom Tab Bar
            Container(
              height: 60,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: const Color(0xFFEFE5D8), borderRadius: BorderRadius.circular(20)),
              child: Row(
                children: [
                  _buildTabItem(0, '일'),
                  _buildTabItem(1, '주'),
                  _buildTabItem(2, '월'),
                ],
              ),
            ),
            const SizedBox(height: 32),
            
            // Stats Grid
            Row(
              children: [
                _buildSmallStatCard('12.4', '거리 (km)'),
                const SizedBox(width: 16),
                _buildSmallStatCard('3:20', '시간'),
                const SizedBox(width: 16),
                _buildSmallStatCard('8', '횟수'),
              ],
            ),
            const SizedBox(height: 24),
            
            // Bar Chart Section
            _buildWhiteCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('요일별 거리', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF5D4037))),
                  const SizedBox(height: 32),
                  SizedBox(
                    height: 180,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _buildBar('월', 0.4),
                        _buildBar('화', 0.5),
                        _buildBar('수', 0.9),
                        _buildBar('목', 0.3),
                        _buildBar('금', 0.6),
                        _buildBar('토', 0.7),
                        _buildBar('일', 0.55),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Goal Progress
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(25)),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('이번 주 목표', style: TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        RichText(
                          text: const TextSpan(
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF5D4037)),
                            children: [
                              TextSpan(text: '15km 중 '),
                              TextSpan(text: '12.4km 달성 ', style: TextStyle(color: Color(0xFFC67C4E))),
                              TextSpan(text: '👏'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 70,
                    height: 70,
                    child: Stack(
                      children: [
                        Center(
                          child: CircularProgressIndicator(
                            value: 0.83,
                            strokeWidth: 8,
                            backgroundColor: Colors.white,
                            valueColor: AlwaysStoppedAnimation<Color>(const Color(0xFF558B2F).withValues(alpha: 0.6)),
                          ),
                        ),
                        const Center(child: Text('83%', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2E7D32)))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 32),
            // Footer Note
            Container(
              padding: const EdgeInsets.all(16),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.grey, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '기간에 기록이 없으면 "아직 산책 기록이 없어요"를 표시하고, 비정상 GPS 값은 집계에서 자동 제외해요.',
                      style: TextStyle(color: Colors.grey, fontSize: 11, height: 1.4),
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

  Widget _buildTabItem(int index, String label) {
    bool isSelected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFC67C4E) : Colors.transparent,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(color: isSelected ? Colors.white : Colors.grey, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSmallStatCard(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Column(
          children: [
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF5D4037))),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildBar(String day, double heightFactor) {
    return Column(
      children: [
        Expanded(
          child: FractionallySizedBox(
            heightFactor: heightFactor,
            child: Container(
              width: 35,
              decoration: BoxDecoration(
                color: heightFactor > 0.8 ? const Color(0xFFC67C4E) : const Color(0xFFEFE5D8),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(day, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
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
