import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/app_config.dart';
import 'models/scan_models.dart';
import 'providers/auth_provider.dart';
import 'providers/bookmark_provider.dart';
import 'providers/history_provider.dart';
import 'providers/network_provider.dart';
import 'providers/scan_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home_screen.dart';
import 'services/auth_service_impl.dart';
import 'services/bookmark_service_impl.dart';
import 'services/history_service_impl.dart';
import 'services/offline_queue_service.dart';
import 'services/scan_service_impl.dart';
import 'services/token_manager.dart';
import 'widgets/network_status_banner.dart';

void main() {
  runApp(const LensELearningApp());
}

class LensELearningApp extends StatelessWidget {
  const LensELearningApp({
    super.key,
    this.enableNetworkMonitoring = true,
  });

  final bool enableNetworkMonitoring;

  static final TokenManager _tokenManager = TokenManager();
  static final AuthServiceImpl _authService = AuthServiceImpl(
    baseUrl: AppConfig.baseUrl,
    tokenManager: _tokenManager,
  );
  static final ScanServiceImpl _scanService = ScanServiceImpl(
    baseUrl: AppConfig.baseUrl,
    authService: _authService,
  );
  static final BookmarkServiceImpl _bookmarkService = BookmarkServiceImpl(
    baseUrl: AppConfig.baseUrl,
    authService: _authService,
  );
  static final HistoryServiceImpl _historyService = HistoryServiceImpl(
    baseUrl: AppConfig.baseUrl,
    authService: _authService,
  );
  static final OfflineQueueService _offlineQueueService = OfflineQueueService(
    baseUrl: AppConfig.baseUrl,
    authService: _authService,
  );

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AuthProvider(
            authService: _authService,
            tokenManager: _tokenManager,
          )..init(),
        ),
        // HistoryProvider must be created before ScanProvider so the
        // ProxyProvider below can reference it.
        ChangeNotifierProvider(
          create: (_) => HistoryProvider(
            historyService: _historyService,
            offlineQueueService: _offlineQueueService,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => NetworkProvider(
            baseUrl: AppConfig.baseUrl,
            offlineQueueService: _offlineQueueService,
            enableMonitoring: enableNetworkMonitoring,
          ),
        ),
        // ScanProvider is wired to HistoryProvider so completed scans are
        // automatically cached locally.
        ChangeNotifierProxyProvider<HistoryProvider, ScanProvider>(
          create: (ctx) => ScanProvider(
            scanService: _scanService,
            onScanCompleted: _makeCacheCallback(ctx),
          ),
          update: (ctx, historyProvider, previous) {
            // Re-create the callback whenever HistoryProvider changes so it
            // always holds a fresh reference.
            if (previous == null) {
              return ScanProvider(
                scanService: _scanService,
                onScanCompleted: _makeCacheCallback(ctx),
              );
            }
            // Update the callback in-place without rebuilding the provider.
            previous.updateCacheCallback(_makeCacheCallback(ctx));
            return previous;
          },
        ),
        ChangeNotifierProvider(
          create: (_) => BookmarkProvider(
            bookmarkService: _bookmarkService,
            offlineQueueService: _offlineQueueService,
          ),
        ),
      ],
      child: MaterialApp(
        title: 'Lens for E-Learning',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        builder: (context, child) => NetworkStatusBanner(
          child: child ?? const SizedBox.shrink(),
        ),
        home: const _AuthGate(),
      ),
    );
  }

  static ScanCompletedCallback _makeCacheCallback(BuildContext ctx) {
    return ({required String localImagePath, required ScanStatusData result}) async {
      final auth = ctx.read<AuthProvider>();
      final userId = auth.currentUser?.userId ?? '';
      await ctx.read<HistoryProvider>().cacheScanResult(
            userId: userId,
            localImagePath: localImagePath,
            result: result,
          );
    };
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
