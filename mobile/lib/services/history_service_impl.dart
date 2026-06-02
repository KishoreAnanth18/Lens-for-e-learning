import 'package:dio/dio.dart';

import '../models/history_models.dart';
import '../models/scan_models.dart';
import 'auth_service.dart';
import 'history_service.dart';
import 'local_database.dart';
import 'network_utils.dart';

class HistoryServiceImpl implements IHistoryService {
  HistoryServiceImpl({
    required String baseUrl,
    required IAuthService authService,
    LocalDatabase? db,
  })  : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 8),
            sendTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 12),
          ),
        ),
        _authService = authService,
        _db = db ?? LocalDatabase.instance;

  final Dio _dio;
  final IAuthService _authService;
  final LocalDatabase _db;

  @override
  Future<void> cacheScanResult({
    required String userId,
    required String localImagePath,
    required ScanStatusData result,
  }) async {
    await _db.upsertScan({
      'scan_id': result.scanId,
      'user_id': userId,
      'status': result.status,
      'created_at': result.createdAt ?? DateTime.now().toIso8601String(),
      'updated_at': result.updatedAt ?? DateTime.now().toIso8601String(),
      'image_local_path': localImagePath,
      'image_thumbnail_url': result.imageThumbnailKey,
      'summary': result.summary,
      'error_message': result.errorMessage,
      'synced': 1,
    });

    if (result.keywords.isNotEmpty) {
      await _db.upsertKeywords(result.scanId, result.keywords);
    }

    final resources = <Map<String, dynamic>>[
      for (final v in result.videos)
        {
          'resource_type': 'video',
          'url': v.url,
          'title': v.title,
          'description': v.description,
        },
      for (final a in result.articles)
        {
          'resource_type': 'article',
          'url': a.url,
          'title': a.title,
          'description': a.description,
        },
      for (final w in result.websites)
        {
          'resource_type': 'website',
          'url': w.url,
          'title': w.title,
          'description': w.description,
        },
    ];

    if (resources.isNotEmpty) {
      await _db.upsertResources(result.scanId, resources);
    }
  }

  @override
  Future<List<ScanHistoryItem>> getHistory(String userId) async {
    final rows = await _db.getScans(userId);
    return _rowsToItems(rows);
  }

  @override
  Future<ScanStatusData?> getCachedResult(String scanId) async {
    final row = await _db.getScan(scanId);
    if (row == null) return null;

    final keywords = await _db.getKeywords(scanId);
    final resourceRows = await _db.getResources(scanId);

    List<ScanResource> byType(String type) => resourceRows
        .where((r) => r['resource_type'] == type)
        .map(
          (r) => ScanResource(
            title: r['title'] as String? ?? '',
            description: r['description'] as String? ?? '',
            url: r['url'] as String? ?? '',
          ),
        )
        .toList();

    return ScanStatusData(
      scanId: row['scan_id'] as String? ?? scanId,
      status: row['status'] as String? ?? 'complete',
      createdAt: row['created_at'] as String?,
      updatedAt: row['updated_at'] as String?,
      imageThumbnailKey: row['image_thumbnail_url'] as String?,
      errorMessage: row['error_message'] as String?,
      summary: row['summary'] as String?,
      keywords: keywords,
      videos: byType('video'),
      articles: byType('article'),
      websites: byType('website'),
    );
  }

  @override
  Future<List<ScanHistoryItem>> searchHistory({
    required String userId,
    String? query,
    String? from,
    String? to,
  }) async {
    final rows = await _db.searchScans(
      userId: userId,
      query: query,
      from: from,
      to: to,
    );
    return _rowsToItems(rows);
  }

  @override
  Future<void> deleteScan(String scanId) async {
    await _db.deleteScan(scanId);

    final token = await _authService.getValidToken();
    await retryWithBackoff(
      () => _dio.delete<void>(
        '/api/v1/scans/$scanId',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      ),
    );
  }

  Future<List<ScanHistoryItem>> _rowsToItems(
    List<Map<String, dynamic>> rows,
  ) async {
    final items = <ScanHistoryItem>[];
    for (final row in rows) {
      final scanId = row['scan_id'] as String? ?? '';
      final keywords = await _db.getKeywords(scanId);
      items.add(ScanHistoryItem.fromDb(row, keywords: keywords));
    }
    return items;
  }
}
