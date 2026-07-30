import 'dart:async';

import 'package:dio/dio.dart';

import '../config/api_config.dart';
import '../storage/token_storage.dart';
import 'api_endpoints.dart';

/// 액세스 토큰 부착 + 401 시 자동 재발급.
///
/// 명세서 3.5 기준으로 재발급 요청 본문은 {refreshToken, deviceId} 이고
/// 응답은 accessToken·refreshToken·accessTokenExpiresAt 을 모두 새로 내려준다.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required TokenStorage tokenStorage,
    required Dio refreshDio,
    this.onSessionExpired,
  })  : _tokenStorage = tokenStorage,
        _refreshDio = refreshDio;

  final TokenStorage _tokenStorage;

  /// 재발급 전용 Dio. 이 인터셉터를 달지 않아 재귀 호출을 막는다.
  final Dio _refreshDio;

  /// 재발급까지 실패했을 때 앱에 알리는 콜백 (로그인 화면으로 보내는 용도).
  final Future<void> Function()? onSessionExpired;

  /// 동시 요청이 한꺼번에 401을 받아도 재발급은 한 번만 수행한다.
  Future<String?>? _refreshInFlight;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!_isPublic(options.path)) {
      final accessToken = await _tokenStorage.readAccessToken();
      if (accessToken != null) {
        options.headers['Authorization'] = 'Bearer $accessToken';
      }
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final statusCode = err.response?.statusCode;
    final isAuthPath = _isPublic(err.requestOptions.path);

    // 재발급 대상이 아니면 그대로 통과.
    if (statusCode != 401 || isAuthPath || err.requestOptions.extra['retried'] == true) {
      return handler.next(err);
    }

    final newAccessToken = await _refresh();
    if (newAccessToken == null) {
      return handler.next(err);
    }

    try {
      final options = err.requestOptions;
      options.headers['Authorization'] = 'Bearer $newAccessToken';
      options.extra['retried'] = true;
      final retried = await _refreshDio.fetch(options);
      return handler.resolve(retried);
    } on DioException catch (e) {
      return handler.next(e);
    }
  }

  Future<String?> _refresh() {
    // 이미 진행 중이면 그 결과를 함께 기다린다.
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;

    final future = _performRefresh();
    _refreshInFlight = future;
    future.whenComplete(() => _refreshInFlight = null);
    return future;
  }

  Future<String?> _performRefresh() async {
    final refreshToken = await _tokenStorage.readRefreshToken();
    if (refreshToken == null) {
      await _expireSession();
      return null;
    }

    try {
      final deviceId = await _tokenStorage.deviceId();
      final res = await _refreshDio.post(
        ApiEndpoints.refresh,
        data: {'refreshToken': refreshToken, 'deviceId': deviceId},
      );

      final body = res.data;
      final data = body is Map<String, dynamic> ? body['data'] : null;
      if (data is! Map<String, dynamic>) {
        await _expireSession();
        return null;
      }

      final accessToken = data['accessToken']?.toString();
      if (accessToken == null) {
        await _expireSession();
        return null;
      }

      await _tokenStorage.saveTokens(
        accessToken: accessToken,
        refreshToken: data['refreshToken']?.toString(),
        accessTokenExpiresAt: data['accessTokenExpiresAt']?.toString(),
      );
      return accessToken;
    } on DioException {
      await _expireSession();
      return null;
    }
  }

  Future<void> _expireSession() async {
    await _tokenStorage.clearTokens();
    await onSessionExpired?.call();
  }

  bool _isPublic(String path) =>
      ApiConfig.publicPaths.any((p) => path.contains(p));
}
