import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../data/models/auth_model.dart';
import '../../viewmodels/auth_view_model.dart';

/// 비밀번호 분실 시 재설정. (명세서 5. 비밀번호 분실 시 재설정)
///
/// 흐름:
///   1) 휴대전화 번호 입력 → POST /auth/verifications (purpose=PASSWORD_RESET)
///   2) 인증번호 확인      → POST /auth/verifications/{id}/confirm
///   3) 새 비밀번호 입력   → POST /auth/password/reset
///
/// 원래 화면은 '이메일로 재설정 링크 발송' 방식이었는데, 명세서는 휴대전화
/// 인증 방식이라 흐름을 맞췄다. 인증 목적을 PASSWORD_RESET 으로 보내야 하며,
/// 회원가입용 토큰으로 재설정을 시도하면 VERIFICATION_PURPOSE_MISMATCH 가 온다.
class PasswordResetScreen extends StatefulWidget {
  const PasswordResetScreen({super.key});

  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

/// 인증번호 기본 유효시간. 서버가 expiresAt 을 주지 않을 때 쓴다.
const _kCodeTtl = Duration(minutes: 3);

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  /// 인증번호 남은 시간. 회원가입 화면과 같은 방식.
  Timer? _codeTimer;
  int _codeSecondsLeft = 0;
  bool _isCodeCountdownStarted = false;

  bool get _isCodeExpired => _isCodeCountdownStarted && _codeSecondsLeft <= 0;

  bool get _isPhoneValid =>
      AuthValidation.phoneNumber.hasMatch(_phoneController.text);
  bool get _isCodeValid =>
      AuthValidation.verificationCode.hasMatch(_codeController.text);
  bool get _isPasswordValid =>
      AuthValidation.password.hasMatch(_passwordController.text);
  bool get _isPasswordMatched =>
      _passwordController.text.isNotEmpty &&
      _passwordController.text == _confirmPasswordController.text;

