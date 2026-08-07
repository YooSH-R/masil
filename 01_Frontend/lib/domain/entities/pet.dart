/// 친밀도 점수에 따라 달라지는 마실이와의 관계 상태.
enum PetMood { wary, calm, friendly, happy }

extension PetMoodX on PetMood {
  String get label => switch (this) {
        PetMood.wary => '낯가리는 중',
        PetMood.calm => '마음 여는 중',
        PetMood.friendly => '가까운 사이',
        PetMood.happy => '최고의 단짝',
      };

  /// 친밀도 상세 화면에 표시할 관계 설명.
  String get homeMessage => switch (this) {
        PetMood.wary => '아직 서로 알아가는 중이에요',
        PetMood.calm => '마실이가 조금씩 마음을 열고 있어요',
        PetMood.friendly => '마실이와 제법 가까워졌어요',
        PetMood.happy => '마실이와 최고의 단짝이에요!',
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
    this.dailyWalkCount = defaultDailyWalkCount,
    this.profileImageUrl,
    this.affinity,
    this.robot,
    this.createdAt,
  });

  /// 서버 `PetJpaEntity.DEFAULT_DAILY_WALK_COUNT` 와 같은 값이다.
  static const int defaultDailyWalkCount = 2;
  static const int minDailyWalkCount = 1;
  static const int maxDailyWalkCount = 24;

  final int id;
  final String name;

  /// 하루 산책 횟수. 마실이가 산책을 조르는 간격을 정한다.
  final int dailyWalkCount;
  final String? profileImageUrl;
  final Affinity? affinity;
  final PairedRobotSummary? robot;
  final DateTime? createdAt;
}
