import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/services/sample_walk_diaries.dart';
import '../../../domain/entities/walk_diary.dart';
import '../../viewmodels/walk_diary_view_model.dart';

/// 산책 일지. GET /walk-diaries 로 받은 기록을 달력에 표시하고,
/// 날짜를 누르면 그 날의 장소·거리·시간을 보여준다.
class WalkLogFeedScreen extends StatefulWidget {
  const WalkLogFeedScreen({super.key});

  @override
  State<WalkLogFeedScreen> createState() => _WalkLogFeedScreenState();
}

class _WalkLogFeedScreenState extends State<WalkLogFeedScreen> {
  late int _currentMonth;
  late int _currentYear;
  late DateTime _selectedDate;
  bool _isWeekly = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentYear = now.year;
    _currentMonth = now.month;
    _selectedDate = DateTime(now.year, now.month, now.day);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<WalkDiaryViewModel>().loadFeed(refresh: true);
    });
  }

  /// 날짜를 누르면 그 날 산책의 상세(경로)와 장소명을 불러온다.
  void _selectDate(DateTime date) {
    setState(() => _selectedDate = date);

    final diaryVm = context.read<WalkDiaryViewModel>();
    final item = diaryVm.itemOn(date);
    if (item != null) diaryVm.selectWalk(item.walkId);
  }


  @override
  Widget build(BuildContext context) {
    final diaryVm = context.watch<WalkDiaryViewModel>();

    final walkDays = diaryVm.byDate.keys.toSet();
    final selectedItem = diaryVm.itemOn(_selectedDate);
    final placeName =
        selectedItem == null ? null : diaryVm.placeNameOf(selectedItem.walkId);

    final monthLogCount = walkDays
        .where((d) => d.year == _currentYear && d.month == _currentMonth)
        .length;

    // 주간은 선택한 날이 속한 주, 월간은 보고 있는 달 기준으로 집계한다.
    final stats = _isWeekly
        ? diaryVm.statsForWeek(_selectedDate)
        : diaryVm.statsForMonth(DateTime(_currentYear, _currentMonth));

    return Scaffold(
      backgroundColor: const Color(0xFFF9F3E7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 20),
          child: Image.asset('assets/images/mysil_logo.png'),
        ),
        leadingWidth: 100,
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_none, color: Color(0xFF5D4037))),
          const SizedBox(width: 12),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10),
        child: Column(
          children: [
            // Month Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, color: Colors.grey),
                  onPressed: _prevMonth,
                ),
                Text(
                  '$_currentYear년 ${_currentMonth.toString().padLeft(2, '0')}월 산책 일지',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF5D4037)),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, color: Colors.grey),
                  onPressed: _nextMonth,
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // Full Month Calendar
            _buildMonthlyCalendar(walkDays),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                const Icon(Icons.circle, color: Color(0xFFC67C4E), size: 10),
                const SizedBox(width: 8),
                Text('일지가 있는 날 · 총 $monthLogCount편', style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 24),

            // 선택한 날의 장소·거리·시간
            if (selectedItem != null)
              _buildDailySummaryCard(selectedItem, placeName)
            else
              _buildEmptySummaryCard(),

            const SizedBox(height: 32),

            // Stats Section
            _buildSectionHeader(_isWeekly ? '이번 주 산책 통계' : '이번 달 산책 통계'),
            const SizedBox(height: 16),
            _buildStatsGrid(stats),
            const SizedBox(height: 32),

            // Detailed View for Selected Day
            if (selectedItem != null)
              _buildLogPost(context, selectedItem, placeName)
            else
              _buildEmptyState(),
            
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  void _prevMonth() {
    setState(() {
      if (_currentMonth == 1) {
        _currentMonth = 12;
        _currentYear--;
      } else {
        _currentMonth--;
      }
      _selectedDate = DateTime(_currentYear, _currentMonth, 1);
    });
  }

  void _nextMonth() {
    setState(() {
      if (_currentMonth == 12) {
        _currentMonth = 1;
        _currentYear++;
      } else {
        _currentMonth++;
      }
      _selectedDate = DateTime(_currentYear, _currentMonth, 1);
    });
  }

  /// [walkDays] 는 산책 기록이 있는 날짜(시각 제거) 집합.
  Widget _buildMonthlyCalendar(Set<DateTime> walkDays) {
    final firstDayOfMonth = DateTime(_currentYear, _currentMonth, 1);
    final lastDayOfMonth = DateTime(_currentYear, _currentMonth + 1, 0);
    final daysInMonth = lastDayOfMonth.day;
    final startWeekday = firstDayOfMonth.weekday % 7; // 0: Sun, 1: Mon...

    final labels = ['일', '월', '화', '수', '목', '금', '토'];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 5)),
        ],
      ),
      child: Column(
        children: [
          // Weekday Labels
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: labels.map((l) => Expanded(
              child: Center(
                child: Text(
                  l,
                  style: TextStyle(
                    color: l == '일' ? Colors.red : (l == '토' ? Colors.blue : Colors.grey),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            )).toList(),
          ),
          const SizedBox(height: 15),
          // Days Grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
            ),
            itemCount: daysInMonth + startWeekday,
            itemBuilder: (context, index) {
              if (index < startWeekday) return const SizedBox();
              
              final day = index - startWeekday + 1;
              final date = DateTime(_currentYear, _currentMonth, day);

              bool isSelected = _selectedDate.year == date.year && _selectedDate.month == date.month && _selectedDate.day == date.day;
              bool hasLog = walkDays.contains(date);
              bool isToday = DateTime.now().year == date.year && DateTime.now().month == date.month && DateTime.now().day == date.day;

              return GestureDetector(
                onTap: () => _selectDate(date),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (isSelected)
                      Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(color: Color(0xFFC67C4E), shape: BoxShape.circle),
                      )
                    else if (isToday)
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFC67C4E), width: 1),
                          shape: BoxShape.circle,
                        ),
                      ),
                    Text(
                      day.toString(),
                      style: TextStyle(
                        color: isSelected ? Colors.white : (hasLog ? const Color(0xFF5D4037) : Colors.grey.shade400),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    if (hasLog && !isSelected)
                      Positioned(
                        bottom: 4,
                        child: Container(
                          width: 4,
                          height: 4,
                          decoration: const BoxDecoration(color: Color(0xFFC67C4E), shape: BoxShape.circle),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// 산책 사진. 서버 사진을 우선하고, 없으면 예시 asset, 둘 다 없으면 안내 아이콘.
  ///
  /// asset 파일이 빠져 있어도 화면이 깨지지 않게 errorBuilder 로 받아준다.
  static Widget _buildWalkImage({
    required String? thumbnailUrl,
    required String? imageAsset,
  }) {
    const placeholder = Center(
      child: Icon(Icons.image_outlined, size: 48, color: Color(0xFFD7CCC8)),
    );

    if (thumbnailUrl != null) {
      return Image.network(
        thumbnailUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => imageAsset == null
            ? placeholder
            : Image.asset(imageAsset,
                fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder),
      );
    }
    if (imageAsset != null) {
      return Image.asset(
        imageAsset,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
      );
    }
    return placeholder;
  }

  /// 선택한 날의 요약. 장소는 역지오코딩 결과이고, 아직 못 구했으면 `-`.
  Widget _buildDailySummaryCard(WalkDiaryFeedItem item, String? placeName) {
    final distance = item.distanceMeters == null
        ? '-'
        : '${(item.distanceMeters! / 1000).toStringAsFixed(1)}km';
    return _buildSummaryCardShell(
      place: placeName ?? '-',
      distance: distance,
      duration: item.durationLabel,
    );
  }

  Widget _buildSummaryCardShell({
    required String place,
    required String distance,
    required String duration,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 15, offset: const Offset(0, 8)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildSummaryCol(Icons.location_on_outlined, '산책 장소', place),
          Container(width: 1, height: 40, color: Colors.grey.shade100),
          _buildSummaryCol(Icons.map_outlined, '산책 거리', distance),
          Container(width: 1, height: 40, color: Colors.grey.shade100),
          _buildSummaryCol(Icons.timer_outlined, '산책 시간', duration),
        ],
      ),
    );
  }

  Widget _buildEmptySummaryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(25),
      ),
      child: const Center(
        child: Text('산책한 날을 클릭해 상세 기록을 확인하세요', style: TextStyle(color: Colors.grey, fontSize: 13)),
      ),
    );
  }

  Widget _buildSummaryCol(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFFC67C4E), size: 20),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF5D4037))),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 60),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30)),
      child: Column(
        children: [
          Icon(Icons.pets, size: 48, color: Colors.grey.shade200),
          const SizedBox(height: 16),
          const Text('이날은 생성된 일지가 없어요', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF5D4037))),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: const Color(0xFFEFE5D8), borderRadius: BorderRadius.circular(15)),
          child: Row(
            children: [
              _buildSmallTab('주간', _isWeekly, () => setState(() => _isWeekly = true)),
              _buildSmallTab('월간', !_isWeekly, () => setState(() => _isWeekly = false)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSmallTab(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFC67C4E) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(color: isSelected ? Colors.white : Colors.grey, fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  /// 주간/월간 집계 결과를 카드 4개로 보여준다.
  ///
  /// 칼로리는 서버가 주는 값이 없어(체중·보폭 정보가 없어 추정도 부정확하다)
  /// '평균 거리'로 대체했다.
  Widget _buildStatsGrid(WalkStats stats) {
    return Column(
      children: [
        Row(
          children: [
            _buildMiniStatCard(Icons.directions_walk, stats.countLabel, '산책 횟수',
                const Color(0xFFFFF1F0)),
            const SizedBox(width: 16),
            _buildMiniStatCard(Icons.map_outlined, stats.distanceLabel, '총 거리',
                const Color(0xFFE8F6F3)),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _buildMiniStatCard(Icons.timer_outlined, stats.durationLabel, '산책 시간',
                const Color(0xFFF9F3E7)),
            const SizedBox(width: 16),
            _buildMiniStatCard(Icons.straighten, stats.averageDistanceLabel,
                '평균 거리', const Color(0xFFFFF8F1)),
          ],
        ),
      ],
    );
  }

  Widget _buildMiniStatCard(IconData icon, String value, String label, Color bgColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(20)),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFFC67C4E), size: 20),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF5D4037))),
                Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogPost(
      BuildContext context, WalkDiaryFeedItem item, String? placeName) {
    final distance = item.distanceMeters == null
        ? '-'
        : '${(item.distanceMeters! / 1000).toStringAsFixed(1)}km';
    return _buildLogPostShell(
      context: context,
      walkId: item.walkId,
      placeName: placeName,
      summary: item.summary,
      durationLabel: item.durationLabel,
      distanceLabel: distance,
      thumbnailUrl: item.thumbnailUrl,
      // 7월 예시 기록은 서버 사진이 없어 asset 그림을 쓴다.
      imageAsset: SampleWalkDiaries.imageAssetOf(item.walkId),
    );
  }

  Widget _buildLogPostShell({
    required BuildContext context,
    required int walkId,
    required String? placeName,
    required String? summary,
    required String durationLabel,
    required String distanceLabel,
    required String? thumbnailUrl,
    String? imageAsset,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Path Image Placeholder
          Container(
            height: 250,
            decoration: BoxDecoration(
              color: const Color(0xFFFDF7F0),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFF0E0D0)),
            ),
            child: Stack(
              children: [
                // 서버 사진(thumbnailUrl)이 있으면 그걸, 없으면 예시 그림을 쓴다.
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: _buildWalkImage(
                      thumbnailUrl: thumbnailUrl,
                      imageAsset: imageAsset,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 20,
                  right: 20,
                  child: ElevatedButton(
                    // 어떤 산책의 경로인지 walkId 를 넘긴다.
                    onPressed: () =>
                        context.push('/walk/path-detail', extra: walkId),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFC67C4E),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                    child: const Text('경로 보기', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          
          Text("${_selectedDate.year}.${_selectedDate.month.toString().padLeft(2, '0')}.${_selectedDate.day.toString().padLeft(2, '0')}", style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 8),
          // 날씨·기분은 서버가 주는 값이 없어 표시하지 않는다.
          Text(
            placeName ?? '산책 기록',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF5D4037)),
          ),
          const SizedBox(height: 12),
          Text(
            summary ?? '이 산책에 남긴 기록이 아직 없어요.',
            style: TextStyle(color: Colors.grey.shade700, height: 1.5),
          ),
          const SizedBox(height: 24),

          Row(
            children: [
              const Icon(Icons.timer_outlined, size: 16, color: Color(0xFFC67C4E)),
              const SizedBox(width: 6),
              Text(durationLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 20),
              const Icon(Icons.map_outlined, size: 16, color: Color(0xFFC67C4E)),
              const SizedBox(width: 6),
              Text(distanceLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 24),
          
          // Action Buttons
          Row(
            children: [
              _buildLogAction(Icons.refresh, '재생성', Colors.blue.shade50, Colors.blue),
              const SizedBox(width: 12),
              _buildLogAction(Icons.edit_outlined, '수정', const Color(0xFFF9F3E7), const Color(0xFF5D4037)),
              const SizedBox(width: 12),
              _buildLogAction(Icons.delete_outline, '삭제', const Color(0xFFFFF1F0), Colors.redAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLogAction(IconData icon, String label, Color bgColor, Color iconColor) {
    return Expanded(
      child: Container(
        height: 50,
        decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(15)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: iconColor, size: 18),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: iconColor, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
