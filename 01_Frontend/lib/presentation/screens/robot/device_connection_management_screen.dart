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
  bool _startingRegistration = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<PetViewModel>().loadCurrentPet(silent: true);
    });
  }

  Future<void> _startRegistration() async {
    if (_startingRegistration) return;
    setState(() => _startingRegistration = true);

    final petVm = context.read<PetViewModel>();
    if (petVm.pet == null) {
      await petVm.loadCurrentPet(silent: true);
    }

    if (!mounted) return;
    if (petVm.pet == null) {
      final name = await _askPetName();
      if (name == null || name.isEmpty || !mounted) {
        setState(() => _startingRegistration = false);
        return;
      }

      final created = await petVm.createPet(name: name);
      if (!mounted) return;
      if (!created) {
        setState(() => _startingRegistration = false);
        _showError(petVm.errorMessage ?? '펫 프로필을 만들지 못했어요.');
        return;
      }
    }

    setState(() => _startingRegistration = false);
    await context.push('/user/robot-mgmt/register');
    if (!mounted) return;
    await petVm.loadCurrentPet(silent: true);
  }

  Future<String?> _askPetName() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('함께할 펫 이름'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '기기에 연결할 펫 프로필을 먼저 만들게요.',
              style: TextStyle(color: Color(0xFF8D6E63), fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 100,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                hintText: '이름 (예: 마실이)',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (value) =>
                  Navigator.of(dialogContext).pop(value.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('다음'),
          ),
        ],
      ),
    );
    controller.dispose();
    return name;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFD32F2F),
        behavior: SnackBarBehavior.floating,
      ),
    );
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
                  if (robot == null) ...[
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
                          const Text(
                            '마실이 기기를 등록해요',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            pet == null
                                ? '펫 이름을 정한 뒤 기기 밑면의 QR을 스캔하면\n프로필 생성과 기기 연결이 한 번에 끝나요.'
                                : '${pet.name} 프로필에 연결할 기기의\n밑면 QR 코드를 스캔해 주세요.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
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
                              onPressed: _startingRegistration
                                  ? null
                                  : _startRegistration,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFC67C4E),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                              ),
                              child: Text(
                                _startingRegistration ? '준비 중...' : '기기 등록 시작',
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
