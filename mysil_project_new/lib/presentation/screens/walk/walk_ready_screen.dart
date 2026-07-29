import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class WalkReadyScreen extends StatelessWidget {
  const WalkReadyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F3E7),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            children: [
              const SizedBox(height: 20),
              // Status Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(20)),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check, color: Colors.green, size: 16),
                    SizedBox(width: 8),
                    Text('산책 제안을 수락했어요', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
              ),
              const Spacer(),
              // Character
              Image.asset('assets/images/mysil_character.png', height: 220),
              const SizedBox(height: 32),
              const Text(
                '마실이가\n준비하고 있어요',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF5D4037), height: 1.3),
              ),
              const SizedBox(height: 12),
              const Text('거치대에서 분리하면 산책이 시작돼요', style: TextStyle(color: Color(0xFF8D6E63), fontSize: 15)),
              
              const SizedBox(height: 48),
              
              // Checklist
              _buildCheckItem(Icons.check, '기기 연결 확인', 'MS-2231 온라인', true),
              const SizedBox(height: 12),
              _buildCheckItem(Icons.check, '위치 권한 · GPS', '정확도 높음', true),
              const SizedBox(height: 12),
              _buildCheckItem(Icons.refresh, '배터리 · 저장공간', '76% · 확인 중', false),
              
              const Spacer(),
              
              // Action Buttons
              SizedBox(
                width: double.infinity,
                height: 64,
                child: ElevatedButton(
                  onPressed: () => context.push('/walk/in-progress'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC67C4E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    elevation: 0,
                  ),
                  child: const Text('지금 바로 시작하기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: TextButton(
                  onPressed: () => context.pop(),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF5D4037),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  child: const Text('제안 취소', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCheckItem(IconData icon, String title, String value, bool isComplete) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isComplete ? const Color(0xFFE8F5E9) : const Color(0xFFFFF8F1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: isComplete ? Colors.green : const Color(0xFFC67C4E), size: 16),
          ),
          const SizedBox(width: 16),
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
          Text(value, style: TextStyle(color: isComplete ? Colors.grey : const Color(0xFFC67C4E), fontSize: 13)),
        ],
      ),
    );
  }
}
