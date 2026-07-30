import 'package:dio/dio.dart';

import 'api_exception.dart';

/// 공통 응답 봉투를 벗겨내는 얇은 래퍼.
///
/// 성공: {"success": true, "data": {...}, "timestamp": "..."} → data만 반환
/// 204 No Content → null 반환
/// 실패: ApiException 으로 변환해서 throw
class ApiClient {
  ApiClient(this._dio);

  final Dio _dio;

  Dio get dio => _dio;

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
  }) =>
      _send(() => _dio.get(path, queryParameters: query));

  Future<dynamic> post(
    String path, {
    Object? data,
    String? idempotencyKey,
  }) =>
      _send(() => _dio.post(
            path,
            data: data,
            options: _options(idempotencyKey),
          ));

  Future<dynamic> patch(
    String path, {
    Object? data,
    String? idempotencyKey,
  }) =>
      _send(() => _dio.patch(
            path,
            data: data,
            options: _options(idempotencyKey),
          ));

  Future<dynamic> put(
    String path, {
    Object? data,
    String? idempotencyKey,
  }) =>
      _send(() => _dio.put(
            path,
            data: data,
            options: _options(idempotencyKey),
          ));

  Future<dynamic> delete(
    String path, {
    Object? data,
    String? idempotencyKey,
  }) =>
      _send(() => _dio.delete(
            path,
            data: data,
            options: _options(idempotencyKey),
          ));

  /// multipart/form-data 업로드 (사진 업로드용).
  Future<dynamic> upload(
    String path, {
    required FormData formData,
    String? idempotencyKey,
    Duration? timeout,
    ProgressCallback? onSendProgress,
  }) =>
      _send(() => _dio.post(
            path,
            data: formData,
            options: _options(idempotencyKey)
              ..contentType = 'multipart/form-data'
              ..sendTimeout = timeout
              ..receiveTimeout = timeout,
            onSendProgress: onSendProgress,
          ));

  /// 사진 원본처럼 봉투 없이 바이트가 오는 응답.
  Future<List<int>> getBytes(String path) async {
    try {
      final res = await _dio.get<List<int>>(
        path,
        options: Options(responseType: ResponseType.bytes),
      );
      return res.data ?? const [];
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Options _options(String? idempotencyKey) => Options(
        headers: idempotencyKey == null
            ? null
            : {'X-Idempotency-Key': _headerSafe(idempotencyKey)},
      );

  /// HTTP 헤더 값에는 ASCII만 들어갈 수 있다. 한글 닉네임처럼 비ASCII가 섞이면
  /// Dio가 요청을 보내기도 전에 FormatException을 던지므로 퍼센트 인코딩한다.
  /// 같은 입력이면 항상 같은 결과라서 멱등성 키의 의미는 그대로 유지된다.
  static String _headerSafe(String value) {
    final isAscii = value.codeUnits.every((c) => c >= 0x20 && c < 0x7F);
    return isAscii ? value : Uri.encodeComponent(value);
  }

  Future<dynamic> _send(Future<Response<dynamic>> Function() request) async {
    try {
      final res = await request();

      // 204 No Content (로그아웃, 푸시 토큰 등록 등)
      if (res.statusCode == 204) return null;

      final body = res.data;
      if (body == null) return null;

      if (body is Map<String, dynamic>) {
        if (body['success'] == false) {
          throw ApiException.fromBody(body, statusCode: res.statusCode);
        }
        // data 키가 있으면 그 안쪽만 넘긴다.
        if (body.containsKey('data')) return body['data'];
      }
      return body;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
