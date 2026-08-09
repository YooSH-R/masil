import 'dart:async';

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

  Future<bool> validateRegistrationQr(String qrToken) async {
    await guard(
        () => _robotRepository.validateRegistrationQr(qrToken: qrToken));
    return !hasError;
  }

  Future<bool> registerNewPet({
    required String qrToken,
    required String petName,
  }) async {
    final pairing = await guard(() => _robotRepository.registerNewPet(
          qrToken: qrToken,
          petName: petName,
        ));
    if (pairing == null) return false;

    _pairing = pairing;
    _pendingQrToken = null;
    safeNotify();
    await loadStatus(silent: true);
    return pairing.isPaired;
  }

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

  /// 스캔에 성공했지만 아직 서버에 등록하지 못한 토큰.
  ///
  /// 서버는 등록에 petId 를 요구하는데, 펫 조회 API 가 아직 배포되지 않아
  /// petId 를 못 구하는 경우가 있다. 그때 스캔 결과를 버리지 않고 여기 담아두면
  /// petId 가 준비되는 즉시 [pairWithPendingToken] 으로 이어서 등록할 수 있다.
  String? _pendingQrToken;
  String? get pendingQrToken => _pendingQrToken;
  bool get hasPendingToken => _pendingQrToken != null;

  /// QR 스캔 결과를 보관한다. 등록은 아직 하지 않는다.
  void holdScannedToken(String qrToken) {
    _pendingQrToken = qrToken;
    safeNotify();
  }

  void clearPendingToken() {
    if (_pendingQrToken == null) return;
    _pendingQrToken = null;
    safeNotify();
  }

  /// 보관해둔 토큰으로 등록을 시도한다. petId 가 생긴 뒤 호출한다.
  Future<bool> pairWithPendingToken({required int petId}) async {
    final token = _pendingQrToken;
    if (token == null) return false;
    return pairRobot(petId: petId, qrToken: token);
  }

  /// POST /robots/pairings — QR 코드로 로봇 등록.
  ///
  /// [qrToken] 은 QR 에서 뽑아낸 정적 토큰(43~512자). 서버는
  /// `{petId, qrToken}` 만 받는다.
  Future<bool> pairRobot({
    required int petId,
    required String qrToken,
  }) async {
    final pairing = await guard(() => _robotRepository.pairRobot(
          petId: petId,
          qrToken: qrToken,
        ));
    if (pairing == null) return false;

    _pairing = pairing;
    // 등록에 성공했으면 보관 중인 토큰은 더 필요 없다.
    _pendingQrToken = null;
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

  void clearAfterPetDeletion() {
    _robot = null;
    _pairing = null;
    _pendingQrToken = null;
    stopWatching();
    safeNotify();
  }

  /// 연결 관리 화면에서 상태를 주기적으로 갱신.
  void startWatching({Duration interval = const Duration(seconds: 10)}) {
    final id = _robot?.id;
    if (id == null || _watchSub != null) return;

    _watchSub =
        _robotRepository.watchStatus(id, interval: interval).listen((robot) {
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
}
