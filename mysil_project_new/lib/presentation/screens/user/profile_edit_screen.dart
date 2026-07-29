import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _emailController = TextEditingController(text: 'sapy@email.com');
  final _nicknameController = TextEditingController(text: '싸피러버');
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

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
        title: const Text('내 정보 수정', style: TextStyle(color: Color(0xFF5D4037), fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.check, color: Color(0xFFC67C4E)),
            onPressed: () => context.pop(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // Profile Image Edit
            Stack(
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFE5D8),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                  child: const Center(
                    child: Text('프로필 사진\nor browse fi', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: Color(0xFF8D6E63))),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(color: Color(0xFFC67C4E), shape: BoxShape.circle),
                    child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),
            
            // Fields
            _buildLabel('이메일'),
            _buildReadOnlyField(controller: _emailController),
            const SizedBox(height: 24),
            
            _buildLabel('닉네임'),
            Row(
              children: [
                Expanded(child: _buildTextField(controller: _nicknameController, hint: '닉네임을 입력하세요')),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF0E0D0),
                    foregroundColor: const Color(0xFF5D4037),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: const Text('중복 확인', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            _buildLabel('새 비밀번호'),
            _buildTextField(controller: _passwordController, hint: '변경할 비밀번호 입력', obscureText: true),
            const SizedBox(height: 12),
            _buildLabel('새 비밀번호 확인'),
            _buildTextField(controller: _confirmPasswordController, hint: '다시 입력해 주세요', obscureText: true),
            
            const SizedBox(height: 24),
            // Caution Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8F1),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lock_outline, color: Color(0xFFC67C4E), size: 18),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '이메일·비밀번호를 바꾸면 다른 기기의 로그인은 모두 해제돼요.',
                      style: TextStyle(color: Color(0xFF8D6E63), fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 40),
            // Save Button
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed: () => context.pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC67C4E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 0,
                ),
                child: const Text('저장하기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => context.push('/user/withdrawal'),
              child: const Text('회원 탈퇴', style: TextStyle(color: Colors.grey, decoration: TextDecoration.underline)),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String label) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF5D4037))),
      ),
    );
  }

  Widget _buildTextField({required TextEditingController controller, required String hint, bool obscureText = false}) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        suffixIcon: obscureText ? const Icon(Icons.visibility_off_outlined, color: Colors.grey, size: 20) : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Color(0xFFF0E0D0))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Color(0xFFF0E0D0))),
      ),
    );
  }

  Widget _buildReadOnlyField({required TextEditingController controller}) {
    return TextField(
      controller: controller,
      readOnly: true,
      style: const TextStyle(color: Colors.grey),
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFFFDFDFD),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Color(0xFFF0E0D0))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Color(0xFFF0E0D0))),
      ),
    );
  }
}
