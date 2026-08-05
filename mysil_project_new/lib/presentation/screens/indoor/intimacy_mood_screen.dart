import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../domain/entities/pet.dart';
import '../../viewmodels/pet_view_model.dart';

/// 친밀도 · 기분 화면.
///
/// **어디서 값이 오는가**: `GET /v1/pets/{petId}` 응답의 `affinity`
/// (`score`·`level`·`mood`)다. 명세서에 있는 `GET /pets/{petId}/affinity` 는
/// 아직 배포되지 않았지만(2026-08-03 확인), 펫 프로필 응답에 친밀도가 함께
/// 들어있어서 **지금 배포된 API 만으로도 실제 값을 보여줄 수 있다.**
///
/// [PetViewModel.affinity] 가 `_affinity ?? _pet?.affinity` 순으로 돌려주므로,
/// 전용 엔드포인트가 배포되면 이 화면은 손대지 않아도 그 값을 쓰게 된다.
///
/// 변화 이력(`/affinity/history`)은 아직 배포되지 않았다. 없는 값을 그럴듯하게
/// 지어내지 않고 "이력이 없다"고 알린다.
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
      // 아래 둘은 아직 미배포다. 조용히 실패하고, 배포되면 값이 채워진다.
      petVm.refreshAffinity();
      petVm.loadAffinityHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    final petVm = context.watch<PetViewModel>();
    final affinity = petVm.affinity;
    final history = petVm.affinityHistory;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F3E7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.chevron_left, color: Color(0xFF5D4037)),
            onPressed: () => context.pop()),
        title: const Text('친밀도 · 기분',
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
                  _buildHistoryCard(history),
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
    final isGood = mood == PetMood.happy || mood == PetMood.excited;
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
            decoration:
                const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
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
              if (!isFirst)
                Expanded(
                    child: Container(
                        height: 2,
                        color: isReached
                            ? const Color(0xFFC67C4E)
                            : Colors.grey.shade200)),
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
              if (!isLast)
                Expanded(
                    child: Container(
                        height: 2,
                        color: isNextReached
                            ? const Color(0xFFC67C4E)
                            : Colors.grey.shade200)),
            ],
          ),
          const SizedBox(height: 12),
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isReached ? const Color(0xFF5D4037) : Colors.grey)),
        ],
      ),
    );
  }

  /// 변화 이력. `/pets/{petId}/affinity/history` 가 배포되면 채워진다.
  Widget _buildHistoryCard(List<AffinityHistoryEntry> history) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(25)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('변화 이력',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 20),
          if (history.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('아직 기록된 변화가 없어요',
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
            )
          else
            for (var i = 0; i < history.length; i++) ...[
              if (i > 0) const Divider(height: 32),
              _buildHistoryItem(history[i]),
            ],
        ],
      ),
    );
  }

  Widget _buildHistoryItem(AffinityHistoryEntry entry) {
    final isUp = entry.change >= 0;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: const Color(0xFFF9F3E7),
              borderRadius: BorderRadius.circular(12)),
          child: Icon(isUp ? Icons.trending_up : Icons.trending_down,
              color: const Color(0xFFC67C4E), size: 18),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.reason ?? '친밀도 변화',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
              Text(_relativeTime(entry.recordedAt),
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ),
        Text('${isUp ? '+' : ''}${entry.change}',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isUp ? Colors.green : Colors.redAccent)),
      ],
    );
  }

  /// 기분에 맞는 이모지. 문구는 엔티티가, 그림은 화면이 정한다.
  static String _moodEmoji(PetMood mood) => switch (mood) {
        PetMood.happy => '🥰',
        PetMood.excited => '🤩',
        PetMood.neutral => '🙂',
        PetMood.lonely => '🥺',
        PetMood.sleeping => '😴',
      };

  /// 레벨 이름. 서버는 숫자만 주므로 표기는 앱이 정한다.
  static String _levelName(int level) => switch (level) {
        <= 1 => '씨앗',
        2 => '새싹',
        3 => '단짝 친구',
        _ => '영혼의 단짝',
      };

  static String _relativeTime(DateTime? at) {
    if (at == null) return '';
    final diff = DateTime.now().difference(at.toLocal());
    if (diff.inMinutes < 1) return '방금';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    return '${at.toLocal().month}월 ${at.toLocal().day}일';
  }
}
