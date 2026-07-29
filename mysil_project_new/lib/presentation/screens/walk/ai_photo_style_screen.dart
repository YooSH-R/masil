import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AiPhotoStyleScreen extends StatefulWidget {
  const AiPhotoStyleScreen({super.key});

  @override
  State<AiPhotoStyleScreen> createState() => _AiPhotoStyleScreenState();
}

class _AiPhotoStyleScreenState extends State<AiPhotoStyleScreen> {
  int _selectedStyle = 0; // 0: 지브리풍, 1: 스케치, 2: 팝아트

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
        title: const Text('AI 스타일 선택 ✨', style: TextStyle(color: Color(0xFF5D4037), fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
        child: Column(
          children: [
            const Text(
              '산책 중 찍은 사진을\n자동으로 멋지게 보정해 줄게요!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF8D6E63), fontSize: 16, height: 1.5),
            ),
            const SizedBox(height: 32),
            
            // Image Area
            Container(
              height: 350,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F6F3),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: const Color(0xFFD7CCC8), width: 1.5, style: BorderStyle.solid), // Dash effect simplified
              ),
              child: Stack(
                children: [
                  const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.image_outlined, size: 48, color: Colors.white),
                        SizedBox(height: 12),
                        Text('원본 사진 (산책 중 촬영)', style: TextStyle(color: Color(0xFF8D6E63), fontSize: 14)),
                        Text('or browse files', style: TextStyle(color: Color(0xFF8D6E63), fontSize: 12, decoration: TextDecoration.underline)),
                      ],
                    ),
                  ),
                  Positioned(
                    bottom: 20,
                    left: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(10)),
                      child: const Text('원본 사진', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            
            // Style Selector
            SizedBox(
              height: 130,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildStyleItem(0, '지브리풍', Icons.filter_vintage),
                  _buildStyleItem(1, '스케치', Icons.edit_note),
                  _buildStyleItem(2, '팝아트', Icons.palette_outlined),
                  _buildStyleItem(3, '수채화', Icons.water_drop_outlined),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            // Progress Bar
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: const LinearProgressIndicator(
                value: 0.6,
                minHeight: 8,
                backgroundColor: Color(0xFFEFE5D8),
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFC67C4E)),
              ),
            ),
            const SizedBox(height: 32),
            
            // Info Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFFC67C4E), size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '생성에는 약 20초가 걸려요. 실패하면 원본은 그대로 남아 있고 다시 시도할 수 있어요.',
                      style: TextStyle(color: Color(0xFF8D6E63), fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 40),
            // Action Button
            SizedBox(
              width: double.infinity,
              height: 64,
              child: ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC67C4E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 0,
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.wb_sunny_outlined, size: 20),
                    SizedBox(width: 12),
                    Text('이 스타일로 생성하기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildStyleItem(int index, String label, IconData icon) {
    bool isSelected = _selectedStyle == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedStyle = index),
      child: Container(
        width: 100,
        margin: const EdgeInsets.only(right: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? const Color(0xFFC67C4E) : Colors.transparent, width: 2),
        ),
        child: Column(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F0),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Stack(
                children: [
                  Center(child: Icon(icon, color: const Color(0xFFC67C4E), size: 24)),
                  if (isSelected)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(color: Color(0xFFC67C4E), shape: BoxShape.circle),
                        child: const Icon(Icons.check, color: Colors.white, size: 12),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isSelected ? const Color(0xFFC67C4E) : const Color(0xFF5D4037))),
          ],
        ),
      ),
    );
  }
}
