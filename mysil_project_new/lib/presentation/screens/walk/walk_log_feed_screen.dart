import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class WalkLogFeedScreen extends StatefulWidget {
  const WalkLogFeedScreen({super.key});

  @override
  State<WalkLogFeedScreen> createState() => _WalkLogFeedScreenState();
}

class _WalkLogFeedScreenState extends State<WalkLogFeedScreen> {
  int _currentMonth = 7;
  int _currentYear = 2026;
  DateTime _selectedDate = DateTime(2026, 7, 27);
  bool _isWeekly = true;

  // Mock Data: Map of ISO date string -> Walk Data
  final Map<String, Map<String, dynamic>> _mockLogs = {
    // June 2026
    '2026-06-05': {'duration': '35분', 'distance': '1.8km', 'location': '골목길 탐험', 'title': '새로운 골목 발견', 'content': '마실이가 처음 가보는 골목에서 호기심이 폭발했어요!', 'calories': '110 kcal', 'mood': '궁금함 🤔', 'weather': '맑음 ☀️'},
    '2026-06-12': {'duration': '50분', 'distance': '2.5km', 'location': '수변 공원', 'title': '물 구경하기', 'content': '강물이 반짝이는 걸 보며 한참을 서있었네요.', 'calories': '160 kcal', 'mood': '평온함 😌', 'weather': '맑음 ☀️'},
    '2026-06-18': {'duration': '25분', 'distance': '1.2km', 'location': '집 앞 마당', 'title': '짧고 굵은 산책', 'content': '비가 오기 전이라 짧게 다녀왔어요.', 'calories': '70 kcal', 'mood': '바쁨 💨', 'weather': '흐림 ☁️'},
    '2026-06-25': {'duration': '40분', 'distance': '2.0km', 'location': '근린 공원', 'title': '친구 만난 날', 'content': '동네 강아지 친구들을 많이 만나서 신나게 인사했어요.', 'calories': '130 kcal', 'mood': '신남 😆', 'weather': '맑음 ☀️'},
    
    // July 2026
    '2026-07-01': {'duration': '30분', 'distance': '1.5km', 'location': '동네 한 바퀴', 'title': '7월의 시작', 'content': '본격적인 여름 산책 시작!', 'calories': '90 kcal', 'mood': '활기참 ⚡', 'weather': '맑음 ☀️'},
    '2026-07-04': {'duration': '45분', 'distance': '2.2km', 'location': '숲속 공원', 'title': '그늘 산책', 'content': '나무 그늘 아래는 시원해서 걷기 좋았어요.', 'calories': '140 kcal', 'mood': '쾌적함 😊', 'weather': '맑음 ☀️'},
    '2026-07-08': {'duration': '20분', 'distance': '1.0km', 'location': '아파트 단지', 'title': '더위 피하기', 'content': '너무 더워서 해 지고 잠시 나왔어요.', 'calories': '60 kcal', 'mood': '나른함 🥱', 'weather': '더움 🌡️'},
    '2026-07-12': {'duration': '55분', 'distance': '2.8km', 'location': '중앙 광장', 'title': '주말 나들이', 'content': '분수대 구경하며 시원하게 보냈습니다.', 'calories': '180 kcal', 'mood': '최고! ✨', 'weather': '맑음 ☀️'},
    '2026-07-15': {'duration': '40분', 'distance': '2.0km', 'location': '뒷산 산책로', 'title': '등산(?) 산책', 'content': '언덕길도 씩씩하게 잘 올라가는 마실이!', 'calories': '155 kcal', 'mood': '씩씩함 💪', 'weather': '구름 ☁️'},
    '2026-07-19': {'duration': '35분', 'distance': '1.7km', 'location': '동네 카페 거리', 'title': '맛있는 냄새 솔솔', 'content': '빵 냄새를 따라가는 마실이가 귀여웠어요.', 'calories': '105 kcal', 'mood': '행복함 🥰', 'weather': '맑음 ☀️'},
    '2026-07-22': {'duration': '60분', 'distance': '3.2km', 'location': '한강 시민공원', 'title': '한강 나들이', 'content': '다른 강아지 친구들도 많이 만나고 즐거운 시간이었어요.', 'calories': '210 kcal', 'mood': '신남 😆', 'weather': '맑음 ☀️'},
    '2026-07-25': {'duration': '30분', 'distance': '1.5km', 'location': '동네 한 바퀴', 'title': '가벼운 저녁 산책', 'content': '선선한 바람이 불어서 걷기 딱 좋은 날씨였어요.', 'calories': '85 kcal', 'mood': '좋음 🙂', 'weather': '구름 ☁️'},
    '2026-07-27': {
      'duration': '45분',
      'distance': '2.3km',
      'location': '숲속 공원',
      'title': '마실이가 나비를 쫓아다녔어요!',
      'content': '나비를 따라가느라 평소보다 더 많이 걸었네요. 마실이의 행복한 표정을 보니 저도 기분이 좋아졌습니다.',
      'calories': '142 kcal',
      'mood': '최고! 😊',
      'weather': '맑음 ☀️',
    },
    '2026-07-31': {'duration': '40분', 'distance': '2.1km', 'location': '수변 산책로', 'title': '7월 마무리', 'content': '한 달 동안 열심히 걸어준 마실이 고마워!', 'calories': '135 kcal', 'mood': '만족함 😋', 'weather': '맑음 ☀️'},
  };

