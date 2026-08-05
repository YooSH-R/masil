import 'package:dio/dio.dart';
import 'package:logger/logger.dart';

import '../config/api_config.dart';
import '../storage/token_storage.dart';
import 'api_client.dart';
import 'auth_interceptor.dart';

class DioClient {
  DioClient({
    required TokenStorage tokenStorage,
    Future<void> Function()? onSessionExpired,
    bool enableLogging = true,
  })  : _dio = Dio(_baseOptions()),
        _refreshDio = Dio(_baseOptions()) {
    if (enableLogging) {
      final logger = Logger(printer: SimplePrinter(printTime: true));
      _dio.interceptors.add(LogInterceptor(
        request: false,
        requestHeader: false,
        requestBody: true,
        responseHeader: false,
        responseBody: true,
        logPrint: (obj) => logger.d(obj),
      ));
    }

    _dio.interceptors.add(AuthInterceptor(
      tokenStorage: tokenStorage,
      refreshDio: _refreshDio,
      onSessionExpired: onSessionExpired,
    ));

    _apiClient = ApiClient(_dio);
  }

  final Dio _dio;
  final Dio _refreshDio;
  late final ApiClient _apiClient;

  static BaseOptions _baseOptions() => BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: ApiConfig.connectTimeout,
        receiveTimeout: ApiConfig.receiveTimeout,
        sendTimeout: ApiConfig.sendTimeout,
        responseType: ResponseType.json,
        contentType: Headers.jsonContentType,
        // 오류 응답 본문(error.code)을 직접 읽어야 하므로 4xx/5xx도 예외 전에 받아본다.
        validateStatus: (status) => status != null && status < 300,
      );

  Dio get dio => _dio;
  ApiClient get client => _apiClient;
}
