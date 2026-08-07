import '../../core/utils/korea_time.dart';

/// 산책 보상으로 받는 리본 한 종류.
class WalkRibbon {
  const WalkRibbon({
    required this.requiredWalks,
    required this.name,
    required this.emoji,
    this.earnedOn,
  });

  /// 이 리본을 받으려면 산책을 몇 번 해야 하는지(누적).
  final int requiredWalks;
  final String name;
  final String emoji;

  /// 이 리본을 받은 날(한국 날짜) = 조건을 채운 그 산책의 날. null 이면 미획득.
  final DateTime? earnedOn;

  bool get isEarned => earnedOn != null;

  WalkRibbon _withEarnedOn(DateTime? day) => WalkRibbon(
        requiredWalks: requiredWalks,
        name: name,
        emoji: emoji,
        earnedOn: day,
      );
}

/// 산책 기록에서 계산한 진행 상황과 보상.
///
/// 홈의 "오늘의 산책"·"산책 미션" 과 친밀도 화면의 "받은 보상" 이 서로 다른
/// 숫자를 보여주면 안 되므로 계산을 이 한곳에 둔다.
///
/// 서버에 보상 API 가 없어서 산책 기록에서 전부 유도한다. 따로 저장하는 상태가
/// 없으니 앱을 지우거나 기기를 바꿔도 같은 기록이면 같은 리본이 나온다.
///
/// **보상 기준은 연속 일수가 아니라 누적 횟수다.** 연속은 하루만 비어도
/// 끊겨서, 실제 기록으로는 리본이 거의 열리지 않고 화면이 빈 채로 남는다.
/// 누적은 걸은 만큼 정직하게 쌓인다. 연속 최고 기록은 참고용으로만 남긴다.
class WalkProgress {
  const WalkProgress({
    required this.todayCount,
    required this.totalCount,
    required this.longestStreakDays,
    required this.ribbons,
  });

  /// 받을 수 있는 리본 목록. 낮은 단계부터 둔다.
  static const List<WalkRibbon> catalog = [
    WalkRibbon(requiredWalks: 1, name: '첫 산책 리본', emoji: '🎀'),
    WalkRibbon(requiredWalks: 5, name: '산책 5회 리본', emoji: '🩵'),
    WalkRibbon(requiredWalks: 10, name: '산책 10회 리본', emoji: '💛'),
    WalkRibbon(requiredWalks: 30, name: '산책 30회 리본', emoji: '💜'),
    WalkRibbon(requiredWalks: 100, name: '산책 100회 리본', emoji: '👑'),
  ];

  /// 오늘 산책한 횟수. 하루 목표(펫 설정)와 비교해 보여준다.
  final int todayCount;

  /// 누적 산책 횟수. 리본 획득 기준이다.
  final int totalCount;

  /// 지금까지의 최장 연속 일수. 보상 카드의 참고 문구에만 쓴다.
  final int longestStreakDays;

  final List<WalkRibbon> ribbons;

  static const WalkProgress none = WalkProgress(
    todayCount: 0,
    totalCount: 0,
    longestStreakDays: 0,
    ribbons: catalog,
  );

  List<WalkRibbon> get earnedRibbons =>
      ribbons.where((ribbon) => ribbon.isEarned).toList(growable: false);

  /// 아직 못 받은 가장 낮은 단계의 리본. 전부 받았으면 null.
  WalkRibbon? get nextRibbon {
    for (final ribbon in ribbons) {
      if (!ribbon.isEarned) return ribbon;
    }
    return null;
  }

  /// 다음 리본까지 남은 산책 횟수. 전부 받았으면 null.
  int? get walksToNextRibbon {
    final next = nextRibbon;
    if (next == null) return null;
    final remaining = next.requiredWalks - totalCount;
    return remaining < 1 ? 1 : remaining;
  }

  /// 다음 리본까지의 진행률(0.0~1.0). 전부 받았으면 1.0.
  ///
  /// 이전 단계부터가 아니라 0부터 센다. 화면에 `10 / 30회` 라고 적어두므로
  /// 진행 바도 같은 비율이어야 사용자가 딴 값으로 읽지 않는다.
  double get progressToNextRibbon {
    final next = nextRibbon;
    if (next == null) return 1;
    return (totalCount / next.requiredWalks).clamp(0.0, 1.0);
  }

  /// 산책 시각 목록에서 계산한다.
  ///
  /// [walkedAt] 은 절대 시각이고, 날짜 경계는 [KoreaTime] 기준으로 본다.
  /// 기기 시간대가 해외로 맞춰져 있어도 "오늘" 이 밀리지 않게 하려는 것이다.
  factory WalkProgress.from(Iterable<DateTime> walkedAt, {DateTime? now}) {
    final today = _dayOf(now ?? DateTime.now());

    final sortedWalks = walkedAt.toList()..sort();
    if (sortedWalks.isEmpty) return none;

    var todayCount = 0;
    final days = <DateTime>{};
    for (final at in sortedWalks) {
      final day = _dayOf(at);
      days.add(day);
      if (day == today) todayCount++;
    }

    // n 번째 산책을 한 날이 곧 그 리본을 받은 날이다.
    final earnedOn = <int, DateTime>{};
    for (final ribbon in catalog) {
      if (sortedWalks.length >= ribbon.requiredWalks) {
        earnedOn[ribbon.requiredWalks] =
            _dayOf(sortedWalks[ribbon.requiredWalks - 1]);
      }
    }

    return WalkProgress(
      todayCount: todayCount,
      totalCount: sortedWalks.length,
      longestStreakDays: _longestStreakDays(days),
      ribbons: catalog
          .map((ribbon) => ribbon._withEarnedOn(earnedOn[ribbon.requiredWalks]))
          .toList(growable: false),
    );
  }

  /// 날짜 집합에서 가장 긴 연속 구간의 일수.
  static int _longestStreakDays(Set<DateTime> days) {
    if (days.isEmpty) return 0;
    final sorted = days.toList()..sort();

    var longest = 1;
    var run = 1;
    for (var i = 1; i < sorted.length; i++) {
      run = sorted[i].difference(sorted[i - 1]).inDays == 1 ? run + 1 : 1;
      if (run > longest) longest = run;
    }
    return longest;
  }

  /// 절대 시각을 한국 날짜(자정)로 자른다.
  static DateTime _dayOf(DateTime value) {
    final korea = KoreaTime.fromInstant(value);
    return DateTime.utc(korea.year, korea.month, korea.day);
  }
}
