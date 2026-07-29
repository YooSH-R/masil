import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class DeviceConnectionManagementScreen extends StatelessWidget {
  const DeviceConnectionManagementScreen({super.key});

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
        title: const Text('기기 연결 관리', style: TextStyle(color: Color(0xFF5D4037), fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // Current Device Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
              child: Row(
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(color: const Color(0xFFF9F3E7), borderRadius: BorderRadius.circular(15)),
                    child: Image.asset('assets/images/mysil_character.png'),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('마실이 · MS-2231', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        SizedBox(height: 4),
                        Text('펌웨어 v2.4.1 · 배터리 76%', style: TextStyle(color: Colors.grey, fontSize: 13)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(10)),
                    child: const Row(
                      children: [
                        Icon(Icons.circle, color: Colors.green, size: 8),
                        SizedBox(width: 4),
                        Text('온라인', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Reconnect / Unregister Buttons
            Row(
              children: [
                Expanded(
                  child: _buildActionBtn('재연결', const Color(0xFFFDFDFD), const Color(0xFF5D4037)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildActionBtn('등록 해제', const Color(0xFFFFF1F0), const Color(0xFFD32F2F)),
                ),
              ],
            ),
            const SizedBox(height: 32),
            
            // New Robot Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: const Color(0xFFE8F6F3), shape: BoxShape.circle),
                    child: const Icon(Icons.qr_code_scanner, color: Color(0xFF16A085), size: 40),
                  ),
                  const SizedBox(height: 24),
                  const Text('새 로봇을 등록하려면', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  const Text(
                    'QR 코드 스캔을 위해 카메라 권한이 필요해요.\n기기 밑면의 QR을 비춰 주세요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 14, height: 1.5),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton(
                      onPressed: () => context.push('/user/robot-mgmt/register'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFC67C4E),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                      child: const Text('카메라 권한 허용하고 스캔', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () {},
                    child: const Text('QR 재검색', style: TextStyle(color: Colors.grey)),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            // Info Note
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: const Color(0xFFFFF8F1), borderRadius: BorderRadius.circular(15)),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFFC67C4E), size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text('이미 다른 계정에 등록된 로봇이거나 QR이 만료된 경우, 안내 후 재검색으로 이동해요.', style: TextStyle(color: Color(0xFF8D6E63), fontSize: 12)),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 32),
            // Connection History
            _buildHistorySection(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildActionBtn(String label, Color bgColor, Color textColor) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Center(
        child: Text(label, style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('연결 이력', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('· 오늘 08:42 — 자동 페어링 성공', style: TextStyle(color: Colors.black87, fontSize: 14)),
              SizedBox(height: 12),
              Text('· 어제 21:10 — 연결 끊김 후 재연결', style: TextStyle(color: Colors.black87, fontSize: 14)),
              SizedBox(height: 12),
              Text('· 07.24 — 펌웨어 v2.4.1 적용', style: TextStyle(color: Colors.black87, fontSize: 14)),
            ],
          ),
        ),
      ],
    );
  }
}
