import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mysil_project_new/domain/entities/walk_diary.dart';
import 'package:mysil_project_new/domain/repositories/walk_diary_repository.dart';
import 'package:mysil_project_new/presentation/viewmodels/walk_diary_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('같은 날짜의 여러 산책을 모두 보관하고 집계한다', () async {
    SharedPreferences.setMockInitialValues({});
    final viewModel = WalkDiaryViewModel(_MultipleWalksRepository());

    await viewModel.loadFeed(refresh: true);

    final items = viewModel.itemsOn(DateTime.utc(2026, 8, 6));
    expect(items, hasLength(2));
    expect(items.map((item) => item.session), [1, 2]);
    expect(viewModel.statsForDay(DateTime.utc(2026, 8, 6)).count, 2);

    viewModel.dispose();
  });
}

class _MultipleWalksRepository implements WalkDiaryRepository {
  @override
  Future<CursorPage<WalkDiaryFeedItem>> getFeed({
    String? cursor,
    int limit = 20,
  }) async {
    return CursorPage<WalkDiaryFeedItem>(items: [
      WalkDiaryFeedItem(
        walkId: -100002,
        walkedAt: DateTime.utc(2026, 8, 6),
        deviceId: 'device-001',
        session: 2,
      ),
      WalkDiaryFeedItem(
        walkId: -100001,
        walkedAt: DateTime.utc(2026, 8, 6),
        deviceId: 'device-001',
        session: 1,
      ),
    ]);
  }

  @override
  Future<WalkDiary> getDiary(int walkId) => throw UnimplementedError();

  @override
  Future<WalkDiaryContent> getS3Diary({
    required String deviceId,
    required DateTime walkDate,
    required int session,
  }) =>
      throw UnimplementedError();

  @override
  Future<WalkDiary> updateCaption({
    required int walkId,
    required int photoId,
    required String caption,
  }) =>
      throw UnimplementedError();
}
