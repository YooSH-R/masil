import 'package:flutter_test/flutter_test.dart';

import 'package:mysil_project_new/data/models/walk_diary_model.dart';

void main() {
  test('S3 날짜별 피드를 세션별 달력 항목으로 펼친다', () {
    final items = WalkDiaryFeedItemModel.fromS3Day({
      'walkDate': '2026-08-03',
      'walkCount': 2,
      'diaries': [
        {'deviceId': 'device-001', 'session': 1},
        {'deviceId': 'device-001', 'session': 2},
      ],
    });

    expect(items, hasLength(2));
    expect(items.first.walkedAt, DateTime.utc(2026, 8, 3));
    expect(items.first.deviceId, 'device-001');
    expect(items.first.session, 1);
    expect(items.first.isS3Diary, isTrue);
    expect(items[1].session, 2);
    expect(items.first.walkId, isNot(items[1].walkId));
  });

  test('UTC 산책 시각을 한국 날짜로 변환한다', () {
    final item = WalkDiaryFeedItemModel.fromJson({
      'walkId': 1,
      'walkedAt': '2026-08-05T15:30:00Z',
    });

    expect(item.walkedAt, DateTime.utc(2026, 8, 6, 0, 30));
  });
}
