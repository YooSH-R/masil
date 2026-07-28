import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthInterceptor extends Interceptor {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final Dio _dio;

  AuthInterceptor(this._dio);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final accessToken = await _storage.read(key: 'access_token');
    if (accessToken != null) {
      options.headers['Authorization'] = 'Bearer $accessToken';
    }
    return handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      // Logic for Refresh Token (FR-02)
      final refreshToken = await _storage.read(key: 'refresh_token');
      if (refreshToken != null) {
        try {
          final response = await _dio.post('/auth/refresh', data: {
            'refresh_token': refreshToken,
          });
          
          if (response.statusCode == 200) {
            final newAccessToken = response.data['access_token'];
            await _storage.write(key: 'access_token', value: newAccessToken);
            
            // Retry the original request
            err.requestOptions.headers['Authorization'] = 'Bearer $newAccessToken';
            final cloneReq = await _dio.fetch(err.requestOptions);
            return handler.resolve(cloneReq);
          }
        } catch (e) {
          // Refresh failed, logout user
          await _storage.deleteAll();
          // TODO: Trigger logout event via Provider/Bus
        }
      }
    }
    return handler.next(err);
  }
}
