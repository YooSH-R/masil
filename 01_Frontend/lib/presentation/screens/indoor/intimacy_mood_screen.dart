import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/korean.dart';
import '../../../domain/entities/pet.dart';
import '../../../domain/entities/walk_progress.dart';
import '../../viewmodels/pet_view_model.dart';
import '../../viewmodels/walk_diary_view_model.dart';

/// 친밀도 상세 화면.
///
/// **어디서 값이 오는가**: `GET /v1/pets/{petId}` 응답의 `affinity`
/// (`score`·`level`·`mood`)다. 명세서에 있는 `GET /pets/{petId}/affinity` 는
/// 아직 배포되지 않았지만(2026-08-03 확인), 펫 프로필 응답에 친밀도가 함께
/// 들어있어서 **지금 배포된 API 만으로도 실제 값을 보여줄 수 있다.**
///
/// [PetViewModel.affinity] 가 `_affinity ?? _pet?.affinity` 순으로 돌려주므로,
/// 전용 엔드포인트가 배포되면 이 화면은 손대지 않아도 그 값을 쓰게 된다.
///
class IntimacyMoodScreen extends StatefulWidget {
  const IntimacyMoodScreen({super.key});

  @override
  State<IntimacyMoodScreen> createState() => _IntimacyMoodScreenState();
}

