import 'package:flutter/foundation.dart';

import '../models/bookmark_models.dart';
import '../models/scan_models.dart';
import '../services/bookmark_service.dart';

class BookmarkProvider extends ChangeNotifier {
  BookmarkProvider({required IBookmarkService bookmarkService})
      : _bookmarkService = bookmarkService;

  final IBookmarkService _bookmarkService;
  List<BookmarkItem> _bookmarks = const [];
  bool _isLoading = false;
  bool _hasLoaded = false;

  List<BookmarkItem> get bookmarks => _bookmarks;
  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;

  Future<void> loadBookmarks({bool force = false}) async {
    if (_isLoading) return;
    if (_hasLoaded && !force) return;
    _isLoading = true;
    notifyListeners();

    try {
      _bookmarks = await _bookmarkService.getBookmarks();
      _hasLoaded = true;
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
    final existingId = bookmarkIdForUrl(resource.url);
    if (existingId != null) {
      await _bookmarkService.deleteBookmark(existingId);
      _bookmarks = _bookmarks.where((item) => item.bookmarkId != existingId).toList();
      notifyListeners();
      return;
    }

    final bookmark = await _bookmarkService.createBookmark(
      scanId: scanId,
      resourceType: resourceType,
      resource: resource,
    );
    _bookmarks = [bookmark, ..._bookmarks];
    notifyListeners();
  }

  Future<void> removeBookmark(String bookmarkId) async {
    await _bookmarkService.deleteBookmark(bookmarkId);
    _bookmarks = _bookmarks.where((bookmark) => bookmark.bookmarkId != bookmarkId).toList();
    notifyListeners();
  }
}
