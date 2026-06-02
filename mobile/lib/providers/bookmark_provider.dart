import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/bookmark_models.dart';
import '../models/scan_models.dart';
import '../services/bookmark_service.dart';
import '../services/network_utils.dart';
import '../services/offline_queue_service.dart';

class BookmarkProvider extends ChangeNotifier {
  BookmarkProvider({
    required IBookmarkService bookmarkService,
    OfflineQueueService? offlineQueueService,
  })  : _bookmarkService = bookmarkService,
        _offlineQueueService = offlineQueueService;

  final IBookmarkService _bookmarkService;
  final OfflineQueueService? _offlineQueueService;
  final _uuid = const Uuid();

  List<BookmarkItem> _bookmarks = const [];
  bool _isLoading = false;
  bool _hasLoaded = false;
  String? _errorMessage;

  List<BookmarkItem> get bookmarks => _bookmarks;
  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;
  String? get errorMessage => _errorMessage;

  Future<void> loadBookmarks({bool force = false}) async {
    if (_isLoading) return;
    if (_hasLoaded && !force) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _bookmarks = await _bookmarkService.getBookmarks();
      _hasLoaded = true;
    } catch (error) {
      _errorMessage = friendlyNetworkMessage(error, action: 'load your bookmarks');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  bool isBookmarked(String url) {
    return _bookmarks.any((bookmark) => bookmark.resourceUrl == url);
  }

  String? bookmarkIdForUrl(String url) {
    for (final bookmark in _bookmarks) {
      if (bookmark.resourceUrl == url) return bookmark.bookmarkId;
    }
    return null;
  }

  Future<void> toggleBookmark({
    required String scanId,
    required String resourceType,
    required ScanResource resource,
  }) async {
    _errorMessage = null;
    final existingId = bookmarkIdForUrl(resource.url);
    if (existingId != null) {
      final previous = _bookmarks;
      _bookmarks = _bookmarks.where((item) => item.bookmarkId != existingId).toList();
      notifyListeners();

      try {
        await _bookmarkService.deleteBookmark(existingId);
      } catch (error) {
        if (isRetryableNetworkError(error)) {
          await _offlineQueueService?.enqueueBookmarkDelete(existingId);
          _errorMessage =
              'Bookmark removal was queued and will sync when you are back online.';
        } else {
          _bookmarks = previous;
          _errorMessage = friendlyNetworkMessage(error, action: 'remove this bookmark');
        }
        notifyListeners();
      }
      return;
    }

    final optimistic = BookmarkItem(
      bookmarkId: 'queued-${_uuid.v4()}',
      scanId: scanId,
      resourceType: resourceType,
      resourceUrl: resource.url,
      resourceTitle: resource.title,
      resourceDescription: resource.description,
      bookmarkedAt: DateTime.now().toIso8601String(),
    );

    _bookmarks = [optimistic, ..._bookmarks];
    notifyListeners();

    try {
      final bookmark = await _bookmarkService.createBookmark(
        scanId: scanId,
        resourceType: resourceType,
        resource: resource,
      );
      _bookmarks = [
        bookmark,
        ..._bookmarks.where((item) => item.bookmarkId != optimistic.bookmarkId),
      ];
    } catch (error) {
      if (isRetryableNetworkError(error)) {
        await _offlineQueueService?.enqueueBookmarkCreate(
          scanId: scanId,
          resourceType: resourceType,
          resource: resource,
        );
        _errorMessage =
            'Bookmark saved locally and queued for sync when your connection returns.';
      } else {
        _bookmarks = _bookmarks.where((item) => item.bookmarkId != optimistic.bookmarkId).toList();
        _errorMessage = friendlyNetworkMessage(error, action: 'save this bookmark');
      }
      notifyListeners();
      return;
    }

    notifyListeners();
  }

  Future<void> removeBookmark(String bookmarkId) async {
    _errorMessage = null;
    final previous = _bookmarks;
    _bookmarks = _bookmarks.where((bookmark) => bookmark.bookmarkId != bookmarkId).toList();

    try {
      await _bookmarkService.deleteBookmark(bookmarkId);
    } catch (error) {
      if (isRetryableNetworkError(error)) {
        await _offlineQueueService?.enqueueBookmarkDelete(bookmarkId);
        _errorMessage =
            'Bookmark removal was queued and will sync when you are back online.';
      } else {
        _bookmarks = previous;
        _errorMessage = friendlyNetworkMessage(error, action: 'remove this bookmark');
      }
    }

    notifyListeners();
  }
}
