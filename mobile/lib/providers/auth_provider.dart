import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';
import '../services/token_manager.dart';

class AuthUser {
  final String? userId;
  final String? email;

  const AuthUser({this.userId, this.email});
}

class AuthProvider extends ChangeNotifier {
  final IAuthService _authService;
  final TokenManager _tokenManager;

  bool _isAuthenticated = false;
  bool _isLoading = false;
  AuthUser? _currentUser;
  String? _errorMessage;

  AuthProvider({
    required IAuthService authService,
    required TokenManager tokenManager,
  })  : _authService = authService,
        _tokenManager = tokenManager;

  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  AuthUser? get currentUser => _currentUser;
  String? get errorMessage => _errorMessage;

  /// Call on app start to restore auth state from stored token.
  Future<void> init() async {
    final hasToken = await _tokenManager.hasValidToken();
    _isAuthenticated = hasToken;
    notifyListeners();
  }

  Future<bool> register(String email, String password) async {
    _setLoading(true);
    final result = await _authService.register(email, password);
    _setLoading(false);

    if (result.success) {
      _errorMessage = null;
      notifyListeners();
      return true;
    } else {
      _errorMessage = result.errorMessage;
      notifyListeners();
      return false;
    }
  }

  Future<bool> login(String email, String password) async {
    _setLoading(true);
    final result = await _authService.login(email, password);
    _setLoading(false);

    if (result.success) {
      _isAuthenticated = true;
      _currentUser = AuthUser(userId: result.userId, email: result.email);
      _errorMessage = null;
      notifyListeners();
      return true;
    } else {
      _isAuthenticated = false;
      _errorMessage = result.errorMessage;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    _setLoading(true);
    await _authService.logout();
    _isAuthenticated = false;
    _currentUser = null;
    _errorMessage = null;
    _setLoading(false);
  }

  Future<bool> verifyEmail(String code) async {
    _setLoading(true);
    final success = await _authService.verifyEmail(code);
    _setLoading(false);

    if (!success) {
      _errorMessage = 'Invalid or expired verification code.';
      notifyListeners();
    }
    return success;
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
