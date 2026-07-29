import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class PasswordResetScreen extends StatefulWidget {
  const PasswordResetScreen({super.key});

  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  final _emailController = TextEditingController();
  bool _isSent = false;

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
        title: const Text('비밀번호 재설정', style: TextStyle(color: Color(0xFF5D4037), fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // Character
            Container(
              width: 140,
              height: 140,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Image.asset('assets/images/mysil_character.png', fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              '이메일을 입력해 주세요',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF5D4037)),
            ),
            const SizedBox(height: 12),
            const Text(
              '가입하신 이메일 주소로\n비밀번호 재설정 링크를 보내드려요.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF8D6E63), fontSize: 16, height: 1.5),
            ),
            const SizedBox(height: 48),
            
            // Form Container
            Container(
              padding: const EdgeInsets.all(24.0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(25),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '이메일 주소',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      hintText: 'example@email.com',
                      prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFFC67C4E), size: 20),
                      filled: true,
                      fillColor: const Color(0xFFFDF7F0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: const BorderSide(color: Color(0xFFF0E0D0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: const BorderSide(color: Color(0xFFF0E0D0)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton(
                      onPressed: _isSent ? null : () => setState(() => _isSent = true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFC67C4E),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        elevation: 0,
                      ),
                      child: Text(
                        _isSent ? '전송 완료' : '재설정 링크 받기',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Info Message
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFFC67C4E), size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '메일이 도착하지 않았나요? 스팸함을 확인하거나 1분 후 다시 시도해 주세요. 링크는 30분 뒤 만료돼요.',
                      style: TextStyle(color: Color(0xFF8D6E63), fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 60),
            const Text(
              '이용약관 · 개인정보처리방침',
              style: TextStyle(color: Color(0xFF8D6E63), fontSize: 13),
            ),
            const SizedBox(height: 8),
            const Text(
              '© 2026 MYSIL. All rights reserved.',
              style: TextStyle(color: Colors.grey, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
