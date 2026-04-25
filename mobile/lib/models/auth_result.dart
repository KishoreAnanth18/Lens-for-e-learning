class AuthResult {
  final bool success;
  final String? token;
  final String? refreshToken;
  final String? userId;
  final String? email;
  final String? errorMessage;

  const AuthResult({
    required this.success,
    this.token,
    this.refreshToken,
    this.userId,
    this.email,
    this.errorMessage,
  });

  factory AuthResult.success({
    String? token,
    String? refreshToken,
    String? userId,
    String? email,
  }) {
    return AuthResult(
      success: true,
      token: token,
      refreshToken: refreshToken,
      userId: userId,
      email: email,
    );
  }

  factory AuthResult.failure(String errorMessage) {
    return AuthResult(success: false, errorMessage: errorMessage);
  }
}
