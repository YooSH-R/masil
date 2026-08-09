import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../../core/services/profile_image_store.dart';
// PetMood.label 은 pet.dart 의 확장(PetMoodX)에 있다.
import '../../../domain/entities/pet.dart';
import '../../viewmodels/auth_view_model.dart';
import '../../viewmodels/pet_view_model.dart';
import '../../widgets/profile_avatar.dart';

class MyPageScreen extends StatefulWidget {
  const MyPageScreen({super.key});

  @override
  State<MyPageScreen> createState() => _MyPageScreenState();
}

class _MyPageScreenState extends State<MyPageScreen> {
  @override
  void initState() {
    super.initState();
    // GET /users/me — 로그인 응답은 {userId, nickname} 만 주므로
    // 이메일·전화번호를 보여주려면 회원정보를 따로 불러와야 한다.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      context.read<AuthViewModel>().loadMyProfile(silent: true);
      // 캐시된 현재 펫을 먼저 복원한 뒤 서버 목록을 불러온다. 목록만 조회하면
      // 등록된 펫이 있어도 캐시가 빈 기기에서는 펫이 없는 것으로 보일 수 있고,
      // 목록을 먼저 적용하면 사용자가 선택한 현재 펫 대신 첫 펫이 보일 수 있다.
      final petVm = context.read<PetViewModel>();
      if (petVm.pet == null) {
        await petVm.loadCurrentPet(silent: true);
      }
      if (!mounted) return;
      await petVm.loadPets(silent: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final authViewModel = context.watch<AuthViewModel>();
    // 현재 펫 캐시가 비어 있어도 서버 목록에 펫이 있으면 등록된 것으로 본다.
    final petViewModel = context.watch<PetViewModel>();
    final pet = petViewModel.pet ??
        (petViewModel.pets.isEmpty ? null : petViewModel.pets.first);
    final hasRegisteredDevice = pet?.robot != null ||
        petViewModel.pets.any((registeredPet) => registeredPet.robot != null);
    final user = authViewModel.user;
    final profile = authViewModel.profile;

    // 회원정보가 있으면 그걸 쓰고, 없으면 로그인 응답의 값으로 보여준다.
    final nickname = profile?.nickname ?? user?.nickname;
    final subtitle = profile?.email ??
        profile?.formattedPhoneNumber ??
        user?.email ??
        '반려견과 함께하는 삶';

    return Scaffold(
      backgroundColor: const Color(0xFFF9F3E7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Color(0xFF5D4037)),
          onPressed: () => context.go('/home'),
        ),
        title: const Text('마이페이지',
            style: TextStyle(
                color: Color(0xFF5D4037), fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // User Info Section
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  // 내 정보 수정에서 등록한 사진을 그대로 보여준다.
                  // 눌러도 수정 화면으로 가서, 사진을 바꾸러 가는 길이 하나 더 생긴다.
                  ProfileAvatar(
                    imageKey: ProfileImageStore.userKey,
                    fallbackImageUrl: authViewModel.user?.profileImageUrl,
                    onTap: () => context.push('/user/profile-edit'),
                  ),
                  const SizedBox(width: 16),
                  // 로그인 응답(3.4)의 user 정보를 그대로 보여준다.
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nickname == null ? '로그인이 필요해요' : '$nickname 님',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF5D4037)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Color(0xFF8D6E63), fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => context.push('/user/reauth'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF9F3E7),
                      foregroundColor: const Color(0xFFC67C4E),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('내 정보\n수정',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 펫이 없을 때는 별도 등록 안내를 중복 노출하지 않는다. 위의 기기
            // 등록 흐름이 이름 입력부터 QR 연결까지 함께 처리한다.
            if (pet != null) ...[
              _buildSectionHeader('내 반려동물'),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        // 펫 프로필 관리에서 등록한 사진. 없으면 기본 마실이 그림.
                        // 반려동물 자체를 가리키므로 스테이션이 아닌 인형 이미지를 쓴다.
                        ProfileAvatar(
                          imageKey: ProfileImageStore.petKeyOrCurrent(pet.id),
                          size: 50,
                          borderRadius: 12,
                          borderWidth: 0,
                          backgroundColor: const Color(0xFFFDF7F0),
                          placeholder:
                              Image.asset('assets/images/mysil_pet.png'),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 이름·기분은 GET /pets/{petId} 의 실제 값이다.
                              Text(pet.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  if (pet.affinity != null)
                                    _buildTag(
                                        pet.affinity!.mood.label,
                                        const Color(0xFFFDF2E9),
                                        const Color(0xFFD35400)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () => context.push('/user/pet-list/edit'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF5D4037),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15)),
                          elevation: 0,
                        ),
                        child: const Text('펫 프로필 관리',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // 기기 등록이 완료될 때 새 펫 프로필도 함께 생성된다.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF5D4037), Color(0xFF3E2723)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(25),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      hasRegisteredDevice ? '기기 추가 등록' : '기기 등록',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.grid_view_rounded,
                          color: Color(0xFF5D4037), size: 30),
                      onPressed: () => context.push('/user/robot-mgmt'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Other Menus
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  _buildMenuItem(
                      Icons.campaign_outlined, '공지사항', Colors.orange),
                  _buildMenuItem(
                      Icons.menu_book_outlined, '서비스 이용 가이드', Colors.blue),
                  _buildMenuItem(
                      Icons.headset_mic_outlined, '1:1 문의', Colors.indigo),
                  _buildMenuItem(
                      Icons.verified_user_outlined, '약관 및 정책', Colors.grey),
                ],
              ),
            ),

            const SizedBox(height: 32),
            // POST /auth/logout — 서버 세션 종료 후 로컬 토큰까지 정리한다.
            TextButton(
              onPressed: authViewModel.isLoading
                  ? null
                  : () async {
                      await authViewModel.logout();
                      if (!context.mounted) return;
                      context.go('/login');
                    },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.logout, color: Color(0xFF8D6E63), size: 18),
                  SizedBox(width: 8),
                  Text('로그아웃',
                      style: TextStyle(
                          color: Color(0xFF8D6E63),
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // 앱 버전. 시연 중 APK 를 여러 번 교체하므로, 화면에서 확인할 수
            // 있어야 업데이트가 됐는지 알 수 있다.
            const _AppVersionLabel(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Row(
        children: [
          const Icon(Icons.pets, size: 16, color: Color(0xFFC67C4E)),
          const SizedBox(width: 8),
          Text(title,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF5D4037))),
        ],
      ),
    );
  }

  Widget _buildTag(String text, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: bgColor, borderRadius: BorderRadius.circular(10)),
      child: Text(text,
          style: TextStyle(
              color: textColor, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildMenuItem(IconData icon, String title, Color iconColor) {
    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
      onTap: () {},
    );
  }
}

/// 앱 버전 표시. `버전 1.0.1 (2)` 형태.
///
/// 괄호 안이 안드로이드 versionCode(pubspec 의 `+N`)다. 시연 중 APK 를 여러 번
/// 교체하는데 이게 없으면 업데이트가 됐는지 확인할 방법이 없다. 새 APK 를 뽑을
/// 때 pubspec 의 `+N` 을 올리면 이 숫자도 함께 올라간다.
class _AppVersionLabel extends StatefulWidget {
  const _AppVersionLabel();

  @override
  State<_AppVersionLabel> createState() => _AppVersionLabelState();
}

class _AppVersionLabelState extends State<_AppVersionLabel> {
  String? _label;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _label = '버전 ${info.version} (${info.buildNumber})');
    } catch (_) {
      // 못 읽어도 화면이 깨지지 않게 조용히 넘어간다.
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = _label;
    if (label == null) return const SizedBox.shrink();
    return Center(
      child: Text(label,
          style: const TextStyle(color: Color(0xFFBCAAA4), fontSize: 12)),
    );
  }
}
