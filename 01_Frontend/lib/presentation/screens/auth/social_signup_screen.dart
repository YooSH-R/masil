import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../data/models/auth_model.dart';
import '../../viewmodels/auth_view_model.dart';

/// 소셜 로그인으로 처음 들어온 회원이 사용자 이름을 확인하고 가입을 마치는 화면.
/// POST /auth/oauth/signup {signupToken, nickname, deviceId}
class SocialSignupScreen extends StatefulWidget {
  const SocialSignupScreen({super.key});

  @override
  State<SocialSignupScreen> createState() => _SocialSignupScreenState();
}

class _SocialSignupScreenState extends State<SocialSignupScreen> {
  final _nicknameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 구글·카카오 프로필에서 받은 이름을 기본값으로 채우고 사용자가 수정할 수 있게 한다.
    final suggested = context.read<AuthViewModel>().suggestedNickname;
    if (suggested != null) _nicknameController.text = suggested;
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  bool get _isFormatValid =>
      AuthValidation.nickname.hasMatch(_nicknameController.text.trim());

  /// GET /users/nickname-availability
  Future<void> _checkNickname() async {
    final authViewModel = context.read<AuthViewModel>();
    final nickname = _nicknameController.text.trim();

    if (!_isFormatValid) {
      _showMessage('이름은 한글·영문·숫자 2~20자로 입력해 주세요.', isError: true);
      return;
    }

    final available = await authViewModel.checkNickname(nickname);
    if (!mounted) return;
    _showMessage(
      available ? '사용 가능한 이름이에요.' : '이미 사용 중인 이름이에요.',
      isError: !available,
    );
  }

  /// POST /auth/oauth/signup
  Future<void> _complete() async {
    final authViewModel = context.read<AuthViewModel>();
    final ok = await authViewModel.completeSocialSignup(
      _nicknameController.text.trim(),
    );
    if (!mounted) return;

    if (ok) {
      context.go('/home');
    } else {
      _showMessage(authViewModel.errorMessage ?? '가입을 마치지 못했어요.', isError: true);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.redAccent : Colors.brown,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final authViewModel = context.watch<AuthViewModel>();
    final canSubmit = _isFormatValid &&
        authViewModel.isNicknameChecked &&
        authViewModel.isNicknameAvailable &&
        !authViewModel.isLoading;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F3E7),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
          child: Column(
            children: [
              const SizedBox(height: 40),
              Container(
                width: 100,
                height: 100,
                decoration:
                    const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                child: Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: Image.asset('assets/images/mysil_character.png',
                      fit: BoxFit.contain),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '거의 다 됐어요!',
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF5D4037)),
              ),
              const SizedBox(height: 4),
              const Text(
                '마실이가 부를 이름만 정해 주세요',
                style: TextStyle(color: Color(0xFF8D6E63), fontSize: 15),
              ),
              const SizedBox(height: 40),

              // Nickname Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 8),
                      child: Text('이름',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.black87)),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _nicknameController,
                            onChanged: (_) {
                              authViewModel.resetNicknameCheck();
                              setState(() {});
                            },
                            decoration: InputDecoration(
                              hintText: '이름을 입력해 주세요',
                              hintStyle: TextStyle(
                                  color: Colors.grey.shade400, fontSize: 14),
                              filled: true,
                              fillColor: const Color(0xFFFDF7F0),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 16),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: Color(0xFFF0E0D0)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: Color(0xFFF0E0D0)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                    color: Color(0xFFC67C4E), width: 1.5),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: authViewModel.isLoading ? null : _checkNickname,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: authViewModel.isNicknameAvailable
                                ? Colors.green
                                : const Color(0xFFC67C4E),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                          ),
                          child: Text(
                            authViewModel.isNicknameAvailable ? '확인됨' : '중복 확인',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    if (authViewModel.isNicknameChecked)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0, left: 4),
                        child: Text(
                          authViewModel.isNicknameAvailable
                              ? '✓ 사용 가능한 이름이에요'
                              : '! 이미 사용 중인 이름이에요',
                          style: TextStyle(
                            color: authViewModel.isNicknameAvailable
                                ? Colors.green
                                : Colors.redAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  onPressed: canSubmit ? _complete : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC67C4E),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30)),
                    elevation: 0,
                  ),
                  child: authViewModel.isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('마실이 만나러 가기',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => context.go('/login'),
                child: const Text('다른 계정으로 로그인',
                    style: TextStyle(color: Color(0xFF8D6E63))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
