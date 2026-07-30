import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ChargingSleepScreen extends StatelessWidget {
  const ChargingSleepScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF3E363F), // Dark theme background
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 20),
          child: Image.asset('assets/images/mysil_logo.png', color: Colors.white, height: 24),
        ),
        leadingWidth: 100,
        actions: [
          CircleAvatar(
            backgroundColor: Colors.white.withValues(alpha: 0.1),
            child: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => context.pop()),
          ),
          const SizedBox(width: 20),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            // Character with sleep icons
            Stack(
              alignment: Alignment.center,
              children: [
                Image.asset('assets/images/mysil_character.png', height: 200),
                const Positioned(
                  top: -20,
                  right: 40,
                  child: Text('Z\n Z', style: TextStyle(color: Colors.white24, fontSize: 32, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 40),
            const Text(
              '마실이가 자는 중이에요',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 12),
            const Text(
              '충전소에서 곤히 쉬고 있어요 💤',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 48),
            
            // Circular Progress
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
                        value: 0.68,
                        strokeWidth: 12,
                        backgroundColor: Colors.white10,
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFA000)),
                      ),
                    ),
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('68%', style: TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.bold)),
                        Text('충전 중', style: TextStyle(color: Colors.white70, fontSize: 14)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            
            // Info Cards
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(color: Color(0xFFFFA000), shape: BoxShape.circle),
                          child: const Icon(Icons.bolt, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('도킹 상태 · 정상 연결', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                              Text('완충까지 약 42분 남았어요', style: TextStyle(color: Colors.white70, fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.white38, size: 18),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '충전 상태가 1분 이상 갱신되지 않거나 도킹 상태와 어긋나면 "상태 확인 중"으로 바꿔 알려드려요.',
                            style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 32),
            // Bottom Action
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  onPressed: () => context.pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.9),
                    foregroundColor: const Color(0xFF3E363F),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    elevation: 0,
                  ),
                  child: const Text('살짝 깨우기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
