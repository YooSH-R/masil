import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ProactivePlayRequestScreen extends StatefulWidget {
  const ProactivePlayRequestScreen({super.key});

  @override
  State<ProactivePlayRequestScreen> createState() => _ProactivePlayRequestScreenState();
}

class _ProactivePlayRequestScreenState extends State<ProactivePlayRequestScreen> {
  int _selectedFrequency = 1; // 0: 가끔, 1: 보통, 2: 자주
  bool _isDndEnabled = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F3E7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.chevron_left, color: Color(0xFF5D4037)), onPressed: () => context.pop()),
        title: const Text('선제적 놀이 요청', style: TextStyle(color: Color(0xFF5D4037), fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // Character & Bubble Card
            _buildCharacterRequestCard(),
            const SizedBox(height: 24),
            
            // Frequency Selector
            _buildFrequencyCard(),
            const SizedBox(height: 16),
            
            // DND Toggle
            _buildDndCard(),
            const SizedBox(height: 24),
            
            // Recent History
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('최근 놀이 요청', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF5D4037))),
            ),
            const SizedBox(height: 16),
            _buildHistoryCard(),
            
            const SizedBox(height: 24),
            // Info Note
            Container(
              padding: const EdgeInsets.all(20),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.grey, size: 18),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '충전 중이거나 오프라인이면 요청을 보내지 않고, 같은 요청은 30분 안에 다시 보내지 않아요.',
                      style: TextStyle(color: Colors.grey, fontSize: 12, height: 1.4),
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

  Widget _buildCharacterRequestCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30)),
      child: Column(
        children: [
          Image.asset('assets/images/mysil_character.png', height: 180),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(color: const Color(0xFFFFF1F0), borderRadius: BorderRadius.circular(15)),
            child: const Text('지금 · 놀이 요청', style: TextStyle(color: Color(0xFFC67C4E), fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          const SizedBox(height: 16),
          const Text('심심해요, 같이 놀아요!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF5D4037))),
          const SizedBox(height: 8),
          const Text('2시간 동안 교감이 없었어요', style: TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF9F3E7),
                      foregroundColor: const Color(0xFF5D4037),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      elevation: 0,
                    ),
                    child: const Text('나중에', style: TextStyle(fontWeight: FontWeight.bold)),
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
                    child: const Text('놀아주기', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFrequencyCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('요청 빈도', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 20),
          Container(
            height: 60,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: const Color(0xFFF9F3E7), borderRadius: BorderRadius.circular(15)),
            child: Row(
              children: [
                _buildFreqBtn(0, '가끔'),
                _buildFreqBtn(1, '보통'),
                _buildFreqBtn(2, '자주'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text('하루 평균 3~4회 먼저 놀이를 요청해요', style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildFreqBtn(int index, String label) {
    bool isSelected = _selectedFrequency == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedFrequency = index),
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFC67C4E) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.grey, fontWeight: FontWeight.bold)),
          ),
        ),
      ),
    );
  }

  Widget _buildDndCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(15)),
            child: const Icon(Icons.nights_stay_outlined, color: Colors.blue),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('방해 금지 시간', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text('22:00 ~ 08:00 · 요청 안 함', style: TextStyle(color: Colors.grey, fontSize: 13)),
              ],
            ),
          ),
          Switch(value: _isDndEnabled, onChanged: (v) => setState(() => _isDndEnabled = v), activeColor: const Color(0xFFC67C4E)),
        ],
      ),
    );
  }

  Widget _buildHistoryCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
      child: Column(
        children: [
          _buildHistoryItem('놀아주기 응답 · 10분 교감', '11:20', Colors.green),
          const Divider(height: 24),
          _buildHistoryItem('나중에 선택 · 30분 후 재요청', '09:05', Colors.grey),
          const Divider(height: 24),
          _buildHistoryItem('충전 중 · 요청 보류', '07:40', Colors.orange),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(String title, String time, Color dotColor) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
        const SizedBox(width: 16),
        Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w500))),
        Text(time, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }
}
