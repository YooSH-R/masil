import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/services/profile_image_store.dart';
import '../../../data/models/auth_model.dart';
import '../../viewmodels/auth_view_model.dart';
import '../../widgets/profile_avatar_picker.dart';

/// 내 정보 수정. GET/PATCH /users/me, PATCH /users/me/password
class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _emailController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  /// 서버 값으로 칸을 한 번만 채운다. 매 rebuild 마다 덮으면
  /// 사용자가 입력하는 중에 글자가 되돌아간다.
  bool _prefilled = false;

  /// 서버에 등록된 전화번호. 값이 바뀌었는지 비교하는 기준.
  String? _originalPhone;

  bool get _isPhoneValid =>
      AuthValidation.phoneNumber.hasMatch(_phoneController.text);
  bool get _isCodeValid =>
      AuthValidation.verificationCode.hasMatch(_codeController.text);

  /// 등록된 번호와 다른 번호를 입력했는지. 같으면 인증을 요구하지 않는다.
  bool get _phoneChanged =>
      _phoneController.text.isNotEmpty &&
      _phoneController.text != (_originalPhone ?? '');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AuthViewModel>().loadMyProfile(silent: true);
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _nicknameController.dispose();
    _phoneController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  /// 전화번호 변경용 인증번호 발송. 목적을 phoneChange 로 보낸다.
  Future<void> _requestPhoneCode() async {
    final authViewModel = context.read<AuthViewModel>();

    _codeController.clear();
    final sent = await authViewModel.requestPhoneVerification(
      _phoneController.text,
      purpose: VerificationPurpose.phoneChange,
    );
    if (!mounted) return;

    _showMessage(
      sent
          ? '인증번호를 보냈어요. 3분 안에 입력해 주세요.'
          : (authViewModel.errorMessage ?? '인증번호 발송에 실패했어요.'),
      isError: !sent,
    );
  }

  Future<void> _confirmPhoneCode() async {
    final authViewModel = context.read<AuthViewModel>();

    final verified =
        await authViewModel.confirmPhoneVerification(_codeController.text);
    if (!mounted) return;

    _showMessage(
      verified ? '휴대전화 인증이 완료됐어요.' : (authViewModel.errorMessage ?? '인증번호가 올바르지 않아요.'),
      isError: !verified,
    );
  }

  /// 닉네임 중복 확인 — GET /users/nickname-availability
  Future<void> _checkNickname() async {
    final authViewModel = context.read<AuthViewModel>();
    final nickname = _nicknameController.text.trim();

    final available = await authViewModel.checkNickname(nickname);
    if (!mounted) return;

    _showMessage(
      available ? '사용할 수 있는 닉네임이에요.' : '이미 사용 중인 닉네임이에요.',
      isError: !available,
    );
  }

  /// 저장. 닉네임 수정과 비밀번호 변경은 서버 API 가 달라 각각 호출한다.
  Future<void> _save() async {
    final authViewModel = context.read<AuthViewModel>();
    final profile = authViewModel.profile;

    final nickname = _nicknameController.text.trim();
    final newPassword = _passwordController.text;
    final wantsPasswordChange = newPassword.isNotEmpty;

    if (wantsPasswordChange &&
        newPassword != _confirmPasswordController.text) {
      _showMessage('새 비밀번호가 일치하지 않아요.', isError: true);
      return;
    }

    // 실제로 바뀐 것만 PATCH 로 보낸다.
    final nicknameChanged =
        nickname.isNotEmpty && nickname != profile?.nickname;
    final phoneChanged = _phoneChanged;

    if (phoneChanged && !authViewModel.isPhoneVerified) {
      _showMessage('전화번호를 바꾸려면 휴대전화 인증을 먼저 완료해 주세요.', isError: true);
      return;
    }

    if (!nicknameChanged && !phoneChanged && !wantsPasswordChange) {
      _showMessage('변경할 내용이 없어요.');
      return;
    }

    if (nicknameChanged || phoneChanged) {
      final ok = await authViewModel.updateMyProfile(
        nickname: nicknameChanged ? nickname : null,
        // 전화번호를 넘기면 뷰모델이 보관 중인 verificationToken 을 함께 보낸다.
        phoneNumber: phoneChanged ? _phoneController.text : null,
      );
      if (!mounted) return;
      if (!ok) {
        _showMessage(authViewModel.errorMessage ?? '회원정보를 저장하지 못했어요.',
            isError: true);
        return;
      }
      // 저장에 성공하면 기준 번호를 갱신해 '변경됨' 표시가 풀리게 한다.
      _originalPhone = _phoneController.text;
      _codeController.clear();
    }

    if (wantsPasswordChange) {
      // 비밀번호 변경에는 현재 비밀번호가 필요하다(명세서 4).
      final currentPassword = await _askCurrentPassword();
      if (currentPassword == null || !mounted) return;

      final ok = await authViewModel.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      if (!mounted) return;
      if (!ok) {
        _showMessage(authViewModel.errorMessage ?? '비밀번호를 변경하지 못했어요.',
            isError: true);
        return;
      }
    }

    _showMessage('저장했어요.');
    if (mounted) context.pop();
  }

  /// 비밀번호 변경 전 현재 비밀번호를 묻는다.
  Future<String?> _askCurrentPassword() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('현재 비밀번호 확인',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: Color(0xFF5D4037))),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(hintText: '현재 비밀번호'),
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => context.pop(controller.text),
            child: const Text('확인',
                style: TextStyle(
                    color: Color(0xFFC67C4E), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    controller.dispose();
    return (result == null || result.isEmpty) ? null : result;
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
    final profile = authViewModel.profile;

    final codeSent = authViewModel.isVerificationRequested;
    final phoneVerified = authViewModel.isPhoneVerified;

    // 서버 값이 도착하면 한 번만 칸을 채운다.
    if (!_prefilled && profile != null) {
      _prefilled = true;
      _emailController.text = profile.email ?? '';
      _nicknameController.text = profile.nickname;
      _phoneController.text = profile.phoneNumber ?? '';
      _originalPhone = profile.phoneNumber ?? '';
    }

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
            // 프로필 사진. 눌러서 갤러리·카메라로 등록하거나 삭제한다.
            //
            // 사진은 이 기기에만 저장된다. 서버 `UpdateMemberRequest` 에는
            // profileImage 항목이 아예 없어서 올릴 곳이 없다. 항목이 생기면
            // onChanged 에서 업로드를 이어 붙이면 된다.
            ProfileAvatarPicker(
              imageKey: ProfileImageStore.userKey,
              fallbackImageUrl: authViewModel.user?.profileImageUrl,
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
                  onPressed: authViewModel.isLoading ? null : _checkNickname,
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

            // 휴대전화 번호 — 변경하려면 인증이 필수다(명세서 3. 회원정보 수정).
            _buildLabel('휴대전화 번호'),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _phoneController,
                    hint: '01012345678',
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(11),
                    ],
                    onChanged: (_) {
                      // 번호를 고치면 기존 인증은 무효다.
                      authViewModel.resetPhoneVerification();
                      _codeController.clear();
                      setState(() {});
                    },
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: phoneVerified ||
                          authViewModel.isLoading ||
                          !_isPhoneValid ||
                          !_phoneChanged
                      ? null
                      : _requestPhoneCode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF0E0D0),
                    foregroundColor: const Color(0xFF5D4037),
                    disabledBackgroundColor: Colors.grey.shade200,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: Text(
                    phoneVerified
                        ? '인증됨'
                        : (codeSent ? '재전송' : '인증번호'),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            if (!_phoneChanged && _phoneController.text.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8.0, left: 4),
                child: Text('현재 등록된 번호예요. 바꾸려면 새 번호를 입력해 주세요.',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
              ),
            if (codeSent && !phoneVerified) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _codeController,
                      hint: '인증번호 6자리',
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed:
                        authViewModel.isLoading || !_isCodeValid
                            ? null
                            : _confirmPhoneCode,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFC67C4E),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade300,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text('확인',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
            if (phoneVerified)
              const Padding(
                padding: EdgeInsets.only(top: 8.0, left: 4),
                child: Text('✓ 휴대전화 인증이 완료됐어요',
                    style: TextStyle(
                        color: Colors.green,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
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
                onPressed: authViewModel.isLoading ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC67C4E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 0,
                ),
                child: authViewModel.isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('저장하기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    bool obscureText = false,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
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
