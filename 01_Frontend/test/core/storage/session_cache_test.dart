import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mysil_project_new/core/storage/session_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('펫 목록을 기억해도 현재 펫은 변경하지 않는다', () async {
    SharedPreferences.setMockInitialValues({});
    final cache = SessionCache();

    await cache.savePetId(4);
    await cache.rememberPetIds([4, 5, 6]);

    expect(await cache.readPetId(), 4);
    expect(await cache.readKnownPetIds(), [4, 5, 6]);
  });
}
