import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../viewmodels/pet_view_model.dart';
import '../../viewmodels/walk_diary_view_model.dart';
import '../../viewmodels/walk_view_model.dart';

/// 산책이 끝난 직후의 요약.
///
/// 여기서부터 감성 일지가 만들어지기 시작한다(마실이가 찍은 영상에서 사진을
/// 뽑고 문구를 붙인다). 그래서 화면에 들어오면 일지 생성을 지켜보기 시작하고,
/// 체크리스트에 진행 상황을 그대로 보여준다.
class WalkSummaryScreen extends StatefulWidget {
  const WalkSummaryScreen({super.key});

  @override
  State<WalkSummaryScreen> createState() => _WalkSummaryScreenState();
}

class _WalkSummaryScreenState extends State<WalkSummaryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final walkVm = context.read<WalkViewModel>();
      final walkId = walkVm.currentWalk?.walkId ?? walkVm.summary?.walkId;
      if (walkId == null) return;

      if (walkVm.summary == null) walkVm.loadSummary(walkId);
      // 일지는 지금부터 만들어진다. 완성되면 체크리스트가 저절로 바뀐다.
      context.read<WalkDiaryViewModel>().startWatchingDiary(walkId);

      // 산책을 하면 친밀도가 오른다. GET /pets/{petId}/affinity 는 아직 배포되지
      // 않았지만, 미리 불러둬서 배포되는 순간 친밀도 카드가 그대로 뜬다.
      // (미배포 상태에서는 조용히 실패하고 카드는 숨은 채로 있는다)
      context.read<PetViewModel>().refreshAffinity();
    });
  }

  @override
  Widget build(BuildContext context) {
    final walkVm = context.watch<WalkViewModel>();
    final diaryVm = context.watch<WalkDiaryViewModel>();
    final petVm = context.watch<PetViewModel>();

    final summary = walkVm.summary;
    final walkId = walkVm.currentWalk?.walkId ?? summary?.walkId;

    // 서버 값이 있으면 그것을, 없으면 이 화면까지 들고 온 로컬 값을 쓴다.
    final distanceMeters = summary?.distanceMeters ?? walkVm.distanceMeters;
    final durationSeconds =
        summary?.durationSeconds ?? walkVm.elapsed.inSeconds;
    final pointCount = (summary?.route.isNotEmpty ?? false)
        ? summary!.route.length
        : walkVm.routePoints.length;

    final photoCount = diaryVm.detail?.photos.length ?? 0;
    final affinity = petVm.affinity;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F3E7),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
          child: Column(
            children: [
              // Top Badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(20)),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.home_outlined, color: Colors.green, size: 16),
                    SizedBox(width: 8),
                    Text('도킹 감지 · 산책 종료',
                        style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              Image.asset('assets/images/mysil_character.png', height: 180),
              const SizedBox(height: 24),
              const Text(
                '오늘 산책 완료!',
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF5D4037)),
              ),
              const SizedBox(height: 8),
              Text(
                _formatPeriod(summary?.startedAt, summary?.endedAt),
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),

              const SizedBox(height: 40),

              // 거리·시간·발자국. kcal 은 서버가 주지 않아서 발자국 수로 바꿨다
              // (있지도 않은 값을 그럴듯하게 보여주지 않는다).
              _buildWhiteCard(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildSummaryStat(
                        (distanceMeters / 1000).toStringAsFixed(2), '거리 (km)'),
                    Container(
                        width: 1, height: 40, color: Colors.grey.shade200),
                    _buildSummaryStat('${durationSeconds ~/ 60}', '시간 (분)'),
                    Container(
                        width: 1, height: 40, color: Colors.grey.shade200),
                    _buildSummaryStat('$pointCount', '발자국'),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 친밀도 카드는 실제 변화값이 있을 때만 보여준다.
              if (affinity != null && affinity.change != null) ...[
                _buildAffinityCard(
                  change: affinity.change!,
                  score: affinity.score,
                  reason: affinity.changeReason,
                ),
                const SizedBox(height: 16),
              ],

              // Checklist
              _buildWhiteCard(
                child: Column(
                  children: [
                    _buildCheckRow(
                      icon: pointCount > 0
                          ? Icons.check_circle_outline
                          : Icons.remove_circle_outline,
                      color: pointCount > 0 ? Colors.green : Colors.grey,
                      label: 'GPS 경로 저장',
                      status: '$pointCount 포인트',
                    ),
                    const SizedBox(height: 12),
                    _buildCheckRow(
                      icon: photoCount > 0
                          ? Icons.check_circle_outline
                          : Icons.refresh,
                      color: photoCount > 0
                          ? Colors.green
                          : const Color(0xFFC67C4E),
                      label: '산책 사진 정리',
                      status: photoCount > 0 ? '$photoCount장' : '고르는 중',
                    ),
                    const SizedBox(height: 12),
                    _buildCheckRow(
                      icon: _diaryIcon(diaryVm),
                      color: _diaryColor(diaryVm),
                      label: '감성 일지 생성',
                      status: _diaryStatusLabel(diaryVm),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(15)),
                child: const Row(
                  children: [
                    Icon(Icons.network_wifi, color: Colors.blue, size: 18),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text('영상 동기화는 Wi-Fi에 연결되면 자동으로 이어서 진행돼요.',
                          style: TextStyle(
                              color: Color(0xFF8D6E63), fontSize: 12)),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  // 감성 사진을 고르는 화면. 아직 만들어지는 중이면 거기서
                  // "만들고 있어요"를 보여주고 완성되면 사진이 채워진다.
                  onPressed: () =>
                      context.push('/walk/ai-photo', extra: walkId),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC67C4E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                  ),
                  child: const Text('감성 일지 보러 가기',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 60,
                child: TextButton(
                  onPressed: () =>
                      context.push('/walk/path-detail', extra: walkId),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF5D4037),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                  ),
                  child: const Text('경로 상세 보기',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // --- 감성 일지 진행 상태 ---

  String _diaryStatusLabel(WalkDiaryViewModel vm) {
    if (vm.hasDiaryFailed) return '만들지 못했어요';
    if (vm.isDiaryGenerating) return '만들고 있어요';
    return vm.detail == null ? '대기 중' : '완료';
  }

  IconData _diaryIcon(WalkDiaryViewModel vm) {
    if (vm.hasDiaryFailed) return Icons.error_outline;
    if (vm.isDiaryGenerating) return Icons.auto_awesome_outlined;
    return vm.detail == null
        ? Icons.auto_awesome_outlined
        : Icons.check_circle_outline;
  }

  Color _diaryColor(WalkDiaryViewModel vm) {
    if (vm.hasDiaryFailed) return Colors.redAccent;
    if (vm.isDiaryGenerating) return const Color(0xFFC67C4E);
    return vm.detail == null ? Colors.grey : Colors.green;
  }

  Widget _buildAffinityCard({
    required int change,
    required int score,
    String? reason,
  }) {
    final sign = change >= 0 ? '+' : '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: const Color(0xFFE8F5E9),
          borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          const Icon(Icons.favorite, color: Colors.redAccent, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('친밀도 $sign$change · ${score - change}% → $score%',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2E7D32))),
                if (reason != null) ...[
                  const SizedBox(height: 4),
                  Text(reason,
                      style: TextStyle(
                          color: const Color(0xFF2E7D32)
                              .withValues(alpha: 0.8),
                          fontSize: 13)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWhiteCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: child,
    );
  }

  Widget _buildSummaryStat(String value, String label) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF5D4037))),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
      ],
    );
  }

  Widget _buildCheckRow({
    required IconData icon,
    required Color color,
    required String label,
    required String status,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w500, fontSize: 15)),
          ],
        ),
        Text(status,
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }

  // --- 날짜·시간 표기 ---
  // intl 의 DateFormat 은 이 프로젝트에서 쓰지 않는다(로케일 초기화가 필요하고
  // 다른 화면도 직접 조립한다). 같은 방식으로 맞춘다.

  static const List<String> _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  /// `2026.07.27 (월) 오후 2:00 ~ 2:45`
  ///
  /// 시작·종료가 오전/오후를 넘나들면 끝 시각에도 붙여서 헷갈리지 않게 한다.
  static String _formatPeriod(DateTime? startedAt, DateTime? endedAt) {
    if (startedAt == null) return '';

    final start = startedAt.toLocal();
    final date = '${start.year}.${_two(start.month)}.${_two(start.day)} '
        '(${_weekdays[start.weekday - 1]})';
    final from = '${_meridiem(start)} ${_hourMinute(start)}';
    if (endedAt == null) return '$date $from';

    final end = endedAt.toLocal();
    final to = _meridiem(start) == _meridiem(end)
        ? _hourMinute(end)
        : '${_meridiem(end)} ${_hourMinute(end)}';
    return '$date $from ~ $to';
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _meridiem(DateTime t) => t.hour < 12 ? '오전' : '오후';
  static String _hourMinute(DateTime t) {
    final hour12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$hour12:${_two(t.minute)}';
  }
}
