/// 명세서 "11. 상태값 - 친밀도 기분 상태".
enum PetMood { happy, neutral, lonely, sleeping, excited }

extension PetMoodX on PetMood {
  String get label => switch (this) {
        PetMood.happy => '기분 좋음',
        PetMood.neutral => '보통',
        PetMood.lonely => '교감 부족',
        PetMood.sleeping => '충전 중',
        PetMood.excited => '신남',
      };

  /// 홈 화면 상태 배지 문구.
  String get homeMessage => switch (this) {
        PetMood.happy => '오늘 기분 최고예요! ✨',
        PetMood.neutral => '평온한 하루를 보내고 있어요',
        PetMood.lonely => '조금 외로워하고 있어요',
        PetMood.sleeping => '충전하며 쉬고 있어요',
        PetMood.excited => '나갈 준비가 됐어요!',
      };
}

/// 친밀도 (명세서 5.2).
class Affinity {
  const Affinity({
    required this.score,
    required this.level,
    required this.mood,
    this.change,
    this.changeReason,
    this.updatedAt,
  });

  final int score;
  final int level;
  final PetMood mood;
  final int? change;
  final String? changeReason;
  final DateTime? updatedAt;

  /// 진행바에 쓰는 0.0~1.0 값.
  double get progress => score.clamp(0, 100) / 100;
}

/// 친밀도 변화 이력 한 건 (명세서 2.3 /affinity/history).
class AffinityHistoryEntry {
  const AffinityHistoryEntry({
    required this.score,
    required this.change,
    this.reason,
    this.recordedAt,
  });

  final int score;
  final int change;
  final String? reason;
  final DateTime? recordedAt;
}

/// 펫 프로필 조회 응답에 함께 오는 로봇 요약.
class PairedRobotSummary {
  const PairedRobotSummary({
    required this.robotId,
    required this.online,
    required this.batteryLevel,
  });

  final int robotId;
  final bool online;
  final int batteryLevel;
}

/// 명세서 4.1/4.2의 펫.
class Pet {
  const Pet({
    required this.id,
    required this.name,
    this.profileImageUrl,
    this.affinity,
    this.robot,
    this.createdAt,
  });

  final int id;
  final String name;
  final String? profileImageUrl;
  final Affinity? affinity;
  final PairedRobotSummary? robot;
  final DateTime? createdAt;
}
