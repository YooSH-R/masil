import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../viewmodels/walk_diary_view_model.dart';

/// 감성 일지 생성이 실패했을 때의 안내.
///
/// 마실이가 찍은 영상에서 사진을 뽑고 문구를 붙이는 데 시간이 걸리는데, 그게
/// 끝내 완성되지 않은 경우다. **산책 기록(경로·거리·시간)은 그대로 남아 있다**는
/// 점을 분명히 알려서, 산책 자체가 사라진 줄 오해하지 않게 한다.
///
/// `다시 만들기` 는 일지를 다시 조회하고 완성될 때까지 기다린다. 그동안 서버가
/// 끝냈을 수도 있어서 실제로 되살아나는 경우가 있다.
class WalkLogFailedScreen extends StatefulWidget {
  const WalkLogFailedScreen({super.key, this.walkId});

  /// 어떤 산책의 일지인지. null 이면 이미 불러와 둔 상세를 쓴다.
  final int? walkId;

  @override
  State<WalkLogFailedScreen> createState() => _WalkLogFailedScreenState();
}

class _WalkLogFailedScreenState extends State<WalkLogFailedScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final walkId = widget.walkId;
      final diaryVm = context.read<WalkDiaryViewModel>();
      if (walkId != null && diaryVm.detail?.walkId != walkId) {
        diaryVm.loadDetail(walkId);
      }
    });
  }

  Future<void> _retry() async {
    final diaryVm = context.read<WalkDiaryViewModel>();
    final id = widget.walkId ?? diaryVm.detail?.walkId;
    if (id == null) return;

    await diaryVm.loadDetail(id);
    if (!mounted) return;
    if (diaryVm.isDiaryGenerating) diaryVm.startWatchingDiary(id);
  }

  @override
  Widget build(BuildContext context) {
    final diaryVm = context.watch<WalkDiaryViewModel>();
    final diary = diaryVm.detail;
    final isGenerating = diaryVm.isDiaryGenerating;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F3E7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Color(0xFF5D4037)),
          onPressed: () => context.pop(),
        ),
        title: const Text('감성 일지',
            style: TextStyle(
                color: Color(0xFF5D4037), fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
        child: Column(
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30)),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(
                        color: Color(0xFFF9F3E7), shape: BoxShape.circle),
                    child: isGenerating
                        ? const SizedBox(
                            width: 40,
                            height: 40,
                            child: CircularProgressIndicator(
                                color: Color(0xFFC67C4E), strokeWidth: 3),
                          )
                        : const Icon(Icons.auto_awesome,
                            color: Color(0xFFC67C4E), size: 40),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    isGenerating ? '다시 만들고 있어요' : '일지를 만들지 못했어요',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF5D4037)),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isGenerating
                        ? '완성되면 이 화면이 바뀌어요.\n조금만 기다려 주세요.'
                        : 'AI 생성이 시간을 초과했어요.\n산책 기록은 그대로 저장돼 있어요.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Color(0xFF8D6E63), fontSize: 16, height: 1.5),
                  ),
                  const SizedBox(height: 48),
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton(
                      onPressed: isGenerating ? null : _retry,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFC67C4E),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFFE0D5C8),
                        disabledForegroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.refresh),
                          SizedBox(width: 8),
                          Text('다시 만들기',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 이 산책의 재료 — 무엇이 남아 있고 무엇이 없는지 실제 값으로 보여준다.
            _buildInfoCard(
              title: '이 산책의 재료',
              children: [
                _buildIngredientItem(
                  ok: (diary?.route.length ?? 0) > 0,
                  label: 'GPS 경로 ${diary?.route.length ?? 0} 포인트',
                ),
                const SizedBox(height: 12),
                _buildIngredientItem(
                  ok: (diary?.photos.length ?? 0) > 0,
                  label: '산책 사진 ${diary?.photos.length ?? 0}장',
                ),
                const SizedBox(height: 12),
                _buildIngredientItem(
                  ok: diary?.distanceMeters != null,
                  label: '성과 기록 '
                      '${diary?.distanceLabel ?? '-'} · ${diary?.durationLabel ?? '-'}',
                ),
              ],
            ),

            const SizedBox(height: 24),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.grey, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '영상과 GPS 기록이 모두 없으면 일지를 만들 수 없어요. 다음 산책에는 마실이가 영상을 담아올게요.',
                      style: TextStyle(
                          color: Colors.grey, fontSize: 11, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildIngredientItem({required bool ok, required String label}) {
    final color = ok ? Colors.green : Colors.redAccent;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: Icon(ok ? Icons.check : Icons.close, color: color, size: 14),
        ),
        const SizedBox(width: 12),
        Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w500))),
      ],
    );
  }

  Widget _buildInfoCard(
      {required String title, required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(25)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }
}
