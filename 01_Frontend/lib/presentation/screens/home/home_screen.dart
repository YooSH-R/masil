import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/korea_time.dart';
import '../../../core/utils/korean.dart';
import '../../../domain/entities/pet.dart';
import '../../../domain/entities/walk_progress.dart';
import '../../../domain/entities/walk_diary.dart';
import '../../viewmodels/notification_view_model.dart';
import '../../viewmodels/pet_view_model.dart';
import '../../viewmodels/walk_diary_view_model.dart';
import '../../viewmodels/walk_view_model.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
  }

  /// 홈 진입 시 필요한 조회를 한 번에 실행.
  Future<void> _loadAll() async {
    if (!mounted) return;
    final petVm = context.read<PetViewModel>();
    final walkVm = context.read<WalkViewModel>();
    final diaryVm = context.read<WalkDiaryViewModel>();
    final notificationVm = context.read<NotificationViewModel>();

    await Future.wait([
      petVm.loadCurrentPet(silent: true), // GET /pets/{petId}
      notificationVm.loadNotifications(refresh: true), // GET /notifications
    ]);
    if (!mounted || petVm.requiresDevicePairing) return;

    await Future.wait([
      walkVm.loadCurrentProposal(silent: true), // GET /walk-proposals/current
      diaryVm.loadFeed(refresh: true), // GET /walk-diaries
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final petVm = context.watch<PetViewModel>();
    final walkVm = context.watch<WalkViewModel>();
    final diaryVm = context.watch<WalkDiaryViewModel>();
    final unreadCount = context.watch<NotificationViewModel>().unreadCount;

    final nickname = petVm.petName;
    final affinity = petVm.affinity;
    final requiresPairing = petVm.requiresDevicePairing;

    // 아래 '최근 산책 일지' 섹션에 보여줄 가장 최근 한 건.
    final latestWalk =
        requiresPairing || diaryVm.feed.isEmpty ? null : diaryVm.feed.first;

    // 오늘 산책 횟수·누적 횟수·받은 리본을 산책 기록에서 함께 계산한다.
    // 친밀도 화면의 "받은 보상" 도 같은 계산을 쓴다([WalkProgress]).
    final progress = requiresPairing
        ? WalkProgress.none
        : WalkProgress.from(
            diaryVm.feed.map((item) => item.walkedAt).whereType<DateTime>(),
          );
    final dailyWalkGoal = petVm.pet?.dailyWalkCount ?? Pet.defaultDailyWalkCount;
    final goalReached = !requiresPairing && progress.todayCount >= dailyWalkGoal;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F3E7),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10),
          child: Column(
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Image.asset('assets/images/mysil_logo.png', height: 32),
                  GestureDetector(
                    onTap: () => context.push('/indoor/notifications'),
                    child: Stack(
                      children: [
                        const Icon(Icons.notifications_none,
                            color: Color(0xFF5D4037), size: 28),
                        // 읽지 않은 알림이 있을 때만 배지를 띄운다 (GET /notifications).
                        if (unreadCount > 0)
                          Positioned(
                            right: 2,
                            top: 2,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                  color: Colors.red, shape: BoxShape.circle),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Character & State
              Center(
                child: Column(
                  children: [
                    Image.asset('assets/images/mysil_character.png',
                        height: 220),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(nickname,
                            style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF5D4037))),
                        const SizedBox(width: 8),
                        const Icon(Icons.mood,
                            color: Color(0xFF8D6E63), size: 24),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            requiresPairing ? Icons.link_off : Icons.circle,
                            color: requiresPairing ? Colors.grey : Colors.green,
                            size: requiresPairing ? 16 : 10,
                          ),
                          const SizedBox(width: 8),
                          // 기분은 친밀도 응답의 mood(HAPPY/NEUTRAL/...)에서 가져온다.
                          Flexible(
                            child: Text(
                              requiresPairing
                                  ? '연결이 필요합니다'
                                  : affinity?.mood.homeMessage ??
                                      '마실이 상태를 불러오는 중...',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: requiresPairing
                                      ? Colors.grey
                                      : Colors.green,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Intimacy Card — GET /pets/{petId}/affinity
              GestureDetector(
                onTap: () => context.push(
                  requiresPairing ? '/user/robot-mgmt' : '/indoor/intimacy',
                ),
                child: _buildWhiteCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.favorite,
                                  color: Colors.redAccent, size: 18),
                              SizedBox(width: 8),
                              Text('친밀도',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                            ],
                          ),
                          Text(
                            affinity == null ? '-' : '${affinity.score}%',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFC67C4E)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius:
                            const BorderRadius.all(Radius.circular(10)),
                        child: LinearProgressIndicator(
                          value: affinity?.progress ?? 0,
                          minHeight: 12,
                          backgroundColor: const Color(0xFFF9F3E7),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFFC67C4E)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        requiresPairing
                            ? '연결이 필요합니다'
                            : affinity == null
                                ? '친밀도를 불러오는 중이에요'
                                : 'Lv.${affinity.level} · ${affinity.mood.label}',
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Stats Row
              Row(
                children: [
                  // 마실이가 산책을 조르는 중이면 카드를 눌러 바로 산책을
                  // 시작할 수 있게 한다(아래 '산책 시작' 메뉴와 같은 경로).
                  Expanded(
                    child: GestureDetector(
                      onTap: walkVm.hasProposal
                          ? () => _openFeature(
                              context, requiresPairing, '/walk/suggestion')
                          : null,
                      child: _buildWhiteCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              walkVm.hasProposal
                                  ? Icons.pets
                                  : Icons.timer_outlined,
                              color: walkVm.hasProposal
                                  ? const Color(0xFFC67C4E)
                                  : Colors.grey,
                              size: 24,
                            ),
                            const SizedBox(height: 8),
                            const Text('산책 제안',
                                style: TextStyle(
                                    color: Colors.grey, fontSize: 13)),
                            // GET /walk-proposals/current 결과에 따라 문구를 바꾼다.
                            Text(
                              requiresPairing
                                  ? '연결 필요'
                                  : walkVm.hasProposal
                                      ? '가고 싶어요!'
                                      : '쉬고 있어요',
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF5D4037)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // 눌러서 산책 리포트로. 목표는 펫 설정(하루 산책 횟수)이라
                  // 설정을 바꾸면 이 칸의 분모도 함께 바뀐다.
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _openFeature(
                          context, requiresPairing, '/walk/dashboard'),
                      child: _buildWhiteCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              goalReached
                                  ? Icons.check_circle_outline
                                  : Icons.directions_walk,
                              color: goalReached
                                  ? const Color(0xFF558B2F)
                                  : Colors.grey,
                              size: 24,
                            ),
                            const SizedBox(height: 8),
                            const Text('오늘의 산책',
                                style: TextStyle(
                                    color: Colors.grey, fontSize: 13)),
                            Text(
                              requiresPairing
                                  ? '연결 필요'
                                  : '${progress.todayCount} / $dailyWalkGoal회',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: goalReached
                                      ? const Color(0xFF558B2F)
                                      : const Color(0xFF5D4037)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Grid Menu
              Row(
                children: [
                  _buildMenuItem(
                      Icons.directions_walk,
                      '산책 시작',
                      Colors.red.shade50,
                      () => _openFeature(
                          context, requiresPairing, '/walk/suggestion')),
                  _buildMenuItem(
                      Icons.event_seat,
                      '실내놀이',
                      Colors.green.shade50,
                      () => _openFeature(
                          context, requiresPairing, '/indoor/play-request')),
                  _buildMenuItem(
                      Icons.book_outlined,
                      '산책일지',
                      Colors.blue.shade50,
                      () => _openFeature(context, requiresPairing, '/walk')),
                  // orange.shade50(#FFF3E0)은 홈 배경(#F9F3E7)과 거의 같은 색이라
                  // 타일이 묻혔다. 옆칸이 파란 계열이라 보라 계열로 띄운다.
                  _buildMenuItem(
                      Icons.auto_awesome,
                      'AI 사진',
                      Colors.deepPurple.shade50,
                      () => _openFeature(
                          context, requiresPairing, '/walk/ai-photo')),
                ],
              ),
              const SizedBox(height: 32),

              // Weather Banner
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9), // Light green
                  borderRadius: BorderRadius.circular(40),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_queue,
                        color: Color(0xFF455A64), size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            requiresPairing
                                ? '기기 연결이 필요해요'
                                : walkVm.hasProposal
                                    ? '$nickname${Korean.subject(nickname)} '
                                        '산책 가고 싶어 해요!'
                                    : '$nickname${Korean.subject(nickname)} '
                                        '지금은 쉬고 있어요',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2E7D32)),
                          ),
                          // 마실이가 조르는 말은 서버 제안 문구를 그대로 쓴다.
                          Text(
                            requiresPairing
                                ? '마이페이지에서 마실이 기기를 등록해 주세요'
                                : walkVm.proposal?.message ??
                                    '다음 산책 시간이 되면 알려드릴게요',
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF2E7D32)),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => _openFeature(
                        context,
                        requiresPairing,
                        '/walk/suggestion',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF558B2F),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                      ),
                      child: Text(
                        requiresPairing ? '연결하기' : '나가기',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Mission Card
              _buildWhiteCard(
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Row(
                            children: [
                              Icon(Icons.local_fire_department,
                                  color: Colors.orange, size: 20),
                              SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  '산책 미션',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _missionCounter(requiresPairing, progress),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, color: Colors.grey),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 리본 조건이 1·5·10·30·100회라 칸 수를 고정할 수 없다.
                    // 7칸짜리 눈금 대신 연속 진행 바를 쓴다.
                    ClipRRect(
                      borderRadius: const BorderRadius.all(Radius.circular(4)),
                      child: LinearProgressIndicator(
                        value: requiresPairing
                            ? 0
                            : progress.progressToNextRibbon,
                        minHeight: 8,
                        backgroundColor: const Color(0xFFF9F3E7),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFFC67C4E)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _missionMessage(requiresPairing, progress, nickname),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      '최근 산책 일지',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF5D4037)),
                    ),
                  ),
                  TextButton(
                      onPressed: () => context.go('/walk'),
                      child: const Text('전체 보기',
                          style: TextStyle(color: Color(0xFF8D6E63)))),
                ],
              ),
              // GET /walk-diaries 의 첫 항목
              if (latestWalk != null)
                _buildLogItem(context, latestWalk)
              else
                _buildEmptyLogItem(diaryVm.isLoading, requiresPairing),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  /// 산책 미션 카드 오른쪽의 `누적 / 다음 리본 조건` 표시.
  String _missionCounter(bool requiresPairing, WalkProgress progress) {
    if (requiresPairing) return '- / ${WalkProgress.catalog.first.requiredWalks}회';
    final next = progress.nextRibbon;
    if (next == null) return '${progress.totalCount}회';
    return '${progress.totalCount} / ${next.requiredWalks}회';
  }

  /// 산책 미션 카드 아래 안내 문구.
  ///
  /// 리본을 받을 조건과 지금 상태를 같은 문장에서 알려준다. 받은 리본은
  /// 친밀도 화면의 "받은 보상" 에서 모아 볼 수 있다.
  String _missionMessage(
    bool requiresPairing,
    WalkProgress progress,
    String nickname,
  ) {
    if (requiresPairing) {
      return '기기를 연결하면 산책 미션을 시작할 수 있어요';
    }
    final next = progress.nextRibbon;
    if (next == null) {
      return '리본을 모두 모았어요! $nickname${Korean.subject(nickname)} 아주 행복해요 🎀';
    }
    return '${progress.walksToNextRibbon}회 더 걸으면 ${next.name}을 받아요 ${next.emoji}';
  }

  Widget _buildWhiteCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }

  Widget _buildMenuItem(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 65,
              height: 65,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(20)),
              child: Icon(icon, color: const Color(0xFFC67C4E), size: 30),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Color(0xFF5D4037)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogItem(BuildContext context, WalkDiaryFeedItem item) {
    return GestureDetector(
      // 탭하면 GET /walks/{walkId}/diary 상세로 이동.
      onTap: () => context.push('/walk/path-detail', extra: item.walkId),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                  color: const Color(0xFFFDF7F0),
                  borderRadius: BorderRadius.circular(15)),
              child: const Icon(Icons.pets, color: Color(0xFFD7CCC8)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatWalkedAt(item.walkedAt),
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  Text(
                    item.summary ?? '산책 기록 · ${item.durationLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyLogItem(bool isLoading, bool requiresPairing) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: Text(
          requiresPairing
              ? '기기를 연결하면 산책 일지를 확인할 수 있어요'
              : isLoading
                  ? '산책 일지를 불러오는 중...'
                  : '아직 산책 일지가 없어요',
          style: const TextStyle(color: Colors.grey, fontSize: 13),
        ),
      ),
    );
  }

  void _openFeature(
    BuildContext context,
    bool requiresPairing,
    String location,
  ) {
    if (requiresPairing) {
      context.push('/user/robot-mgmt');
      return;
    }
    if (location == '/walk') {
      context.go(location);
    } else {
      context.push(location);
    }
  }

  /// 모델에서 이미 대한민국 벽시계 시각으로 변환된 walkedAt을 표시한다.
  String _formatWalkedAt(DateTime? walkedAt) {
    if (walkedAt == null) return '날짜 미상';

    final korea = walkedAt;
    final now = KoreaTime.now();
    final isToday = korea.year == now.year &&
        korea.month == now.month &&
        korea.day == now.day;

    final hour = korea.hour;
    final period = hour < 12 ? '오전' : '오후';
    final hour12 = hour % 12 == 0 ? 12 : hour % 12;
    final time = '$period $hour12시';

    if (isToday) return '오늘 $time';
    return '${korea.month}월 ${korea.day}일 $time';
  }
}
