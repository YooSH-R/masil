import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../viewmodels/profile_image_view_model.dart';

/// 프로필 사진을 보여주고, 눌러서 등록·삭제하는 동그란 아바타.
///
/// 회원 프로필과 펫 프로필이 같은 위젯을 쓴다. 다른 점은 [imageKey] 하나뿐이다.
///
/// 누르면 아래에서 시트가 올라온다.
/// - 갤러리에서 선택 / 사진 촬영
/// - 사진이 이미 있으면 `사진 삭제`
///
/// 사진은 [ProfileImageStore] 가 앱 전용 폴더에 보관한다. 서버가 프로필 사진을
/// 받아주게 되면 [onChanged] 에서 업로드를 이어 붙이면 된다.
class ProfileAvatarPicker extends StatefulWidget {
  const ProfileAvatarPicker({
    super.key,
    required this.imageKey,
    this.size = 120,
    this.placeholder,
    this.fallbackImageUrl,
    this.onChanged,
  });

  /// [ProfileImageStore.userKey] 또는 [ProfileImageStore.petKey] 값.
  final String imageKey;

  final double size;

  /// 사진이 없을 때 동그라미 안에 보여줄 것(펫 캐릭터 그림 등).
  final Widget? placeholder;

  /// 서버가 내려준 사진 주소. 기기에 저장된 사진이 없을 때만 쓴다.
  /// (서버가 프로필 사진을 지원하면 이쪽이 기본이 된다)
  final String? fallbackImageUrl;

  /// 사진이 바뀐 뒤 호출된다. 지운 경우 null 이 넘어온다.
  final ValueChanged<File?>? onChanged;

  @override
  State<ProfileAvatarPicker> createState() => _ProfileAvatarPickerState();
}

class _ProfileAvatarPickerState extends State<ProfileAvatarPicker> {
  final ImagePicker _picker = ImagePicker();

  bool _busy = false;

  /// 지금 보여줄 사진. 공용 상태에서 가져오므로 다른 화면과 항상 같다.
  File? get _image =>
      context.read<ProfileImageViewModel>().imageOf(widget.imageKey);

  @override
  void initState() {
    super.initState();
    _ensure();
  }

  @override
  void didUpdateWidget(ProfileAvatarPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 펫을 바꿔 들어온 경우처럼 열쇠가 달라지면 다시 읽는다.
    if (oldWidget.imageKey != widget.imageKey) _ensure();
  }

  /// 프레임 뒤로 미룬다. build 중에 notifyListeners 가 불리면 예외가 난다.
  void _ensure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProfileImageViewModel>().ensureLoaded(widget.imageKey);
    });
  }

  @override
  Widget build(BuildContext context) {
    // watch 로 구독해서, 다른 화면에서 사진이 바뀌어도 여기도 따라 바뀐다.
    context.watch<ProfileImageViewModel>();

    return Stack(
      children: [
        Container(
          width: widget.size,
          height: widget.size,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFFEFE5D8),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
          ),
          child: _buildContent(),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: GestureDetector(
            onTap: _busy ? null : _openSheet,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                  color: Color(0xFFC67C4E), shape: BoxShape.circle),
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : Icon(
                      _image == null ? Icons.camera_alt : Icons.edit,
                      color: Colors.white,
                      size: 20,
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    final image = _image;
    if (image != null) {
      return GestureDetector(
        onTap: _busy ? null : _openSheet,
        child: Image.file(image, fit: BoxFit.cover),
      );
    }

    final url = widget.fallbackImageUrl;
    if (url != null && url.isNotEmpty) {
      return GestureDetector(
        onTap: _busy ? null : _openSheet,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildPlaceholder(),
        ),
      );
    }

    return GestureDetector(
      onTap: _busy ? null : _openSheet,
      child: _buildPlaceholder(),
    );
  }

  Widget _buildPlaceholder() =>
      widget.placeholder ??
      const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_a_photo_outlined,
                color: Color(0xFF8D6E63), size: 28),
            SizedBox(height: 6),
            Text('사진 등록',
                style: TextStyle(fontSize: 11, color: Color(0xFF8D6E63))),
          ],
        ),
      );

  Future<void> _openSheet() async {
    final hasImage = _image != null;

    final action = await showModalBottomSheet<_PhotoAction>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: const Color(0xFFE0D5C8),
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            _sheetItem(
              sheetContext,
              icon: Icons.photo_library_outlined,
              label: '갤러리에서 선택',
              action: _PhotoAction.gallery,
            ),
            _sheetItem(
              sheetContext,
              icon: Icons.photo_camera_outlined,
              label: '사진 촬영',
              action: _PhotoAction.camera,
            ),
            if (hasImage)
              _sheetItem(
                sheetContext,
                icon: Icons.delete_outline,
                label: '사진 삭제',
                action: _PhotoAction.delete,
                color: const Color(0xFFD32F2F),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (action == null || !mounted) return;

    switch (action) {
      case _PhotoAction.gallery:
        await _pick(ImageSource.gallery);
      case _PhotoAction.camera:
        await _pick(ImageSource.camera);
      case _PhotoAction.delete:
        await _delete();
    }
  }

  Widget _sheetItem(
    BuildContext sheetContext, {
    required IconData icon,
    required String label,
    required _PhotoAction action,
    Color color = const Color(0xFF5D4037),
  }) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w600, fontSize: 16)),
      onTap: () => Navigator.of(sheetContext).pop(action),
    );
  }

  Future<void> _pick(ImageSource source) async {
    final images = context.read<ProfileImageViewModel>();
    setState(() => _busy = true);
    try {
      // 프로필용이라 크게 받을 필요가 없다. 원본을 그대로 두면 사진 한 장이
      // 수 MB 라서 저장·표시가 다 느려진다.
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (picked == null) return;

      final ok = await images.save(widget.imageKey, picked.path);
      if (!mounted) return;

      if (!ok) {
        _toast('사진을 저장하지 못했어요');
        return;
      }
      widget.onChanged?.call(images.imageOf(widget.imageKey));
    } catch (_) {
      // 권한 거부·카메라 없음 등. 화면이 멈추지 않게 안내만 한다.
      if (mounted) _toast('사진을 가져오지 못했어요. 권한을 확인해 주세요');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final images = context.read<ProfileImageViewModel>();
    setState(() => _busy = true);
    try {
      await images.remove(widget.imageKey);
      if (!mounted) return;
      widget.onChanged?.call(null);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF5D4037),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

enum _PhotoAction { gallery, camera, delete }
