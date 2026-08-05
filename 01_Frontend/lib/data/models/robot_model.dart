import '../../core/utils/json_parse.dart';
import '../../domain/entities/robot.dart';

const _modeMapping = <String, RobotMode>{
  'IDLE': RobotMode.idle,
  'WALKING': RobotMode.walking,
  'WALK': RobotMode.walking,
  'PLAYING': RobotMode.playing,
  'PLAY': RobotMode.playing,
  'CHARGING': RobotMode.charging,
  'DOCKED': RobotMode.charging,
  'ROAMING': RobotMode.roaming,
};

class RobotModel extends Robot {
  const RobotModel({
    required super.id,
    required super.online,
    required super.batteryLevel,
    super.docked,
    super.currentMode,
    super.serialNumber,
    super.lastConnectedAt,
  });

  factory RobotModel.fromJson(Map<String, dynamic> json) {
    return RobotModel(
      id: Json.asInt(json['robotId'] ?? json['id']),
      online: Json.asBool(json['online']),
      batteryLevel: Json.asInt(json['batteryLevel']),
      docked: Json.asBool(json['docked']),
      currentMode: Json.asEnum(json['currentMode'], _modeMapping, RobotMode.unknown),
      serialNumber: Json.asStringOrNull(json['serialNumber']),
      lastConnectedAt: Json.asDateTime(json['lastConnectedAt']),
    );
  }
}

class RobotPairingModel extends RobotPairing {
  const RobotPairingModel({
    required super.robotId,
    required super.petId,
    required super.serialNumber,
    required super.pairingStatus,
    super.pairingId,
    super.modelName,
    super.firmwareVersion,
    super.pairedAt,
  });

  factory RobotPairingModel.fromJson(Map<String, dynamic> json) {
    return RobotPairingModel(
      robotId: Json.asInt(json['robotId']),
      petId: Json.asInt(json['petId']),
      serialNumber: Json.asString(json['serialNumber']),
      pairingStatus: Json.asString(json['pairingStatus'], fallback: 'UNKNOWN'),
      pairingId: Json.asIntOrNull(json['pairingId']),
      modelName: Json.asStringOrNull(json['modelName']),
      firmwareVersion: Json.asStringOrNull(json['firmwareVersion']),
      pairedAt: Json.asDateTime(json['pairedAt']),
    );
  }
}
