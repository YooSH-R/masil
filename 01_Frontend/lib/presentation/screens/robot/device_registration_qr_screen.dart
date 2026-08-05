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
///   카메라 권한 → QR 스캔 → 토큰 형식 검증 → POST /robots/pairings
///
/// 서버는 등록에 `petId` 를 요구하는데 펫 조회 API 가 아직 배포되지 않았다.
/// petId 를 못 구하면 스캔 결과를 [RobotViewModel.holdScannedToken] 으로
/// 보관해두고, petId 가 생기면 `pairWithPendingToken` 으로 이어서 등록한다.
/// 즉 스캔·권한·검증은 지금 그대로 동작하고, 서버 등록만 나중에 이어진다.
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

  /// 보관해둔 토큰으로 이어서 등록하는 중인지. 매 rebuild 마다 다시 시도하는
  /// 것을 막는다.
  bool _resumingPending = false;

  @override
  void initState() {
    super.initState();
    // 등록에는 petId 가 필요하다. 미리 불러두면 스캔 직후 바로 등록까지 간다.
    // 펫 API 가 없으면 조용히 실패하고, 스캔은 그대로 동작한다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<PetViewModel>().loadCurrentPet(silent: true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// petId 를 못 구해 보관해둔 토큰으로 등록을 마무리한다.
  ///
  /// 스캔 시점에 펫 정보가 없어 미뤄둔 경우, 펫 정보가 도착하면 사용자가
  /// QR 을 다시 찍지 않아도 등록이 이어진다.
  Future<void> _resumePendingPairing(int petId) async {
    final robotVm = context.read<RobotViewModel>();

    final paired = await robotVm.pairWithPendingToken(petId: petId);
    if (!mounted) return;

    if (!paired) {
      // 실패했으면 다시 시도할 수 있게 플래그를 풀어준다.
      _resumingPending = false;
      _show(robotVm.errorMessage ?? '기기 등록에 실패했어요. 다시 시도해 주세요.',
          isError: true);
      return;
    }

    _show('기기가 등록됐어요!');
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    context.pop();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling || capture.barcodes.isEmpty) return;

    final raw = capture.barcodes.first.rawValue;
    final token = RobotQr.extractToken(raw);

    if (token == null) {
      // 다른 앱 QR·광고 QR 등. 서버에 보내지 않고 바로 안내한다.
      _show('마실이 기기의 QR 코드가 아니에요. 기기 밑면의 QR을 비춰 주세요.',
          isError: true);
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
    final petId = context.read<PetViewModel>().petId;

    if (petId == null) {
      // 펫이 없어 petId 를 못 구한 경우. 토큰은 버리지 않고 보관한다.
      robotVm.holdScannedToken(token);
      _show('QR을 인식했어요. 펫 정보를 불러온 뒤 등록을 완료할 수 있어요.');
      return;
    }

    final paired = await robotVm.pairRobot(petId: petId, qrToken: token);
    if (!mounted) return;

    if (!paired) {
      _show(robotVm.errorMessage ?? '기기 등록에 실패했어요. 다시 시도해 주세요.',
          isError: true);
      return;
    }

    _show('기기가 등록됐어요!');
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    context.pop();
  }

  /// 카메라 없이 토큰을 직접 넣어 등록해 본다. **디버그 빌드에서만** 쓴다.
  ///
  /// 에뮬레이터 카메라는 호스트 화면을 못 보기 때문에 QR 을 비출 수가 없다.
  /// 그렇다고 스캔 이후 흐름(형식 검증 → petId 확인 → 서버 등록 → 결과 표시)을
  /// 확인 못 하면 시연 전에 남는 위험이 크다. 그래서 카메라 단계만 건너뛴다.
  Future<void> _openManualEntry() async {
    final controller = TextEditingController();

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
              controller: controller,
              autofocus: true,
              maxLines: 3,
              minLines: 2,
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
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('등록 시도'),
          ),
        ],
      ),
    );

    if (input == null || input.isEmpty || !mounted) return;

    // 스캔과 똑같이 형식부터 검증한다. 이 단계도 확인 대상이다.
    final token = RobotQr.extractToken(input);
    if (token == null) {
      _show('토큰 형식이 맞지 않아요. 43자 이상의 영문·숫자·_- 조합이어야 해요.',
          isError: true);
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
    final petId = context.watch<PetViewModel>().petId;

    // 스캔은 됐지만 petId 가 없어 미뤄둔 등록이 있고, 이제 petId 가 생겼으면
    // 사용자가 QR 을 다시 찍지 않아도 이어서 등록한다.
    if (!_resumingPending &&
        !_handling &&
        robotVm.hasPendingToken &&
        petId != null &&
        !robotVm.isLoading) {
      _resumingPending = true;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _resumePendingPairing(petId));
    }

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
          Positioned(
            top: 120,
            left: 24,
            right: 24,
            child: Column(
              children: [
                const Text(
                  '마실이 기기 하단의\nQR 코드를 스캔해 주세요',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(blurRadius: 8, color: Colors.black54)]),
                ),
                if (robotVm.hasPendingToken && _message == null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '인식된 QR이 있어요 · 펫 정보 준비 후 등록됩니다',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ],
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
    final denied =
        error.errorCode == MobileScannerErrorCode.permissionDenied;

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
                  style:
                      TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
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
              color: isError ? const Color(0xFFFFF1F0) : const Color(0xFFE8F5E9),
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
