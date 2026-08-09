import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/walk.dart';
import '../../domain/entities/walk_diary.dart';
import '../utils/geo.dart';
import '../utils/korea_time.dart';

/// 끝낸 산책을 **이 기기에** 보관한다.
///
/// **왜 로컬에 두는가**: dev 서버에 산책 관련 엔드포인트가 하나도 없다
/// (2026-08-04 확인, 16개 중 walk/diary 0개). 백엔드에 구현은 있지만
/// `feat/BE/walk_api` 브랜치에 있고 배포되지 않았다. 그래서 서버에 기록을
/// 남길 방법이 없다.
///
/// 산책일지에서 **날짜별로 내가 걸은 경로를 카카오맵에서 다시 보는 것**이
/// 목표이므로, 서버가 준비될 때까지 기기에 저장해 그 경험을 만든다.
///
/// 서버가 배포되면 이 저장소는 지워도 되고, 오프라인 캐시로 남겨도 된다.
/// 화면·뷰모델은 [WalkSummary]·[WalkDiaryFeedItem] 만 보므로 출처가 바뀌어도
/// 손댈 필요가 없다.
class WalkRecordStore {
  const WalkRecordStore();

  static const String _key = 'local_walk_records';

  /// 보관할 최대 개수. 오래된 것부터 지운다.
  /// 좌표까지 담기 때문에 무제한으로 두면 저장소가 계속 커진다.
  static const int _maxRecords = 50;

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  /// 로컬 기록의 walkId 인지.
  ///
  /// 서버 id(양수)와 예시 기록 id(-1~-7)와 겹치지 않도록, 로컬 기록은
  /// **epoch 초를 음수로 뒤집은 값**을 쓴다(-1_780_000_000 규모).
  static bool isLocalId(int walkId) => walkId <= _localIdFloor;
  static const int _localIdFloor = -1000000000;

  static int _newId(DateTime startedAt) =>
      -(startedAt.toUtc().millisecondsSinceEpoch ~/ 1000);

  /// 산책 하나를 저장한다. 좌표가 2개 미만이면 경로가 아니므로 건너뛴다.
  ///
  /// 반환값은 저장된 기록의 walkId. 저장하지 않았으면 null.
  Future<int?> save({
    required DateTime startedAt,
    required DateTime endedAt,
    required List<WalkLocationPoint> route,
    int? distanceMeters,
  }) async {
    if (route.length < 2) return null;

    final id = _newId(startedAt);
    final duration = endedAt.difference(startedAt).inSeconds;
    final distance = distanceMeters ?? Geo.routeDistanceMeters(route).round();

    final entry = <String, dynamic>{
      'walkId': id,
      'startedAt': startedAt.toUtc().toIso8601String(),
      'endedAt': endedAt.toUtc().toIso8601String(),
      'durationSeconds': duration < 0 ? 0 : duration,
      'distanceMeters': distance,
      'route': [
        for (final p in route)
          {
            'lat': p.latitude,
            'lng': p.longitude,
            'seq': p.sequence,
            'at': p.recordedAt.toUtc().toIso8601String(),
          },
      ],
    };

    final prefs = await _prefs;
    final raw = (prefs.getStringList(_key) ?? <String>[]).toList()
      ..add(jsonEncode(entry));
    // 최신 것만 남긴다.
    while (raw.length > _maxRecords) {
      raw.removeAt(0);
    }
    await prefs.setStringList(_key, raw);
    return id;
  }

  /// 저장된 산책 전부. 최신순.
  Future<List<WalkSummary>> readAll() async {
    final raw = (await _prefs).getStringList(_key) ?? const <String>[];

    final records = <WalkSummary>[];
    for (final line in raw) {
      final parsed = _parse(line);
      if (parsed != null) records.add(parsed);
    }
    records.sort((a, b) {
      final at = a.startedAt, bt = b.startedAt;
      if (at == null || bt == null) return 0;
      return bt.compareTo(at);
    });
    return records;
  }

  /// 특정 산책 하나. 없으면 null.
  Future<WalkSummary?> read(int walkId) async {
    for (final record in await readAll()) {
      if (record.walkId == walkId) return record;
    }
    return null;
  }

  /// 일지 목록에 올릴 형태로.
  Future<List<WalkDiaryFeedItem>> readFeedItems() async {
    return [
      for (final r in await readAll())
        WalkDiaryFeedItem(
          walkId: r.walkId,
          walkedAt: KoreaTime.fromNullableInstant(r.startedAt),
          durationSeconds: r.durationSeconds,
          distanceMeters: r.distanceMeters,
        ),
    ];
  }

  Future<void> clear() async => (await _prefs).remove(_key);

  /// 앱 시작 때 한 번만 도는 정리. 지웠으면 true.
  ///
  /// 서버에 산책 세션을 만들기 전에 걸은 산책은 이 기기에만 남아 있다. 계정이
  /// 같아도 다른 기기에서는 안 보이는 기록이라, 시연에서 한 사람 폰에만 뜨는
  /// 줄이 섞이면 헷갈린다. 그래서 한 번 비운다.
  ///
  /// 이 뒤로 쌓이는 기록은 서버 전송이 실패했을 때의 폴백이므로 지우지 않는다.
  /// 플래그를 남겨서 앱을 다시 켜도 다시 지우지 않는다.
  Future<bool> purgeUnsyncedRecordsOnce() async {
    final prefs = await _prefs;
    if (prefs.getBool(_purgeFlagKey) ?? false) return false;

    await prefs.setBool(_purgeFlagKey, true);
    final had = (prefs.getStringList(_key) ?? const <String>[]).isNotEmpty;
    if (had) await prefs.remove(_key);
    return had;
  }

  static const String _purgeFlagKey = 'local_walk_records_purged_v1';

  /// 형태가 깨진 항목은 조용히 버린다. 하나가 깨졌다고 목록 전체를 잃지 않는다.
  WalkSummary? _parse(String line) {
    try {
      final map = jsonDecode(line);
      if (map is! Map<String, dynamic>) return null;

      final startedAt = DateTime.tryParse(map['startedAt']?.toString() ?? '');

      final routeRaw = map['route'];
      final route = <WalkLocationPoint>[];
      if (routeRaw is List) {
        for (final item in routeRaw) {
          if (item is! Map) continue;
          final lat = (item['lat'] as num?)?.toDouble();
          final lng = (item['lng'] as num?)?.toDouble();
          if (lat == null || lng == null) continue;
          route.add(WalkLocationPoint(
            latitude: lat,
            longitude: lng,
            sequence: (item['seq'] as num?)?.toInt() ?? route.length + 1,
            // 좌표 시각이 깨졌으면 산책 시작 시각으로 대체한다. 지도에 그릴 때는
            // 쓰이지 않지만 [WalkLocationPoint] 가 필수로 요구한다.
            recordedAt: DateTime.tryParse(item['at']?.toString() ?? '') ??
                startedAt ??
                DateTime.now().toUtc(),
          ));
        }
      }

      return WalkSummary(
        walkId: (map['walkId'] as num).toInt(),
        durationSeconds: (map['durationSeconds'] as num?)?.toInt(),
        distanceMeters: (map['distanceMeters'] as num?)?.toInt(),
        startedAt: startedAt,
        endedAt: DateTime.tryParse(map['endedAt']?.toString() ?? ''),
        route: route,
      );
    } catch (_) {
      return null;
    }
  }
}
