import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../viewmodels/pet_view_model.dart';
import '../../viewmodels/robot_view_model.dart';
import '../../viewmodels/walk_view_model.dart';

class WalkSuggestionScreen extends StatefulWidget {
  const WalkSuggestionScreen({super.key});

  @override
  State<WalkSuggestionScreen> createState() => _WalkSuggestionScreenState();
}

class _WalkSuggestionScreenState extends State<WalkSuggestionScreen> {
  @override
  void initState() {
    super.initState();
    // GET /walk-proposals/current — 화면 진입 시 현재 제안을 불러온다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<WalkViewModel>().loadCurrentProposal();
      context.read<PetViewModel>().loadCurrentPet(silent: true);
      context.read<RobotViewModel>().loadStatus(silent: true);
    });
  }

  /// 제안 수락 → POST responses(ACCEPTED) → POST /walks
  Future<void> _accept() async {
    final walkVm = context.read<WalkViewModel>();
    final petId = context.read<PetViewModel>().petId;
    final robotId = context.read<RobotViewModel>().robot?.id;

    // 펫·로봇·산책제안 API가 서버에 아직 없어 위 값들이 모두 null로 온다.
    // 값이 갖춰졌을 때만 서버에 수락을 보내고, 못 받아도 다음 화면으로 넘긴다.
    // 서버가 준비되면 아래 분기를 지우고 실패 시 return 하도록 되돌리면 된다.
    if (petId != null && robotId != null) {
      final walk = await walkVm.acceptProposal(petId: petId, robotId: robotId);
      if (!mounted) return;
      if (walk == null) {
        _showMessage(walkVm.errorMessage ?? '산책 정보를 서버에서 받지 못했어요.');
      }
    }

    if (!mounted) return;
    context.push('/walk/ready');
  }

  /// 제안 거절 → POST responses(DECLINED)
  Future<void> _decline() async {
    final walkVm = context.read<WalkViewModel>();
    final declined = await walkVm.declineProposal();
    if (!mounted) return;

    if (!declined && walkVm.hasError) {
      _showMessage(walkVm.errorMessage ?? '요청을 처리하지 못했어요.', isError: true);
      return;
    }
    context.push('/walk/declined');
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.redAccent : Colors.brown,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final walkVm = context.watch<WalkViewModel>();
    final proposal = walkVm.proposal;
    final petName = context.watch<PetViewModel>().petName;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F3E7),
      body: SafeArea(
        // 화면이 짧으면 스크롤, 여유가 있으면 Spacer가 그대로 벌어지도록.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    // Top App Bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                      child: Row(
                        children: [
                          Image.asset('assets/images/mysil_logo.png', height: 28),
                        ],
                      ),
                    ),
                    
                    // Notification-style Banner
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(25),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15, offset: const Offset(0, 5)),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: const BoxDecoration(color: Color(0xFFFDF7F0), shape: BoxShape.circle),
                            child: Image.asset('assets/images/mysil_character.png'),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('마실 · 지금 · 산책 제안 알림',
                                    style: TextStyle(color: Colors.grey, fontSize: 12)),
                                const SizedBox(height: 4),
                                // 제안 문구는 서버가 내려준 message를 그대로 보여준다.
                                Text(
                                  proposal?.message ??
                                      (walkVm.isLoading
                                          ? '산책 제안을 확인하고 있어요...'
                                          : '지금은 산책 제안이 없어요'),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const Spacer(),
                    
                    // Large Character
                    Image.asset('assets/images/mysil_character.png', height: 280),
                    
                    const SizedBox(height: 40),
                    
                    const Text(
                      '오늘도 같이\n마실 나가요!',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF5D4037), height: 1.3),
                    ),
                    const SizedBox(height: 12),
                    Text('$petName가 산책을 기다리고 있어요',
                        style: const TextStyle(color: Color(0xFF8D6E63), fontSize: 16)),
                    
                    const SizedBox(height: 40),
                    
                    // Stats Row
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildChip(Icons.wb_cloudy_outlined, '맑음 22°'),
                        _buildChip(Icons.air, '미세먼지 좋음'),
                        _buildChip(Icons.access_time, '오후 3:00'),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                    const Text('일몰까지 4시간 · 오늘 아직 산책하지 않았어요', style: TextStyle(color: Color(0xFFBCAAA4), fontSize: 13)),
                    
                    const Spacer(),
                    
                    // Buttons
                    Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 60,
                              // POST /walk-proposals/{proposalId}/responses (DECLINED)
                              child: ElevatedButton(
                                onPressed: walkVm.isLoading ? null : _decline,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: const Color(0xFF5D4037),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  elevation: 0,
                                ),
                                child: const Text('나중에 할게요', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: SizedBox(
                              height: 60,
                              // POST responses(ACCEPTED) → POST /walks
                              child: ElevatedButton(
                                // 서버에 산책 제안 API가 아직 없어 hasProposal이 항상
                                // false다. 제안 유무와 무관하게 눌러볼 수 있게 둔다.
                                onPressed: walkVm.isLoading ? null : _accept,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFC67C4E),
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: Colors.grey.shade300,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  elevation: 0,
                                ),
                                child: walkVm.isLoading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                            color: Colors.white, strokeWidth: 2),
                                      )
                                    : const Text('산책 수락하기',
                                        style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const Text('산책 제안 시간대는 설정에서 바꿀 수 있어요', style: TextStyle(color: Colors.grey, fontSize: 11)),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF5D4037)),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF5D4037))),
        ],
      ),
    );
  }
}
