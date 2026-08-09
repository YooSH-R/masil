import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/robot_qr.dart';
import '../../viewmodels/pet_view_model.dart';
import '../../viewmodels/robot_view_model.dart';

/// 마실이 기기 밑면 QR 을 스캔해 기기를 등록한다.
///
/// 흐름:
///   카메라 권한 → QR 스캔 → 서버 유효성 확인 → 새 펫 이름 입력
///   → 펫 생성과 기기 연결을 하나의 서버 트랜잭션으로 처리
class DeviceRegistrationQrScreen extends StatefulWidget {
  const DeviceRegistrationQrScreen({super.key});

  @override
  State<DeviceRegistrationQrScreen> createState() =>
      _DeviceRegistrationQrScreenState();
}

class _DeviceRegistrationQrScreenState
    extends State<DeviceRegistrationQrScreen> {
  final MobileScannerController _controller = MobileScannerController(
    // QR 만 찾으면 되니 다른 바코드 형식은 끈다. 인식이 빨라진다.
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  /// 처리 중 중복 스캔을 막는다. QR 은 초당 여러 번 인식된다.
  bool _handling = false;
  String? _message;
  bool _isError = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling || capture.barcodes.isEmpty) return;

    final raw = capture.barcodes.first.rawValue;
    final token = RobotQr.extractToken(raw);

    if (token == null) {
      // 다른 앱 QR·광고 QR 등. 서버에 보내지 않고 바로 안내한다.
      _show('마실이 기기의 QR 코드가 아니에요. 기기 밑면의 QR을 비춰 주세요.', isError: true);
      return;
    }

    _handling = true;
    await _controller.stop();
    if (!mounted) return;

    await _registerToken(token);
  }

  /// 토큰 하나로 등록까지 가는 공통 경로.
  ///
  /// 카메라 스캔과 (디버그용) 직접 입력이 **같은 길**을 지나야, 직접 입력으로 한
  /// 확인이 실제 스캔 동작을 보증한다. 갈라지면 한쪽만 되는 상황이 생긴다.
  Future<void> _registerToken(String token) async {
    final robotVm = context.read<RobotViewModel>();

    _show('QR 코드를 확인하고 있어요.');
    final valid = await robotVm.validateRegistrationQr(token);
    if (!mounted) return;
    if (!valid) {
      _show(robotVm.errorMessage ?? '등록할 수 없는 QR 코드예요.', isError: true);
      return;
    }

    final petName = await _askPetName();
    if (!mounted) return;
    if (petName == null) {
      await _retry();
      return;
    }

    _show('$petName 프로필과 기기를 등록하고 있어요.');
    final paired = await robotVm.registerNewPet(
      qrToken: token,
      petName: petName,
    );
    if (!mounted) return;

    if (!paired) {
      _show(robotVm.errorMessage ?? '기기 등록에 실패했어요. 다시 시도해 주세요.', isError: true);
      return;
    }

    await context.read<PetViewModel>().loadCurrentPet(silent: true);
    if (!mounted) return;
    _show('$petName 등록이 완료됐어요!');
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    context.pop();
  }

  Future<String?> _askPetName() async {
    var input = '';
    final name = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('새 반려동물 이름'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'QR 확인이 끝났어요. 이 기기와 함께할 반려동물의 이름을 입력해 주세요.',
              style: TextStyle(color: Color(0xFF8D6E63), fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              autofocus: true,
              maxLength: 100,
              textInputAction: TextInputAction.done,
              onChanged: (value) => input = value,
              decoration: const InputDecoration(
                hintText: '이름 (예: 마실이)',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (value) {
                final trimmed = value.trim();
                if (trimmed.isNotEmpty) {
                  Navigator.of(dialogContext).pop(trimmed);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              final trimmed = input.trim();
              if (trimmed.isNotEmpty) {
                Navigator.of(dialogContext).pop(trimmed);
              }
            },
            child: const Text('등록'),
          ),
        ],
      ),
    );
    return name;
  }

  /// 카메라 없이 토큰을 직접 넣어 등록해 본다. **디버그 빌드에서만** 쓴다.
  ///
  /// 에뮬레이터 카메라는 호스트 화면을 못 보기 때문에 QR 을 비출 수가 없다.
  /// 그렇다고 스캔 이후 흐름(형식 검증 → petId 확인 → 서버 등록 → 결과 표시)을
  /// 확인 못 하면 시연 전에 남는 위험이 크다. 그래서 카메라 단계만 건너뛴다.
  Future<void> _openManualEntry() async {
    var value = '';

    final input = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('QR 토큰 직접 입력'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '카메라 없이 등록 흐름을 확인하는 디버그 기능이에요.\n'
              '토큰(43자 이상) 또는 mysil://pair?token=... 형태를 넣어 주세요.',
              style: TextStyle(fontSize: 12, color: Color(0xFF8D6E63)),
            ),
            const SizedBox(height: 16),
            TextField(
              autofocus: true,
              maxLines: 3,
              minLines: 2,
              onChanged: (input) => value = input,
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                hintText: 'vWy6ljEwfJ8-jNFG_2tgCk8rFn1Xg3dMXthSV3liX7M',
                hintStyle: TextStyle(fontSize: 11),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(value.trim()),
            child: const Text('등록 시도'),
          ),
        ],
      ),
    );

    if (input == null || input.isEmpty || !mounted) return;

    // 스캔과 똑같이 형식부터 검증한다. 이 단계도 확인 대상이다.
    final token = RobotQr.extractToken(input);
    if (token == null) {
      _show('토큰 형식이 맞지 않아요. 43자 이상의 영문·숫자·_- 조합이어야 해요.', isError: true);
      return;
    }

    _handling = true;
    await _controller.stop();
    if (!mounted) return;

    await _registerToken(token);
  }

  void _show(String message, {bool isError = false}) {
    setState(() {
      _message = message;
      _isError = isError;
    });
  }

  /// 다시 스캔할 수 있게 상태를 되돌린다.
  Future<void> _retry() async {
    setState(() {
      _message = null;
      _isError = false;
    });
    _handling = false;
    await _controller.start();
  }

  @override
  Widget build(BuildContext context) {
    final robotVm = context.watch<RobotViewModel>();

    return Scaffold(
      backgroundColor: const Color(0xFF2D2621),
      body: Stack(
        children: [
          // 카메라 프리뷰 + QR 인식
          Positioned.fill(
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (context, error) =>
                  _CameraErrorView(error: error, onBack: () => context.pop()),
            ),
          ),

          // 스캔 가이드 프레임
          const Positioned.fill(child: _ScanFrame()),

          // 뒤로가기
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

          // 토큰 직접 입력 (디버그 빌드 전용).
          //
          // 에뮬레이터 카메라로는 QR 을 비출 수 없어서 스캔 이후 흐름을 확인할
          // 방법이 없다. kDebugMode 로 묶어 릴리즈 빌드에는 나가지 않는다.
          if (kDebugMode)
            Positioned(
              top: 60,
              right: 24,
              child: CircleAvatar(
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                child: IconButton(
                  icon: const Icon(Icons.keyboard_alt_outlined,
                      color: Colors.white),
                  tooltip: 'QR 토큰 직접 입력 (디버그)',
                  onPressed: _openManualEntry,
                ),
              ),
            ),

          // 안내 문구
          const Positioned(
            top: 120,
            left: 24,
            right: 24,
            child: Column(
              children: [
                Text(
                  '마실이 기기 하단의\nQR 코드를 스캔해 주세요',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(blurRadius: 8, color: Colors.black54)]),
                ),
              ],
            ),
          ),

          // 결과 시트
          if (_message != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: _ResultSheet(
                message: _message!,
                isError: _isError,
                isLoading: robotVm.isLoading,
                onRetry: _retry,
                onClose: () => context.pop(),
              ),
            )
          else
            const Align(
              alignment: Alignment.bottomCenter,
              child: _PermissionNote(),
            ),
        ],
      ),
    );
  }
}

