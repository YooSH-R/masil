import 'package:flutter_test/flutter_test.dart';
import 'package:mysil_project_new/domain/entities/walk_progress.dart';

/// 한국 시각(KST)을 절대 시각으로. 산책 기록은 UTC 로 들어온다.
DateTime kst(int year, int month, int day, [int hour = 12]) =>
    DateTime.utc(year, month, day, hour).subtract(const Duration(hours: 9));

void main() {
  // 기준 '오늘' — 2026-08-10 12:00 KST
  final now = kst(2026, 8, 10);

  group('WalkProgress.from', () {
    test('기록이 없으면 전부 0이고 리본도 없다', () {
      final progress = WalkProgress.from(const [], now: now);

      expect(progress.todayCount, 0);
      expect(progress.totalCount, 0);
      expect(progress.longestStreakDays, 0);
      expect(progress.earnedRibbons, isEmpty);
      expect(progress.nextRibbon?.requiredWalks, 1);
    });

    test('누적 횟수는 날짜와 무관하게 산책 건수를 센다', () {
      final progress = WalkProgress.from([
        kst(2026, 7, 2),
        kst(2026, 7, 5),
        kst(2026, 7, 8),
      ], now: now);

      expect(progress.totalCount, 3);
      // 하루도 이어지지 않아도 누적은 쌓인다. 이게 누적 기준을 쓰는 이유다.
      expect(progress.longestStreakDays, 1);
    });

    test('오늘 산책 횟수는 하루에 여러 번이면 그만큼 센다', () {
      final progress = WalkProgress.from([
        kst(2026, 8, 10, 8),
        kst(2026, 8, 10, 19),
        kst(2026, 8, 9, 9),
      ], now: now);

      expect(progress.todayCount, 2);
      expect(progress.totalCount, 3);
    });

    test('날짜 경계는 한국 시간 기준이다', () {
      // 2026-08-10 00:30 KST = 2026-08-09 15:30 UTC.
      // UTC 로 자르면 어제가 되어 오늘 산책이 0회로 보인다.
      final progress = WalkProgress.from([kst(2026, 8, 10, 0)], now: now);

      expect(progress.todayCount, 1);
    });

    test('최장 연속 일수는 참고용으로 계산된다', () {
      final progress = WalkProgress.from([
        kst(2026, 7, 1), kst(2026, 7, 2), kst(2026, 7, 3),
        kst(2026, 7, 10), kst(2026, 7, 11),
      ], now: now);

      expect(progress.longestStreakDays, 3);
    });
  });

  group('리본 획득', () {
    test('예시 데이터와 같은 10회면 1·5·10회 리본이 열린다', () {
      final walks = [
        for (final day in [2, 5, 8, 11, 15, 18, 22, 25, 28, 31])
          kst(2026, 7, day),
      ];
      final progress = WalkProgress.from(walks, now: now);

      expect(progress.totalCount, 10);
      expect(
        progress.earnedRibbons.map((r) => r.requiredWalks).toList(),
        [1, 5, 10],
      );
      expect(progress.nextRibbon?.requiredWalks, 30);
      expect(progress.walksToNextRibbon, 20);
    });

    test('리본을 받은 날은 그 조건을 채운 산책의 날이다', () {
      final walks = [
        for (final day in [2, 5, 8, 11, 15]) kst(2026, 7, day),
      ];
      final progress = WalkProgress.from(walks, now: now);

      final first = progress.ribbons.firstWhere((r) => r.requiredWalks == 1);
      final fifth = progress.ribbons.firstWhere((r) => r.requiredWalks == 5);

      // 1번째 산책은 7/2, 5번째 산책은 7/15 이다.
      expect(first.earnedOn, DateTime.utc(2026, 7, 2));
      expect(fifth.earnedOn, DateTime.utc(2026, 7, 15));
    });

    test('산책 순서가 뒤섞여 들어와도 획득일이 맞는다', () {
      // 피드는 최신순이라 역순으로 들어온다.
      final walks = [
        kst(2026, 7, 15),
        kst(2026, 7, 2),
        kst(2026, 7, 8),
      ];
      final progress = WalkProgress.from(walks, now: now);

      final first = progress.ribbons.firstWhere((r) => r.requiredWalks == 1);
      expect(first.earnedOn, DateTime.utc(2026, 7, 2));
    });

    test('진행률은 다음 리본 기준이고 라벨과 같은 비율이다', () {
      final walks = [for (var i = 0; i < 15; i++) kst(2026, 7, 1 + i)];
      final progress = WalkProgress.from(walks, now: now);

      // 15 / 30회 → 0.5
      expect(progress.nextRibbon?.requiredWalks, 30);
      expect(progress.progressToNextRibbon, closeTo(0.5, 0.001));
    });

    test('리본을 전부 받으면 다음 리본이 없고 진행률은 1.0이다', () {
      final walks = [
        for (var i = 0; i < 100; i++)
          kst(2026, 1, 1).add(Duration(hours: i)),
      ];
      final progress = WalkProgress.from(walks, now: now);

      expect(progress.totalCount, 100);
      expect(progress.earnedRibbons.length, WalkProgress.catalog.length);
      expect(progress.nextRibbon, isNull);
      expect(progress.walksToNextRibbon, isNull);
      expect(progress.progressToNextRibbon, 1);
    });

    test('남은 횟수는 최소 1회다', () {
      // 리본 조건과 누적이 같은 순간에도 0이나 음수가 나오지 않아야 한다.
      final walks = [for (var i = 0; i < 5; i++) kst(2026, 7, 1 + i)];
      final progress = WalkProgress.from(walks, now: now);

      expect(progress.nextRibbon?.requiredWalks, 10);
      expect(progress.walksToNextRibbon, greaterThanOrEqualTo(1));
    });
  });
}
