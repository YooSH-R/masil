import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/network/api_exception.dart';
import '../../core/storage/session_cache.dart';
import '../../core/storage/token_storage.dart';
import '../../core/utils/json_parse.dart';
import '../../domain/entities/robot.dart';
import '../../domain/repositories/robot_repository.dart';
import '../models/robot_model.dart';

class RobotRepositoryImpl implements RobotRepository {
  RobotRepositoryImpl({
    required ApiClient client,
    required SessionCache sessionCache,
    required TokenStorage tokenStorage,
  })  : _client = client,
        _cache = sessionCache,
        _tokenStorage = tokenStorage;

  final ApiClient _client;
  final SessionCache _cache;
  final TokenStorage _tokenStorage;

  @override
  Future<RobotPairing> pairRobot({
    required int petId,
    required String qrToken,
    required String deviceNonce,
  }) async {
    final data = await _client.post(
      ApiEndpoints.robotPairings,
      data: {
        'petId': petId,
        'qrToken': qrToken,
        'deviceNonce': deviceNonce,
      },
      idempotencyKey: 'pairing-robot-$qrToken',
    );

    final pairing = RobotPairingModel.fromJson(Json.asMap(data));
    await _cache.saveRobotId(pairing.robotId);

    // Jetson 전용 토큰은 페어링 응답에서만 받을 수 있어 즉시 저장한다.
    final deviceToken = pairing.deviceAccessToken;
    if (deviceToken != null) {
      await _tokenStorage.saveDeviceAccessToken(deviceToken);
    }
    return pairing;
  }

  @override
  Future<Robot> getStatus(int robotId) async {
    final data = await _client.get(ApiEndpoints.robotStatus(robotId));
    return RobotModel.fromJson(Json.asMap(data));
  }

  @override
  Future<void> unpair(int robotId) async {
    await _client.delete(ApiEndpoints.robotPairing(robotId));
    await _cache.clearRobotId();
  }

  @override
  Future<Robot?> getCurrentRobotStatus() async {
    final robotId = await _cache.readRobotId();
    if (robotId == null) return null;
    try {
      return await getStatus(robotId);
    } on ApiException catch (e) {
      if (e.isNotFound) return null;
      rethrow;
    }
  }

  @override
  Stream<Robot> watchStatus(
    int robotId, {
    Duration interval = const Duration(seconds: 10),
  }) async* {
    while (true) {
      try {
        yield await getStatus(robotId);
      } on ApiException {
        // 일시적 실패는 건너뛰고 다음 주기에 재시도한다.
      }
      await Future<void>.delayed(interval);
    }
  }
}
