import '../entities/user.dart';

abstract class AuthRepository {
  Future<User?> login(String email, String password);
  Future<bool> signup(String email, String password, String nickname, String phone);
  Future<void> logout();
  Future<bool> resetPassword(String email);
  Future<User?> getAuthenticatedUser();
  Future<bool> checkEmailDuplicate(String email);
  Future<bool> requestSmsVerification(String phone);
  Future<bool> verifySmsCode(String phone, String code);
}
