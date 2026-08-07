import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/services/profile_image_store.dart';
import '../../../domain/entities/pet.dart';
import '../../viewmodels/pet_view_model.dart';
import '../../widgets/profile_avatar_picker.dart';

class PetProfileEditScreen extends StatefulWidget {
  const PetProfileEditScreen({super.key});

  @override
  State<PetProfileEditScreen> createState() => _PetProfileEditScreenState();
}

class _PetProfileEditScreenState extends State<PetProfileEditScreen> {
  /// 서버에서 이름이 오기 전까지 보여줄 값. 도착하면 [_syncName] 이 덮어쓴다.
  final _nameController = TextEditingController(text: '마실이');

  /// 하루 산책 횟수. 서버 `pets.daily_walk_count` 와 이어져 있고, 산책 제안
  /// 간격을 실제로 정한다. 서버 값이 오면 [_syncPet] 이 덮어쓴다.
  final _cycleController =
      TextEditingController(text: '${Pet.defaultDailyWalkCount}');

  /// 알림 동의는 아직 서버 `UpdatePetRequest` 에 항목이 없다([_save] 주석 참고).
  bool _isNotificationEnabled = true;

  /// 산책 알림이 오는 활동 시간대. [_cycleGuide] 문구를 만들 때만 쓴다.
  static const int _activeStartHour = 8;
  static const int _activeEndHour = 22;

