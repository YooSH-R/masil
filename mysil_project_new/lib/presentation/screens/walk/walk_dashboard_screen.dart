import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../viewmodels/walk_diary_view_model.dart';

/// 산책 리포트. 일/주/월 집계와 요일별 거리를 보여준다.
///
/// 값은 산책일지 피드에서 계산한다. 지금 그 피드는 **기기에 저장한 산책**과
/// 7월 예시 데이터로 채워진다(서버에 산책 API 가 없다 — [WalkRecordStore] 참고).
/// 서버 기록이 들어오면 같은 계산이 그대로 적용된다.
class WalkDashboardScreen extends StatefulWidget {
  const WalkDashboardScreen({super.key});

  /// 주간 목표 거리(m). 서버에 목표 설정이 없어 앱이 정한 값이다.
  static const int weeklyGoalMeters = 15000;

  @override
  State<WalkDashboardScreen> createState() => _WalkDashboardScreenState();
}

class _WalkDashboardScreenState extends State<WalkDashboardScreen> {
  int _selectedTab = 1; // 0: 일, 1: 주, 2: 월

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final diaryVm = context.read<WalkDiaryViewModel>();
      // 집계는 피드에서 계산한다. 아직 안 불렀으면 지금 불러온다.
      if (diaryVm.feed.isEmpty) diaryVm.loadFeed();
    });
  }

  @override
  Widget build(BuildContext context) {
    final diaryVm = context.watch<WalkDiaryViewModel>();
    final now = DateTime.now();

    final stats = switch (_selectedTab) {
      0 => diaryVm.statsForDay(now),
      2 => diaryVm.statsForMonth(now),
      _ => diaryVm.statsForWeek(now),
    };

    // 요일별 막대는 항상 "이번 주" 기준이다(탭과 무관하게 주간 분포를 본다).
    final weekMeters = diaryVm.weekdayMeters(now);
    final weekStats = diaryVm.statsForWeek(now);

    return Scaffold(
      backgroundColor: const Color(0xFFF9F3E7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Color(0xFF5D4037)),
          onPressed: () => context.pop(),
        ),
        title: const Text('산책 리포트', style: TextStyle(color: Color(0xFF5D4037), fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
        child: Column(
          children: [
            // Custom Tab Bar
            Container(
              height: 60,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: const Color(0xFFEFE5D8), borderRadius: BorderRadius.circular(20)),
              child: Row(
                children: [
                  _buildTabItem(0, '일'),
                  _buildTabItem(1, '주'),
                  _buildTabItem(2, '월'),
                ],
              ),
            ),
            const SizedBox(height: 32),
            
            // Stats Grid — 선택한 기간의 실제 집계
            Row(
              children: [
                _buildSmallStatCard(
                    (stats.totalMeters / 1000).toStringAsFixed(1), '거리 (km)'),
                const SizedBox(width: 16),
                _buildSmallStatCard(_hourMinute(stats.totalSeconds), '시간'),
                const SizedBox(width: 16),
                _buildSmallStatCard('${stats.count}', '횟수'),
              ],
            ),
            const SizedBox(height: 24),

            // 기록이 없으면 그래프·목표 대신 안내만 보여준다.
            // 0km 옆에 빈 그래프를 두면 데이터를 못 불러온 것처럼 보인다.
            if (stats.count == 0)
              const _NoRecordNotice()
            else ...[
            // Bar Chart Section
            _buildWhiteCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('요일별 거리', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF5D4037))),
                  const SizedBox(height: 32),
                  SizedBox(
                    height: 180,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // 가장 많이 걸은 요일을 100% 로 두고 나머지를 비례로 그린다.
                        // 절대 기준이 없으면 하루만 걸었을 때 막대가 안 보인다.
                        for (var i = 0; i < 7; i++)
                          _buildBar(
                            _weekdayLabels[i],
                            _barRatio(weekMeters, i),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Goal Progress
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(25)),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('이번 주 목표', style: TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        RichText(
                          text: TextSpan(
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF5D4037)),
                            children: [
                              TextSpan(
                                  text:
                                      '${(WalkDashboardScreen.weeklyGoalMeters / 1000).toStringAsFixed(0)}km 중 '),
                              TextSpan(
                                  text:
                                      '${(weekStats.totalMeters / 1000).toStringAsFixed(1)}km 달성 ',
                                  style: const TextStyle(color: Color(0xFFC67C4E))),
                              const TextSpan(text: '👏'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 70,
                    height: 70,
                    child: Stack(
                      children: [
                        Center(
                          child: CircularProgressIndicator(
                            value: _goalRatio(weekStats.totalMeters),
                            strokeWidth: 8,
                            backgroundColor: Colors.white,
                            valueColor: AlwaysStoppedAnimation<Color>(const Color(0xFF558B2F).withValues(alpha: 0.6)),
                          ),
                        ),
                        Center(
                            child: Text(
                                '${(_goalRatio(weekStats.totalMeters) * 100).round()}%',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2E7D32)))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ],

            const SizedBox(height: 32),
            // Footer Note
            Container(
              padding: const EdgeInsets.all(16),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.grey, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '기간에 기록이 없으면 "아직 산책 기록이 없어요"를 표시하고, 비정상 GPS 값은 집계에서 자동 제외해요.',
                      style: TextStyle(color: Colors.grey, fontSize: 11, height: 1.4),
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

  static const List<String> _weekdayLabels = ['월', '화', '수', '목', '금', '토', '일'];

  /// `3:20` 형태. 1시간 미만이면 `0:45`.
  static String _hourMinute(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    return '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}';
  }

  /// 막대 높이 비율. 그 주에서 가장 많이 걸은 요일을 1.0 으로 둔다.
  static double _barRatio(List<int> weekMeters, int index) {
    final max = weekMeters.fold<int>(0, (a, b) => b > a ? b : a);
    if (max <= 0) return 0;
    return weekMeters[index] / max;
  }

  /// 주간 목표 달성률. 넘겨도 막대가 깨지지 않게 1.0 으로 자른다.
  static double _goalRatio(int weekMeters) {
    final ratio = weekMeters / WalkDashboardScreen.weeklyGoalMeters;
    return ratio.clamp(0.0, 1.0);
  }

  Widget _buildTabItem(int index, String label) {
    bool isSelected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFC67C4E) : Colors.transparent,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(color: isSelected ? Colors.white : Colors.grey, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSmallStatCard(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Column(
          children: [
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF5D4037))),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildBar(String day, double heightFactor) {
    return Column(
      children: [
        Expanded(
          child: FractionallySizedBox(
            heightFactor: heightFactor,
            child: Container(
              width: 35,
              decoration: BoxDecoration(
                color: heightFactor > 0.8 ? const Color(0xFFC67C4E) : const Color(0xFFEFE5D8),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(day, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildWhiteCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
      child: child,
    );
  }
}

/// 선택한 기간에 산책 기록이 없을 때.
///
/// 화면 아래 안내 문구가 약속하는 동작이다. 0km·0회 옆에 빈 그래프를 두면
/// 데이터를 못 불러온 것처럼 보인다.
class _NoRecordNotice extends StatelessWidget {
  const _NoRecordNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(25)),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
                color: Color(0xFFF9F3E7), shape: BoxShape.circle),
            child: const Icon(Icons.directions_walk,
                color: Color(0xFFC67C4E), size: 36),
          ),
          const SizedBox(height: 24),
          const Text('아직 산책 기록이 없어요',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF5D4037))),
          const SizedBox(height: 12),
          const Text(
            '마실이와 한 바퀴 다녀오면\n여기에 기록이 쌓여요',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Color(0xFF8D6E63), fontSize: 14, height: 1.5),
          ),
        ],
      ),
    );
  }
}
