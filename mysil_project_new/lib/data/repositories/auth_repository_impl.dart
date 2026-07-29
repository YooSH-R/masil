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
    // Simulate network delay
    await Future.delayed(const Duration(seconds: 1));

    // MOCK SUCCESS LOGIC
    final mockUser = UserModel(
      id: '1',
      email: email,
      nickname: '마실이친구',
      profileImageUrl: null,
    );

    await _storage.write(key: 'access_token', value: 'mock_access_token');
    await _storage.write(key: 'refresh_token', value: 'mock_refresh_token');

    return mockUser;
  }

  @override
  Future<bool> signup(String email, String password, String nickname, String phone) async {
    // Simulate network delay
    await Future.delayed(const Duration(seconds: 1));
    
    // MOCK SUCCESS LOGIC
    return true;
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

  @override
  Future<bool> checkEmailDuplicate(String email) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return false; // Mock: Email is always available
  }

  @override
  Future<bool> requestSmsVerification(String phone) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return true; // Mock: SMS sent
  }

  @override
  Future<bool> verifySmsCode(String phone, String code) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return code == '1234'; // Mock: 1234 is the correct code
  }
}
