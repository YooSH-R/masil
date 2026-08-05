import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 산책 일시정지 오버레이.
///
/// 일시정지 표시와 `산책 다시 이어가기` 버튼만 둔다.
///
/// 이전에는 `기기 연결이 끊어졌어요`·`기록 복구 중 78%`·`마지막 기록 시각
/// 00:24:18`·`다시 연결` 같은 것들이 있었는데 전부 하드코딩이었다. 복구
/// 진행률이나 마지막 기록 시각을 알 방법이 없어서, 없는 정보를 그럴듯하게
/// 보여주는 대신 지웠다.
class WalkDisconnectedScreen extends StatelessWidget {
  const WalkDisconnectedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.5),
      body: Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 32),
          decoration: BoxDecoration(
            color: const Color(0xFFFDF7F0),
            borderRadius: BorderRadius.circular(35),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 일시정지 표시
              Container(
                width: 120,
                height: 120,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(Icons.pause_rounded,
                      color: Color(0xFFC67C4E), size: 64),
                ),
              ),
              const SizedBox(height: 40),

              // 산책 다시 이어가기 — 산책 중 화면으로 돌아간다.
              // 위치 수신은 그 화면이 다시 시작한다.
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  onPressed: () => context.pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC67C4E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    elevation: 0,
                  ),
                  child: const Text('산책 다시 이어가기',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
