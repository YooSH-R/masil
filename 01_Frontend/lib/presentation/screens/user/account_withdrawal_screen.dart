import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../viewmodels/auth_view_model.dart';
import '../../viewmodels/pet_view_model.dart';

/// 회원탈퇴. DELETE /users/me
///
/// 일반 회원은 비밀번호 재확인이 필요하고, 소셜 전용 회원은 생략한다
/// (명세서 6. 회원탈퇴). 되돌릴 수 없는 동작이라 확인 다이얼로그를 한 번 거친다.
class AccountWithdrawalScreen extends StatefulWidget {
  const AccountWithdrawalScreen({super.key});

  @override
  State<AccountWithdrawalScreen> createState() => _AccountWithdrawalScreenState();
}

class _AccountWithdrawalScreenState extends State<AccountWithdrawalScreen> {
  int _selectedReason = 0;
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 소셜 전용 회원인지 알아야 비밀번호 입력칸을 띄울지 정할 수 있다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AuthViewModel>().loadMyProfile(silent: true);
      // 무엇이 사라지는지 실제 값으로 보여주기 위해 친밀도도 불러온다.
      final petVm = context.read<PetViewModel>();
      if (petVm.pet == null) petVm.loadCurrentPet(silent: true);
    });
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  /// 탈퇴 실행. 성공하면 로그인 화면으로 되돌린다.
  Future<void> _withdraw({required bool needsPassword}) async {
    final authViewModel = context.read<AuthViewModel>();

    if (needsPassword && _passwordController.text.isEmpty) {
      _showMessage('비밀번호를 입력해 주세요.', isError: true);
      return;
    }

    final confirmed = await _confirmOnce();
    if (!confirmed || !mounted) return;

    final done = await authViewModel.withdraw(
      currentPassword: needsPassword ? _passwordController.text : null,
    );
    if (!mounted) return;

    if (!done) {
      _showMessage(authViewModel.errorMessage ?? '탈퇴 처리에 실패했어요.',
          isError: true);
      return;
    }

    _showMessage('탈퇴가 완료됐어요. 그동안 이용해 주셔서 감사합니다.');
    context.go('/login');
  }

  /// 되돌릴 수 없는 동작이라 한 번 더 묻는다.
  Future<bool> _confirmOnce() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('정말 탈퇴하시겠어요?',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: Color(0xFF5D4037))),
        content: const Text(
          '탈퇴하면 마실이와의 기록이 사라지고 되돌릴 수 없어요.',
          style: TextStyle(color: Color(0xFF8D6E63), height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(false),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => context.pop(true),
            child: const Text('탈퇴하기',
                style: TextStyle(
                    color: Color(0xFFD32F2F), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    return result ?? false;
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
    final affinity = context.watch<PetViewModel>().affinity;

    // 프로필을 아직 못 받았으면(서버 미배포 등) 일반 회원으로 보고 비밀번호를
    // 받는다. 소셜 전용 회원이면 서버가 비밀번호를 무시한다.
    final needsPassword = authViewModel.profile?.hasPassword ?? true;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F3E7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Color(0xFF5D4037)),
          onPressed: () => context.pop(),
        ),
        title: const Text('회원 탈퇴', style: TextStyle(color: Color(0xFF5D4037), fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
        child: Column(
          children: [
            // Character
            Image.asset('assets/images/mysil_character.png', height: 180),
            const SizedBox(height: 24),
            const Text(
              '정말 떠나실 거예요?',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF5D4037)),
            ),
            const SizedBox(height: 8),
            const Text(
              '마실이가 아쉬워하고 있어요 🥲',
              style: TextStyle(color: Color(0xFF8D6E63), fontSize: 15),
            ),
            const SizedBox(height: 40),
            
            // Info Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F0),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('탈퇴 시 삭제되는 정보', style: TextStyle(color: Color(0xFFD32F2F), fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 16),
                  const Text('· 산책 기록 128회 · 214km', style: TextStyle(color: Color(0xFF5D4037), fontSize: 14)),
                  const SizedBox(height: 8),
                  const Text('· 저장된 영상 12개 및 감성 일지 34편', style: TextStyle(color: Color(0xFF5D4037), fontSize: 14)),
                  const SizedBox(height: 8),
                  // 친밀도는 GET /pets/{petId} 응답에서 온다. 탈퇴는 되돌릴 수
                  // 없으므로, 못 불러왔으면 숫자를 지어내지 않고 생략한다.
                  Text(
                    affinity == null
                        ? '· 마실이와 쌓은 친밀도'
                        : '· 마실이와의 친밀도 ${affinity.score}%',
                    style: const TextStyle(color: Color(0xFF5D4037), fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  const Text('· 등록된 로봇 연결 해제', style: TextStyle(color: Color(0xFF5D4037), fontSize: 14)),
                ],
              ),
            ),
            const SizedBox(height: 32),
            
            // Reasons
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('떠나시는 이유 (선택)', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF5D4037))),
            ),
            const SizedBox(height: 16),
            _buildReasonTile(0, '산책을 잘 안 하게 돼요'),
            const SizedBox(height: 12),
            _buildReasonTile(1, '기능이 아쉬워요'),
            const SizedBox(height: 12),
            _buildReasonTile(2, '기타'),
            
            const SizedBox(height: 32),

            // 비밀번호 재확인 — 일반 회원(LOCAL)만.
            // 소셜 전용 회원은 비밀번호가 없어 서버도 요구하지 않는다.
            if (needsPassword) ...[
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: '비밀번호를 입력해 주세요',
                  prefixIcon: const Icon(Icons.lock_outline,
                      color: Color(0xFFC67C4E), size: 20),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 10),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_outline, size: 14, color: Colors.grey),
                  SizedBox(width: 6),
                  Text('탈퇴 진행 시 비밀번호 재인증이 필요해요',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ] else
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.info_outline, size: 14, color: Colors.grey),
                  SizedBox(width: 6),
                  Text('소셜 계정으로 가입해 비밀번호 확인 없이 진행돼요',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            const SizedBox(height: 16),

            // Buttons
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed: authViewModel.isLoading
                    ? null
                    : () => _withdraw(needsPassword: needsPassword),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD32F2F),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: const Text('탈퇴하기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 60,
              child: TextButton(
                onPressed: () => context.pop(),
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF5D4037),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: const Text('계속 함께하기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildReasonTile(int index, String label) {
    return InkWell(
      onTap: () => setState(() => _selectedReason = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _selectedReason == index ? const Color(0xFFC67C4E) : Colors.transparent, width: 2),
        ),
        child: Row(
          children: [
            Icon(
              _selectedReason == index ? Icons.radio_button_checked : Icons.radio_button_off,
              color: _selectedReason == index ? const Color(0xFFC67C4E) : Colors.grey,
            ),
            const SizedBox(width: 16),
            Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
