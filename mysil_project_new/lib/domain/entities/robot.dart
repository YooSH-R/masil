/// 로봇 동작 모드. 명세서 4.4의 currentMode.
/// 명세서에 전체 목록이 없어 IDLE 외에는 서버 값에 맞춰 확장한다.
enum RobotMode { idle, walking, playing, charging, roaming, unknown }

extension RobotModeX on RobotMode {
  String get label => switch (this) {
        RobotMode.idle => '대기 중',
        RobotMode.walking => '산책 중',
        RobotMode.playing => '놀이 중',
        RobotMode.charging => '충전 중',
        RobotMode.roaming => '자율 주행 중',
        RobotMode.unknown => '알 수 없음',
      };
}

/// 명세서 4.4 로봇 상태 조회.
class Robot {
  const Robot({
    required this.id,
    required this.online,
    required this.batteryLevel,
    this.docked = false,
    this.currentMode = RobotMode.unknown,
    this.serialNumber,
    this.lastConnectedAt,
  });

  final int id;
  final bool online;
  final int batteryLevel;
  final bool docked;
  final RobotMode currentMode;
  final String? serialNumber;
  final DateTime? lastConnectedAt;

  bool get isLowBattery => batteryLevel <= 20;
}

/// 명세서 4.3 QR 로봇 등록 결과.
class RobotPairing {
  const RobotPairing({
    required this.robotId,
    required this.petId,
    required this.serialNumber,
    required this.pairingStatus,
    this.deviceAccessToken,
    this.pairedAt,
  });

  final int robotId;
  final int petId;
  final String serialNumber;
  final String pairingStatus;
  final String? deviceAccessToken;
  final DateTime? pairedAt;

  bool get isPaired => pairingStatus.toUpperCase() == 'PAIRED';
}
