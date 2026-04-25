class AppConfig {
  // For physical devices, use your machine's local network IP (e.g. http://192.168.1.x:8000)
  // For Android emulator, use http://10.0.2.2:8000
  // For iOS simulator, localhost works fine
  static const String baseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );
}
