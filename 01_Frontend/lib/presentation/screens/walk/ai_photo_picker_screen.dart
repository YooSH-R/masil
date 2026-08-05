import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../domain/entities/walk_photo.dart';
import '../../viewmodels/walk_diary_view_model.dart';
import '../../viewmodels/walk_photo_view_model.dart';
import '../../widgets/walk_photo_image.dart';

/// 마실이가 만들어 준 감성 사진 중 마음에 드는 것을 골라 기기에 저장하는 화면.
///
/// 스타일(지브리풍·스케치…)을 사용자가 고르지 않는다. 서버가 여러 느낌으로
/// 알아서 만들어 여러 장을 내려주고, 사용자는 그중에서 **고르기만** 한다.
/// 그래서 이 화면의 일은 두 가지다: 여러 장을 보여주기, 고른 것을 저장하기.
///
/// 사진은 [WalkDiary.photos] 에서 온다. `/photos/{id}/content` 는 인증이
/// 필요해서 URL 로 바로 그리지 못하고, [WalkPhotoViewModel] 이 바이트를 받아
/// 캐시해 둔 것을 쓴다(저장할 때 그 바이트를 그대로 재사용한다).
class AiPhotoPickerScreen extends StatefulWidget {
  const AiPhotoPickerScreen({super.key, this.walkId});

  /// 어떤 산책의 사진인지. null 이면 이미 불러와 둔 산책일지 상세를 쓴다.
  final int? walkId;

  @override
  State<AiPhotoPickerScreen> createState() => _AiPhotoPickerScreenState();
}

class _AiPhotoPickerScreenState extends State<AiPhotoPickerScreen> {
  /// 사용자가 고른 photoId.
  final Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// 일지 상세를 불러온다. 사진 바이트는 각 칸([WalkPhotoImage])이 알아서 받는다.
  ///
  /// 아직 만들어지는 중이면 완성될 때까지 지켜본다. 이 폴링은 화면을 떠나도
  /// 이어진다(완성되거나 시간이 초과되면 스스로 멈춘다) — 그래야 잠깐 나갔다
  /// 돌아왔을 때 사진이 준비돼 있다.
  Future<void> _load() async {
    if (!mounted) return;
    final diaryVm = context.read<WalkDiaryViewModel>();

    final walkId = widget.walkId;
    if (walkId != null && diaryVm.detail?.walkId != walkId) {
      await diaryVm.loadDetail(walkId);
    }
    if (!mounted) return;

    final id = walkId ?? diaryVm.detail?.walkId;
    if (id != null && diaryVm.isDiaryGenerating) {
      diaryVm.startWatchingDiary(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final diaryVm = context.watch<WalkDiaryViewModel>();
    final photoVm = context.watch<WalkPhotoViewModel>();
    final photos = diaryVm.detail?.photos ?? const <WalkPhoto>[];

    return Scaffold(
      backgroundColor: const Color(0xFFF9F3E7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Color(0xFF5D4037)),
          onPressed: () => context.pop(),
        ),
        title: const Text('감성 사진 고르기 ✨',
            style: TextStyle(
                color: Color(0xFF5D4037), fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: diaryVm.isLoading && photos.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFFC67C4E)))
                  : photos.isEmpty
                      ? _EmptyPhotos(
                          isGenerating: diaryVm.isDiaryGenerating,
                          hasFailed: diaryVm.hasDiaryFailed,
                          onRetry: _retry,
                        )
                      // 사진이 한 장이면 고를 게 없다. 크게 보여주고 저장만
                      // 하게 한다. AI 파이프라인이 여러 삽화를 **한 장으로
                      // 합쳐서**(story_image.png) 올리기 때문에 지금은 이 경우다.
                      // 개별 삽화가 올라오게 되면 자동으로 그리드로 바뀐다.
                      : photos.length == 1
                          ? _buildSingle(photos.first)
                          : _buildGrid(photos, photoVm),
            ),
            _buildSaveBar(photoVm, photos),
          ],
        ),
      ),
    );
  }

  /// 사진이 한 장일 때. 고르는 단계 없이 크게 보여주고 저장만 한다.
  ///
  /// AI 파이프라인(05_AI)이 삽화 4장을 스토리보드 한 장으로 합성해서
  /// `story_image.png` 하나만 올린다. 그래서 실제로는 이 경로를 탄다.
  Widget _buildSingle(WalkPhoto photo) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      children: [
        const Text(
          '마실이가 오늘 산책을 그림으로 남겼어요.\n마음에 들면 기기에 저장해 보세요',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF8D6E63), fontSize: 16, height: 1.5),
        ),
        const SizedBox(height: 24),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFFFDF7F0),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFF0E0D0)),
          ),
          // 스토리보드는 세로로 길 수 있어 비율을 고정하지 않는다.
          constraints: const BoxConstraints(minHeight: 220),
          child: WalkPhotoImage(photo: photo, fit: BoxFit.contain),
        ),
        if (photo.caption != null && photo.caption!.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            photo.caption!,
            style: const TextStyle(
                color: Color(0xFF5D4037), fontSize: 14, height: 1.5),
          ),
        ],
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildGrid(List<WalkPhoto> photos, WalkPhotoViewModel photoVm) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      children: [
        const Text(
          '마실이가 여러 느낌으로 만들어 봤어요.\n마음에 드는 사진을 골라 저장해 보세요',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF8D6E63), fontSize: 16, height: 1.5),
        ),
        const SizedBox(height: 24),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: photos.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            // 사진(정사각) + 아래 문구 한두 줄이 들어갈 만큼.
            childAspectRatio: 0.78,
          ),
          itemBuilder: (context, index) {
            final photo = photos[index];
            return _PhotoTile(
              photo: photo,
              isSelected: _selected.contains(photo.photoId),
              onTap: () => _toggle(photo),
            );
          },
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  /// 실패했을 때 다시 기다려 본다. 서버가 그동안 끝냈을 수도 있다.
  Future<void> _retry() async {
    final diaryVm = context.read<WalkDiaryViewModel>();
    final id = widget.walkId ?? diaryVm.detail?.walkId;
    if (id == null) return;

    await diaryVm.loadDetail(id);
    if (!mounted) return;
    if (diaryVm.isDiaryGenerating) diaryVm.startWatchingDiary(id);
  }

  /// 아직 만들어지는 중인 사진은 고를 수 없다.
  void _toggle(WalkPhoto photo) {
    if (photo.processingStatus.isPending) return;

    setState(() {
      if (!_selected.remove(photo.photoId)) _selected.add(photo.photoId);
    });
  }

  Widget _buildSaveBar(WalkPhotoViewModel photoVm, List<WalkPhoto> photos) {
    // 한 장뿐이면 고르는 단계가 없다. 그 한 장을 바로 저장 대상으로 삼는다.
    final isSingle = photos.length == 1;
    final targets = isSingle
        ? <int>[photos.first.photoId]
        : _selected.toList(growable: false);

    // 아직 만들어지는 중인 사진은 내려받을 수 없다.
    final ready = !isSingle || !photos.first.processingStatus.isPending;
    final canSave = targets.isNotEmpty && ready && !photoVm.isSaving;

    final label = isSingle
        ? (ready ? '기기에 저장하기' : '아직 만들고 있어요')
        : (_selected.isEmpty ? '사진을 골라 주세요' : '선택한 ${_selected.length}장 저장하기');

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: SizedBox(
        width: double.infinity,
        height: 64,
        child: ElevatedButton(
          onPressed: canSave ? () => _save(photoVm, targets) : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFC67C4E),
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFFE0D5C8),
            disabledForegroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            elevation: 0,
          ),
          child: photoVm.isSaving
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.download_outlined, size: 20),
                    const SizedBox(width: 12),
                    Text(
                      label,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _save(WalkPhotoViewModel photoVm, List<int> photoIds) async {
    final summary = await photoVm.saveToGallery(photoIds);
    if (!mounted) return;

    // 저장에 성공한 사진은 선택을 풀어 둔다. 같은 사진을 또 저장하는 실수를 막고,
    // 실패한 것만 남아 다시 시도하기 쉽다.
    // (한 장짜리는 _selected 를 쓰지 않으므로 비우기만 하면 된다)
    if (summary.allSaved && _selected.isNotEmpty) setState(_selected.clear);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(summary.message),
        backgroundColor:
            summary.noneSaved ? const Color(0xFFD32F2F) : const Color(0xFF5D4037),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// 사진 한 칸. 탭하면 선택/해제된다.
class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.photo,
    required this.isSelected,
    required this.onTap,
  });

  final WalkPhoto photo;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isPending = photo.processingStatus.isPending;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: const Color(0xFFFDF7F0),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFFC67C4E)
                      : const Color(0xFFF0E0D0),
                  width: isSelected ? 3 : 1,
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  WalkPhotoImage(photo: photo),
                  if (isSelected)
                    const Positioned(
                      top: 8,
                      right: 8,
                      child: _SelectedBadge(),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isPending ? photo.processingStatus.label : (photo.caption ?? ''),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              height: 1.3,
              color: isPending ? const Color(0xFFC67C4E) : const Color(0xFF8D6E63),
              fontWeight: isPending ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

}

