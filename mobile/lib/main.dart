import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/app_config.dart';
import 'providers/auth_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home_screen.dart';
import 'services/auth_service_impl.dart';
import 'services/token_manager.dart';

void main() {
  runApp(const LensELearningApp());
}

class LensELearningApp extends StatelessWidget {
  const LensELearningApp({super.key});

  @override
  Widget build(BuildContext context) {
    final tokenManager = TokenManager();
    final authService = AuthServiceImpl(
      baseUrl: AppConfig.baseUrl,
      tokenManager: tokenManager,
    );

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AuthProvider(
            authService: authService,
            tokenManager: tokenManager,
          )..init(),
        ),
      ],
      child: MaterialApp(
        title: 'Lens for E-Learning',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: const _AuthGate(),
      ),
    );
  }
}

/// Decides the initial route based on authentication state.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (auth.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return auth.isAuthenticated ? const HomeScreen() : const LoginScreen();
  }
}
