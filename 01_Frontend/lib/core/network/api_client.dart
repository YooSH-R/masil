import 'dart:convert';

import 'package:dio/dio.dart';

import 'api_exception.dart';
import 'sse_client.dart';

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

  /// `text/event-stream` 응답을 프레임 단위로 돌려준다.
  ///
  /// 일반 요청과 두 가지가 다르다.
  /// 1. 응답 전체를 기다릴 수 없다. 연결이 열려 있는 동안 계속 흘러온다.
  /// 2. **receiveTimeout 을 없애야 한다.** 전역 기본값(15초)을 그대로 쓰면
  ///    서버가 20초마다 보내는 heartbeat 사이에서 정상 연결이 끊긴다.
  ///    Dio 는 `Duration.zero` 를 "타임아웃 없음" 으로 본다.
  ///
  /// 구독을 취소하면 소켓도 닫아야 하므로 [cancelToken] 을 받는다.
  Future<Stream<SseEvent>> eventStream(
    String path, {
    CancelToken? cancelToken,
  }) async {
    try {
      final res = await _dio.get<ResponseBody>(
        path,
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Accept': 'text/event-stream'},
          receiveTimeout: Duration.zero,
        ),
        cancelToken: cancelToken,
      );
      final body = res.data;
      if (body == null) return const Stream<SseEvent>.empty();
      return decodeSseEvents(body.stream);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Options _options(String? idempotencyKey) => Options(
        headers: idempotencyKey == null
            ? null
            : {'X-Idempotency-Key': _headerSafe(idempotencyKey)},
      );

  /// 서버가 `X-Idempotency-Key` 에 허용하는 문자. OpenAPI 스펙의
  /// `^[A-Za-z0-9._:-]+$` 를 그대로 옮긴 것이다.
  static final RegExp _keyUnsafe = RegExp(r'[^A-Za-z0-9._:-]+');

  /// 서버 스펙의 `maxLength: 100`.
  static const int _keyMaxLength = 100;

  /// 멱등성 키를 서버가 받아주는 형태로 바꾼다.
  ///
  /// 두 가지를 동시에 지켜야 한다.
  /// 1. HTTP 헤더 값은 ASCII 만 가능하다. 한글 펫 이름처럼 비ASCII가 섞이면
  ///    Dio 가 요청을 보내기도 전에 FormatException 을 던진다.
  /// 2. 서버는 거기서 다시 `^[A-Za-z0-9._:-]+$` 로 검증한다. 그래서 예전처럼
  ///    퍼센트 인코딩을 하면 `%` 가 패턴에 없어 **400 으로 거절된다.**
  ///    (`create-pet-마실이` → `create-pet-%EB%A7%88...` → 400)
  ///
  /// base64url 알파벳(`A-Za-z0-9-_`)은 패딩 `=` 만 빼면 위 패턴에 전부 들어간다.
  /// 그래서 허용되지 않는 구간만 base64url 로 바꾼다. `create-pet-` 같은 앞부분은
  /// 그대로 남아 서버 로그에서 읽을 수 있다.
  ///
  /// 같은 입력이면 항상 같은 결과라서 멱등성 키의 의미는 그대로 유지된다.
  static String _headerSafe(String value) {
    final safe = value.replaceAllMapped(
      _keyUnsafe,
      (m) => base64Url.encode(utf8.encode(m[0]!)).replaceAll('=', ''),
    );
    return safe.length <= _keyMaxLength
        ? safe
        : safe.substring(0, _keyMaxLength);
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
