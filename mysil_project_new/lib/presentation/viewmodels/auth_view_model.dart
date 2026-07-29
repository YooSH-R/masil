import 'package:flutter/material.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';

class AuthViewModel extends ChangeNotifier {
  final AuthRepository _authRepository;
  User? _user;
  bool _isLoading = false;

  AuthViewModel(this._authRepository);

  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _user != null;

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    notifyListeners();

    _user = await _authRepository.login(email, password);
    
    _isLoading = false;
    notifyListeners();
    return _user != null;
  }

  Future<bool> signup(String email, String password, String nickname, String phone) async {
    _isLoading = true;
    notifyListeners();

    final success = await _authRepository.signup(email, password, nickname, phone);
    if (success) {
      // Simulate user creation after signup for mock flow
      _user = User(id: 'mock', email: email, nickname: nickname);
    }
    
    _isLoading = false;
    notifyListeners();
    return success;
  }

  Future<bool> checkEmailDuplicate(String email) async {
    return await _authRepository.checkEmailDuplicate(email);
  }

  Future<bool> requestSms(String phone) async {
    return await _authRepository.requestSmsVerification(phone);
  }

  Future<bool> verifySms(String phone, String code) async {
    return await _authRepository.verifySmsCode(phone, code);
  }

  Future<void> logout() async {
    await _authRepository.logout();
    _user = null;
    notifyListeners();
  }

  Future<void> checkAuthStatus() async {
    _user = await _authRepository.getAuthenticatedUser();
    notifyListeners();
  }
}