class _SelectedBadge extends StatelessWidget {
  const _SelectedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: const BoxDecoration(
          color: Color(0xFFC67C4E), shape: BoxShape.circle),
      child: const Icon(Icons.check, color: Colors.white, size: 16),
    );
  }
}

/// 사진이 아직 없을 때. 세 가지 경우를 구분해서 보여준다.
///
/// 이 구분이 중요하다. 산책이 끝난 직후에는 서버가 영상에서 사진을 뽑는 중이라
/// 일지가 없는 게 정상인데, 이걸 "없음"이나 "오류"로 보여주면 사용자는 기능이
/// 고장난 줄 안다.
class _EmptyPhotos extends StatelessWidget {
  const _EmptyPhotos({
    required this.isGenerating,
    required this.hasFailed,
    required this.onRetry,
  });

  final bool isGenerating;
  final bool hasFailed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final (title, body) = switch ((isGenerating, hasFailed)) {
      (_, true) => (
          '일지를 만들지 못했어요',
          'AI 생성이 시간을 초과했어요.\n산책 기록은 그대로 저장돼 있어요',
        ),
      (true, _) => (
          '감성 사진을 만들고 있어요',
          '마실이가 찍은 장면을 고르는 중이에요.\n조금만 기다려 주세요',
        ),
      _ => (
          '아직 감성 사진이 없어요',
          '산책이 끝나면 마실이가 찍은 장면으로\n사진을 만들어 둘 거예요',
        ),
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                  color: Colors.white, shape: BoxShape.circle),
              child: isGenerating && !hasFailed
                  ? const SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(
                          color: Color(0xFFC67C4E), strokeWidth: 3),
                    )
                  : const Icon(Icons.auto_awesome,
                      color: Color(0xFFC67C4E), size: 36),
            ),
            const SizedBox(height: 24),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF5D4037))),
            const SizedBox(height: 12),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Color(0xFF8D6E63), fontSize: 14, height: 1.5),
            ),
            if (hasFailed) ...[
              const SizedBox(height: 32),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('다시 시도'),
                style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFC67C4E)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
