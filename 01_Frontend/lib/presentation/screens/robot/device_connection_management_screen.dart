import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../viewmodels/pet_view_model.dart';

/// 펫 생성과 로봇 QR 등록을 하나의 기기 등록 흐름으로 제공한다.
class DeviceConnectionManagementScreen extends StatefulWidget {
  const DeviceConnectionManagementScreen({super.key});

  @override
  State<DeviceConnectionManagementScreen> createState() =>
      _DeviceConnectionManagementScreenState();
}

class _DeviceConnectionManagementScreenState
    extends State<DeviceConnectionManagementScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<PetViewModel>().loadCurrentPet(silent: true);
    });
  }

  Future<void> _startRegistration() async {
    final petVm = context.read<PetViewModel>();
    await context.push('/user/robot-mgmt/register');
    if (!mounted) return;
    await petVm.loadCurrentPet(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final petVm = context.watch<PetViewModel>();
    final pet = petVm.pet;
    final robot = pet?.robot;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F3E7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Color(0xFF5D4037)),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          '기기 등록',
          style: TextStyle(
            color: Color(0xFF5D4037),
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: petVm.isLoading && pet == null
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFC67C4E)),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  if (robot != null) ...[
                    _ConnectedDeviceCard(
                      petName: pet!.name,
                      robotId: robot.robotId,
                      online: robot.online,
                      batteryLevel: robot.batteryLevel,
                    ),
                    const SizedBox(height: 24),
                  ],
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 40,
                      horizontal: 24,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: const BoxDecoration(
                            color: Color(0xFFE8F6F3),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.qr_code_scanner,
                            color: Color(0xFF16A085),
                            size: 40,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          robot == null ? '마실이 기기를 등록해요' : '새 기기를 추가해요',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '기기 밑면의 QR을 먼저 확인한 뒤\n새 반려동물의 이름을 등록해요.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 32),
                        SizedBox(
                          width: double.infinity,
                          height: 60,
                          child: ElevatedButton(
                            onPressed: _startRegistration,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFC67C4E),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                            ),
                            child: Text(
                              robot == null ? '기기 등록 시작' : '기기 추가 등록',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8F1),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Color(0xFFC67C4E),
                          size: 20,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '이미 다른 계정에 등록된 기기이거나 QR이 만료된 경우 연결할 수 없어요.',
                            style: TextStyle(
                              color: Color(0xFF8D6E63),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _ConnectedDeviceCard extends StatelessWidget {
  const _ConnectedDeviceCard({
    required this.petName,
    required this.robotId,
    required this.online,
    required this.batteryLevel,
  });

  final String petName;
  final int robotId;
  final bool online;
  final int batteryLevel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
      ),
      child: Row(
        children: [
          Container(
            width: 70,
            height: 70,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF9F3E7),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Image.asset('assets/images/mysil_character.png'),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$petName · 기기 $robotId',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '배터리 $batteryLevel%',
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: online ? Colors.green.shade50 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              online ? '온라인' : '오프라인',
              style: TextStyle(
                color: online ? Colors.green : Colors.grey.shade700,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
