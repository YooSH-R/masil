import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/services/profile_image_store.dart';
import '../../../domain/entities/pet.dart';
import '../../viewmodels/pet_view_model.dart';
import '../../widgets/profile_avatar.dart';

/// 내 반려동물 목록.
///
/// **서버에 펫 목록 API 가 없다.** 배포·소스 모두 `POST /pets`,
/// `GET /pets/{petId}`, `PATCH /pets/{petId}` 뿐이고 `GET /pets` 가 없다.
/// 그래서 앱이 알 수 있는 펫은 **캐시된 petId 하나**다(펫을 만들 때 저장한다).
///
/// 목록 API 가 생기면 [PetViewModel] 에 `loadPets()` 를 더하고 이 화면이 그
/// 리스트를 그리도록 바꾸면 된다. 지금은 현재 펫 하나만 보여준다.
class PetListScreen extends StatefulWidget {
  const PetListScreen({super.key});

  /// 제품 규칙상의 상한. 서버가 검증하지는 않는다.
  static const int maxPets = 3;

  @override
  State<PetListScreen> createState() => _PetListScreenState();
}

class _PetListScreenState extends State<PetListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 아는 petId 를 모두 조회해 목록을 채운다(서버에 목록 API 가 없다).
      context.read<PetViewModel>().loadPets();
    });
  }

  /// 펫을 새로 만든다. POST /pets — 이름만 있으면 서버가 만들어 준다.
  ///
  /// 기기 등록(POST /robots/pairings)이 petId 를 요구하기 때문에, 펫이 없으면
  /// QR 을 찍어도 등록을 끝낼 수 없다. 그래서 이 버튼이 실제로 동작해야 한다.
  ///
  /// 주의: 목록 API 가 없어서 새로 만들면 **현재 펫이 새 펫으로 바뀐다.**
  /// 이전 펫은 서버에 남아 있지만 앱에서 다시 찾아갈 방법이 없다.
  Future<void> _addPet() async {
    final controller = TextEditingController();

    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('펫 추가'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 100,
              decoration: const InputDecoration(
                hintText: '이름 (예: 마실이)',
                border: OutlineInputBorder(),
              ),
            ),
            const Text(
              '지금은 펫을 한 마리만 관리할 수 있어요.\n새로 추가하면 현재 펫이 바뀝니다.',
              style: TextStyle(fontSize: 11, color: Color(0xFF8D6E63)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('추가'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty || !mounted) return;

    final petVm = context.read<PetViewModel>();
    final created = await petVm.createPet(name: name);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(created
            ? '$name 을(를) 추가했어요'
            : petVm.errorMessage ?? '펫을 추가하지 못했어요'),
        backgroundColor:
            created ? const Color(0xFF5D4037) : const Color(0xFFD32F2F),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final petVm = context.watch<PetViewModel>();
    final pets = petVm.pets;
    final currentId = petVm.pet?.id;
    final count = pets.length;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F3E7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Color(0xFF5D4037)),
          onPressed: () => context.pop(),
        ),
        title: const Text('내 반려동물',
            style: TextStyle(
                color: Color(0xFF5D4037), fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Center(
              child: Text('$count / ${PetListScreen.maxPets}',
                  style: const TextStyle(
                      color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
      body: petVm.isLoading && pets.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFC67C4E)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  if (pets.isEmpty)
                    const _NoPetNotice()
                  else
                    // 만든 순서대로. 대표 펫이 맨 위로 온다.
                    for (final p in _sorted(pets, currentId)) ...[
                      _buildPetCard(p, isCurrent: p.id == currentId),
                      const SizedBox(height: 16),
                    ],
                  const SizedBox(height: 8),
                  _buildAddButton(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  /// 대표 펫을 맨 위로 올린다. 나머지는 만든 순서 그대로.
  static List<Pet> _sorted(List<Pet> pets, int? currentId) {
    if (currentId == null) return pets;
    final index = pets.indexWhere((p) => p.id == currentId);
    if (index <= 0) return pets;
    return [pets[index], ...pets.where((p) => p.id != currentId)];
  }

  /// 펫 카드. 이름·기분은 서버 값(`GET /pets/{petId}`)이고,
  /// 사진은 기기에 저장한 프로필 사진이다.
  ///
  /// 대표 펫만 테두리와 `대표` 배지를 붙인다.
  Widget _buildPetCard(Pet pet, {required bool isCurrent}) {
    final mood = pet.affinity?.mood;

    return GestureDetector(
      // 탭하면 그 펫을 대표로 지정하고 프로필 편집으로 넘어간다.
      // 편집 화면은 현재 펫을 보므로 지정이 먼저여야 한다.
      onTap: () async {
        if (!isCurrent) {
          await context.read<PetViewModel>().selectPet(pet.id);
          if (!mounted) return;
        }
        if (!mounted) return;
        context.push('/user/pet-list/edit');
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(25),
          border: isCurrent
              ? Border.all(color: const Color(0xFFC67C4E), width: 2)
              : null,
        ),
        child: Row(
          children: [
            ProfileAvatar(
              imageKey: ProfileImageStore.petKeyOrCurrent(pet.id),
              size: 70,
              borderRadius: 15,
              borderWidth: 0,
              backgroundColor: const Color(0xFFF9F3E7),
              placeholder:
                  Image.asset('assets/images/mysil_character.png'),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pet.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF5D4037))),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      // 기분은 친밀도 응답의 mood 에서 온다. 없으면 표시하지 않는다.
                      if (mood != null)
                        _buildSmallTag(mood.label, const Color(0xFFFDF2E9),
                            const Color(0xFFD35400)),
                      if (pet.robot != null) ...[
                        const SizedBox(width: 8),
                        _buildSmallTag(
                            pet.robot!.online ? '마실이 연결됨' : '마실이 오프라인',
                            const Color(0xFFE8F6F3),
                            const Color(0xFF16A085)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (isCurrent)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: const Color(0xFFC67C4E),
                    borderRadius: BorderRadius.circular(10)),
                child: const Text('대표',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              )
            else
              const Icon(Icons.chevron_right, color: Color(0xFFBCAAA4)),
          ],
        ),
      ),
    );
  }

  Widget _buildAddButton() {
    return GestureDetector(
      onTap: _addPet,
      child: Container(
        width: double.infinity,
        height: 100,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: Colors.grey.shade400, width: 1.5),
        ),
        child: const Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, color: Colors.grey),
              SizedBox(width: 8),
              Text('펫 추가하기',
                  style: TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSmallTag(String text, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8)),
      child: Text(text,
          style: TextStyle(
              color: textColor, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}

/// 펫이 아직 없을 때.
///
/// 기기 등록이 petId 를 요구하므로, 펫이 없으면 QR 을 찍어도 등록이 끝나지
/// 않는다. 그래서 여기서 먼저 만들어야 한다는 것을 알려준다.
class _NoPetNotice extends StatelessWidget {
  const _NoPetNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(25)),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
                color: Color(0xFFF9F3E7), shape: BoxShape.circle),
            child: const Icon(Icons.pets, color: Color(0xFFC67C4E), size: 36),
          ),
          const SizedBox(height: 24),
          const Text('아직 등록된 펫이 없어요',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF5D4037))),
          const SizedBox(height: 12),
          const Text(
            '펫을 등록하면 마실이 기기를 연결하고\n친밀도를 쌓을 수 있어요',
            textAlign: TextAlign.center,
            style:
                TextStyle(color: Color(0xFF8D6E63), fontSize: 14, height: 1.5),
          ),
        ],
      ),
    );
  }
}
