import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../services/offline_queue_service.dart';

class NetworkProvider extends ChangeNotifier {
  NetworkProvider({
    required String baseUrl,
    required OfflineQueueService offlineQueueService,
    bool enableMonitoring = true,
  })  : _offlineQueueService = offlineQueueService,
        _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 5),
          ),
        ) {
    if (enableMonitoring) {
      _startMonitoring();
    }
  }

  final OfflineQueueService _offlineQueueService;
  final Dio _dio;

  Timer? _timer;
  bool _isOnline = true;
  bool _isSyncing = false;
  int _pendingOperationCount = 0;
  String? _statusMessage;

  bool get isOnline => _isOnline;
  bool get isSyncing => _isSyncing;
  int get pendingOperationCount => _pendingOperationCount;
  String? get statusMessage => _statusMessage;

  Future<void> refreshNow() async {
    await _checkConnection();
  }

  Future<void> refreshPendingCount() async {
    _pendingOperationCount = await _offlineQueueService.pendingCount();
    notifyListeners();
  }

  void _startMonitoring() {
    unawaited(_checkConnection());
    _timer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(_checkConnection()),
    );
  }

  Future<void> _checkConnection() async {
    final wasOnline = _isOnline;

    try {
      final response = await _dio.get<Map<String, dynamic>>('/api/v1/health');
      _isOnline = response.statusCode == 200;
    } catch (_) {
      _isOnline = false;
    }

    _pendingOperationCount = await _offlineQueueService.pendingCount();

    if (!_isOnline) {
      _statusMessage = _pendingOperationCount > 0
          ? 'Offline. $_pendingOperationCount change(s) will sync automatically later.'
          : 'Offline. Changes may be queued until your connection returns.';
    } else if (!wasOnline && _pendingOperationCount > 0) {
      _statusMessage = 'Back online. Syncing queued changes...';
      notifyListeners();
      await _syncPendingOperations();
      return;
    } else if (_pendingOperationCount > 0) {
      _statusMessage = '$_pendingOperationCount queued change(s) pending sync.';
    } else {
      _statusMessage = null;
    }

    notifyListeners();
  }

  Future<void> _syncPendingOperations() async {
    _isSyncing = true;
    notifyListeners();

    try {
      await _offlineQueueService.syncPendingOperations();
      _pendingOperationCount = await _offlineQueueService.pendingCount();
      _statusMessage = _pendingOperationCount == 0
          ? 'Queued changes synced successfully.'
          : 'Some queued changes are still waiting to sync.';
    } catch (_) {
      _statusMessage = 'We could not sync queued changes yet.';
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _dio.close(force: true);
    super.dispose();
  }
}
