import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class PetDeleteConfirmScreen extends StatelessWidget {
  const PetDeleteConfirmScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.5), // Simulated overlay
      body: Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(35),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(color: Color(0xFFFFF1F0), shape: BoxShape.circle),
                child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFD32F2F), size: 40),
              ),
              const SizedBox(height: 24),
              const Text(
                '정말 삭제하시겠어요?',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF5D4037)),
              ),
              const SizedBox(height: 12),
              const Text(
                '마실이와의 기록이 모두 사라져요.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF8D6E63), fontSize: 16),
              ),
              const SizedBox(height: 32),
              
              // Stats Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F0),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('· 산책 기록 128회 · 214km', style: TextStyle(color: Color(0xFFD32F2F), fontSize: 14)),
                    SizedBox(height: 8),
                    Text('· 저장된 영상 12개 · 감성 일지 34편', style: TextStyle(color: Color(0xFFD32F2F), fontSize: 14)),
                    SizedBox(height: 8),
                    Text('· 친밀도 80% · 기기 연결 해제', style: TextStyle(color: Color(0xFFD32F2F), fontSize: 14)),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              
              // Buttons
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 60,
                      child: ElevatedButton(
                        onPressed: () => context.pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEFE5D8),
                          foregroundColor: const Color(0xFF8D6E63),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          elevation: 0,
                        ),
                        child: const Text('취소', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SizedBox(
                      height: 60,
                      child: ElevatedButton(
                        onPressed: () => context.pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD32F2F),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          elevation: 0,
                        ),
                        child: const Text('삭제', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                '삭제 후 30일간은 고객센터에서 복구 요청할 수 있어요',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
