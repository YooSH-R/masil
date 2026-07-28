import '../entities/robot.dart';

abstract class RobotRepository {
  Future<Robot?> registerRobot(String qrCode);
  Future<Robot?> getMyRobot();
  Future<bool> unregisterRobot();
  Stream<RobotStatus> monitorStatus();
}
