import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/entities/walk_photo.dart';
import '../viewmodels/walk_photo_view_model.dart';

/// 산책 사진 한 장을 그린다. 필요한 바이트는 스스로 받아온다.
///
/// `/photos/{id}/content` 는 인증이 필요해서 `Image.network` 로는 401 이 날 수
/// 있다. 그래서 [WalkPhotoViewModel] 이 ApiClient 로 받아 캐시해 둔 바이트를
/// `Image.memory` 로 그린다. 갤러리 저장도 같은 캐시를 쓰므로, 화면에 보인
/// 사진은 저장이 곧바로 끝난다.
///
/// 상태별로 다르게 보여준다.
/// - 아직 서버가 만드는 중(`processingStatus.isPending`): 반짝이 아이콘
/// - 바이트 받는 중: 로딩 표시
/// - 실패: 탭하면 다시 받는 버튼
class WalkPhotoImage extends StatefulWidget {
  const WalkPhotoImage({super.key, required this.photo, this.fit = BoxFit.cover});

  final WalkPhoto photo;
  final BoxFit fit;

  @override
  State<WalkPhotoImage> createState() => _WalkPhotoImageState();
}

class _WalkPhotoImageState extends State<WalkPhotoImage> {
  @override
  void initState() {
    super.initState();
    _ensure();
  }

  @override
  void didUpdateWidget(WalkPhotoImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photo.photoId != widget.photo.photoId) _ensure();
  }

  /// build 중에 부르면 notify 가 겹치므로 프레임 뒤로 미룬다.
  /// 이미 받아둔 사진이면 뷰모델에서 곧바로 빠져나온다.
  void _ensure() {
    if (widget.photo.processingStatus.isPending) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<WalkPhotoViewModel>().ensureBytes(widget.photo.photoId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final photoVm = context.watch<WalkPhotoViewModel>();
    final photoId = widget.photo.photoId;

    final bytes = photoVm.bytesOf(photoId);
    if (bytes != null) return Image.memory(bytes, fit: widget.fit);

    if (photoVm.didFailBytesOf(photoId)) {
      return InkWell(
        onTap: () => photoVm.retryBytes(photoId),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.refresh, color: Color(0xFFC67C4E), size: 26),
              SizedBox(height: 6),
              Text('다시 불러오기',
                  style: TextStyle(fontSize: 11, color: Color(0xFF8D6E63))),
            ],
          ),
        ),
      );
    }

    return Center(
      child: widget.photo.processingStatus.isPending
          ? const Icon(Icons.auto_awesome, color: Color(0xFFD7CCC8), size: 32)
          : const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                  color: Color(0xFFD7CCC8), strokeWidth: 2.5),
            ),
    );
  }
}
