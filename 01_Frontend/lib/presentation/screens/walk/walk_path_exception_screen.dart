import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class WalkPathExceptionScreen extends StatelessWidget {
  const WalkPathExceptionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F3E7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Color(0xFF5D4037)),
          onPressed: () => context.pop(),
        ),
        title: const Text('산책 경로', style: TextStyle(color: Color(0xFF5D4037), fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
        child: Column(
          children: [
            // Empty Map Area
            Container(
              height: 350,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFF0E0D0).withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: const Icon(Icons.satellite_alt_outlined, color: Color(0xFFC67C4E), size: 40),
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      '위치 권한이 필요해요',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF5D4037)),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'GPS 경로를 지도에 표시하려면\n위치 권한을 허용해 주세요.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF8D6E63), fontSize: 16, height: 1.5),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: 220,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFC67C4E),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        child: const Text('위치 권한 설정 열기', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('권한 없이도 거리·시간은 기록돼요', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            
            // Other Exceptions
            _buildExceptionItem(Icons.wb_twilight, 'GPS 신호가 약해요', '실외로 이동하면 정확도가 올라가요'),
            const SizedBox(height: 12),
            _buildExceptionItem(Icons.location_off_outlined, '경로 기록이 없는 산책', '이번 산책은 GPS 없이 기록됐어요'),
            const SizedBox(height: 12),
            _buildExceptionItem(Icons.map_outlined, '지도를 불러오지 못했어요', '카카오맵 연결 오류 · 잠시 후 재시도'),
            
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildExceptionItem(IconData icon, String title, String desc) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(color: Color(0xFFF9F3E7), shape: BoxShape.circle),
            child: Icon(icon, color: const Color(0xFFC67C4E), size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                Text(desc, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
