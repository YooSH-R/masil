import 'package:dio/dio.dart';

import '../config/map_config.dart';

/// 좌표를 사람이 읽는 장소명으로 바꿔준다. 산책 일지의 `산책 장소`에 쓴다.
///
/// 카카오 로컬 REST API(`coord2regioncode`)를 쓴다. 응답의 행정동 이름을 골라
/// `여의도동` 같은 문자열을 만든다.
///
/// ## 키에 대한 주의
///
/// 이 API는 **REST API 키**를 요구한다. REST 키는 원래 서버용이라 앱에 심으면
/// 노출된다(APK를 뜯으면 보인다). 지금은 백엔드에 산책 API가 없어 앱에서 직접
/// 호출하지만, **백엔드가 준비되면 서버가 좌표를 저장할 때 장소명을 함께
/// 계산해 내려주는 쪽으로 옮기는 것이 옳다.** 그러면 이 클래스는 지워도 된다.
///
/// 키가 주입되지 않으면 조용히 null 을 돌려주고, 화면은 `-` 를 보여준다.
class PlaceNameResolver {
  PlaceNameResolver({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  /// 같은 좌표를 여러 번 묻지 않도록 캐시한다.
  /// 소수점 3자리(약 100m)로 뭉쳐서 키를 만든다.
  final Map<String, String?> _cache = {};

  static const String _endpoint =
      'https://dapi.kakao.com/v2/local/geo/coord2regioncode.json';

  /// 좌표에 해당하는 장소명. 실패하거나 키가 없으면 null.
  Future<String?> resolve({
    required double latitude,
    required double longitude,
  }) async {
    if (!MapConfig.isPlaceLookupConfigured) return null;

    final key = '${latitude.toStringAsFixed(3)},'
        '${longitude.toStringAsFixed(3)}';
    if (_cache.containsKey(key)) return _cache[key];

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        _endpoint,
        // 카카오 로컬은 x=경도, y=위도 순서다. 바꿔 넣으면 엉뚱한 곳이 나온다.
        queryParameters: {'x': longitude, 'y': latitude},
        options: Options(
          headers: {'Authorization': 'KakaoAK ${MapConfig.kakaoRestApiKey}'},
          receiveTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 8),
        ),
      );

      final name = _pickRegionName(response.data);
      _cache[key] = name;
      return name;
    } on DioException {
      // 장소명은 부가 정보다. 실패해도 화면은 그대로 동작해야 한다.
      _cache[key] = null;
      return null;
    }
  }

  /// 응답에서 쓸 이름을 고른다.
  ///
  /// documents 에 `region_type` 이 `H`(행정동)와 `B`(법정동)로 두 건 온다.
  /// 행정동을 우선하고, 동 이름이 비면 구/시 이름으로 내려간다.
  static String? _pickRegionName(Map<String, dynamic>? body) {
    final documents = body?['documents'];
    if (documents is! List || documents.isEmpty) return null;

    Map<String, dynamic>? preferred;
    for (final doc in documents) {
      if (doc is! Map<String, dynamic>) continue;
      preferred ??= doc;
      if (doc['region_type'] == 'H') {
        preferred = doc;
        break;
      }
    }
    if (preferred == null) return null;

    final candidates = [
      preferred['region_3depth_name'], // 동
      preferred['region_2depth_name'], // 구·군
      preferred['region_1depth_name'], // 시·도
    ];
    for (final c in candidates) {
      final text = c?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }
}
