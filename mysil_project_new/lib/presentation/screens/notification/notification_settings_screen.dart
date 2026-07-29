import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  bool _walkSug = true;
  bool _robotStat = true;
  bool _playReq = true;
  bool _welcomeHome = true;
  bool _marketing = false;
  bool _isDnd = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F3E7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.chevron_left, color: Color(0xFF5D4037)), onPressed: () => context.pop()),
        title: const Text('알림', style: TextStyle(color: Color(0xFF5D4037), fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Master Toggles Card
            _buildWhiteCard(
              child: Column(
                children: [
                  _buildToggleItem(Icons.directions_walk, '산책 제안', _walkSug, (v) => setState(() => _walkSug = v)),
                  const Divider(height: 32),
                  _buildToggleItem(Icons.battery_charging_full, '로봇 상태 · 충전/오류', _robotStat, (v) => setState(() => _robotStat = v)),
                  const Divider(height: 32),
                  _buildToggleItem(Icons.sports_tennis, '놀이 요청', _playReq, (v) => setState(() => _playReq = v)),
                  const Divider(height: 32),
                  _buildToggleItem(Icons.home_work_outlined, '귀가 마중', _welcomeHome, (v) => setState(() => _welcomeHome = v)),
                  const Divider(height: 32),
                  _buildToggleItem(Icons.mail_outline, '마케팅 · 이벤트', _marketing, (v) => setState(() => _marketing = v)),
                ],
              ),
            ),
            const SizedBox(height: 32),
            
            // Notification History Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('알림 내역', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF5D4037))),
                TextButton(onPressed: () {}, child: const Text('모두 읽음', style: TextStyle(color: Color(0xFF8D6E63)))),
              ],
            ),
            const SizedBox(height: 12),
            
            // History List
            _buildHistoryItem(Icons.wb_sunny_outlined, '산책하기 좋은 날씨예요!', '산책 제안 · 방금 전', '산책 탭 〉', const Color(0xFFFFF1F0)),
            const SizedBox(height: 12),
            _buildHistoryItem(Icons.sports_tennis, '마실이가 놀자고 해요', '놀이 요청 · 1시간 전', '실내모드 〉', const Color(0xFFE8F6F3)),
            const SizedBox(height: 12),
            _buildHistoryItem(Icons.battery_charging_full, '충전을 시작했어요', '로봇 상태 · 2시간 전', '상태 보기 〉', const Color(0xFFF9F3E7)),
            
            const SizedBox(height: 32),
            
            // DND & Sound Card
            _buildWhiteCard(
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: Colors.blue.shade50, shape: BoxShape.circle),
                        child: const Icon(Icons.nights_stay_outlined, color: Colors.blue, size: 20),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('방해 금지 시간', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            Text('22:00 ~ 08:00', style: TextStyle(color: Colors.grey, fontSize: 13)),
                          ],
                        ),
                      ),
                      Switch(value: _isDnd, onChanged: (v) => setState(() => _isDnd = v), activeColor: const Color(0xFFC67C4E)),
                    ],
                  ),
                  const Divider(height: 40),
                  const Row(
                    children: [
                      Icon(Icons.volume_up_outlined, color: Colors.grey, size: 24),
                      SizedBox(width: 16),
                      Expanded(child: Text('알림음', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                      Text('마실 기본음 〉', style: TextStyle(color: Colors.grey, fontSize: 14)),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            // Verification Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(15)),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check, color: Color(0xFF2E7D32), size: 16),
                  SizedBox(width: 8),
                  Text('푸시 알림이 정상 연결되어 있어요', style: TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildWhiteCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30)),
      child: child,
    );
  }

  Widget _buildToggleItem(IconData icon, String label, bool value, Function(bool) onChanged) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFF9F3E7), shape: BoxShape.circle),
          child: Icon(icon, color: const Color(0xFFC67C4E), size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
        Switch(value: value, onChanged: onChanged, activeColor: const Color(0xFFC67C4E)),
      ],
    );
  }

  Widget _buildHistoryItem(IconData icon, String title, String subtitle, String linkText, Color iconBg) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, color: const Color(0xFF5D4037), size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: const Color(0xFFF9F3E7), borderRadius: BorderRadius.circular(10)),
            child: Text(linkText, style: const TextStyle(color: Color(0xFFC67C4E), fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
