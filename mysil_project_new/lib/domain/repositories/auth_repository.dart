import '../entities/user.dart';

abstract class AuthRepository {
  Future<User?> login(String email, String password);
  Future<bool> signup(String email, String password, String nickname);
  Future<void> logout();
  Future<bool> resetPassword(String email);
  Future<User?> getAuthenticatedUser();
}
