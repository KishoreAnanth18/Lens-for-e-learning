// Unit tests for scan history and offline caching (Task 17.1)
// Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 8.6, 8.7

import 'package:flutter_test/flutter_test.dart';
import 'package:lens_elearning/models/history_models.dart';
import 'package:lens_elearning/models/scan_models.dart';
import 'package:lens_elearning/providers/history_provider.dart';
import 'package:lens_elearning/services/history_service.dart';

// ---------------------------------------------------------------------------
// Fake in-memory implementation of IHistoryService for testing
// ---------------------------------------------------------------------------

class _FakeHistoryService implements IHistoryService {
  final List<ScanHistoryItem> _items = [];
  final Map<String, ScanStatusData> _cache = {};
  final List<String> _deletedIds = [];

  List<String> get deletedIds => List.unmodifiable(_deletedIds);

  @override
  Future<void> cacheScanResult({
    required String userId,
    required String localImagePath,
    required ScanStatusData result,
  }) async {
    final item = ScanHistoryItem.fromScanResult(
      userId: userId,
      localImagePath: localImagePath,
      result: result,
    );
    _items.removeWhere((i) => i.scanId == item.scanId);
    _items.add(item);
    _cache[result.scanId] = result;
  }

  @override
  Future<List<ScanHistoryItem>> getHistory(String userId) async {
    final userItems = _items.where((i) => i.userId == userId).toList();
    // Sort newest-first (descending by createdAt).
    userItems.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return userItems;
  }

  @override
  Future<ScanStatusData?> getCachedResult(String scanId) async {
    return _cache[scanId];
  }

  @override
  Future<List<ScanHistoryItem>> searchHistory({
    required String userId,
    String? query,
    String? from,
    String? to,
  }) async {
    var results = await getHistory(userId);

    if (query != null && query.isNotEmpty) {
      final lower = query.toLowerCase();
      results = results.where((item) {
        final summaryMatch =
            item.summary?.toLowerCase().contains(lower) ?? false;
        final keywordMatch =
            item.keywords.any((k) => k.toLowerCase().contains(lower));
        return summaryMatch || keywordMatch;
      }).toList();
    }

    if (from != null && from.isNotEmpty) {
      results = results.where((item) => item.createdAt.compareTo(from) >= 0).toList();
    }

    if (to != null && to.isNotEmpty) {
      results = results.where((item) => item.createdAt.compareTo(to) <= 0).toList();
    }

    return results;
  }

