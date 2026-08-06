import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/korea_time.dart';
import '../../../domain/entities/pet.dart';
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
      petVm.loadCurrentPet(silent: true),          // GET /pets/{petId}
      walkVm.loadCurrentProposal(silent: true),    // GET /walk-proposals/current
      diaryVm.loadFeed(refresh: true),             // GET /walk-diaries
      notificationVm.loadNotifications(refresh: true), // GET /notifications
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
    final latestWalk = diaryVm.feed.isEmpty ? null : diaryVm.feed.first;

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
                        const Icon(Icons.notifications_none, color: Color(0xFF5D4037), size: 28),
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
                    Image.asset('assets/images/mysil_character.png', height: 220),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(nickname, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF5D4037))),
                        const SizedBox(width: 8),
                        const Icon(Icons.mood, color: Color(0xFF8D6E63), size: 24),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.circle, color: Colors.green, size: 10),
                          const SizedBox(width: 8),
                          // 기분은 친밀도 응답의 mood(HAPPY/NEUTRAL/...)에서 가져온다.
                          Flexible(
                            child: Text(
                              affinity?.mood.homeMessage ?? '마실이 상태를 불러오는 중...',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.green,
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
                onTap: () => context.push('/indoor/intimacy'),
                child: _buildWhiteCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.favorite, color: Colors.redAccent, size: 18),
                              SizedBox(width: 8),
                              Text('친밀도',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 16)),
                            ],
                          ),
                          Text(
                            affinity == null ? '-' : '${affinity.score}%',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, color: Color(0xFFC67C4E)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: const BorderRadius.all(Radius.circular(10)),
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
                        affinity == null
                            ? '친밀도를 불러오는 중이에요'
                            : 'Lv.${affinity.level} · ${affinity.mood.label}',
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              // Stats Row
              Row(
                children: [
                  Expanded(
                    child: _buildWhiteCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.timer_outlined, color: Colors.grey, size: 24),
                          const SizedBox(height: 8),
                          const Text('산책 제안',
                              style: TextStyle(color: Colors.grey, fontSize: 13)),
                          // GET /walk-proposals/current 결과에 따라 문구를 바꾼다.
                          Text(
                            walkVm.hasProposal ? '지금 가능!' : '대기 중',
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF5D4037)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildWhiteCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.directions_walk, color: Colors.grey, size: 24),
                          const SizedBox(height: 8),
                          const Text('최근 산책',
                              style: TextStyle(color: Colors.grey, fontSize: 13)),
                          // 걸음 수 API가 없어 최근 산책 거리로 대체한다.
                          Text(
                            latestWalk == null
                                ? '-'
                                : '${((latestWalk.distanceMeters ?? 0) / 1000).toStringAsFixed(1)}km',
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF5D4037)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              
              // Grid Menu
              Row(
                children: [
                  _buildMenuItem(Icons.directions_walk, '산책 시작', Colors.red.shade50, () => context.push('/walk/suggestion')),
                  _buildMenuItem(Icons.event_seat, '실내놀이', Colors.green.shade50, () => context.push('/indoor/play-request')),
                  _buildMenuItem(Icons.book_outlined, '산책일지', Colors.blue.shade50, () => context.go('/walk')),
                  _buildMenuItem(Icons.auto_awesome, 'AI 사진', Colors.orange.shade50, () => context.push('/walk/ai-photo')),
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
                    const Icon(Icons.cloud_queue, color: Color(0xFF455A64), size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            walkVm.hasProposal ? '지금 산책하기 좋아요!' : '산책 제안을 기다리고 있어요',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, color: Color(0xFF2E7D32)),
                          ),
                          // 제안 이유(SCHEDULE_AND_WEATHER 등)를 보조 문구로 노출.
                          Text(
                            walkVm.proposal?.reason ?? '언제든 산책을 시작할 수 있어요',
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF2E7D32)),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => context.push('/walk/suggestion'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF558B2F),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                      ),
                      child: const Text('나가기', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              
              // Mission Card
              _buildWhiteCard(
                child: Column(
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Icon(Icons.local_fire_department, color: Colors.orange, size: 20),
                              SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  '연속 산책 미션',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: 8),
                        Text('3 / 7일', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: List.generate(7, (index) {
                        return Expanded(
                          child: Container(
                            height: 8,
                            margin: EdgeInsets.only(right: index == 6 ? 0 : 6),
                            decoration: BoxDecoration(
                              color: index < 3 ? const Color(0xFFC67C4E) : const Color(0xFFF9F3E7),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '7일 달성하면 마실이가 새 리본을 선물해요 🎀',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 12),
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
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF5D4037)),
                    ),
                  ),
                  TextButton(onPressed: () => context.go('/walk'), child: const Text('전체 보기', style: TextStyle(color: Color(0xFF8D6E63)))),
                ],
              ),
              // GET /walk-diaries 의 첫 항목
              if (latestWalk != null)
                _buildLogItem(context, latestWalk)
              else
                _buildEmptyLogItem(diaryVm.isLoading),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
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

  Widget _buildMenuItem(IconData icon, String label, Color color, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 65,
              height: 65,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
              child: Icon(icon, color: const Color(0xFFC67C4E), size: 30),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF5D4037)),
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
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(color: const Color(0xFFFDF7F0), borderRadius: BorderRadius.circular(15)),
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
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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

  Widget _buildEmptyLogItem(bool isLoading) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: Text(
          isLoading ? '산책 일지를 불러오는 중...' : '아직 산책 일지가 없어요',
          style: const TextStyle(color: Colors.grey, fontSize: 13),
        ),
      ),
    );
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
