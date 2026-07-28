import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'auth_interceptor.dart';

class DioClient {
  final Dio _dio;
  final Logger _logger = Logger();

  DioClient() : _dio = Dio() {
    _dio
      ..options.baseUrl = 'https://api.mysil.com' // Placeholder BASE_URL
      ..options.connectTimeout = const Duration(seconds: 15)
      ..options.receiveTimeout = const Duration(seconds: 15)
      ..options.responseType = ResponseType.json;
    
    // Add logging for development
    _dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
      logPrint: (obj) => _logger.d(obj),
    ));

    // Add Auth Interceptor
    _dio.interceptors.add(AuthInterceptor(_dio));
  }

  Dio get dio => _dio;
}
