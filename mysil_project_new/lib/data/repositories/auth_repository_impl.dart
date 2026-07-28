import '../../core/network/dio_client.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../models/user_model.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthRepositoryImpl implements AuthRepository {
  final DioClient _dioClient;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  AuthRepositoryImpl(this._dioClient);

  @override
  Future<User?> login(String email, String password) async {
    try {
      final response = await _dioClient.dio.post('/auth/login', data: {
        'email': email,
        'password': password,
      });

      if (response.statusCode == 200) {
        final accessToken = response.data['access_token'];
        final refreshToken = response.data['refresh_token'];
        final userData = response.data['user'];

        await _storage.write(key: 'access_token', value: accessToken);
        await _storage.write(key: 'refresh_token', value: refreshToken);

        return UserModel.fromJson(userData);
      }
    } catch (e) {
      // Handle error
    }
    return null;
  }

  @override
  Future<bool> signup(String email, String password, String nickname) async {
    try {
      final response = await _dioClient.dio.post('/auth/signup', data: {
        'email': email,
        'password': password,
        'nickname': nickname,
      });
      return response.statusCode == 201;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> logout() async {
    await _storage.deleteAll();
  }

  @override
  Future<bool> resetPassword(String email) async {
    try {
      final response = await _dioClient.dio.post('/auth/password-reset', data: {
        'email': email,
      });
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<User?> getAuthenticatedUser() async {
    try {
      final response = await _dioClient.dio.get('/auth/me');
      if (response.statusCode == 200) {
        return UserModel.fromJson(response.data);
      }
    } catch (e) {
      // Handle error
    }
    return null;
  }
}
