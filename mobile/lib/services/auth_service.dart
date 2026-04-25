import '../models/auth_result.dart';

abstract class IAuthService {
  Future<AuthResult> register(String email, String password);
  Future<AuthResult> login(String email, String password);
  Future<AuthResult> loginWithGoogle();
  Future<AuthResult> loginWithFacebook();
  Future<void> logout();
  Future<bool> verifyEmail(String code);
  Future<String> getValidToken();
}
