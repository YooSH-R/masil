import 'dart:async';
import 'dart:math';

import '../../domain/entities/robot.dart';
import '../../domain/repositories/robot_repository.dart';
import 'base_view_model.dart';

class RobotViewModel extends BaseViewModel {
  RobotViewModel(this._robotRepository);

  final RobotRepository _robotRepository;

  Robot? _robot;
  RobotPairing? _pairing;
  StreamSubscription<Robot>? _watchSub;

  Robot? get robot => _robot;
  RobotPairing? get pairing => _pairing;
  bool get isConnected => _robot?.online ?? false;
  bool get hasRobot => _robot != null;

  /// GET /robots/{robotId}/status — 캐시된 robotId 기준.
  Future<void> loadStatus({bool silent = false}) async {
    final robot = await guard<Robot?>(
      () => _robotRepository.getCurrentRobotStatus(),
      silent: silent,
    );
    if (robot == null) return;

    _robot = robot;
    safeNotify();
  }

  /// POST /robots/pairings — QR 코드로 로봇 등록.
  /// [qrToken]은 QR 스캔 결과 문자열.
  Future<bool> pairRobot({
    required int petId,
    required String qrToken,
  }) async {
    final pairing = await guard(() => _robotRepository.pairRobot(
          petId: petId,
          qrToken: qrToken,
          deviceNonce: _generateNonce(),
        ));
    if (pairing == null) return false;

    _pairing = pairing;
    safeNotify();

    // 등록 직후 상태를 한 번 읽어 화면에 배터리·모드를 채운다.
    await loadStatus(silent: true);
    return pairing.isPaired;
  }

  /// DELETE /robots/{robotId}/pairing — 등록 해제.
  Future<bool> unpair() async {
    final id = _robot?.id ?? _pairing?.robotId;
    if (id == null) return false;

    await guard(() => _robotRepository.unpair(id));
    if (hasError) return false;

    _robot = null;
    _pairing = null;
    stopWatching();
    safeNotify();
    return true;
  }

  /// 연결 관리 화면에서 상태를 주기적으로 갱신.
  void startWatching({Duration interval = const Duration(seconds: 10)}) {
    final id = _robot?.id;
    if (id == null || _watchSub != null) return;

    _watchSub = _robotRepository
        .watchStatus(id, interval: interval)
        .listen((robot) {
      _robot = robot;
      safeNotify();
    });
  }

  void stopWatching() {
    _watchSub?.cancel();
    _watchSub = null;
  }

  @override
  void dispose() {
    stopWatching();
    super.dispose();
  }

  /// 명세서 4.3의 deviceNonce (BLE에서 생성하는 값 대체).
  String _generateNonce() {
    final random = Random.secure();
    final bytes = List.generate(12, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
