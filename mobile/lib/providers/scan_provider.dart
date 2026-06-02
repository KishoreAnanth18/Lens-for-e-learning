import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/camera_models.dart';
import '../models/scan_models.dart';
import '../services/scan_service.dart';

/// Callback invoked when a scan completes successfully so the result can be
/// persisted to the local cache.
typedef ScanCompletedCallback = Future<void> Function({
  required String localImagePath,
  required ScanStatusData result,
});

class ScanProvider extends ChangeNotifier {
  ScanProvider({
    required IScanService scanService,
    ScanCompletedCallback? onScanCompleted,
  })  : _scanService = scanService,
        _onScanCompleted = onScanCompleted;

  final IScanService _scanService;
  ScanCompletedCallback? _onScanCompleted;
  final Map<String, ScanProgress> _sessions = {};
  final Map<String, StreamSubscription<ScanProgress>> _subscriptions = {};
  final Map<String, Set<String>> _bookmarksBySession = {};

  ScanProgress? get latestSession {
    if (_sessions.isEmpty) return null;
    return _sessions.values.last;
  }

  ScanProgress? sessionById(String sessionId) => _sessions[sessionId];

  /// Exposes the full sessions map for cross-provider lookups (e.g. history).
  Map<String, ScanProgress> get sessions => Map.unmodifiable(_sessions);

  Set<String> bookmarksFor(String sessionId) => _bookmarksBySession[sessionId] ?? <String>{};

  /// Update the cache callback (called by ProxyProvider when HistoryProvider
  /// changes).
  void updateCacheCallback(ScanCompletedCallback? callback) {
    _onScanCompleted = callback;
  }

  Future<String> startScan(CompressedImage image) async {
    final stream = _scanService.processScan(image);
    final first = await stream.first;
    _sessions[first.sessionId] = first;
    notifyListeners();

    _subscriptions[first.sessionId] = stream.listen(
      (progress) {
        _sessions[progress.sessionId] = progress;
        notifyListeners();

        // Cache the result when the scan completes successfully.
        if (progress.isSuccessful && progress.result != null) {
          _onScanCompleted?.call(
            localImagePath: progress.localImagePath ?? '',
            result: progress.result!,
          );
        }
      },
      onError: (Object error) {
        final previous = _sessions[first.sessionId];
        if (previous != null) {
          _sessions[first.sessionId] = previous.copyWith(
            stage: ScanStage.failed,
            progress: 1,
            statusMessage: 'Scan failed',
            errorMessage: '$error',
          );
          notifyListeners();
        }
      },
    );

    return first.sessionId;
  }

  void markBackgrounded(String sessionId, bool backgrounded) {
    final session = _sessions[sessionId];
    if (session == null) return;
    if (session.isInBackground == backgrounded) return;
    _sessions[sessionId] = session.copyWith(isInBackground: backgrounded);
    notifyListeners();
  }

  void clearSession(String sessionId) {
    _subscriptions.remove(sessionId)?.cancel();
    _sessions.remove(sessionId);
    _bookmarksBySession.remove(sessionId);
    notifyListeners();
  }

  bool isBookmarked(String sessionId, String url) {
    return bookmarksFor(sessionId).contains(url);
  }

  void toggleBookmark(String sessionId, String url) {
    final bookmarks = _bookmarksBySession.putIfAbsent(sessionId, () => <String>{});
    if (bookmarks.contains(url)) {
      bookmarks.remove(url);
    } else {
      bookmarks.add(url);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions.values) {
      subscription.cancel();
    }
    super.dispose();
  }
}
