import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class LoginLockedScreen extends StatelessWidget {
  const LoginLockedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F3E7),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const SizedBox(height: 40),
              // Character
              Container(
                width: 120,
                height: 120,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Image.asset('assets/images/mysil_character.png', fit: BoxFit.contain),
                ),
              ),
              const SizedBox(height: 16),
              const Text('마실', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF5D4037))),
              const SizedBox(height: 40),
              
              const Text(
                '! 비밀번호를 5회 잘못 입력했어요.\n10분 후 다시 시도하거나 비밀번호를 재설정해 주세요.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w500, height: 1.5),
              ),
              const SizedBox(height: 24),
              
              // Countdown Card
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: const Color(0xFFF0E0D0)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('다시 시도까지', style: TextStyle(color: Color(0xFF8D6E63), fontWeight: FontWeight.bold)),
                    Text('09:41', style: TextStyle(color: Color(0xFFC67C4E), fontSize: 20, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              
              // Inactive Login Button
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  onPressed: null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade300,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    elevation: 0,
                  ),
                  child: const Text('로그인', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 16),
              
              // Reset Button
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  onPressed: () => context.push('/password-reset'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC67C4E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    elevation: 0,
                  ),
                  child: const Text('비밀번호 재설정하기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 40),
              
              // Info Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('이런 경우에도 로그인이 막혀요', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    SizedBox(height: 12),
                    Text('· 탈퇴한 계정 — 다시 가입해야 해요', style: TextStyle(color: Color(0xFF8D6E63), fontSize: 13)),
                    SizedBox(height: 6),
                    Text('· 관리자가 정지한 계정 — 1:1 문의로 도와드려요', style: TextStyle(color: Color(0xFF8D6E63), fontSize: 13)),
                    SizedBox(height: 6),
                    Text('· SSO 연결 실패 — 카카오·Google 재연결이 필요해요', style: TextStyle(color: Color(0xFF8D6E63), fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
