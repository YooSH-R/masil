import '../entities/robot.dart';

/// 명세서 2.2 로봇 API.
///
/// POST /robots/{robotId}/interactions 는 Jetson 보드가 DEVICE_ACCESS_TOKEN으로
/// 호출하는 엔드포인트라 앱에서는 다루지 않는다(명세서 5.1).
abstract class RobotRepository {
  /// POST /robots/pairings — QR 로봇 등록
  Future<RobotPairing> pairRobot({
    required int petId,
    required String qrToken,
    required String deviceNonce,
  });

  /// GET /robots/{robotId}/status — 로봇 상태 조회
  Future<Robot> getStatus(int robotId);

  /// DELETE /robots/{robotId}/pairing — 로봇 등록 해제
  Future<void> unpair(int robotId);

  /// 캐시된 robotId로 현재 로봇 상태 조회. 등록된 로봇이 없으면 null.
  Future<Robot?> getCurrentRobotStatus();

  /// 상태 화면에서 주기적으로 폴링할 때 사용.
  Stream<Robot> watchStatus(int robotId, {Duration interval});
}
