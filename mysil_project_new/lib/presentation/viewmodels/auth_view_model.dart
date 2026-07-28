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

  Future<bool> signup(String email, String password, String nickname) async {
    _isLoading = true;
    notifyListeners();

    final success = await _authRepository.signup(email, password, nickname);
    
    _isLoading = false;
    notifyListeners();
    return success;
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
