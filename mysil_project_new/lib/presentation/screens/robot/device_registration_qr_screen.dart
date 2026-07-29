import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class DeviceRegistrationQrScreen extends StatelessWidget {
  const DeviceRegistrationQrScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2D2621), // Dark background for camera view
      body: Stack(
        children: [
          // Simulated Camera Preview
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  '마실이 기기 하단의\nQR 코드를 스캔해 주세요',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 60),
                // QR Scanner Frame
                Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 2),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Stack(
                    children: [
                      // Scanning line (animation placeholder)
                      Center(
                        child: Container(
                          width: 200,
                          height: 2,
                          decoration: BoxDecoration(
                            color: const Color(0xFFC67C4E),
                            boxShadow: [
                              BoxShadow(color: const Color(0xFFC67C4E).withValues(alpha: 0.5), blurRadius: 10, spreadRadius: 2),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                const Icon(Icons.image_outlined, color: Colors.white24, size: 32),
                const Text('카메라 프리뷰 (기기 밑면 QR)', style: TextStyle(color: Colors.white24, fontSize: 13)),
                const Text('or browse files', style: TextStyle(color: Colors.white24, fontSize: 12, decoration: TextDecoration.underline)),
                const SizedBox(height: 40),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(20)),
                  child: const Text('페어링 유효시간 02:41 남음', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          
          // Back Button
          Positioned(
            top: 60,
            left: 24,
            child: CircleAvatar(
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              child: IconButton(
                icon: const Icon(Icons.chevron_left, color: Colors.white),
                onPressed: () => context.pop(),
              ),
            ),
          ),
          
          // Bottom Permission Sheet (Simulated)
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: const BoxDecoration(
                color: Color(0xFFFDF7F0),
                borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(color: Color(0xFFFFF3F0), shape: BoxShape.circle),
                    child: const Icon(Icons.camera_alt, color: Color(0xFFC67C4E), size: 30),
                  ),
                  const SizedBox(height: 20),
                  const Text('카메라 접근 권한 안내', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF5D4037))),
                  const SizedBox(height: 12),
                  const Text(
                    'QR 스캔을 위해 카메라 접근 권한이 필요해요.\n사진은 저장되지 않아요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF8D6E63), fontSize: 15, height: 1.5),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton(
                      onPressed: () => context.pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3E2723), // Dark brown
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      ),
                      child: const Text('권한 허용하기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('직접 시리얼 번호 입력하기', style: TextStyle(color: Colors.grey, decoration: TextDecoration.underline)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