/// 화면 가운데 스캔 영역 표시. 카메라 위에 얹는다.
class _ScanFrame extends StatelessWidget {
  const _ScanFrame();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 250,
        height: 250,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white, width: 2),
          borderRadius: BorderRadius.circular(30),
        ),
      ),
    );
  }
}

/// 카메라를 열 수 없을 때(권한 거부, 카메라 없음 등).
class _CameraErrorView extends StatelessWidget {
  const _CameraErrorView({required this.error, required this.onBack});

  final MobileScannerException error;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;

    return Container(
      color: const Color(0xFF2D2621),
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
                color: Color(0xFF3E332C), shape: BoxShape.circle),
            child: const Icon(Icons.no_photography_outlined,
                color: Color(0xFFC67C4E), size: 32),
          ),
          const SizedBox(height: 20),
          Text(
            denied ? '카메라 권한이 거부됐어요' : '카메라를 열 수 없어요',
            style: const TextStyle(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            denied
                ? '설정 → 앱 → 권한에서 카메라를 허용하면\nQR 스캔을 쓸 수 있어요.'
                : '기기에 카메라가 없거나 다른 앱이 쓰는 중일 수 있어요.',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white70, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: onBack,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.9),
                foregroundColor: const Color(0xFF3E2723),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
              ),
              child: const Text('돌아가기',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 스캔 전 하단 안내.
class _PermissionNote extends StatelessWidget {
  const _PermissionNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(32, 20, 32, 36),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45)),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.camera_alt, color: Color(0xFFC67C4E), size: 24),
          SizedBox(height: 10),
          Text(
            'QR 스캔에만 카메라를 사용해요. 사진은 저장되지 않아요.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// 스캔 결과(성공·실패) 시트.
class _ResultSheet extends StatelessWidget {
  const _ResultSheet({
    required this.message,
    required this.isError,
    required this.isLoading,
    required this.onRetry,
    required this.onClose,
  });

  final String message;
  final bool isError;
  final bool isLoading;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
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
            decoration: BoxDecoration(
              color:
                  isError ? const Color(0xFFFFF1F0) : const Color(0xFFE8F5E9),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: isError ? Colors.redAccent : Colors.green,
              size: 30,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Color(0xFF5D4037), fontSize: 15, height: 1.5),
          ),
          const SizedBox(height: 28),
          if (isLoading)
            const CircularProgressIndicator(color: Color(0xFFC67C4E))
          else
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: TextButton(
                      onPressed: onClose,
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF5D4037),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                      ),
                      child: const Text('닫기',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: onRetry,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3E2723),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                      ),
                      child: const Text('다시 스캔',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
