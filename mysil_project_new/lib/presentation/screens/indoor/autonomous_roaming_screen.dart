import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AutonomousRoamingScreen extends StatefulWidget {
  const AutonomousRoamingScreen({super.key});

  @override
  State<AutonomousRoamingScreen> createState() => _AutonomousRoamingScreenState();
}

class _AutonomousRoamingScreenState extends State<AutonomousRoamingScreen> {
  bool _isAllowed = true;
  int _activeStatus = 0; // 0: 충전 중, 1: 이동 중, 2: 오류

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F3E7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.chevron_left, color: Color(0xFF5D4037)), onPressed: () => context.pop()),
        title: const Text('자율 배회', style: TextStyle(color: Color(0xFF5D4037), fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // Top Toggle Card
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('자율 활동 허용', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Text('집 안을 스스로 돌아다녀요', style: TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                  Switch(
                    value: _isAllowed,
                    onChanged: (v) => setState(() => _isAllowed = v),
                    activeColor: const Color(0xFFC67C4E),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Status Visualization Area
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: const Color(0xFFFDF7F0),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
                    child: const Text('현재 상태', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                  ),
                  const SizedBox(height: 32),
                  const Icon(Icons.battery_charging_full, size: 60, color: Color(0xFF81C784)),
                  const SizedBox(height: 32),
                  const Text('충전 중이에요', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF5D4037))),
                  const SizedBox(height: 12),
                  const Text('충전소에서 배터리를 채우고 있어요', style: TextStyle(color: Color(0xFF8D6E63))),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Status Tabs
            Row(
              children: [
                _buildStatusBtn(0, Icons.battery_charging_full, '충전 중'),
                const SizedBox(width: 12),
                _buildStatusBtn(1, Icons.arrow_forward, '이동 중'),
                const SizedBox(width: 12),
                _buildStatusBtn(2, Icons.warning_amber_rounded, '오류'),
              ],
            ),
            const SizedBox(height: 32),
            
            // Activity Log
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('활동 로그', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF5D4037))),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
              child: Column(
                children: [
                  _buildLogItem('충전소로 복귀 · 충전 시작', '오후 2:40', const Color(0xFFC67C4E)),
                  _buildLogDivider(),
                  _buildLogItem('거실 창가 순찰', '오후 2:12', const Color(0xFF81C784)),
                  _buildLogDivider(),
                  _buildLogItem('현관 앞에서 대기', '오후 1:55', Colors.grey.shade300),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            // Info Banner
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(20)),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFF2E7D32), size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '장애물이나 오류가 생기면 즉시 알림으로 알려드려요. 배터리 20% 아래면 배회를 멈추고 복귀해요.',
                      style: TextStyle(color: Color(0xFF2E7D32), fontSize: 12, height: 1.4),
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

  Widget _buildStatusBtn(int index, IconData icon, String label) {
    bool isSelected = _activeStatus == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeStatus = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isSelected ? const Color(0xFFC67C4E) : Colors.transparent, width: 2),
          ),
          child: Column(
            children: [
              Icon(icon, color: isSelected ? const Color(0xFFC67C4E) : Colors.grey, size: 20),
              const SizedBox(height: 8),
              Text(label, style: TextStyle(color: isSelected ? const Color(0xFFC67C4E) : Colors.grey, fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogItem(String title, String time, Color dotColor) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
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
      ],
    );
  }

  Widget _buildLogDivider() {
    return Padding(
      padding: const EdgeInsets.only(left: 4.5, top: 4, bottom: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(width: 1, height: 20, color: Colors.grey.shade200),
      ),
    );
  }
}
