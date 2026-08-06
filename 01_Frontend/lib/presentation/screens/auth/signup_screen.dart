import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../data/models/auth_model.dart';
import '../../viewmodels/auth_view_model.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

/// 인증번호 기본 유효시간. 서버가 expiresAt을 주지 않을 때 쓴다.
const _kCodeTtl = Duration(minutes: 3);

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isAgreedToTerms = false;

  /// 인증번호 입력 제한시간. 1초마다 줄어들고, 0이 되면 타이머를 멈춘다.
  Timer? _codeTimer;
  int _codeSecondsLeft = 0;

  /// 카운트다운이 한 번이라도 시작됐는지. 발송 응답을 기다리는 동안
  /// (아직 0초인 상태로) 만료 표시가 새어 나가지 않게 하는 조건이다.
  bool _isCodeCountdownStarted = false;

  bool get _isCodeExpired => _isCodeCountdownStarted && _codeSecondsLeft <= 0;

  // 이메일 중복 확인 API가 없어 형식 검사만 로컬로 처리한다.
  // (닉네임은 GET /users/nickname-availability 로 서버에 물어본다)
  bool _isEmailChecked = false;
  bool _isEmailAvailable = false;

  /// 서버 규칙: 8~72자, 영문과 숫자를 각각 1개 이상.
  bool get _isPasswordValid =>
      AuthValidation.password.hasMatch(_passwordController.text);

  bool get _isPasswordMatched =>
      _passwordController.text.isNotEmpty &&
      _passwordController.text == _confirmPasswordController.text;

  /// 서버 규칙: 하이픈 없는 01X 휴대폰 번호.
  bool get _isPhoneValid =>
      AuthValidation.phoneNumber.hasMatch(_phoneController.text);

  bool get _isCodeValid =>
      AuthValidation.verificationCode.hasMatch(_codeController.text);

  @override
  void initState() {
    super.initState();
    // AuthViewModel은 앱 전역이라 이 화면을 떠났다 돌아와도 인증 진행 상태가
    // 남아 있다. 그때 카운트다운이 0:00으로 보이지 않게 남은 시간을 복원한다.
    final authViewModel = context.read<AuthViewModel>();
    if (authViewModel.isVerificationRequested &&
        !authViewModel.isPhoneVerified) {
      _startCodeCountdown(authViewModel.codeExpiresAt);
    }
  }

  /// 인증번호 제한시간 카운트다운 시작. 재전송 때도 다시 호출된다.
  ///
  /// 서버가 준 expiresAt을 우선 쓰되, 값이 없거나 시계 차이/타임존 때문에
  /// 상식적인 범위(0초~10분)를 벗어나면 기본 3분으로 떨어진다.
  void _startCodeCountdown(DateTime? expiresAt) {
    final int seconds;
    if (expiresAt == null) {
      // 서버가 만료 시각을 안 줬으면 기본 3분.
      seconds = _kCodeTtl.inSeconds;
    } else {
      // 올림으로 계산한다. 발송~수신 사이에 0.x초가 지나 179.5초가 되는데,
      // 내림이면 첫 표시가 2:59로 시작해 3:00을 못 보여준다.
      final remaining =
          (expiresAt.toUtc().difference(DateTime.now().toUtc()).inMilliseconds /
                  1000)
              .ceil();
      if (remaining > const Duration(minutes: 10).inSeconds) {
        // 시계 차이나 타임존 문제로 비상식적인 값이면 기본 3분으로 떨어진다.
        seconds = _kCodeTtl.inSeconds;
      } else {
        // 이미 지났으면 0 (화면 재진입 시 만료 상태를 그대로 보여준다).
        seconds = remaining > 0 ? remaining : 0;
      }
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

  /// 남은 시간을 3:00 / 0:07 형태로.
  String get _codeTimeLabel {
    final s = _codeSecondsLeft < 0 ? 0 : _codeSecondsLeft;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _codeTimer?.cancel();
    _emailController.dispose();
    _nicknameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  /// POST /auth/signup → 성공하면 로그인 화면으로 보낸다.
  /// 입력한 이메일을 함께 넘겨 로그인 화면에 미리 채워준다.
  Future<void> _submit() async {
    final authViewModel = context.read<AuthViewModel>();
    final email = _emailController.text.trim();

    final success = await authViewModel.signup(
      email: email,
      password: _passwordController.text,
      nickname: _nicknameController.text.trim(),
      // 서버는 phoneNumber와 verificationToken을 필수로 요구한다.
      phoneNumber: _phoneController.text,
    );
    if (!mounted) return;

    if (!success) {
      _showSnackBar(
        authViewModel.errorMessage ?? '회원가입에 실패했어요.',
        isError: true,
      );
      return;
    }

    _showSnackBar('가입이 완료됐어요! 로그인해 주세요.');
    context.go('/login', extra: email);
  }

  /// 이메일 형식 검사. (중복 확인 API 없음)
  void _checkEmail() {
    final email = _emailController.text.trim();
    final isValid = RegExp(r'^[\w.\-+]+@[\w\-]+\.[\w.\-]+$').hasMatch(email);
    setState(() {
      _isEmailChecked = true;
      _isEmailAvailable = isValid;
    });
  }

  /// POST /auth/verifications — 입력한 번호로 인증번호를 보낸다.
  Future<void> _requestVerification() async {
    final authViewModel = context.read<AuthViewModel>();

    if (!_isPhoneValid) {
      _showSnackBar('휴대전화 번호를 하이픈 없이 정확히 입력해 주세요.', isError: true);
      return;
    }

    _codeController.clear();
    final sent = await authViewModel.requestPhoneVerification(
      _phoneController.text,
    );
    if (!mounted) return;

    // 발송이 됐을 때만 카운트다운을 (재)시작한다.
    if (sent) setState(() => _startCodeCountdown(authViewModel.codeExpiresAt));

    _showSnackBar(
      sent
          ? '인증번호를 보냈어요. 3분 안에 입력해 주세요.'
          : (authViewModel.errorMessage ?? '인증번호 발송에 실패했어요.'),
      isError: !sent,
    );
  }

  /// POST /auth/verifications/{verificationId}/confirm
  /// 성공하면 회원가입에 쓸 verificationToken이 뷰모델에 저장된다.
  Future<void> _confirmVerification() async {
    final authViewModel = context.read<AuthViewModel>();

    if (_isCodeExpired) {
      _showSnackBar('시간이 만료됐어요. 재전송해 주세요.', isError: true);
      return;
    }

    if (!_isCodeValid) {
      _showSnackBar('인증번호 6자리를 입력해 주세요.', isError: true);
      return;
    }

    final verified =
        await authViewModel.confirmPhoneVerification(_codeController.text);
    if (!mounted) return;

    // 인증이 끝나면 입력칸이 사라지므로 타이머도 정리한다.
    if (verified) setState(_stopCodeCountdown);

    _showSnackBar(
      verified
          ? '휴대전화 인증이 완료됐어요.'
          : (authViewModel.errorMessage ?? '인증번호가 올바르지 않아요.'),
      isError: !verified,
    );
  }

  /// GET /users/nickname-availability — 서버에 닉네임 중복을 물어본다.
  Future<void> _checkNickname() async {
    final authViewModel = context.read<AuthViewModel>();
    final nickname = _nicknameController.text.trim();

    if (!AuthValidation.nickname.hasMatch(nickname)) {
      _showSnackBar('이름은 한글·영문·숫자 2~20자로 입력해 주세요.', isError: true);
      return;
    }

    final available = await authViewModel.checkNickname(nickname);
    if (!mounted) return;
    if (!available && authViewModel.hasError) {
      _showSnackBar(authViewModel.errorMessage!, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authViewModel = context.watch<AuthViewModel>();

    bool isFormValid = _isEmailChecked &&
        _isEmailAvailable &&
        authViewModel.isNicknameChecked &&
        authViewModel.isNicknameAvailable &&
        authViewModel.isPhoneVerified &&
        _isAgreedToTerms &&
        _isPasswordValid &&
        _isPasswordMatched;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F3E7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Color(0xFF5D4037)),
          onPressed: () => context.pop(),
        ),
        title: const Text('회원가입',
            style: TextStyle(
                color: Color(0xFF5D4037), fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Header Character
              Container(
                width: 100,
                height: 100,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: Colors.white),
                child: Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: Image.asset('assets/images/mysil_character.png',
                      fit: BoxFit.contain),
                ),
              ),
              const SizedBox(height: 16),
              const Text('반가워요!',
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF5D4037))),
              const Text('마실이의 새로운 가족이 되어 주세요 🐾',
                  style: TextStyle(color: Color(0xFF8D6E63), fontSize: 15)),
              const SizedBox(height: 40),

              // Email Card
              _buildSectionCard([
                _buildLabel('이메일 주소'),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextFormField(
                        controller: _emailController,
                        hint: 'example@email.com',
                        keyboardType: TextInputType.emailAddress,
                        // 입력이 바뀌면 확인 결과를 초기화한다.
                        onChanged: (v) =>
                            setState(() => _isEmailChecked = false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildSmallButton(
                      label: _isEmailChecked && _isEmailAvailable
                          ? '확인됨'
                          : '중복 확인',
                      color: _isEmailChecked && _isEmailAvailable
                          ? Colors.green
                          : const Color(0xFFC67C4E),
                      onPressed: _isEmailChecked && _isEmailAvailable
                          ? null
                          : _checkEmail,
                    ),
                  ],
                ),
                if (_isEmailChecked)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0, left: 4),
                    child: Text(
                      _isEmailAvailable
                          ? '✓ 사용 가능한 이메일이에요'
                          : '! 이메일 형식을 확인해 주세요',
                      style: TextStyle(
                        color:
                            _isEmailAvailable ? Colors.green : Colors.redAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 16),

              // Password Card
              _buildSectionCard([
                _buildLabel('비밀번호'),
                _buildTextFormField(
                  controller: _passwordController,
                  hint: '********',
                  obscureText: _obscurePassword,
                  onChanged: (v) => setState(() {}),
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: Colors.grey,
                        size: 18),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                const SizedBox(height: 12),
                _buildLabel('비밀번호 확인'),
                _buildTextFormField(
                  controller: _confirmPasswordController,
                  hint: '********',
                  obscureText: _obscureConfirmPassword,
                  onChanged: (v) => setState(() {}),
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: Colors.grey,
                        size: 18),
                    onPressed: () => setState(() =>
                        _obscureConfirmPassword = !_obscureConfirmPassword),
                  ),
                ),
                // 서버 규칙(8~72자, 영문+숫자)을 입력 중에 바로 알려준다.
                if (_passwordController.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0, left: 4),
                    child: Text(
                      _isPasswordValid
                          ? '✓ 사용 가능한 비밀번호예요'
                          : '! 8자 이상, 영문과 숫자를 함께 넣어 주세요',
                      style: TextStyle(
                        color:
                            _isPasswordValid ? Colors.green : Colors.redAccent,
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (_confirmPasswordController.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0, left: 4),
                    child: Text(
                      _isPasswordMatched ? '✓ 비밀번호가 일치해요' : '! 비밀번호가 일치하지 않아요',
                      style: TextStyle(
                        color: _isPasswordMatched
                            ? Colors.green
                            : Colors.redAccent,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 16),

              // Nickname Card
              _buildSectionCard([
                _buildLabel('이름'),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _nicknameController,
                        onChanged: (v) {
                          // 입력이 바뀌면 서버 확인 결과를 초기화한다.
                          context.read<AuthViewModel>().resetNicknameCheck();
                          setState(() {});
                        },
                        decoration: _inputDecoration('이름을 입력해 주세요'),
                        // DO NOT add inputFormatters to allow Hangul
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildSmallButton(
                      label:
                          authViewModel.isNicknameAvailable ? '확인됨' : '중복 확인',
                      color: authViewModel.isNicknameAvailable
                          ? Colors.green
                          : const Color(0xFFC67C4E),
                      onPressed: authViewModel.isNicknameAvailable ||
                              authViewModel.isLoading
                          ? null
                          : _checkNickname,
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
              ]),
              const SizedBox(height: 16),

              // 휴대전화 인증 Card — 서버 회원가입 필수값(phoneNumber, verificationToken)
              _buildSectionCard([
                _buildLabel('휴대전화 인증'),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextFormField(
                        controller: _phoneController,
                        hint: '01012345678',
                        keyboardType: TextInputType.phone,
                        enabled: !authViewModel.isPhoneVerified,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(11),
                        ],
                        onChanged: (v) {
                          // 번호가 바뀌면 인증을 처음부터 다시 받아야 한다.
                          authViewModel.resetPhoneVerification();
                          _codeController.clear();
                          setState(_stopCodeCountdown);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildSmallButton(
                      label: authViewModel.isPhoneVerified
                          ? '인증됨'
                          : (authViewModel.isVerificationRequested
                              ? '재전송'
                              : '인증번호 받기'),
                      color: authViewModel.isPhoneVerified
                          ? Colors.green
                          : const Color(0xFFC67C4E),
                      onPressed: authViewModel.isPhoneVerified ||
                              authViewModel.isLoading ||
                              !_isPhoneValid
                          ? null
                          : _requestVerification,
                    ),
                  ],
                ),
                if (_phoneController.text.isNotEmpty && !_isPhoneValid)
                  const Padding(
                    padding: EdgeInsets.only(top: 8.0, left: 4),
                    child: Text(
                      '! 하이픈 없이 숫자만 입력해 주세요 (예: 01012345678)',
                      style: TextStyle(color: Colors.redAccent, fontSize: 12),
                    ),
                  ),
                // 인증번호를 보낸 뒤에만 입력칸을 보여준다.
                if (authViewModel.isVerificationRequested &&
                    !authViewModel.isPhoneVerified) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextFormField(
                          controller: _codeController,
                          hint: '인증번호 6자리',
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
                          ],
                          onChanged: (v) => setState(() {}),
                          // 칸 오른쪽 끝에 남은 시간(3:00 → 0:00)을 띄운다.
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
                            minWidth: 0,
                            minHeight: 0,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildSmallButton(
                        label: '확인',
                        // 시간이 만료되면 서버가 어차피 거절하므로 미리 잠근다.
                        onPressed: authViewModel.isLoading ||
                                !_isCodeValid ||
                                _isCodeExpired
                            ? null
                            : _confirmVerification,
                      ),
                    ],
                  ),
                  if (_isCodeExpired)
                    const Padding(
                      padding: EdgeInsets.only(top: 8.0, left: 4),
                      child: Text(
                        '! 시간이 만료됐어요. 재전송해 주세요',
                        style:
                            TextStyle(color: Colors.redAccent, fontSize: 12),
                      ),
                    ),
                ],
                if (authViewModel.isPhoneVerified)
                  const Padding(
                    padding: EdgeInsets.only(top: 8.0, left: 4),
                    child: Text(
                      '✓ 휴대전화 인증이 완료됐어요',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 32),

              // Terms
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: InkWell(
                  onTap: () =>
                      setState(() => _isAgreedToTerms = !_isAgreedToTerms),
                  child: Row(
                    children: [
                      Icon(
                        _isAgreedToTerms
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: _isAgreedToTerms
                            ? const Color(0xFFC67C4E)
                            : Colors.grey,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                          child: Text('이용약관 및 개인정보 처리방침에 동의합니다.',
                              style: TextStyle(fontSize: 14))),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // 가입하기 — POST /auth/signup → 성공 시 로그인 화면으로
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  onPressed: (!isFormValid || authViewModel.isLoading)
                      ? null
                      : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isFormValid
                        ? const Color(0xFFC67C4E)
                        : Colors.grey.shade300,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30)),
                    elevation: 0,
                  ),
                  child: authViewModel.isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('가입하기',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard(List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 5))
          ]),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _buildSmallButton(
      {required String label, required VoidCallback? onPressed, Color? color}) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
          backgroundColor: color ?? const Color(0xFFC67C4E),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0),
      child: Text(label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.brown));
  }

  Widget _buildLabel(String label) {
    return Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.black87)));
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
      filled: true,
      fillColor: const Color(0xFFFDF7F0),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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

  Widget _buildTextFormField(
      {required TextEditingController controller,
      required String hint,
      bool obscureText = false,
      bool enabled = true,
      TextInputType? keyboardType,
      List<TextInputFormatter>? inputFormatters,
      Widget? suffixIcon,
      BoxConstraints? suffixIconConstraints,
      ValueChanged<String>? onChanged}) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      enabled: enabled,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      decoration: _inputDecoration(hint).copyWith(
        suffixIcon: suffixIcon,
        suffixIconConstraints: suffixIconConstraints,
      ),
    );
  }

  /// 구글 가입이 이미 끝난 계정으로 들어온 경우의 환영 안내.
  /// (신규 회원의 닉네임 설정 완료 후 안내는 SocialSignupScreen에서 처리)
  void showWelcomeDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: Column(
          children: [
            Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                    color: Color(0xFFF9F3E7), shape: BoxShape.circle),
                child: const Icon(Icons.celebration,
                    color: Color(0xFFC67C4E), size: 40)),
            const SizedBox(height: 20),
            const Text('환영합니다!',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: Color(0xFF5D4037))),
          ],
        ),
        content: const Text('마실의 회원이 되셨습니다.\n이제 마실이와 함께 산책을 시작해볼까요?',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF8D6E63))),
        actions: [
          Center(
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  context.pop();
                  context.go('/home');
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC67C4E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                child: const Text('시작하기',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
