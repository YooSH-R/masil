import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class IntimacyMoodScreen extends StatelessWidget {
  const IntimacyMoodScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F3E7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.chevron_left, color: Color(0xFF5D4037)), onPressed: () => context.pop()),
        title: const Text('친밀도 · 기분', style: TextStyle(color: Color(0xFF5D4037), fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // Gauge Card
            _buildGaugeCard(),
            const SizedBox(height: 24),
            
            // Mood Banner
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(25)),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: const Text('😊', style: TextStyle(fontSize: 24)),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('오늘 기분 최고예요', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF2E7D32))),
                        Text('함께 산책하고 놀아줘서 기분이 좋아요', style: TextStyle(color: Color(0xFF2E7D32), fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Evolution Track
            _buildEvolutionCard(),
            const SizedBox(height: 24),
            
            // Change History
            _buildHistoryCard(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildGaugeCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30)),
      child: Column(
        children: [
          const SizedBox(
            width: 180,
            height: 180,
            child: Stack(
              children: [
                Center(
                  child: SizedBox(
                    width: 160,
                    height: 160,
                    child: CircularProgressIndicator(
                      value: 0.78,
                      strokeWidth: 12,
                      backgroundColor: Color(0xFFF9F3E7),
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFC67C4E)),
                    ),
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('🥰', style: TextStyle(fontSize: 32)),
                      Text('78%', style: TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: Color(0xFF5D4037))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(color: const Color(0xFFFFF1F0), borderRadius: BorderRadius.circular(20)),
            child: const Text('레벨 3 · 단짝 친구', style: TextStyle(color: Color(0xFFC67C4E), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildEvolutionCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('친밀도 단계', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildEvolutionStep('씨앗', '🌱', true, true),
              _buildEvolutionStep('새싹', '🌿', true, true),
              _buildEvolutionStep('단짝', '🐻', true, false),
              _buildEvolutionStep('영혼', '❤️', false, false),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEvolutionStep(String label, String icon, bool isReached, bool isLineNext) {
    return Expanded(
      child: Column(
        children: [
          Row(
            children: [
              if (label != '씨앗') Expanded(child: Container(height: 2, color: isReached ? const Color(0xFFC67C4E) : Colors.grey.shade200)),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isReached ? const Color(0xFFC67C4E) : const Color(0xFFFDF7F0),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Center(child: Text(icon, style: const TextStyle(fontSize: 20))),
              ),
              if (label != '영혼') Expanded(child: Container(height: 2, color: isLineNext ? const Color(0xFFC67C4E) : Colors.grey.shade200)),
            ],
          ),
          const SizedBox(height: 12),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isReached ? const Color(0xFF5D4037) : Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildHistoryCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('변화 이력', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 20),
          _buildHistoryItem(Icons.directions_walk, '산책 30분 완료', '오늘 오후 2시', '+5', Colors.green),
          const Divider(height: 32),
          _buildHistoryItem(Icons.sports_tennis, '놀이 요청에 응답', '오늘 오전 11시', '+2', Colors.green),
          const Divider(height: 32),
          _buildHistoryItem(Icons.nights_stay, '오랫만에 교감', '어제', '-1', Colors.redAccent),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(IconData icon, String title, String time, String points, Color pointColor) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFF9F3E7), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: const Color(0xFFC67C4E), size: 18),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              Text(time, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ),
        Text(points, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: pointColor)),
      ],
    );
  }
}