class _IntimacyMoodScreenState extends State<IntimacyMoodScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final petVm = context.read<PetViewModel>();

      // 펫 프로필에 친밀도가 함께 온다. 이게 지금 유일하게 배포된 경로다.
      if (petVm.pet == null) {
        petVm.loadCurrentPet(silent: true);
      }
      // 전용 친밀도 API가 배포되면 최신 값으로 덮어쓴다.
      petVm.refreshAffinity();

      // 받은 보상은 산책 기록에서 계산한다. 홈을 거치지 않고 이 화면으로
      // 바로 들어오는 경우가 있어 여기서도 한 번 불러온다.
      final diaryVm = context.read<WalkDiaryViewModel>();
      if (diaryVm.feed.isEmpty) {
        diaryVm.loadFeed(refresh: true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final petVm = context.watch<PetViewModel>();
    final affinity = petVm.affinity;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F3E7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.chevron_left, color: Color(0xFF5D4037)),
            onPressed: () => context.pop()),
        title: const Text('친밀도',
            style: TextStyle(
                color: Color(0xFF5D4037), fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: affinity == null
          ? _buildEmpty(petVm)
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  _buildGaugeCard(affinity),
                  const SizedBox(height: 24),
                  _buildMoodBanner(affinity.mood),
                  const SizedBox(height: 24),
                  _buildEvolutionCard(affinity.level),
                  const SizedBox(height: 24),
                  _buildRewardCard(petVm.petName),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  /// 펫이 없거나 아직 못 불러왔을 때.
  Widget _buildEmpty(PetViewModel petVm) {
    if (petVm.isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFFC67C4E)));
    }

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
              child: const Icon(Icons.favorite_border,
                  color: Color(0xFFC67C4E), size: 36),
            ),
            const SizedBox(height: 24),
            const Text('아직 친밀도가 없어요',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF5D4037))),
            const SizedBox(height: 12),
            const Text(
              '펫을 등록하면 마실이와 쌓아 온\n친밀도를 볼 수 있어요',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Color(0xFF8D6E63), fontSize: 14, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGaugeCard(Affinity affinity) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(30)),
      child: Column(
        children: [
          SizedBox(
            width: 180,
            height: 180,
            child: Stack(
              children: [
                Center(
                  child: SizedBox(
                    width: 160,
                    height: 160,
                    child: CircularProgressIndicator(
                      value: affinity.progress,
                      strokeWidth: 12,
                      backgroundColor: const Color(0xFFF9F3E7),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFFC67C4E)),
                    ),
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_moodEmoji(affinity.mood),
                          style: const TextStyle(fontSize: 32)),
                      Text('${affinity.score}%',
                          style: const TextStyle(
                              fontSize: 42,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF5D4037))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
                color: const Color(0xFFFFF1F0),
                borderRadius: BorderRadius.circular(20)),
            child: Text(
              '레벨 ${affinity.level} · ${_levelName(affinity.level)}',
              style: const TextStyle(
                  color: Color(0xFFC67C4E), fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMoodBanner(PetMood mood) {
    final isGood = mood == PetMood.happy || mood == PetMood.friendly;
    final bg = isGood ? const Color(0xFFE8F5E9) : const Color(0xFFFDF7F0);
    final fg = isGood ? const Color(0xFF2E7D32) : const Color(0xFF8D6E63);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(25)),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
                color: Colors.white, shape: BoxShape.circle),
            child: Text(_moodEmoji(mood), style: const TextStyle(fontSize: 24)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(mood.homeMessage,
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16, color: fg)),
                Text(mood.label, style: TextStyle(color: fg, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 친밀도 단계. [level] 까지 도달한 것으로 칠한다.
  Widget _buildEvolutionCard(int level) {
    const steps = [
      ('씨앗', '🌱'),
      ('새싹', '🌿'),
      ('단짝', '🐻'),
      ('영혼', '❤️'),
    ];

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(25)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('친밀도 단계',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < steps.length; i++)
                _buildEvolutionStep(
                  label: steps[i].$1,
                  icon: steps[i].$2,
                  isFirst: i == 0,
                  isLast: i == steps.length - 1,
                  // 단계는 1부터. level 3 이면 씨앗·새싹·단짝이 채워진다.
                  isReached: level >= i + 1,
                  // 다음 단계까지 이어진 선은 그 단계에 도달했을 때만 칠한다.
                  isNextReached: level >= i + 2,
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 산책 보상으로 받은 리본.
  ///
  /// 서버에 보상 API 가 없어서 산책 기록에서 계산한다([WalkProgress]). 홈의
  /// "산책 미션" 과 같은 계산을 쓰므로 두 화면의 숫자가 어긋나지 않는다.
  /// 아직 못 받은 리본도 흐리게 함께 보여줘서 무엇을 더 모을 수 있는지 알린다.
  Widget _buildRewardCard(String nickname) {
    final diaryVm = context.watch<WalkDiaryViewModel>();
    final progress = WalkProgress.from(
      diaryVm.feed.map((item) => item.walkedAt).whereType<DateTime>(),
    );
    final earnedCount = progress.earnedRibbons.length;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(25)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('받은 보상',
                  style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text('$earnedCount / ${progress.ribbons.length}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Color(0xFFC67C4E))),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            earnedCount == 0
                ? '산책을 다녀오면 $nickname${Korean.subject(nickname)} 리본을 선물해요'
                : '지금까지 ${progress.totalCount}번 산책했어요 · '
                    '최장 연속 ${progress.longestStreakDays}일',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 20),
          for (final ribbon in progress.ribbons) ...[
            _buildRibbonRow(ribbon),
            if (ribbon != progress.ribbons.last) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildRibbonRow(WalkRibbon ribbon) {
    final earned = ribbon.isEarned;
    return Opacity(
      // 못 받은 리본은 흐리게. 목록에서 빼면 목표가 안 보인다.
      opacity: earned ? 1 : 0.4,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: earned
                  ? const Color(0xFFFDF7F0)
                  : const Color(0xFFF5F5F5),
              shape: BoxShape.circle,
              border: Border.all(
                color: earned ? const Color(0xFFC67C4E) : Colors.grey.shade300,
              ),
            ),
            alignment: Alignment.center,
            child: Text(ribbon.emoji, style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ribbon.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Color(0xFF5D4037))),
                const SizedBox(height: 2),
                Text(
                  earned
                      ? '${_formatDay(ribbon.earnedOn!)} 획득'
                      : '산책 ${ribbon.requiredWalks}회 달성',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          Icon(
            earned ? Icons.check_circle : Icons.lock_outline,
            size: 20,
            color: earned ? const Color(0xFF558B2F) : Colors.grey,
          ),
        ],
      ),
    );
  }

  /// [WalkProgress] 가 돌려주는 한국 날짜는 UTC 객체에 담긴 벽시계 값이라
  /// 그대로 연·월·일만 읽는다.
  String _formatDay(DateTime day) =>
      '${day.year}년 ${day.month}월 ${day.day}일';

  Widget _buildEvolutionStep({
    required String label,
    required String icon,
    required bool isFirst,
    required bool isLast,
    required bool isReached,
    required bool isNextReached,
  }) {
    return Expanded(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 2,
                  color: isFirst
                      ? Colors.transparent
                      : isReached
                          ? const Color(0xFFC67C4E)
                          : Colors.grey.shade200,
                ),
              ),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isReached
                      ? const Color(0xFFC67C4E)
                      : const Color(0xFFFDF7F0),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Center(
                    child: Text(icon, style: const TextStyle(fontSize: 20))),
              ),
              Expanded(
                child: Container(
                  height: 2,
                  color: isLast
                      ? Colors.transparent
                      : isNextReached
                          ? const Color(0xFFC67C4E)
                          : Colors.grey.shade200,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 32,
            child: Center(
              child: Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.2,
                  fontWeight: FontWeight.bold,
                  color: isReached ? const Color(0xFF5D4037) : Colors.grey,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 관계 단계에 맞는 이모지.
  static String _moodEmoji(PetMood mood) => switch (mood) {
        PetMood.wary => '🥺',
        PetMood.calm => '🙂',
        PetMood.friendly => '😊',
        PetMood.happy => '🥰',
      };

  /// 레벨 이름. 서버는 숫자만 주므로 표기는 앱이 정한다.
  static String _levelName(int level) => switch (level) {
        <= 1 => '씨앗',
        2 => '새싹',
        3 => '단짝 친구',
        _ => '영혼의 단짝',
      };
}
