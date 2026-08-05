import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../viewmodels/auth_view_model.dart';

class AutoLoginScreen extends StatefulWidget {
  const AutoLoginScreen({super.key});

  @override
  State<AutoLoginScreen> createState() => _AutoLoginScreenState();
}

class _AutoLoginScreenState extends State<AutoLoginScreen> {
  @override
  void initState() {
    super.initState();
    // initState는 빌드 도중에 실행되므로 여기서 바로 호출하면
    // guard()의 notifyListeners()가 빌드 중에 불려 예외가 난다.
    // 첫 프레임이 끝난 뒤로 미룬다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _performAutoLogin();
    });
  }

  Future<void> _performAutoLogin() async {
    final authViewModel = context.read<AuthViewModel>();

    // 저장된 refreshToken으로 POST /auth/refresh 를 호출해 세션을 복구한다.
    final restored = await authViewModel.restoreSession();

    if (!mounted) return;
    context.go(restored ? '/home' : '/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F3E7),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            children: [
              const Spacer(),
              // Character
              Container(
                width: 160,
                height: 160,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Image.asset('assets/images/mysil_character.png',
                      fit: BoxFit.contain),
                ),
              ),
              const SizedBox(height: 40),
              const Text(
                '마실이랑 다시 만나는 중',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF5D4037),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '저장된 로그인 정보로\n자동으로 들어가고 있어요.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Color(0xFF8D6E63), fontSize: 16, height: 1.5),
              ),
              const SizedBox(height: 40),
              // Progress Bar
              Container(
                width: 200,
                height: 8,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFE5D8),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 120, // Simulated progress
                      decoration: BoxDecoration(
                        color: const Color(0xFFC67C4E),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Security Info Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.lock_outline,
                        color: Color(0xFFC67C4E), size: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '비밀번호는 기기 보안 저장소에만 보관돼요. 토큰이 만료되면 조용히 다시 발급해요.',
                        style: TextStyle(
                            color: Color(0xFF8D6E63),
                            fontSize: 13,
                            height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Switch Account Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton(
                  onPressed: () => context.go('/login'),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    side: BorderSide(color: Colors.grey.shade200),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25)),
                  ),
                  child: const Text(
                    '다른 계정으로 로그인',
                    style: TextStyle(
                        color: Color(0xFF5D4037), fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
