import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class WalkDeclinedScreen extends StatelessWidget {
  const WalkDeclinedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F3E7),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            children: [
              const Spacer(),
              // Character
              Image.asset('assets/images/mysil_character.png', height: 220),
              const SizedBox(height: 32),
              const Text(
                '알겠어요,\n다음에 나가요',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF5D4037), height: 1.3),
              ),
              const SizedBox(height: 12),
              const Text('마실이가 조금 아쉽워하지만\n기다릴 수 있어요.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF8D6E63), fontSize: 16)),
              
              const SizedBox(height: 48),
              
              // Next Suggestion Card
              _buildWhiteCard(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('다음 산책 제안', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        SizedBox(height: 4),
                        Text('오후 6:30 · 일몰 전', style: TextStyle(color: Colors.grey, fontSize: 13)),
                      ],
                    ),
                    ElevatedButton(
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFF1F0),
                        foregroundColor: const Color(0xFFC67C4E),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('시간 변경', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              
              // Intimacy Penalty Card
              _buildWhiteCard(
                child: const Row(
                  children: [
                    Icon(Icons.favorite, color: Colors.redAccent, size: 18),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('친밀도 -1', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF5D4037))),
                          SizedBox(height: 4),
                          Text('오늘 산책을 하면 바로 회복돼요', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              
              // Mute Toggle Card
              _buildWhiteCard(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('오늘은 제안 그만 받기', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        SizedBox(height: 4),
                        Text('자정까지 알림을 보내지 않아요', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                    Switch(value: false, onChanged: (v) {}, activeColor: const Color(0xFFC67C4E)),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFFE8F5E9).withValues(alpha: 0.6), borderRadius: BorderRadius.circular(15)),
                child: const Row(
                  children: [
                    Icon(Icons.nights_stay_outlined, color: Colors.green, size: 18),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text('🌙 방해 금지 시간(22:00~08:00)에는 제안이 자동으로 미뤄져요. 같은 제안은 하루 3번까지만 보내요.', style: TextStyle(color: Color(0xFF2E7D32), fontSize: 11, height: 1.4)),
                    ),
                  ],
                ),
              ),
              
              const Spacer(),
              
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  onPressed: () => context.go('/home'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC67C4E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  child: const Text('홈으로 돌아가기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }
}
