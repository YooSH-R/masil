import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class WalkDisconnectedScreen extends StatelessWidget {
  const WalkDisconnectedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.5),
      body: Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: const Color(0xFFFDF7F0),
            borderRadius: BorderRadius.circular(35),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(color: Color(0xFFFFF1F0), shape: BoxShape.circle),
                child: const Icon(Icons.power_settings_new, color: Color(0xFFD32F2F), size: 40),
              ),
              const SizedBox(height: 24),
              const Text(
                '기기 연결이 끊어졌어요',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF5D4037)),
              ),
              const SizedBox(height: 12),
              const Text(
                '마실이와의 연결이 잠시 끊겼어요.\n산책 기록은 안전하게 저장되고 있어요.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF8D6E63), fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 32),
              
              // Recovery Progress
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: const Color(0xFFFFF8F1), borderRadius: BorderRadius.circular(20)),
                child: Column(
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('기록 복구 중', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFC67C4E))),
                        Text('78%', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFC67C4E))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: const LinearProgressIndicator(
                        value: 0.78,
                        minHeight: 10,
                        backgroundColor: Color(0xFFEFE5D8),
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFC67C4E)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              
              // Stats Info
              const Column(
                children: [
                  Text('· 마지막 기록 시각 00:24:18', style: TextStyle(color: Color(0xFF8D6E63), fontSize: 13)),
                  SizedBox(height: 8),
                  Text('· 재연결되면 이어서 기록해요', style: TextStyle(color: Color(0xFF8D6E63), fontSize: 13)),
                  SizedBox(height: 8),
                  Text('· 60초 안에 못 붙으면 자동으로 종료하고 저장해요', style: TextStyle(color: Color(0xFF8D6E63), fontSize: 13)),
                ],
              ),
              const SizedBox(height: 32),
              
              // Buttons
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: () => context.pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF5D4037),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          elevation: 0,
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: const Text('산책 이어가기', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFC67C4E),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          elevation: 0,
                        ),
                        child: const Text('다시 연결', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