  @override
  Future<void> deleteScan(String scanId) async {
    _items.removeWhere((i) => i.scanId == scanId);
    _cache.remove(scanId);
    _deletedIds.add(scanId);
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ScanStatusData _makeScanResult({
  required String scanId,
  required String createdAt,
  String summary = 'A test summary',
  List<String> keywords = const ['flutter', 'dart'],
}) {
  return ScanStatusData(
    scanId: scanId,
    status: 'complete',
    createdAt: createdAt,
    updatedAt: createdAt,
    summary: summary,
    keywords: keywords,
    videos: const [
      ScanResource(
        title: 'Video 1',
        description: 'Desc',
        url: 'https://youtube.com/v1',
      ),
    ],
    articles: const [],
    websites: const [],
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ScanHistoryItem.fromScanResult', () {
    test('maps all fields from ScanStatusData', () {
      final result = _makeScanResult(
        scanId: 'scan-1',
        createdAt: '2024-01-15T10:00:00.000Z',
        summary: 'Photosynthesis overview',
        keywords: ['photosynthesis', 'chlorophyll'],
      );

      final item = ScanHistoryItem.fromScanResult(
        userId: 'user-1',
        localImagePath: '/tmp/img.jpg',
        result: result,
      );

      expect(item.scanId, 'scan-1');
      expect(item.userId, 'user-1');
      expect(item.imageLocalPath, '/tmp/img.jpg');
      expect(item.summary, 'Photosynthesis overview');
      expect(item.keywords, containsAll(['photosynthesis', 'chlorophyll']));
      expect(item.createdAt, '2024-01-15T10:00:00.000Z');
    });
  });

  group('HistoryProvider', () {
    late _FakeHistoryService service;
    late HistoryProvider provider;

    setUp(() {
      service = _FakeHistoryService();
      provider = HistoryProvider(historyService: service);
    });

    // Requirement 8.1 — reverse chronological order
    test('getHistory returns scans in reverse chronological order', () async {
      await service.cacheScanResult(
        userId: 'u1',
        localImagePath: '',
        result: _makeScanResult(
          scanId: 'old',
          createdAt: '2024-01-01T00:00:00.000Z',
        ),
      );
      await service.cacheScanResult(
        userId: 'u1',
        localImagePath: '',
        result: _makeScanResult(
          scanId: 'new',
          createdAt: '2024-06-01T00:00:00.000Z',
        ),
      );

      await provider.loadHistory('u1', force: true);

      expect(provider.items.length, 2);
      expect(provider.items.first.scanId, 'new',
          reason: 'Newest scan should appear first');
      expect(provider.items.last.scanId, 'old');
    });

    // Requirement 8.2 — history item display completeness
    test('history items contain date, thumbnail URL, and summary', () async {
      await service.cacheScanResult(
        userId: 'u1',
        localImagePath: '/img/thumb.jpg',
        result: _makeScanResult(
          scanId: 's1',
          createdAt: '2024-03-10T08:30:00.000Z',
          summary: 'Cell biology basics',
        ),
      );

      await provider.loadHistory('u1', force: true);
      final item = provider.items.first;

      expect(item.createdAt, isNotEmpty);
      expect(item.imageLocalPath, '/img/thumb.jpg');
      expect(item.summary, 'Cell biology basics');
    });

    // Requirement 8.4 — result caching round-trip
    test('cacheScanResult stores and getCachedResult retrieves same data', () async {
      final result = _makeScanResult(
        scanId: 'scan-rt',
        createdAt: '2024-04-01T12:00:00.000Z',
        summary: 'Round-trip summary',
        keywords: ['round', 'trip'],
      );

      await provider.cacheScanResult(
        userId: 'u1',
        localImagePath: '/img/rt.jpg',
        result: result,
      );

      final cached = await provider.getCachedResult('scan-rt');

      expect(cached, isNotNull);
      expect(cached!.scanId, 'scan-rt');
      expect(cached.summary, 'Round-trip summary');
      expect(cached.keywords, containsAll(['round', 'trip']));
      expect(cached.videos.length, 1);
      expect(cached.videos.first.url, 'https://youtube.com/v1');
    });

    // Requirement 8.5 — offline access (data is available from local cache)
    test('getCachedResult returns data without network access', () async {
      final result = _makeScanResult(
        scanId: 'offline-scan',
        createdAt: '2024-05-01T09:00:00.000Z',
        summary: 'Offline content',
      );

      await service.cacheScanResult(
        userId: 'u1',
        localImagePath: '',
        result: result,
      );

      // getCachedResult should work purely from local storage (fake service
      // has no network dependency).
      final cached = await provider.getCachedResult('offline-scan');
      expect(cached, isNotNull);
      expect(cached!.summary, 'Offline content');
    });

    // Requirement 8.6 — deletion consistency
    test('deleteScan removes item from provider list and calls service', () async {
      await service.cacheScanResult(
        userId: 'u1',
        localImagePath: '',
        result: _makeScanResult(
          scanId: 'del-scan',
          createdAt: '2024-02-01T00:00:00.000Z',
        ),
      );

      await provider.loadHistory('u1', force: true);
      expect(provider.items.any((i) => i.scanId == 'del-scan'), isTrue);

      await provider.deleteScan('del-scan');

      expect(provider.items.any((i) => i.scanId == 'del-scan'), isFalse,
          reason: 'Deleted scan should not appear in provider list');
      expect(service.deletedIds, contains('del-scan'),
          reason: 'Service deleteScan should have been called');
    });

    // Requirement 8.7 — search filtering
    test('setSearchQuery filters items by summary text', () async {
      await service.cacheScanResult(
        userId: 'u1',
        localImagePath: '',
        result: _makeScanResult(
          scanId: 's-match',
          createdAt: '2024-06-01T00:00:00.000Z',
          summary: 'Quantum mechanics introduction',
          keywords: ['quantum', 'mechanics'],
        ),
      );
      await service.cacheScanResult(
        userId: 'u1',
        localImagePath: '',
        result: _makeScanResult(
          scanId: 's-no-match',
          createdAt: '2024-06-02T00:00:00.000Z',
          summary: 'Cell biology overview',
          keywords: ['cell', 'biology'],
        ),
      );

      provider.setSearchQuery('quantum', 'u1');
      // Wait for async load triggered by setSearchQuery.
      await Future<void>.delayed(Duration.zero);
      await provider.loadHistory('u1', force: true);

      expect(provider.items.length, 1);
      expect(provider.items.first.scanId, 's-match');
    });

    // Requirement 8.7 — date range filtering
    test('setDateFilter restricts results to the given date range', () async {
      await service.cacheScanResult(
        userId: 'u1',
        localImagePath: '',
        result: _makeScanResult(
          scanId: 'jan',
          createdAt: '2024-01-15T00:00:00.000Z',
        ),
      );
      await service.cacheScanResult(
        userId: 'u1',
        localImagePath: '',
        result: _makeScanResult(
          scanId: 'mar',
          createdAt: '2024-03-20T00:00:00.000Z',
        ),
      );
      await service.cacheScanResult(
        userId: 'u1',
        localImagePath: '',
        result: _makeScanResult(
          scanId: 'jun',
          createdAt: '2024-06-01T00:00:00.000Z',
        ),
      );

      provider.setDateFilter(
        userId: 'u1',
        from: '2024-02-01T00:00:00.000Z',
        to: '2024-04-30T23:59:59.000Z',
      );
      await Future<void>.delayed(Duration.zero);
      await provider.loadHistory('u1', force: true);

      final ids = provider.items.map((i) => i.scanId).toList();
      expect(ids, contains('mar'));
      expect(ids, isNot(contains('jan')));
      expect(ids, isNot(contains('jun')));
    });

    // Requirement 8.7 — clearing filters restores full list
    test('clearFilters restores full history', () async {
      await service.cacheScanResult(
        userId: 'u1',
        localImagePath: '',
        result: _makeScanResult(
          scanId: 'a',
          createdAt: '2024-01-01T00:00:00.000Z',
          summary: 'Alpha topic',
        ),
      );
      await service.cacheScanResult(
        userId: 'u1',
        localImagePath: '',
        result: _makeScanResult(
          scanId: 'b',
          createdAt: '2024-02-01T00:00:00.000Z',
          summary: 'Beta topic',
        ),
      );

      provider.setSearchQuery('alpha', 'u1');
      await Future<void>.delayed(Duration.zero);
      await provider.loadHistory('u1', force: true);
      expect(provider.items.length, 1);

      provider.clearFilters('u1');
      await Future<void>.delayed(Duration.zero);
      await provider.loadHistory('u1', force: true);
      expect(provider.items.length, 2);
    });

    // Requirement 8.3 — tap to view full results (getCachedResult returns full data)
    test('getCachedResult returns full resource lists for a cached scan', () async {
      const result = ScanStatusData(
        scanId: 'full-scan',
        status: 'complete',
        createdAt: '2024-07-01T00:00:00.000Z',
        updatedAt: '2024-07-01T00:00:00.000Z',
        summary: 'Full results test',
        keywords: ['test'],
        videos: [
          ScanResource(title: 'V1', description: 'D1', url: 'https://yt.com/1'),
          ScanResource(title: 'V2', description: 'D2', url: 'https://yt.com/2'),
        ],
        articles: [
          ScanResource(
              title: 'A1', description: 'DA1', url: 'https://article.com/1'),
        ],
        websites: [
          ScanResource(
              title: 'W1', description: 'DW1', url: 'https://site.com/1'),
        ],
      );

      await service.cacheScanResult(
        userId: 'u1',
        localImagePath: '',
        result: result,
      );

      final cached = await provider.getCachedResult('full-scan');
      expect(cached!.videos.length, 2);
      expect(cached.articles.length, 1);
      expect(cached.websites.length, 1);
    });
  });
}
