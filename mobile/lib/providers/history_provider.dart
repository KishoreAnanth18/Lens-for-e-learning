import 'package:flutter/foundation.dart';

import '../models/history_models.dart';
import '../models/scan_models.dart';
import '../services/history_service.dart';
import '../services/network_utils.dart';
import '../services/offline_queue_service.dart';

/// State management for scan history and offline caching.
class HistoryProvider extends ChangeNotifier {
  HistoryProvider({
    required IHistoryService historyService,
    OfflineQueueService? offlineQueueService,
  })  : _historyService = historyService,
        _offlineQueueService = offlineQueueService;

  final IHistoryService _historyService;
  final OfflineQueueService? _offlineQueueService;

  List<ScanHistoryItem> _items = const [];
  bool _isLoading = false;
  bool _hasLoaded = false;
  String? _errorMessage;

  String _searchQuery = '';
  String? _filterFrom;
  String? _filterTo;

  List<ScanHistoryItem> get items => _items;
  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;
  String? get errorMessage => _errorMessage;
  String get searchQuery => _searchQuery;
  String? get filterFrom => _filterFrom;
  String? get filterTo => _filterTo;

  bool get hasActiveFilter =>
      _searchQuery.isNotEmpty ||
      (_filterFrom != null && _filterFrom!.isNotEmpty) ||
      (_filterTo != null && _filterTo!.isNotEmpty);

  Future<void> loadHistory(String userId, {bool force = false}) async {
    if (_isLoading) return;
    if (_hasLoaded && !force && !hasActiveFilter) return;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      if (hasActiveFilter) {
        _items = await _historyService.searchHistory(
          userId: userId,
          query: _searchQuery.isEmpty ? null : _searchQuery,
          from: _filterFrom,
          to: _filterTo,
        );
      } else {
        _items = await _historyService.getHistory(userId);
      }
      _hasLoaded = true;
    } catch (error) {
      _errorMessage = friendlyNetworkMessage(error, action: 'load your scan history');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> cacheScanResult({
    required String userId,
    required String localImagePath,
    required ScanStatusData result,
  }) async {
    await _historyService.cacheScanResult(
      userId: userId,
      localImagePath: localImagePath,
      result: result,
    );
    _hasLoaded = false;
  }

  Future<ScanStatusData?> getCachedResult(String scanId) {
    return _historyService.getCachedResult(scanId);
  }

  void setSearchQuery(String query, String userId) {
    if (_searchQuery == query) return;
    _searchQuery = query;
    _hasLoaded = false;
    notifyListeners();
    loadHistory(userId, force: true);
  }

  void setDateFilter({
    required String userId,
    String? from,
    String? to,
  }) {
    _filterFrom = from;
    _filterTo = to;
    _hasLoaded = false;
    notifyListeners();
    loadHistory(userId, force: true);
  }

  void clearFilters(String userId) {
    _searchQuery = '';
    _filterFrom = null;
    _filterTo = null;
    _hasLoaded = false;
    notifyListeners();
    loadHistory(userId, force: true);
  }

  Future<void> deleteScan(String scanId) async {
    _errorMessage = null;
    _items = _items.where((item) => item.scanId != scanId).toList();
    notifyListeners();

    try {
      await _historyService.deleteScan(scanId);
    } catch (error) {
      if (isRetryableNetworkError(error)) {
        await _offlineQueueService?.enqueueScanDelete(scanId);
        _errorMessage =
            'Scan removed locally and queued for server sync when your connection returns.';
      } else {
        _errorMessage =
            'Scan removed from this device, but we could not confirm deletion on the server.';
      }
      notifyListeners();
    }
  }
}
