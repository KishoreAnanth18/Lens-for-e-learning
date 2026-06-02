import '../models/history_models.dart';
import '../models/scan_models.dart';

/// Interface for scan history and offline caching operations.
abstract class IHistoryService {
  /// Cache a completed scan result locally.
  Future<void> cacheScanResult({
    required String userId,
    required String localImagePath,
    required ScanStatusData result,
  });

  /// Return all cached scans for [userId] in reverse chronological order.
  Future<List<ScanHistoryItem>> getHistory(String userId);

  /// Return the full cached [ScanStatusData] for [scanId], or null if not
  /// cached.
  Future<ScanStatusData?> getCachedResult(String scanId);

  /// Search history by keyword query and/or date range.
  ///
  /// [from] and [to] are ISO-8601 date strings (inclusive).
  Future<List<ScanHistoryItem>> searchHistory({
    required String userId,
    String? query,
    String? from,
    String? to,
  });

  /// Delete a scan from local cache and from the remote API.
  Future<void> deleteScan(String scanId);
}
