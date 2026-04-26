import '../models/bookmark_models.dart';
import '../models/scan_models.dart';

abstract class IBookmarkService {
  Future<List<BookmarkItem>> getBookmarks();
  Future<BookmarkItem> createBookmark({
    required String scanId,
    required String resourceType,
    required ScanResource resource,
  });
  Future<void> deleteBookmark(String bookmarkId);
}
