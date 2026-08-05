import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class CallNameSettingScreen extends StatefulWidget {
  const CallNameSettingScreen({super.key});

  @override
  State<CallNameSettingScreen> createState() => _CallNameSettingScreenState();
}

class _CallNameSettingScreenState extends State<CallNameSettingScreen> {
  final _nameController = TextEditingController(text: '마실이');
  bool _isTesting = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F3E7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.chevron_left, color: Color(0xFF5D4037)), onPressed: () => context.pop()),
        title: const Text('이름 호출', style: TextStyle(color: Color(0xFF5D4037), fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // Name Input Card
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('호출 이름', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF5D4037))),
                  const SizedBox(height: 12),
                  Stack(
                    alignment: Alignment.centerRight,
                    children: [
                      _buildTextField(_nameController),
                      const Padding(
                        padding: EdgeInsets.only(right: 16),
                        child: Text('3/10', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      Icon(Icons.check, color: Colors.green, size: 14),
                      SizedBox(width: 6),
                      Text('기기 동기화 완료 · 방금 전 (설정 v12)', style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            
            // Test Area
            const Text('불러서 테스트해보세요', style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text('"마실아~"', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF5D4037))),
            const SizedBox(height: 48),
            
            // Microphone Button
            GestureDetector(
              onTap: () => setState(() => _isTesting = !_isTesting),
              child: Container(
                width: 140,
                height: 140,
                decoration: const BoxDecoration(color: Color(0xFFC67C4E), shape: BoxShape.circle),
                child: const Icon(Icons.mic, color: Colors.white, size: 48),
              ),
            ),
            const SizedBox(height: 24),
            // Waves Placeholder
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) => Container(
                width: 4,
                height: [20, 40, 60, 30, 15][index].toDouble(),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(color: const Color(0xFFC67C4E).withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)),
              )),
            ),
            const SizedBox(height: 48),
            
            // Success Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(20)),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.pets, color: Colors.brown, size: 16),
                  SizedBox(width: 12),
                  Text('인식 성공! 마실이가 뒤돌아봤어요', style: TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
            ),
            const SizedBox(height: 32),
            
            // Instructions
            _buildInstructions(),
            const SizedBox(height: 40),
            
            // Bottom Action
            SizedBox(
              width: double.infinity,
              height: 64,
              child: ElevatedButton(
                onPressed: () => context.pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC67C4E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: const Text('이름 저장하기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFFFFF1F0).withValues(alpha: 0.5),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Color(0xFFF0E0D0))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Color(0xFFF0E0D0))),
      ),
    );
  }

  Widget _buildInstructions() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('· 또렷하고 일정한 톤으로 불러주세요', style: TextStyle(color: Color(0xFF8D6E63), fontSize: 14)),
          SizedBox(height: 12),
          Text('· 조용한 환경에서 인식률이 높아요', style: TextStyle(color: Color(0xFF8D6E63), fontSize: 14)),
          SizedBox(height: 12),
          Text('· 2~10자 한글·영문만 쓸 수 있어요', style: TextStyle(color: Color(0xFF8D6E63), fontSize: 14)),
        ],
      ),
    );
  }
}
