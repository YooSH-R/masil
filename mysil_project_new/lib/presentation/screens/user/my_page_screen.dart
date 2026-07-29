import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MyPageScreen extends StatelessWidget {
  const MyPageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F3E7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Color(0xFF5D4037)),
          onPressed: () => context.go('/home'),
        ),
        title: const Text('마이페이지', style: TextStyle(color: Color(0xFF5D4037), fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // User Info Section
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9F3E7),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFEFE5D8), width: 2),
                    ),
                    child: const Center(
                      child: Text(
                        '프로필\n사진',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 10, color: Color(0xFF8D6E63)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('김싸피 님', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF5D4037))),
                        SizedBox(height: 4),
                        Text('반려견과 함께하는 삶', style: TextStyle(color: Color(0xFF8D6E63), fontSize: 13)),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => context.push('/user/reauth'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF9F3E7),
                      foregroundColor: const Color(0xFFC67C4E),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('내 정보\n수정', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            
            // Device Registration Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF5D4037), Color(0xFF3E2723)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(25),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('기기 등록', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                        SizedBox(height: 8),
                        Text('새로운 마실 디바이스를\n앱과 연결해 보세요.', style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4)),
                      ],
                    ),
                  ),
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.grid_view_rounded, color: Color(0xFF5D4037), size: 30),
                      onPressed: () => context.push('/user/robot-mgmt'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // My Pets Section
            _buildSectionHeader('내 반려동물'),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFDF7F0),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Image.asset('assets/images/mysil_character.png'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('마실이', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                _buildTag('활발함', const Color(0xFFFDF2E9), const Color(0xFFD35400)),
                                const SizedBox(width: 8),
                                _buildTag('산책러버', const Color(0xFFE8F6F3), const Color(0xFF16A085)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () => context.push('/user/pet-list'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF5D4037),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        elevation: 0,
                      ),
                      child: const Text('프로필 관리 (3마리)', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Other Menus
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  _buildMenuItem(Icons.campaign_outlined, '공지사항', Colors.orange),
                  _buildMenuItem(Icons.menu_book_outlined, '서비스 이용 가이드', Colors.blue),
                  _buildMenuItem(Icons.headset_mic_outlined, '1:1 문의', Colors.indigo),
                  _buildMenuItem(Icons.verified_user_outlined, '약관 및 정책', Colors.grey),
                ],
              ),
            ),
            
            const SizedBox(height: 32),
            TextButton(
              onPressed: () => context.go('/login'),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.logout, color: Color(0xFF8D6E63), size: 18),
                  SizedBox(width: 8),
                  Text('로그아웃', style: TextStyle(color: Color(0xFF8D6E63), fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Row(
        children: [
          const Icon(Icons.pets, size: 16, color: Color(0xFFC67C4E)),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF5D4037))),
        ],
      ),
    );
  }

  Widget _buildTag(String text, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(10)),
      child: Text(text, style: TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildMenuItem(IconData icon, String title, Color iconColor) {
    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
      onTap: () {},
    );
  }
}