  /// 사용자가 직접 고쳤는지. 고친 뒤에 서버 값으로 되돌리지 않기 위한 표시.
  bool _nameTouched = false;
  bool _cycleTouched = false;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() => _nameTouched = true);
    // 횟수를 고칠 때마다 알림 간격 안내 문구를 다시 계산한다.
    _cycleController.addListener(() {
      _cycleTouched = true;
      setState(() {});
    });
    // 사진을 어느 펫 자리에 저장할지 알려면 petId 가 필요하다.
    // 펫 API 가 아직 없으면 조용히 실패하고 공용 자리를 쓴다.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final petVm = context.read<PetViewModel>();
      if (petVm.pet == null) await petVm.loadCurrentPet(silent: true);
      if (!mounted) return;
      _syncPet(petVm.pet);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cycleController.dispose();
    super.dispose();
  }

  /// 서버에서 온 펫 정보를 입력칸에 채운다.
  ///
  /// 사용자가 이미 고쳐 둔 값을 서버 값으로 되돌리면 입력을 잃어버리므로,
  /// 아직 손대지 않았을 때만(=처음 채울 때) 넣는다.
  void _syncPet(Pet? pet) {
    if (pet == null) return;
    if (pet.name.isNotEmpty && !_nameTouched) {
      _nameController.text = pet.name;
    }
    if (!_cycleTouched) {
      _cycleController.text = '${pet.dailyWalkCount}';
      // 위 대입이 리스너를 깨워 _cycleTouched 를 세우므로 되돌려 놓는다.
      // 그러지 않으면 서버 값을 채운 것만으로 "사용자가 고쳤다" 가 된다.
      _cycleTouched = false;
    }
  }

  /// PATCH /pets/{petId} — 펫 정보 저장.
  ///
  /// 이름과 하루 산책 횟수를 함께 보낸다. 횟수는 서버에서 산책 제안 간격이
  /// 되므로 저장하는 순간 마실이가 조르는 주기가 바뀐다.
  ///
  /// **알림 수신 동의는 아직 서버에 보낼 항목이 없다** — 저장돼도 이 기기에만
  /// 남는다. 서버에 항목이 생기면 여기에 함께 실어 보내면 된다.
  Future<void> _save() async {
    final petVm = context.read<PetViewModel>();
    final name = _nameController.text.trim();
    final cycle = int.tryParse(_cycleController.text.trim());

    if (name.isEmpty) {
      _toast('펫 이름을 입력해 주세요', isError: true);
      return;
    }
    if (cycle == null ||
        cycle < Pet.minDailyWalkCount ||
        cycle > Pet.maxDailyWalkCount) {
      _toast(
        '하루 산책 횟수는 ${Pet.minDailyWalkCount}~${Pet.maxDailyWalkCount}회로 입력해 주세요',
        isError: true,
      );
      return;
    }
    if (petVm.pet == null) {
      _toast('펫 정보를 불러오지 못했어요. 먼저 펫을 등록해 주세요', isError: true);
      return;
    }

    final ok = await petVm.updatePet(name: name, dailyWalkCount: cycle);
    if (!mounted) return;

    if (!ok) {
      _toast(petVm.errorMessage ?? '저장하지 못했어요', isError: true);
      return;
    }
    _toast('저장했어요');
    context.pop();
  }

  /// 하루 산책 횟수에 따른 알림 간격 안내 문구.
  ///
  /// 활동 시간대(08:00~22:00, 14시간)를 입력한 횟수로 나눈 값이다.
  String get _cycleGuide {
    const window = '$_activeStartHour:00 ~ $_activeEndHour:00';
    final count = int.tryParse(_cycleController.text.trim());

    if (count == null ||
        count < Pet.minDailyWalkCount ||
        count > Pet.maxDailyWalkCount) {
      return '하루 산책 횟수를 '
          '${Pet.minDailyWalkCount}~${Pet.maxDailyWalkCount}회 사이 숫자로 입력해 주세요.';
    }
    if (count == 1) {
      return '$window 사이에 한 번 마실이가 산책 가자고 조릅니다.';
    }

    const totalMinutes = (_activeEndHour - _activeStartHour) * 60;
    return '$window 사이에 약 ${_formatInterval(totalMinutes ~/ count)} 간격으로 '
        '마실이가 산책 가자고 조릅니다.';
  }

  /// 분을 `7시간`, `4시간 40분`, `42분` 처럼 읽기 쉬운 형태로 바꾼다.
  String _formatInterval(int minutes) {
    if (minutes < 60) return '$minutes분';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '$hours시간' : '$hours시간 $rest분';
  }

  void _toast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? const Color(0xFFD32F2F) : const Color(0xFF5D4037),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pet = context.watch<PetViewModel>().pet;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F3E7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Color(0xFF5D4037)),
          onPressed: () => context.pop(),
        ),
        title: const Text('펫 프로필 관리',
            style: TextStyle(
                color: Color(0xFF5D4037), fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.check, color: Color(0xFFC67C4E)),
            onPressed: _save,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // 펫 프로필 사진. 눌러서 갤러리·카메라로 등록하거나 삭제한다.
            //
            // 사진이 없으면 기본 마실이 그림을 보여준다(전과 같은 모습).
            // 서버 `UpdatePetRequest.profileImage` 는 있지만 이미지를 올릴
            // 엔드포인트가 없어서, 지금은 기기에만 저장한다.
            ProfileAvatarPicker(
              imageKey: ProfileImageStore.petKeyOrCurrent(pet?.id),
              size: 150,
              fallbackImageUrl: pet?.profileImageUrl,
              placeholder: Padding(
                padding: const EdgeInsets.all(12.0),
                child: ClipOval(
                  child: Image.asset('assets/images/mysil_character.png',
                      fit: BoxFit.contain),
                ),
              ),
            ),
            const SizedBox(height: 40),

            // Name Field
            _buildSectionCard([
              _buildLabel('펫 이름 설정'),
              Stack(
                alignment: Alignment.centerRight,
                children: [
                  _buildTextField(controller: _nameController),
                  const Padding(
                    padding: EdgeInsets.only(right: 16),
                    child: Text('3/10',
                        style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ),
                ],
              ),
            ]),
            const SizedBox(height: 16),

            // Cycle Field
            _buildSectionCard([
              _buildLabel('산책 주기 설정'),
              const Text('하루 산책 횟수',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                      child: _buildTextField(
                          controller: _cycleController,
                          textAlign: TextAlign.center)),
                  const SizedBox(width: 12),
                  const Text('회',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 10),
              // 숫자만 보면 알림이 얼마나 자주 오는지 알 수 없어서 함께 보여준다.
              Text(
                _cycleGuide,
                style: const TextStyle(
                    color: Color(0xFF8D6E63), fontSize: 12, height: 1.5),
              ),
            ]),
            const SizedBox(height: 16),

            // Notification Toggle
            _buildSectionCard([
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('알림 수신 동의',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      SizedBox(height: 4),
                      Text('산책 알림 및 중요 공지',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                  Switch(
                    value: _isNotificationEnabled,
                    onChanged: (val) =>
                        setState(() => _isNotificationEnabled = val),
                    activeThumbColor: const Color(0xFFC67C4E),
                  ),
                ],
              ),
            ]),
            const SizedBox(height: 32),

            // Save Button
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed:
                    context.watch<PetViewModel>().isLoading ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC67C4E),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFE0D5C8),
                  disabledForegroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  elevation: 0,
                ),
                child: const Text('저장하기',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: pet == null
                  ? null
                  : () => context.push(
                        '/pet-delete-confirm/${pet.id}',
                      ),
              child: const Text('펫 정보 삭제하기',
                  style: TextStyle(
                      color: Color(0xFFD32F2F), fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard(List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _buildLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(label,
          style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Color(0xFF5D4037))),
    );
  }

  Widget _buildTextField(
      {required TextEditingController controller,
      String? hint,
      TextAlign textAlign = TextAlign.start}) {
    return TextField(
      controller: controller,
      textAlign: textAlign,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFFDF7F0),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: Color(0xFFF0E0D0))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: Color(0xFFF0E0D0))),
      ),
    );
  }
}
