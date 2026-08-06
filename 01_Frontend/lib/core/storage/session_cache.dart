import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../utils/json_parse.dart';

/// 명세서에 없는 조회 경로를 메우는 로컬 캐시.
///
/// - GET /users/me 가 없어서 로그인 응답의 user를 저장해 자동 로그인 시 재사용한다.
/// - GET /pets (목록)가 없어서 현재 펫·로봇 id를 저장해 두고 상세 조회에 쓴다.
class SessionCache {
  static const _kUser = 'cached_user';
  static const _kPetId = 'current_pet_id';
  static const _kKnownPetIds = 'known_pet_ids';
  static const _kRobotId = 'current_robot_id';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<Map<String, dynamic>?> readUser() async {
    final raw = (await _prefs).getString(_kUser);
    if (raw == null) return null;
    try {
      return Json.asMapOrNull(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  Future<void> saveUser(Map<String, dynamic> userJson) async =>
      (await _prefs).setString(_kUser, jsonEncode(userJson));

  /// 대표(현재) 펫.
  Future<int?> readPetId() async => (await _prefs).getInt(_kPetId);

  /// 현재 펫으로 지정하고, 아는 펫 목록에도 넣는다.
  Future<void> savePetId(int petId) async {
    final prefs = await _prefs;
    await prefs.setInt(_kPetId, petId);
    await _rememberPetId(petId);
  }

  /// 펫 목록만 기억한다. 대표(현재) 펫은 변경하지 않는다.
  Future<void> rememberPetIds(Iterable<int> petIds) async {
    final prefs = await _prefs;
    final ids = (prefs.getStringList(_kKnownPetIds) ?? <String>[]).toList();
    for (final petId in petIds) {
      final key = petId.toString();
      if (!ids.contains(key)) ids.add(key);
    }
    await prefs.setStringList(_kKnownPetIds, ids);
  }

  /// 이 앱이 아는 펫 id 전부. 만든 순서대로.
  ///
  /// **왜 목록을 직접 들고 있는가**: 서버에 `GET /pets` 가 없다. 그래서 펫을
  /// 만들 때 받은 id 를 모아두고, 화면에서 하나씩 `GET /pets/{petId}` 로
  /// 조회해야 여러 마리를 보여줄 수 있다. 이게 없으면 새 펫을 만들 때마다
  /// 이전 펫이 화면에서 사라진다(서버에는 남아 있는데 찾아갈 수 없다).
  ///
  /// 한계: 이 기기에서 만든 펫만 안다. 앱을 지우거나 다른 기기로 로그인하면
  /// 목록이 비어 있다. 서버에 목록 API 가 생기면 이 저장은 지워도 된다.
  Future<List<int>> readKnownPetIds() async {
    final prefs = await _prefs;
    final raw = prefs.getStringList(_kKnownPetIds);

    // 목록 저장은 나중에 생겼다. 그 전에 만든 펫은 current_pet_id 에만 남아
    // 있으므로, 목록이 아직 없으면 그 값을 옮겨와 첫 항목으로 삼는다.
    // (이 처리가 없으면 기존 사용자에게 "펫이 없어요"로 보인다)
    if (raw == null) {
      final currentId = prefs.getInt(_kPetId);
      if (currentId == null) return const [];
      await prefs.setStringList(_kKnownPetIds, [currentId.toString()]);
      return [currentId];
    }

    return raw.map(int.tryParse).whereType<int>().toList(growable: false);
  }

  Future<void> _rememberPetId(int petId) async {
    final prefs = await _prefs;
    final ids = (prefs.getStringList(_kKnownPetIds) ?? <String>[]).toList();
    final key = petId.toString();
    if (ids.contains(key)) return;
    ids.add(key);
    await prefs.setStringList(_kKnownPetIds, ids);
  }

  /// 삭제된 펫을 목록에서 뺀다. 현재 펫이었으면 지정도 함께 푼다.
  Future<void> forgetPetId(int petId) async {
    final prefs = await _prefs;
    final ids = (prefs.getStringList(_kKnownPetIds) ?? <String>[]).toList()
      ..remove(petId.toString());
    await prefs.setStringList(_kKnownPetIds, ids);
    if (prefs.getInt(_kPetId) == petId) await prefs.remove(_kPetId);
  }

  Future<int?> readRobotId() async => (await _prefs).getInt(_kRobotId);
  Future<void> saveRobotId(int robotId) async =>
      (await _prefs).setInt(_kRobotId, robotId);

  Future<void> clearRobotId() async => (await _prefs).remove(_kRobotId);

  Future<void> clear() async {
    final prefs = await _prefs;
    await prefs.remove(_kUser);
    await prefs.remove(_kPetId);
    await prefs.remove(_kKnownPetIds);
    await prefs.remove(_kRobotId);
  }
}
