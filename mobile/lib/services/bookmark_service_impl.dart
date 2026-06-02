import 'package:dio/dio.dart';

import '../models/bookmark_models.dart';
import '../models/scan_models.dart';
import 'auth_service.dart';
import 'bookmark_service.dart';
import 'network_utils.dart';

class BookmarkServiceImpl implements IBookmarkService {
  BookmarkServiceImpl({
    required String baseUrl,
    required IAuthService authService,
  })  : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 8),
            sendTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 12),
          ),
        ),
        _authService = authService;

  final Dio _dio;
  final IAuthService _authService;

  @override
  Future<List<BookmarkItem>> getBookmarks() async {
    final token = await _authService.getValidToken();
    final response = await retryWithBackoff(
      () => _dio.get<Map<String, dynamic>>(
        '/api/v1/bookmarks',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      ),
    );
    final raw = response.data?['bookmarks'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => BookmarkItem.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  @override
  Future<BookmarkItem> createBookmark({
    required String scanId,
    required String resourceType,
    required ScanResource resource,
  }) async {
    final token = await _authService.getValidToken();
    final response = await retryWithBackoff(
      () => _dio.post<Map<String, dynamic>>(
        '/api/v1/scans/$scanId/bookmarks',
        data: {
          'resource_type': resourceType,
          'resource_url': resource.url,
          'resource_title': resource.title,
          'resource_description': resource.description,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      ),
    );
    return BookmarkItem.fromJson(response.data ?? const <String, dynamic>{});
  }

  @override
  Future<void> deleteBookmark(String bookmarkId) async {
    final token = await _authService.getValidToken();
    await retryWithBackoff(
      () => _dio.delete<void>(
        '/api/v1/bookmarks/$bookmarkId',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      ),
    );
  }
}
