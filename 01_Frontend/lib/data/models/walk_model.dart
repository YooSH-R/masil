import '../../core/utils/json_parse.dart';
import '../../domain/entities/walk.dart';

const _walkStatusMapping = <String, WalkStatus>{
  'READY': WalkStatus.ready,
  'ACTIVE': WalkStatus.active,
  'PROCESSING': WalkStatus.processing,
  'COMPLETED': WalkStatus.completed,
  'CANCELLED': WalkStatus.cancelled,
  'CANCELED': WalkStatus.cancelled,
};

class WalkProposalModel extends WalkProposal {
  const WalkProposalModel({
    required super.proposalId,
    required super.petId,
    required super.message,
    super.reason,
    super.expiresAt,
  });

  factory WalkProposalModel.fromJson(Map<String, dynamic> json) {
    return WalkProposalModel(
      proposalId: Json.asInt(json['proposalId']),
      petId: Json.asInt(json['petId']),
      message: Json.asString(json['message'], fallback: '산책하러 갈까요?'),
      reason: Json.asStringOrNull(json['reason']),
      expiresAt: Json.asDateTime(json['expiresAt']),
    );
  }
}

class WalkModel extends Walk {
  const WalkModel({
    required super.walkId,
    required super.status,
    super.createdAt,
    super.startedAt,
    super.endedAt,
    super.durationSeconds,
    super.distanceMeters,
  });

  factory WalkModel.fromJson(Map<String, dynamic> json) {
    return WalkModel(
      walkId: Json.asInt(json['walkId'] ?? json['id']),
      status: Json.asEnum(json['status'], _walkStatusMapping, WalkStatus.unknown),
      createdAt: Json.asDateTime(json['createdAt']),
      startedAt: Json.asDateTime(json['startedAt']),
      endedAt: Json.asDateTime(json['endedAt']),
      durationSeconds: Json.asIntOrNull(json['durationSeconds']),
      distanceMeters: Json.asIntOrNull(json['distanceMeters']),
    );
  }
}

class WalkLocationPointModel extends WalkLocationPoint {
  const WalkLocationPointModel({
    required super.latitude,
    required super.longitude,
    required super.sequence,
    required super.recordedAt,
    super.accuracy,
  });

  factory WalkLocationPointModel.fromJson(Map<String, dynamic> json) {
    return WalkLocationPointModel(
      latitude: Json.asDouble(json['latitude']),
      longitude: Json.asDouble(json['longitude']),
      sequence: Json.asInt(json['sequence']),
      recordedAt: Json.asDateTime(json['recordedAt']) ?? DateTime.now().toUtc(),
      accuracy: Json.asDoubleOrNull(json['accuracy']),
    );
  }
}

class WalkLocationBatchResultModel extends WalkLocationBatchResult {
  const WalkLocationBatchResultModel({
    required super.walkId,
    required super.receivedCount,
    required super.savedCount,
    required super.rejectedCount,
  });

  factory WalkLocationBatchResultModel.fromJson(Map<String, dynamic> json) {
    return WalkLocationBatchResultModel(
      walkId: Json.asInt(json['walkId']),
      receivedCount: Json.asInt(json['receivedCount']),
      savedCount: Json.asInt(json['savedCount']),
      rejectedCount: Json.asInt(json['rejectedCount']),
    );
  }
}

class WalkSummaryModel extends WalkSummary {
  const WalkSummaryModel({
    required super.walkId,
    super.durationSeconds,
    super.distanceMeters,
    super.route,
    super.startedAt,
    super.endedAt,
  });

  factory WalkSummaryModel.fromJson(Map<String, dynamic> json) {
    return WalkSummaryModel(
      walkId: Json.asInt(json['walkId']),
      durationSeconds: Json.asIntOrNull(json['durationSeconds']),
      distanceMeters: Json.asIntOrNull(json['distanceMeters']),
      route: Json.asMapList(json['route'])
          .map(WalkLocationPointModel.fromJson)
          .toList(growable: false),
      startedAt: Json.asDateTime(json['startedAt']),
      endedAt: Json.asDateTime(json['endedAt']),
    );
  }
}
