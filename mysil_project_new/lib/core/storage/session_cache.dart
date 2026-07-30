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

  Future<int?> readPetId() async => (await _prefs).getInt(_kPetId);
  Future<void> savePetId(int petId) async => (await _prefs).setInt(_kPetId, petId);

  Future<int?> readRobotId() async => (await _prefs).getInt(_kRobotId);
  Future<void> saveRobotId(int robotId) async =>
      (await _prefs).setInt(_kRobotId, robotId);

  Future<void> clearRobotId() async => (await _prefs).remove(_kRobotId);

  Future<void> clear() async {
    final prefs = await _prefs;
    await prefs.remove(_kUser);
    await prefs.remove(_kPetId);
    await prefs.remove(_kRobotId);
  }
}