  @override
  Widget build(BuildContext context) {
    final dateKey = "${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}";
    final selectedLog = _mockLogs[dateKey];
    
    // Calculate current month's log count
    final monthPrefix = "$_currentYear-${_currentMonth.toString().padLeft(2, '0')}";
    final monthLogCount = _mockLogs.keys.where((k) => k.startsWith(monthPrefix)).length;

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
            _buildMonthlyCalendar(),
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

            // Daily Summary Detail (Requested feature)
            if (selectedLog != null)
              _buildDailySummaryCard(selectedLog)
            else
              _buildEmptySummaryCard(),
              
            const SizedBox(height: 32),
            
            // Stats Section
            _buildSectionHeader(_isWeekly ? '이번 주 산책 통계' : '이번 달 산책 통계'),
            const SizedBox(height: 16),
            _buildStatsGrid(),
            const SizedBox(height: 32),
            
            // Detailed View for Selected Day
            if (selectedLog != null)
              _buildLogPost(context, selectedLog)
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

  Widget _buildMonthlyCalendar() {
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
              final dateStr = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
              
              bool isSelected = _selectedDate.year == date.year && _selectedDate.month == date.month && _selectedDate.day == date.day;
              bool hasLog = _mockLogs.containsKey(dateStr);
              bool isToday = DateTime.now().year == date.year && DateTime.now().month == date.month && DateTime.now().day == date.day;

              return GestureDetector(
                onTap: () => setState(() => _selectedDate = date),
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

  Widget _buildDailySummaryCard(Map<String, dynamic> log) {
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
          _buildSummaryCol(Icons.location_on_outlined, '산책 장소', log['location']),
          Container(width: 1, height: 40, color: Colors.grey.shade100),
          _buildSummaryCol(Icons.map_outlined, '산책 거리', log['distance']),
          Container(width: 1, height: 40, color: Colors.grey.shade100),
          _buildSummaryCol(Icons.timer_outlined, '산책 시간', log['duration']),
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

  Widget _buildStatsGrid() {
    return Column(
      children: [
        Row(
          children: [
            _buildMiniStatCard(Icons.directions_walk, _isWeekly ? '5 회' : '22 회', '산책 횟수', const Color(0xFFFFF1F0)),
            const SizedBox(width: 16),
            _buildMiniStatCard(Icons.map_outlined, _isWeekly ? '11.4 km' : '48.2 km', '총 거리', const Color(0xFFE8F6F3)),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _buildMiniStatCard(Icons.timer_outlined, _isWeekly ? '3시간 12분' : '14시간 45분', '산책 시간', const Color(0xFFF9F3E7)),
            const SizedBox(width: 16),
            _buildMiniStatCard(Icons.local_fire_department_outlined, _isWeekly ? '640 kcal' : '2,850 kcal', '소모 칼로리', const Color(0xFFFFF8F1)),
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

  Widget _buildLogPost(BuildContext context, Map<String, dynamic> log) {
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
                const Center(child: Icon(Icons.image_outlined, size: 48, color: Color(0xFFD7CCC8))),
                Positioned(
                  bottom: 20,
                  right: 20,
                  child: ElevatedButton(
                    onPressed: () => context.push('/walk/path-detail'),
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
          Row(
            children: [
              Text('날씨 : ${log['weather']}', style: const TextStyle(color: Color(0xFF5D4037), fontSize: 14)),
              const SizedBox(width: 16),
              Text('기분 : ${log['mood']}', style: const TextStyle(color: Color(0xFF5D4037), fontSize: 14)),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            log['title'],
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF5D4037)),
          ),
          const SizedBox(height: 12),
          Text(
            log['content'],
            style: TextStyle(color: Colors.grey.shade700, height: 1.5),
          ),
          const SizedBox(height: 24),
          
          Row(
            children: [
              const Icon(Icons.timer_outlined, size: 16, color: Color(0xFFC67C4E)),
              const SizedBox(width: 6),
              Text(log['duration'], style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 20),
              const Icon(Icons.location_on_outlined, size: 16, color: Color(0xFFC67C4E)),
              const SizedBox(width: 6),
              Text(log['distance'], style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 24),
          
          const Text('오늘 산책은 정말 즐거웠어요 😊', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF5D4037))),
          const SizedBox(height: 12),
          const Row(
            children: [
              Text('✨ AI 감성 사진 3장', style: TextStyle(color: Color(0xFF16A085), fontSize: 12, fontWeight: FontWeight.bold)),
              SizedBox(width: 16),
              Text('✨ AI 감성일지 자동 생성됨', style: TextStyle(color: Color(0xFF16A085), fontSize: 12, fontWeight: FontWeight.bold)),
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