  @override
  void dispose() {
    _codeTimer?.cancel();
    _phoneController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _startCodeCountdown(DateTime? expiresAt) {
    final int seconds;
    if (expiresAt == null) {
      seconds = _kCodeTtl.inSeconds;
    } else {
      final remaining =
          (expiresAt.toUtc().difference(DateTime.now().toUtc()).inMilliseconds /
                  1000)
              .ceil();
      seconds = remaining > const Duration(minutes: 10).inSeconds
          ? _kCodeTtl.inSeconds
          : (remaining > 0 ? remaining : 0);
    }

    _codeTimer?.cancel();
    _codeTimer = null;
    _codeSecondsLeft = seconds;
    _isCodeCountdownStarted = true;
    if (seconds <= 0) return;

    _codeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _codeSecondsLeft--);
      if (_codeSecondsLeft <= 0) timer.cancel();
    });
  }

  void _stopCodeCountdown() {
    _codeTimer?.cancel();
    _codeTimer = null;
    _codeSecondsLeft = 0;
    _isCodeCountdownStarted = false;
  }

  String get _codeTimeLabel {
    final s = _codeSecondsLeft < 0 ? 0 : _codeSecondsLeft;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  /// 1단계 — 인증번호 발송. purpose 를 PASSWORD_RESET 으로 보낸다.
  Future<void> _requestCode() async {
    final authViewModel = context.read<AuthViewModel>();

    if (!_isPhoneValid) {
      _showMessage('휴대전화 번호를 하이픈 없이 정확히 입력해 주세요.', isError: true);
      return;
    }

    _codeController.clear();
    final sent = await authViewModel.requestPhoneVerification(
      _phoneController.text,
      purpose: VerificationPurpose.passwordReset,
    );
    if (!mounted) return;

    if (sent) setState(() => _startCodeCountdown(authViewModel.codeExpiresAt));

    _showMessage(
      sent
          ? '인증번호를 보냈어요. 3분 안에 입력해 주세요.'
          : (authViewModel.errorMessage ?? '인증번호 발송에 실패했어요.'),
      isError: !sent,
    );
  }

  /// 2단계 — 인증번호 확인. 성공하면 뷰모델이 verificationToken 을 보관한다.
  Future<void> _confirmCode() async {
    final authViewModel = context.read<AuthViewModel>();

    if (_isCodeExpired) {
      _showMessage('시간이 만료됐어요. 재전송해 주세요.', isError: true);
      return;
    }
    if (!_isCodeValid) {
      _showMessage('인증번호 6자리를 입력해 주세요.', isError: true);
      return;
    }

    final verified =
        await authViewModel.confirmPhoneVerification(_codeController.text);
    if (!mounted) return;

    if (verified) setState(_stopCodeCountdown);

    _showMessage(
      verified ? '인증됐어요. 새 비밀번호를 설정해 주세요.' : (authViewModel.errorMessage ?? '인증번호가 올바르지 않아요.'),
      isError: !verified,
    );
  }

  /// 3단계 — 새 비밀번호 설정. 성공 후 모든 세션이 폐기되므로 로그인 화면으로.
  Future<void> _submitNewPassword() async {
    final authViewModel = context.read<AuthViewModel>();

    if (!_isPasswordValid) {
      _showMessage('비밀번호는 8~72자로, 영문과 숫자를 각각 1개 이상 포함해야 해요.',
          isError: true);
      return;
    }
    if (!_isPasswordMatched) {
      _showMessage('비밀번호가 일치하지 않아요.', isError: true);
      return;
    }

    final done = await authViewModel.resetPassword(
      phoneNumber: _phoneController.text,
      newPassword: _passwordController.text,
    );
    if (!mounted) return;

    if (!done) {
      _showMessage(authViewModel.errorMessage ?? '비밀번호를 변경하지 못했어요.',
          isError: true);
      return;
    }

    _showMessage('비밀번호를 변경했어요. 새 비밀번호로 로그인해 주세요.');
    context.go('/login');
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
    final codeSent = authViewModel.isVerificationRequested;
    final verified = authViewModel.isPhoneVerified;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F3E7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Color(0xFF5D4037)),
          onPressed: () => context.pop(),
        ),
        title: const Text('비밀번호 재설정',
            style: TextStyle(
                color: Color(0xFF5D4037), fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Container(
              width: 120,
              height: 120,
              decoration:
                  const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
              child: Padding(
                padding: const EdgeInsets.all(14.0),
                child: Image.asset('assets/images/mysil_character.png',
                    fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              verified ? '새 비밀번호를 설정해 주세요' : '휴대전화로 본인 확인할게요',
              style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF5D4037)),
            ),
            const SizedBox(height: 12),
            Text(
              verified
                  ? '변경하면 다른 기기의 로그인은 모두 해제돼요.'
                  : '가입할 때 등록한 번호로 인증번호를 보내드려요.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Color(0xFF8D6E63), fontSize: 15, height: 1.5),
            ),
            const SizedBox(height: 32),

            Container(
              padding: const EdgeInsets.all(24.0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(25),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- 1단계: 휴대전화 번호 ---
                  _buildLabel('휴대전화 번호'),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          enabled: !verified,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(11),
                          ],
                          onChanged: (_) => setState(() {}),
                          decoration: _inputDecoration('01012345678'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildSmallButton(
                        label: codeSent ? '재전송' : '인증번호 받기',
                        onPressed:
                            verified || authViewModel.isLoading || !_isPhoneValid
                                ? null
                                : _requestCode,
                      ),
                    ],
                  ),

                  // --- 2단계: 인증번호 ---
                  if (codeSent && !verified) ...[
                    const SizedBox(height: 20),
                    _buildLabel('인증번호'),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _codeController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(6),
                            ],
                            onChanged: (_) => setState(() {}),
                            decoration:
                                _inputDecoration('인증번호 6자리').copyWith(
                              suffixIcon: !_isCodeCountdownStarted
                                  ? null
                                  : Padding(
                                      padding: const EdgeInsets.only(
                                          right: 16, left: 8),
                                      child: Text(
                                        _codeTimeLabel,
                                        style: TextStyle(
                                          color: _isCodeExpired
                                              ? Colors.redAccent
                                              : const Color(0xFFC67C4E),
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                              suffixIconConstraints: const BoxConstraints(
                                  minWidth: 0, minHeight: 0),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildSmallButton(
                          label: '확인',
                          onPressed: authViewModel.isLoading ||
                                  !_isCodeValid ||
                                  _isCodeExpired
                              ? null
                              : _confirmCode,
                        ),
                      ],
                    ),
                    if (_isCodeExpired)
                      const Padding(
                        padding: EdgeInsets.only(top: 8.0, left: 4),
                        child: Text('! 시간이 만료됐어요. 재전송해 주세요',
                            style: TextStyle(
                                color: Colors.redAccent, fontSize: 12)),
                      ),
                  ],

                  // --- 3단계: 새 비밀번호 ---
                  if (verified) ...[
                    const SizedBox(height: 8),
                    const Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 12),
                      child: Text('✓ 휴대전화 인증이 완료됐어요',
                          style: TextStyle(
                              color: Colors.green,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ),
                    _buildLabel('새 비밀번호'),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      onChanged: (_) => setState(() {}),
                      decoration: _inputDecoration('영문·숫자 포함 8자 이상'),
                    ),
                    if (_passwordController.text.isNotEmpty && !_isPasswordValid)
                      const Padding(
                        padding: EdgeInsets.only(top: 8.0, left: 4),
                        child: Text('! 영문과 숫자를 각각 1개 이상 넣어 8~72자로 만들어 주세요',
                            style: TextStyle(
                                color: Colors.redAccent, fontSize: 12)),
                      ),
                    const SizedBox(height: 20),
                    _buildLabel('새 비밀번호 확인'),
                    TextField(
                      controller: _confirmPasswordController,
                      obscureText: true,
                      onChanged: (_) => setState(() {}),
                      decoration: _inputDecoration('다시 입력해 주세요'),
                    ),
                    if (_confirmPasswordController.text.isNotEmpty &&
                        !_isPasswordMatched)
                      const Padding(
                        padding: EdgeInsets.only(top: 8.0, left: 4),
                        child: Text('! 비밀번호가 일치하지 않아요',
                            style: TextStyle(
                                color: Colors.redAccent, fontSize: 12)),
                      ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 58,
                      child: ElevatedButton(
                        onPressed: authViewModel.isLoading ||
                                !_isPasswordValid ||
                                !_isPasswordMatched
                            ? null
                            : _submitNewPassword,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFC67C4E),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey.shade300,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                          elevation: 0,
                        ),
                        child: authViewModel.isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              )
                            : const Text('비밀번호 변경하기',
                                style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 24),
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
                      '비밀번호를 바꾸면 로그인된 모든 기기에서 다시 로그인해야 해요.',
                      style: TextStyle(
                          color: Color(0xFF8D6E63), fontSize: 13, height: 1.4),
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

  Widget _buildLabel(String label) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.black87)),
      );

  Widget _buildSmallButton({
    required String label,
    required VoidCallback? onPressed,
  }) =>
      ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFC67C4E),
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade300,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0,
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
        filled: true,
        fillColor: const Color(0xFFFDF7F0),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFF0E0D0))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFF0E0D0))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFC67C4E), width: 1.5)),
      );
}
