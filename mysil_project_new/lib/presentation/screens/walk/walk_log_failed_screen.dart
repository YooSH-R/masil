import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class WalkLogFailedScreen extends StatelessWidget {
  const WalkLogFailedScreen({super.key});

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
        title: const Text('감성 일지', style: TextStyle(color: Color(0xFF5D4037), fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
        child: Column(
          children: [
            // Error Container
            Container(
              padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30)),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(color: Color(0xFFF9F3E7), shape: BoxShape.circle),
                    child: const Icon(Icons.auto_awesome, color: Color(0xFFC67C4E), size: 40),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    '일지를 만들지 못했어요',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF5D4037)),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'AI 생성이 시간을 초과했어요.\n산책 기록은 그대로 저장돼 있어요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF8D6E63), fontSize: 16, height: 1.5),
                  ),
                  const SizedBox(height: 48),
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton(
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFC67C4E),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.refresh),
                          SizedBox(width: 8),
                          Text('다시 만들기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: TextButton(
                      onPressed: () {},
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF5D4037),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.grey.shade200)),
                      ),
                      child: const Text('직접 일지 쓰기', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text('자동 재시도 2회 완료 · 다음 재시도 03:00 후', style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Ingredients Card
            _buildInfoCard(
              title: '이 산책의 재료',
              children: [
                _buildIngredientItem(Icons.check, Colors.green, 'GPS 경로 312 포인트', null),
                const SizedBox(height: 12),
                _buildIngredientItem(Icons.close, Colors.redAccent, '산책 사진 0장 · 동기화 실패', '재시도'),
                const SizedBox(height: 12),
                _buildIngredientItem(Icons.check, Colors.green, '성과 기록 2.3km · 45분', null),
              ],
            ),
            
            const SizedBox(height: 24),
            // Info Note
            Container(
              padding: const EdgeInsets.all(16),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.grey, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('영상과 GPS 기록이 모두 없으면 일지를 만들 수 없어요. 다음 산책에는 마실이가 영상을 담아올게요.', style: TextStyle(color: Colors.grey, fontSize: 11, height: 1.4)),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            // Pending Logs
            _buildInfoCard(
              title: '생성 대기 중인 일지 2편',
              children: [
                _buildPendingItem('07.25 천변 산책', '대기 중', const Color(0xFFFFF8F1), const Color(0xFFC67C4E)),
                const SizedBox(height: 12),
                _buildPendingItem('07.24 골목 탐험', '완료', const Color(0xFFE8F6F3), const Color(0xFF16A085)),
              ],
            ),
            
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildIngredientItem(IconData icon, Color iconColor, String label, String? action) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: Icon(icon, color: iconColor, size: 14),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
        if (action != null)
          Text(action, style: TextStyle(color: iconColor, fontWeight: FontWeight.bold, fontSize: 13, decoration: TextDecoration.underline)),
      ],
    );
  }

  Widget _buildPendingItem(String title, String status, Color bgColor, Color textColor) {
    return Row(
      children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: const Color(0xFFF9F3E7), borderRadius: BorderRadius.circular(10))),
        const SizedBox(width: 12),
        Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(10)),
          child: Text(status, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 11)),
        ),
      ],
    );
  }

  Widget _buildInfoCard({required String title, required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }
}
