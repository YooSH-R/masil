import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

// PetMood.label 은 pet.dart 의 확장(PetMoodX)에 있다.
import '../../../domain/entities/pet.dart';
import '../../viewmodels/pet_view_model.dart';

class IndoorHomeScreen extends StatefulWidget {
  const IndoorHomeScreen({super.key});

  @override
  State<IndoorHomeScreen> createState() => _IndoorHomeScreenState();
}

class _IndoorHomeScreenState extends State<IndoorHomeScreen> {
  @override
  void initState() {
    super.initState();
    // 친밀도·기분은 GET /pets/{petId} 응답의 affinity 에서 온다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final petVm = context.read<PetViewModel>();
      if (petVm.pet == null) petVm.loadCurrentPet(silent: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final affinity = context.watch<PetViewModel>().affinity;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F3E7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('실내모드', style: TextStyle(color: Color(0xFF5D4037), fontWeight: FontWeight.bold, fontSize: 22)),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 20),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: const Color(0xFFE3F2FD), borderRadius: BorderRadius.circular(20)),
            child: const Row(
              children: [
                Icon(Icons.nights_stay, color: Color(0xFF1976D2), size: 14),
                SizedBox(width: 4),
                Text('충전 중 · 수면 중', style: TextStyle(color: Color(0xFF1976D2), fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // Character Card
            _buildCharacterCard(context),
            const SizedBox(height: 24),
            
            // Autonomous Roaming Bar
            _buildRoamingCard(context),
            const SizedBox(height: 24),
            
            // Intimacy & Mood Row
            Row(
              children: [
                Expanded(
                    child: _buildStatCard(
                        '친밀도',
                        affinity == null ? '-' : '${affinity.score}%',
                        Icons.favorite,
                        Colors.redAccent,
                        affinity?.progress ?? 0,
                        () => context.push('/indoor/intimacy'))),
                const SizedBox(width: 16),
                Expanded(
                    child: _buildStatCard(
                        '오늘 기분',
                        affinity?.mood.label ?? '불러오는 중',
                        Icons.sentiment_very_satisfied,
                        Colors.orange,
                        null,
                        () => context.push('/indoor/intimacy'))),
              ],
            ),
            const SizedBox(height: 24),
            
            // Grid Menu
            _buildGridMenu(context),
            const SizedBox(height: 32),
            
            // Info Note
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(20)),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFFC67C4E), size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '로봇이 오프라인이거나 배터리가 부족하면 명령 버튼이 잠기고, 이유를 이 자리에서 알려드려요.',
                      style: TextStyle(color: Color(0xFF8D6E63), fontSize: 12, height: 1.4),
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

  Widget _buildCharacterCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 5)),
        ],
      ),
      child: Column(
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(10)),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.battery_charging_full, color: Colors.green, size: 14),
                  SizedBox(width: 4),
                  Text('76%', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          GestureDetector(
            onTap: () => context.push('/indoor/charging'),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Image.asset('assets/images/mysil_character.png', height: 180),
                const Positioned(
                  top: 0,
                  right: 20,
                  child: Text('Z\n Z', style: TextStyle(color: Color(0xFFD7CCC8), fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('마실이가 충전하며 자고 있어요', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF5D4037))),
          const SizedBox(height: 8),
          const Text('완충까지 약 40분 · 새근새근 😴', style: TextStyle(color: Color(0xFF8D6E63), fontSize: 14)),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: const LinearProgressIndicator(
              value: 0.76,
              minHeight: 10,
              backgroundColor: Color(0xFFF9F3E7),
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFC67C4E)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoamingCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFE8F6F3), borderRadius: BorderRadius.circular(15)),
            child: const Icon(Icons.explore_outlined, color: Color(0xFF16A085)),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('자율 배회', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                Text('지금은 충전소에서 쉬는 중', style: TextStyle(color: Colors.grey, fontSize: 13)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color iconColor, double? progress, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 16),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
            const SizedBox(height: 12),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF5D4037))),
            if (progress != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: const Color(0xFFF9F3E7),
                  valueColor: AlwaysStoppedAnimation<Color>(iconColor),
                ),
              ),
            ] else ...[
              const SizedBox(height: 4),
              const Text('함께 산책해서 좋아요', style: TextStyle(color: Colors.grey, fontSize: 11)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGridMenu(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildIconMenu('이름 호출', Icons.mic_none, const Color(0xFFFFF1F0), () => context.push('/indoor/name-setting')),
        _buildIconMenu('놀이 요청', Icons.sports_tennis, const Color(0xFFE8F6F3), () => context.push('/indoor/play-request')),
        _buildIconMenu('귀가 마중', Icons.home_outlined, const Color(0xFFFFDDB8), () => context.push('/indoor/welcome-home')),
        _buildIconMenu('알림 설정', Icons.notifications_none, const Color(0xFFE8F5E9), () => context.push('/indoor/notifications')),
      ],
    );
  }

  Widget _buildIconMenu(String label, IconData icon, Color bgColor, VoidCallback onTap) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 65,
            height: 65,
            decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(20)),
            child: Icon(icon, color: const Color(0xFF5D4037), size: 28),
          ),
        ),
        const SizedBox(height: 10),
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF5D4037))),
      ],
    );
  }
}
