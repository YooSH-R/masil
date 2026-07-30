import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../viewmodels/auth_view_model.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    // 회원가입 직후 넘어온 이메일을 미리 채워 준다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final extra = GoRouterState.of(context).extra;
      if (extra is String && extra.isNotEmpty) {
        _emailController.text = extra;
      }
    });
  }

  /// 구글 계정으로 인증 → 기존 회원은 홈, 신규 회원은 닉네임 화면으로.
  Future<void> _signInWithGoogle() => _handleSocialSignIn(
        () => context.read<AuthViewModel>().signInWithGoogle(),
        '구글 로그인에 실패했어요.',
      );

  /// 카카오 계정으로 인증. 이후 흐름은 구글과 같다.
  Future<void> _signInWithKakao() => _handleSocialSignIn(
        () => context.read<AuthViewModel>().signInWithKakao(),
        '카카오 로그인에 실패했어요.',
      );

  Future<void> _handleSocialSignIn(
    Future<SocialSignInOutcome> Function() signIn,
    String failureMessage,
  ) async {
    final authViewModel = context.read<AuthViewModel>();
    final outcome = await signIn();
    if (!mounted) return;

    switch (outcome) {
      case SocialSignInOutcome.loggedIn:
        context.go('/home');
      case SocialSignInOutcome.needsNickname:
        context.go('/social-signup');
      case SocialSignInOutcome.cancelled:
        break;
      case SocialSignInOutcome.failed:
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(authViewModel.errorMessage ?? failureMessage),
          backgroundColor: Colors.redAccent,
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final authViewModel = context.watch<AuthViewModel>();

    return Scaffold(
      backgroundColor: const Color(0xFFF9F3E7), // Beige background
      body: SingleChildScrollView(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            children: [
              const SizedBox(height: 80),
              // Character Icon
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Image.asset('assets/images/mysil_character.png', fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '마실',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF5D4037),
                ),
              ),
              const Text(
                '오늘도 같이 마실 나가요!',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF8D6E63),
                ),
              ),
              const SizedBox(height: 40),
              // White Form Container
              Container(
                padding: const EdgeInsets.all(24.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '아이디',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    _buildInputField(
                      controller: _emailController,
                      hintText: '아이디를 입력해 주세요',
                      prefixIcon: Icons.person,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      '비밀번호',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    _buildInputField(
                      controller: _passwordController,
                      hintText: '비밀번호를 입력해 주세요',
                      prefixIcon: Icons.lock,
                      obscureText: _obscurePassword,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off : Icons.visibility,
                          color: Colors.grey,
                          size: 20,
                        ),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Checkbox and Reset Link
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: Checkbox(
                                value: true,
                                onChanged: (v) {},
                                activeColor: const Color(0xFFC67C4E),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text('자동 로그인', style: TextStyle(color: Color(0xFF8D6E63), fontSize: 14)),
                          ],
                        ),
                        TextButton(
                          onPressed: () => context.push('/password-reset'),
                          child: const Text('비밀번호 재설정', style: TextStyle(color: Color(0xFFC67C4E), fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Login Button
                    SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: ElevatedButton(
                        onPressed: authViewModel.isLoading
                            ? null
                            : () async {
                                final success = await authViewModel.login(
                                  _emailController.text,
                                  _passwordController.text,
                                );
                                if (!context.mounted) return;
                                if (success) {
                                  context.go('/home');
                                } else {
                                  // 서버가 준 오류 메시지를 그대로 노출한다.
                                  // (예: INVALID_CREDENTIALS → "이메일 또는 비밀번호가 올바르지 않습니다.")
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(authViewModel.errorMessage ??
                                          '로그인에 실패했어요.'),
                                      backgroundColor: Colors.redAccent,
                                    ),
                                  );
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFC67C4E),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          elevation: 0,
                        ),
                        child: authViewModel.isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text(
                                '로그인',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // "Or" Divider
                    const Row(
                      children: [
                        Expanded(child: Divider()),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Text('또는', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ),
                        Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Social Buttons
                    // POST /auth/oauth/kakao
                    _buildSocialButton(
                      label: '카카오로 시작하기',
                      color: const Color(0xFFFFE812),
                      textColor: Colors.black87,
                      icon: Icons.chat_bubble,
                      onPressed: authViewModel.isLoading ? null : _signInWithKakao,
                    ),
                    const SizedBox(height: 12),
                    // POST /auth/oauth/google
                    _buildSocialButton(
                      label: 'Google로 시작하기',
                      color: Colors.white,
                      textColor: Colors.black87,
                      icon: Icons.g_mobiledata,
                      onPressed: authViewModel.isLoading ? null : _signInWithGoogle,
                      border: BorderSide(color: Colors.grey.shade200),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              // Signup Link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('아직 마실이 친구가 아니야? ', style: TextStyle(color: Color(0xFF8D6E63))),
                  GestureDetector(
                    onTap: () => context.push('/signup'),
                    child: const Text(
                      '회원가입',
                      style: TextStyle(
                        color: Color(0xFFC67C4E),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '© 2026 MYSIL. All rights reserved.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hintText,
    required IconData prefixIcon,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFDF7F0),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFF0E0D0)),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
          prefixIcon: Icon(prefixIcon, color: const Color(0xFFC67C4E), size: 20),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
        ),
      ),
    );
  }

  Widget _buildSocialButton({
    required String label,
    required Color color,
    required Color textColor,
    required IconData icon,
    // 로딩 중에는 null을 넘겨 비활성화한다.
    required VoidCallback? onPressed,
    BorderSide? border,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: textColor,
          side: border ?? BorderSide.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
