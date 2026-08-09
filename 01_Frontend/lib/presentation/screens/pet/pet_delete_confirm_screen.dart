import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../viewmodels/pet_view_model.dart';
import '../../viewmodels/robot_view_model.dart';

class PetDeleteConfirmScreen extends StatelessWidget {
  const PetDeleteConfirmScreen({super.key, required this.petId});

  final int petId;

  Future<void> _delete(BuildContext context) async {
    final petVm = context.read<PetViewModel>();
    final deleted = await petVm.deletePet(petId);
    if (!context.mounted) return;

    if (!deleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(petVm.errorMessage ?? '펫 정보를 삭제하지 못했어요.'),
          backgroundColor: const Color(0xFFD32F2F),
        ),
      );
      return;
    }

    context.read<RobotViewModel>().clearAfterPetDeletion();
    context.go('/user');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('펫 정보와 기기 연결을 삭제했어요.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final petVm = context.watch<PetViewModel>();
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.5), // Simulated overlay
      body: Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(35),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                    color: Color(0xFFFFF1F0), shape: BoxShape.circle),
                child: const Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFD32F2F), size: 40),
              ),
              const SizedBox(height: 24),
              const Text(
                '정말 삭제하시겠어요?',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF5D4037)),
              ),
              const SizedBox(height: 12),
              const Text(
                '펫 프로필을 삭제하고 기기 연결을 해제해요.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF8D6E63), fontSize: 16),
              ),
              const SizedBox(height: 32),

              // Stats Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F0),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('· 펫 프로필 삭제',
                        style:
                            TextStyle(color: Color(0xFFD32F2F), fontSize: 14)),
                    SizedBox(height: 8),
                    Text('· 기기 페어링 및 소유권 해제',
                        style:
                            TextStyle(color: Color(0xFFD32F2F), fontSize: 14)),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 60,
                      child: ElevatedButton(
                        onPressed: petVm.isLoading ? null : () => context.pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEFE5D8),
                          foregroundColor: const Color(0xFF8D6E63),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                          elevation: 0,
                        ),
                        child: const Text('취소',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 18)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SizedBox(
                      height: 60,
                      child: ElevatedButton(
                        onPressed:
                            petVm.isLoading ? null : () => _delete(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD32F2F),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                          elevation: 0,
                        ),
                        child: petVm.isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('삭제',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 18)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
