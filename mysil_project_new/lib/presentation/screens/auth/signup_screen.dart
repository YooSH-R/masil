import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../viewmodels/auth_view_model.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _verificationCodeController = TextEditingController();
  
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isEmailChecked = false;
  bool _isNicknameChecked = false;
  bool _isNicknameAvailable = false;
  bool _isPhoneRequested = false;
  bool _isPhoneVerified = false;
  bool _isAgreedToTerms = false;

  @override
  void dispose() {
    _emailController.dispose();
    _nicknameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneController.dispose();
    _verificationCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authViewModel = context.watch<AuthViewModel>();

    bool isFormValid = _isEmailChecked && 
                      _isNicknameChecked && 
                      _isNicknameAvailable && 
                      _isPhoneVerified && 
                      _isAgreedToTerms &&
                      _passwordController.text.isNotEmpty && 
                      _passwordController.text == _confirmPasswordController.text;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F3E7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Color(0xFF5D4037)),
          onPressed: () => context.pop(),
        ),
        title: const Text('회원가입', style: TextStyle(color: Color(0xFF5D4037), fontWeight: FontWeight.bold)),
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
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                child: Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: Image.asset('assets/images/mysil_character.png', fit: BoxFit.contain),
                ),
              ),
              const SizedBox(height: 16),
              const Text('반가워요!', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF5D4037))),
              const Text('마실이의 새로운 가족이 되어 주세요 🐾', style: TextStyle(color: Color(0xFF8D6E63), fontSize: 15)),
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
                        onChanged: (v) => setState(() => _isEmailChecked = false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildSmallButton(
                      label: _isEmailChecked ? '확인됨' : '중복 확인',
                      onPressed: _isEmailChecked ? null : () async {
                        if (_emailController.text.contains('@')) {
                          await authViewModel.checkEmailDuplicate(_emailController.text);
                          setState(() => _isEmailChecked = true);
                          _showSnackBar('사용 가능한 이메일입니다.');
                        }
                      },
                    ),
                  ],
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
                    icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.grey, size: 18),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
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
                    icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility, color: Colors.grey, size: 18),
                    onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                  ),
                ),
                if (_confirmPasswordController.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0, left: 4),
                    child: Text(
                      _passwordController.text == _confirmPasswordController.text ? '✓ 비밀번호가 일치해요' : '! 비밀번호가 일치하지 않아요',
                      style: TextStyle(
                        color: _passwordController.text == _confirmPasswordController.text ? Colors.green : Colors.redAccent,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 16),

              // Nickname Card
              _buildSectionCard([
                _buildLabel('닉네임'),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _nicknameController,
                        onChanged: (v) => setState(() => _isNicknameChecked = false),
                        decoration: _inputDecoration('멋진 댕댕이'),
                        // DO NOT add inputFormatters to allow Hangul
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildSmallButton(
                      label: _isNicknameChecked ? '확인됨' : '중복 확인',
                      onPressed: _isNicknameChecked ? null : () {
                        if (_nicknameController.text.trim().isNotEmpty) {
                          setState(() {
                            _isNicknameChecked = true;
                            _isNicknameAvailable = true;
                          });
                        }
                      },
                    ),
                  ],
                ),
                if (_isNicknameChecked)
                  const Padding(
                    padding: EdgeInsets.only(top: 8.0, left: 4),
                    child: Text(
                      '사용 가능한 닉네임입니다 ^_^',
                      style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
              ]),
              const SizedBox(height: 16),

              // Phone Auth Card
              _buildSectionCard([
                _buildLabel('휴대폰 번호'),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextFormField(
                        controller: _phoneController,
                        hint: '010-0000-0000',
                        keyboardType: TextInputType.phone,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildSmallButton(
                      label: _isPhoneRequested ? '재전송' : '인증번호 전송',
                      onPressed: _isPhoneVerified ? null : () => setState(() => _isPhoneRequested = true),
                    ),
                  ],
                ),
                if (_isPhoneRequested) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Stack(
                          alignment: Alignment.centerRight,
                          children: [
                            _buildTextFormField(
                              controller: _verificationCodeController,
                              hint: '123456',
                              keyboardType: TextInputType.number,
                            ),
                            const Padding(
                              padding: EdgeInsets.only(right: 16.0),
                              child: Text('03:00', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildSmallButton(
                        label: _isPhoneVerified ? '완료' : '인증 확인',
                        color: _isPhoneVerified ? Colors.green : const Color(0xFFC67C4E),
                        onPressed: _isPhoneVerified ? null : () {
                          if (_verificationCodeController.text == '123456') {
                            setState(() => _isPhoneVerified = true);
                            _showSnackBar('인증이 완료되었습니다.');
                          } else {
                            _showSnackBar('인증번호(123456)가 일치하지 않습니다.', isError: true);
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ]),
              const SizedBox(height: 32),

              // Terms
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: InkWell(
                  onTap: () => setState(() => _isAgreedToTerms = !_isAgreedToTerms),
                  child: Row(
                    children: [
                      Icon(
                        _isAgreedToTerms ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: _isAgreedToTerms ? const Color(0xFFC67C4E) : Colors.grey,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(child: Text('이용약관 및 개인정보 처리방침에 동의합니다.', style: TextStyle(fontSize: 14))),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              
              // Signup Button
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  onPressed: (!isFormValid || authViewModel.isLoading)
                      ? null
                      : () async {
                          final success = await authViewModel.signup(
                            _emailController.text,
                            _passwordController.text,
                            _nicknameController.text,
                            _phoneController.text,
                          );
                          if (mounted && success) {
                            _showSuccessDialog();
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isFormValid ? const Color(0xFFC67C4E) : Colors.grey.shade300,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    elevation: 0,
                  ),
                  child: authViewModel.isLoading 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('가입하기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 5))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _buildSmallButton({required String label, required VoidCallback? onPressed, Color? color}) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(backgroundColor: color ?? const Color(0xFFC67C4E), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0),
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: isError ? Colors.redAccent : Colors.brown));
  }

  Widget _buildLabel(String label) {
    return Padding(padding: const EdgeInsets.only(left: 4, bottom: 8), child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)));
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
      filled: true,
      fillColor: const Color(0xFFFDF7F0),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFF0E0D0))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFF0E0D0))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFC67C4E), width: 1.5)),
    );
  }

  Widget _buildTextFormField({required TextEditingController controller, required String hint, bool obscureText = false, TextInputType? keyboardType, Widget? suffixIcon, ValueChanged<String>? onChanged}) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      onChanged: onChanged,
      decoration: _inputDecoration(hint).copyWith(suffixIcon: suffixIcon),
    );
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: Column(
          children: [
            Container(padding: const EdgeInsets.all(16), decoration: const BoxDecoration(color: Color(0xFFF9F3E7), shape: BoxShape.circle), child: const Icon(Icons.celebration, color: Color(0xFFC67C4E), size: 40)),
            const SizedBox(height: 20),
            const Text('환영합니다!', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF5D4037))),
          ],
        ),
        content: const Text('마실의 회원이 되셨습니다.\n이제 마실이와 함께 산책을 시작해볼까요?', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF8D6E63))),
        actions: [
          Center(
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  context.pop();
                  context.go('/home');
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFC67C4E), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('시작하기', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
