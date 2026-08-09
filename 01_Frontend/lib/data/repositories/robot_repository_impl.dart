import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/network/api_exception.dart';
import '../../core/storage/session_cache.dart';
import '../../core/utils/json_parse.dart';
import '../../domain/entities/robot.dart';
import '../../domain/repositories/robot_repository.dart';
import '../models/robot_model.dart';

class RobotRepositoryImpl implements RobotRepository {
  RobotRepositoryImpl({
    required ApiClient client,
    required SessionCache sessionCache,
  })  : _client = client,
        _cache = sessionCache;

  final ApiClient _client;
  final SessionCache _cache;

  @override
  Future<void> validateRegistrationQr({required String qrToken}) async {
    await _client.post(
      ApiEndpoints.robotRegistrationValidation,
      data: {'qrToken': qrToken},
    );
  }

  @override
  Future<RobotPairing> registerNewPet({
    required String qrToken,
    required String petName,
  }) async {
    final data = await _client.post(
      ApiEndpoints.robotRegistrations,
      data: {
        'qrToken': qrToken,
        'petName': petName,
      },
      idempotencyKey: 'register-robot-$qrToken',
    );

    final pairing = RobotPairingModel.fromJson(Json.asMap(data));
    await _cache.savePetId(pairing.petId);
    await _cache.saveRobotId(pairing.robotId);
    return pairing;
  }

  @override
  Future<RobotPairing> pairRobot({
    required int petId,
    required String qrToken,
  }) async {
    final data = await _client.post(
      ApiEndpoints.robotPairings,
      // 서버 RobotPairingRequest 는 {petId, qrToken} 만 받는다.
      // 이전에 함께 보내던 deviceNonce 는 서버에 없는 필드였다.
      data: {
        'petId': petId,
        'qrToken': qrToken,
      },
      idempotencyKey: 'pairing-robot-$qrToken',
    );

    final pairing = RobotPairingModel.fromJson(Json.asMap(data));
    await _cache.saveRobotId(pairing.robotId);

    // 명세서 2026-07-29 개정으로 등록 응답에서 deviceAccessToken 이 제거됐다.
    // (정적 QR 방식으로 바뀌면서 기기 토큰은 이 응답으로 내려오지 않는다)
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
