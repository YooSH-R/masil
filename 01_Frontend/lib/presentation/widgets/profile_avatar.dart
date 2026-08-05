import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../viewmodels/profile_image_view_model.dart';

/// 등록된 프로필 사진을 보여주는 동그란 아바타(보기 전용).
///
/// 사진을 고치는 곳에서는 [ProfileAvatarPicker] 를 쓴다. 이 위젯은 마이페이지
/// 처럼 **보여주기만** 하는 자리에 쓴다. 둘 다 [ProfileImageViewModel] 을 보므로
/// 한쪽에서 사진을 바꾸면 다른 쪽도 바로 따라 바뀐다.
class ProfileAvatar extends StatefulWidget {
  const ProfileAvatar({
    super.key,
    required this.imageKey,
    this.size = 70,
    this.placeholder,
    this.fallbackImageUrl,
    this.borderColor = const Color(0xFFEFE5D8),
    this.borderWidth = 2,
    this.backgroundColor = const Color(0xFFF9F3E7),
    this.borderRadius,
    this.onTap,
  });

  final String imageKey;
  final double size;

  /// 주면 동그라미 대신 이만큼 둥근 네모로 그린다(마이페이지 펫 썸네일처럼).
  final double? borderRadius;

  /// 사진이 없을 때 보여줄 것.
  final Widget? placeholder;

  /// 서버가 내려준 사진 주소. 기기에 저장된 사진이 없을 때만 쓴다.
  final String? fallbackImageUrl;

  final Color borderColor;
  final double borderWidth;
  final Color backgroundColor;
  final VoidCallback? onTap;

  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar> {
  @override
  void initState() {
    super.initState();
    _ensure();
  }

  @override
  void didUpdateWidget(ProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    final image =
        context.watch<ProfileImageViewModel>().imageOf(widget.imageKey);

    final radius = widget.borderRadius;
    final avatar = Container(
      width: widget.size,
      height: widget.size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: widget.backgroundColor,
        shape: radius == null ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: radius == null ? null : BorderRadius.circular(radius),
        border: widget.borderWidth <= 0
            ? null
            : Border.all(color: widget.borderColor, width: widget.borderWidth),
      ),
      child: image != null
          ? Image.file(image, fit: BoxFit.cover)
          : _buildFallback(),
    );

    if (widget.onTap == null) return avatar;
    return GestureDetector(onTap: widget.onTap, child: avatar);
  }

  Widget _buildFallback() {
    final url = widget.fallbackImageUrl;
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder,
      );
    }
    return _placeholder;
  }

  Widget get _placeholder =>
      widget.placeholder ??
      Center(
        child: Icon(Icons.person_outline,
            color: const Color(0xFF8D6E63), size: widget.size * 0.42),
      );
}
