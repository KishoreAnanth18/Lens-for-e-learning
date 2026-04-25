import 'package:dio/dio.dart';
import '../models/auth_result.dart';
import 'auth_service.dart';
import 'token_manager.dart';

class AuthServiceImpl implements IAuthService {
  final Dio _dio;
  final TokenManager _tokenManager;

  AuthServiceImpl({required String baseUrl, TokenManager? tokenManager})
      : _dio = Dio(BaseOptions(baseUrl: baseUrl)),
        _tokenManager = tokenManager ?? TokenManager();

  @override
  Future<AuthResult> register(String email, String password) async {
    try {
      final response = await _dio.post('/api/v1/auth/register', data: {
        'email': email,
        'password': password,
      });
      final data = response.data as Map<String, dynamic>;
      return AuthResult.success(
        userId: data['user_id'] as String?,
        email: data['email'] as String?,
      );
    } on DioException catch (e) {
      return AuthResult.failure(_extractError(e));
    } catch (e) {
      return AuthResult.failure('Registration failed: $e');
    }
  }

  @override
  Future<AuthResult> login(String email, String password) async {
    try {
      final response = await _dio.post('/api/v1/auth/login', data: {
        'email': email,
        'password': password,
      });
      final data = response.data as Map<String, dynamic>;
      final accessToken = data['access_token'] as String?;
      final refreshToken = data['refresh_token'] as String?;

      if (accessToken != null) {
        await _tokenManager.saveToken(
          accessToken: accessToken,
          refreshToken: refreshToken,
        );
      }

      return AuthResult.success(
        token: accessToken,
        refreshToken: refreshToken,
        userId: data['user_id'] as String?,
        email: data['email'] as String?,
      );
    } on DioException catch (e) {
      return AuthResult.failure(_extractError(e));
    } catch (e) {
      return AuthResult.failure('Login failed: $e');
    }
  }

  @override
  Future<AuthResult> loginWithGoogle() async {
    // TODO: Implement Google OAuth with native SDK
    throw UnimplementedError('Google OAuth is not yet implemented for MVP');
  }

  @override
  Future<AuthResult> loginWithFacebook() async {
    // TODO: Implement Facebook OAuth with native SDK
    throw UnimplementedError('Facebook OAuth is not yet implemented for MVP');
  }

  @override
  Future<void> logout() async {
    try {
      final token = await _tokenManager.getToken();
      if (token != null) {
        await _dio.post(
          '/api/v1/auth/logout',
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
      }
    } catch (_) {
      // Ignore server errors on logout — always clear local tokens
    } finally {
      // Requirement 1.7: clear all local tokens on logout
      await _tokenManager.clearToken();
    }
  }

  @override
  Future<bool> verifyEmail(String code) async {
    try {
      await _dio.post('/api/v1/auth/verify-email', data: {'code': code});
      return true;
    } on DioException catch (_) {
      return false;
    }
  }

  @override
  Future<String> getValidToken() async {
    // Requirement 1.6: check expiry and refresh if needed
    final expired = await _tokenManager.isTokenExpired();
    if (expired) {
      final refreshed = await _refreshToken();
      if (!refreshed) {
        throw Exception('Session expired. Please log in again.');
      }
    }
    final token = await _tokenManager.getToken();
    if (token == null) {
      throw Exception('No authentication token found.');
    }
    return token;
  }

  Future<bool> _refreshToken() async {
    try {
      final refreshToken = await _tokenManager.getRefreshToken();
      if (refreshToken == null) return false;

      final response = await _dio.post('/api/v1/auth/refresh', data: {
        'refresh_token': refreshToken,
      });
      final data = response.data as Map<String, dynamic>;
      final newAccessToken = data['access_token'] as String?;
      final newRefreshToken = data['refresh_token'] as String?;

      if (newAccessToken == null) return false;

      await _tokenManager.saveToken(
        accessToken: newAccessToken,
        refreshToken: newRefreshToken,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  String _extractError(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      return data['detail'] as String? ??
          data['message'] as String? ??
          'Request failed';
    }
    return e.message ?? 'Request failed';
  }
}
