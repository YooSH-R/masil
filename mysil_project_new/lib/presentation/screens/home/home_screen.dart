import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../viewmodels/auth_view_model.dart';


class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authViewModel = context.watch<AuthViewModel>();
    final nickname = authViewModel.user?.nickname ?? '마실이';

    return Scaffold(
      backgroundColor: const Color(0xFFF9F3E7),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10),
          child: Column(
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Image.asset('assets/images/mysil_logo.png', height: 32),
                  Stack(
                    children: [
                      const Icon(Icons.notifications_none, color: Color(0xFF5D4037), size: 28),
                      Positioned(
                        right: 2,
                        top: 2,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              
              // Character & State
              Center(
                child: Column(
                  children: [
                    Image.asset('assets/images/mysil_character.png', height: 220),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(nickname, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF5D4037))),
                        const SizedBox(width: 8),
                        const Icon(Icons.mood, color: Color(0xFF8D6E63), size: 24),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle, color: Colors.green, size: 10),
                          SizedBox(width: 8),
                          Text('오늘 기분 최고예요! ✨', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              
              // Intimacy Card
              _buildWhiteCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.favorite, color: Colors.redAccent, size: 18),
                            SizedBox(width: 8),
                            Text('친밀도', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          ],
                        ),
                        Text('80%', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFC67C4E))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: const BorderRadius.all(Radius.circular(10)),
                      child: LinearProgressIndicator(
                        value: 0.8,
                        minHeight: 12,
                        backgroundColor: const Color(0xFFF9F3E7),
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFC67C4E)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('조금만 더 산책하면 새 표정을 볼 수 있어요!', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              // Stats Row
              Row(
                children: [
                  Expanded(
                    child: _buildWhiteCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.timer_outlined, color: Colors.grey, size: 24),
                          const SizedBox(height: 8),
                          const Text('다음 산책까지', style: TextStyle(color: Colors.grey, fontSize: 13)),
                          const Text('2시간 30분', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF5D4037))),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildWhiteCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.home_outlined, color: Colors.grey, size: 24),
                          const SizedBox(height: 8),
                          const Text('오늘 걸음', style: TextStyle(color: Colors.grey, fontSize: 13)),
                          const Text('4,120보', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF5D4037))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              
              // Grid Menu
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildMenuItem(Icons.directions_walk, '산책 시작', Colors.red.shade50, () => context.push('/walk/suggestion')),
                  _buildMenuItem(Icons.event_seat, '실내놀이', Colors.green.shade50, () => context.push('/indoor/play-request')),
                  _buildMenuItem(Icons.book_outlined, '산책일지', Colors.blue.shade50, () => context.go('/walk')),
                  _buildMenuItem(Icons.auto_awesome, 'AI 사진', Colors.orange.shade50, () => context.push('/walk/ai-photo')),
                ],
              ),
              const SizedBox(height: 32),
              
              // Weather Banner
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9), // Light green
                  borderRadius: BorderRadius.circular(40),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_queue, color: Color(0xFF455A64), size: 32),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('지금 산책하기 좋아요!', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2E7D32))),
                          Text('미세먼지 좋음 · 22° · 바람 약함', style: TextStyle(fontSize: 12, color: Color(0xFF2E7D32))),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => context.push('/walk/in-progress'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF558B2F),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                      ),
                      child: const Text('나가기', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              
              // Mission Card
              _buildWhiteCard(
                child: Column(
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.local_fire_department, color: Colors.orange, size: 20),
                            const SizedBox(width: 8),
                            const Text('연속 산책 미션', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          ],
                        ),
                        const Text('3 / 7일', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(7, (index) {
                        return Container(
                          width: 40,
                          height: 8,
                          decoration: BoxDecoration(
                            color: index < 3 ? const Color(0xFFC67C4E) : const Color(0xFFF9F3E7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 8),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('7일 달성하면 마실이가 새 리본을 선물해요 🎀', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('최근 산책 일지', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF5D4037))),
                  TextButton(onPressed: () => context.go('/walk'), child: const Text('전체 보기', style: TextStyle(color: Color(0xFF8D6E63)))),
                ],
              ),
              _buildLogItem(context),
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

  Widget _buildMenuItem(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 65,
            height: 65,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
            child: Icon(icon, color: const Color(0xFFC67C4E), size: 30),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF5D4037))),
        ],
      ),
    );
  }

  Widget _buildLogItem(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go('/walk'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(color: const Color(0xFFFDF7F0), borderRadius: BorderRadius.circular(15)),
              child: const Icon(Icons.pets, color: Color(0xFFD7CCC8)),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('오늘 오후 2시', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  Text('동네 한 바퀴 · 30분', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
