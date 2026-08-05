import '../../core/utils/json_parse.dart';
import '../../domain/entities/pet.dart';

const _moodMapping = <String, PetMood>{
  'HAPPY': PetMood.happy,
  'NEUTRAL': PetMood.neutral,
  'LONELY': PetMood.lonely,
  'SLEEPING': PetMood.sleeping,
  'EXCITED': PetMood.excited,
  // 현재 로컬 백엔드 시드와 MQTT 친밀도 상태값.
  'FRIENDLY': PetMood.happy,
};

class AffinityModel extends Affinity {
  const AffinityModel({
    required super.score,
    required super.level,
    required super.mood,
    super.change,
    super.changeReason,
    super.updatedAt,
  });

  factory AffinityModel.fromJson(Map<String, dynamic> json) {
    return AffinityModel(
      score: Json.asInt(json['score']),
      level: Json.asInt(json['level'], fallback: 1),
      mood: Json.asEnum(json['mood'], _moodMapping, PetMood.neutral),
      change: Json.asIntOrNull(json['change']),
      changeReason: Json.asStringOrNull(json['changeReason']),
      updatedAt: Json.asDateTime(json['updatedAt']),
    );
  }
}

class AffinityHistoryEntryModel extends AffinityHistoryEntry {
  const AffinityHistoryEntryModel({
    required super.score,
    required super.change,
    super.reason,
    super.recordedAt,
  });

  factory AffinityHistoryEntryModel.fromJson(Map<String, dynamic> json) {
    return AffinityHistoryEntryModel(
      score: Json.asInt(json['score']),
      change: Json.asInt(json['change']),
      reason: Json.asStringOrNull(json['reason'] ?? json['changeReason']),
      recordedAt: Json.asDateTime(json['recordedAt'] ?? json['updatedAt']),
    );
  }
}

class PairedRobotSummaryModel extends PairedRobotSummary {
  const PairedRobotSummaryModel({
    required super.robotId,
    required super.online,
    required super.batteryLevel,
  });

  factory PairedRobotSummaryModel.fromJson(Map<String, dynamic> json) {
    return PairedRobotSummaryModel(
      robotId: Json.asInt(json['robotId']),
      online: Json.asBool(json['online']),
      batteryLevel: Json.asInt(json['batteryLevel']),
    );
  }
}

class PetModel extends Pet {
  const PetModel({
    required super.id,
    required super.name,
    super.profileImageUrl,
    super.affinity,
    super.robot,
    super.createdAt,
  });

  factory PetModel.fromJson(Map<String, dynamic> json) {
    final affinityJson = Json.asMapOrNull(json['affinity']);
    final robotJson = Json.asMapOrNull(json['robot']);
    return PetModel(
      id: Json.asInt(json['petId'] ?? json['id']),
      name: Json.asString(json['name']),
      profileImageUrl: Json.asStringOrNull(
        json['profileImageUrl'] ?? json['profileImage'],
      ),
      affinity:
          affinityJson == null ? null : AffinityModel.fromJson(affinityJson),
      robot: robotJson == null
          ? null
          : PairedRobotSummaryModel.fromJson(robotJson),
      createdAt: Json.asDateTime(json['createdAt']),
    );
  }
}
