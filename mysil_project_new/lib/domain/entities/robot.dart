enum RobotStatus { connected, disconnected, charging, roaming }

class Robot {
  final String id;
  final String serialNumber;
  final RobotStatus status;
  final int batteryLevel;

  Robot({
    required this.id,
    required this.serialNumber,
    required this.status,
    required this.batteryLevel,
  });
}
