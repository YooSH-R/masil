import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AccountWithdrawalScreen extends StatefulWidget {
  const AccountWithdrawalScreen({super.key});

  @override
  State<AccountWithdrawalScreen> createState() => _AccountWithdrawalScreenState();
}

class _AccountWithdrawalScreenState extends State<AccountWithdrawalScreen> {
  int _selectedReason = 0;

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
        title: const Text('회원 탈퇴', style: TextStyle(color: Color(0xFF5D4037), fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
        child: Column(
          children: [
            // Character
            Image.asset('assets/images/mysil_character.png', height: 180),
            const SizedBox(height: 24),
            const Text(
              '정말 떠나실 거예요?',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF5D4037)),
            ),
            const SizedBox(height: 8),
            const Text(
              '마실이가 아쉬워하고 있어요 🥲',
              style: TextStyle(color: Color(0xFF8D6E63), fontSize: 15),
            ),
            const SizedBox(height: 40),
            
            // Info Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F0),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('탈퇴 시 삭제되는 정보', style: TextStyle(color: Color(0xFFD32F2F), fontWeight: FontWeight.bold, fontSize: 16)),
                  SizedBox(height: 16),
                  Text('· 산책 기록 128회 · 214km', style: TextStyle(color: Color(0xFF5D4037), fontSize: 14)),
                  SizedBox(height: 8),
                  Text('· 저장된 영상 12개 및 감성 일지 34편', style: TextStyle(color: Color(0xFF5D4037), fontSize: 14)),
                  SizedBox(height: 8),
                  Text('· 마실이와의 친밀도 80%', style: TextStyle(color: Color(0xFF5D4037), fontSize: 14)),
                  SizedBox(height: 8),
                  Text('· 등록된 로봇 MS-2231 연결 해제', style: TextStyle(color: Color(0xFF5D4037), fontSize: 14)),
                ],
              ),
            ),
            const SizedBox(height: 32),
            
            // Reasons
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('떠나시는 이유 (선택)', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF5D4037))),
            ),
            const SizedBox(height: 16),
            _buildReasonTile(0, '산책을 잘 안 하게 돼요'),
            const SizedBox(height: 12),
            _buildReasonTile(1, '기능이 아쉬워요'),
            const SizedBox(height: 12),
            _buildReasonTile(2, '기타'),
            
            const SizedBox(height: 32),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 14, color: Colors.grey),
                SizedBox(width: 6),
                Text('탈퇴 진행 시 비밀번호 재인증이 필요해요', style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 16),
            
            // Buttons
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD32F2F),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: const Text('탈퇴하기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 60,
              child: TextButton(
                onPressed: () => context.pop(),
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF5D4037),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: const Text('계속 함께하기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildReasonTile(int index, String label) {
    return InkWell(
      onTap: () => setState(() => _selectedReason = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _selectedReason == index ? const Color(0xFFC67C4E) : Colors.transparent, width: 2),
        ),
        child: Row(
          children: [
            Icon(
              _selectedReason == index ? Icons.radio_button_checked : Icons.radio_button_off,
              color: _selectedReason == index ? const Color(0xFFC67C4E) : Colors.grey,
            ),
            const SizedBox(width: 16),
            Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
