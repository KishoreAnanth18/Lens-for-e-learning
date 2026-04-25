import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenManager {
  static const _keyAccessToken = 'access_token';
  static const _keyRefreshToken = 'refresh_token';
  static const _keyTokenExpiry = 'token_expiry';

  // Token valid for 30 days (Requirement 1.3)
  static const Duration tokenValidDuration = Duration(days: 30);

  final FlutterSecureStorage _storage;

  TokenManager({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<void> saveToken({
    required String accessToken,
    String? refreshToken,
    DateTime? expiry,
  }) async {
    final tokenExpiry = expiry ?? DateTime.now().add(tokenValidDuration);
    await Future.wait([
      _storage.write(key: _keyAccessToken, value: accessToken),
      _storage.write(key: _keyTokenExpiry, value: tokenExpiry.toIso8601String()),
      if (refreshToken != null)
        _storage.write(key: _keyRefreshToken, value: refreshToken),
    ]);
  }

  Future<String?> getToken() async {
    return _storage.read(key: _keyAccessToken);
  }

  Future<String?> getRefreshToken() async {
    return _storage.read(key: _keyRefreshToken);
  }

  Future<void> clearToken() async {
    await Future.wait([
      _storage.delete(key: _keyAccessToken),
      _storage.delete(key: _keyRefreshToken),
      _storage.delete(key: _keyTokenExpiry),
    ]);
  }

  Future<bool> isTokenExpired() async {
    final expiryStr = await _storage.read(key: _keyTokenExpiry);
    if (expiryStr == null) return true;
    final expiry = DateTime.tryParse(expiryStr);
    if (expiry == null) return true;
    return DateTime.now().isAfter(expiry);
  }

  Future<bool> hasValidToken() async {
    final token = await getToken();
    if (token == null || token.isEmpty) return false;
    return !(await isTokenExpired());
  }
}
