import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Manages the local SQLite database for offline caching.
///
/// Schema mirrors the design document:
///   scans, scan_keywords, resources, bookmarks
class LocalDatabase {
  LocalDatabase._();

  static final LocalDatabase instance = LocalDatabase._();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'lens_elearning.db');

    return openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE scans (
        scan_id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        image_local_path TEXT,
        image_thumbnail_url TEXT,
        summary TEXT,
        error_message TEXT,
        synced INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE scan_keywords (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        scan_id TEXT NOT NULL,
        keyword TEXT NOT NULL,
        score REAL,
        FOREIGN KEY (scan_id) REFERENCES scans(scan_id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE resources (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        scan_id TEXT NOT NULL,
        resource_type TEXT NOT NULL,
        url TEXT NOT NULL,
        title TEXT NOT NULL,
        description TEXT,
        metadata TEXT,
        FOREIGN KEY (scan_id) REFERENCES scans(scan_id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE bookmarks (
        bookmark_id TEXT PRIMARY KEY,
        scan_id TEXT NOT NULL,
        resource_id INTEGER NOT NULL,
        bookmarked_at TEXT NOT NULL,
        synced INTEGER DEFAULT 0,
        FOREIGN KEY (resource_id) REFERENCES resources(id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_scans_user_created ON scans(user_id, created_at DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_resources_scan ON resources(scan_id)',
    );
    await db.execute(
      'CREATE INDEX idx_bookmarks_scan ON bookmarks(scan_id)',
    );

    await db.execute('''
      CREATE TABLE queued_operations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        operation_type TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL,
        attempt_count INTEGER DEFAULT 0,
        last_error TEXT
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_queued_operations_created ON queued_operations(created_at ASC)',
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE queued_operations (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          operation_type TEXT NOT NULL,
          payload TEXT NOT NULL,
          created_at TEXT NOT NULL,
          attempt_count INTEGER DEFAULT 0,
          last_error TEXT
        )
      ''');

      await db.execute(
        'CREATE INDEX idx_queued_operations_created ON queued_operations(created_at ASC)',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Scans
  // ---------------------------------------------------------------------------

  /// Insert or replace a scan record.
  Future<void> upsertScan(Map<String, dynamic> row) async {
    final db = await database;
    await db.insert(
      'scans',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Return all scans for [userId] ordered newest-first.
  Future<List<Map<String, dynamic>>> getScans(String userId) async {
    final db = await database;
    return db.query(
      'scans',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
    );
  }

  /// Return a single scan row or null.
  Future<Map<String, dynamic>?> getScan(String scanId) async {
    final db = await database;
    final rows = await db.query(
      'scans',
      where: 'scan_id = ?',
      whereArgs: [scanId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// Delete a scan and all its related rows (cascade).
  Future<void> deleteScan(String scanId) async {
    final db = await database;
    await db.delete('scans', where: 'scan_id = ?', whereArgs: [scanId]);
  }

  // ---------------------------------------------------------------------------
  // Keywords
  // ---------------------------------------------------------------------------

  Future<void> upsertKeywords(
    String scanId,
    List<String> keywords,
  ) async {
    final db = await database;
    final batch = db.batch();
    batch.delete(
      'scan_keywords',
      where: 'scan_id = ?',
      whereArgs: [scanId],
    );
    for (final kw in keywords) {
      batch.insert('scan_keywords', {
        'scan_id': scanId,
        'keyword': kw,
        'score': null,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<List<String>> getKeywords(String scanId) async {
    final db = await database;
    final rows = await db.query(
      'scan_keywords',
      columns: ['keyword'],
      where: 'scan_id = ?',
      whereArgs: [scanId],
    );
    return rows.map((r) => r['keyword'] as String).toList();
  }

  // ---------------------------------------------------------------------------
  // Resources
  // ---------------------------------------------------------------------------

  Future<void> upsertResources(
    String scanId,
    List<Map<String, dynamic>> resources,
  ) async {
    final db = await database;
    final batch = db.batch();
    batch.delete(
      'resources',
      where: 'scan_id = ?',
      whereArgs: [scanId],
    );
    for (final res in resources) {
      batch.insert('resources', {
        'scan_id': scanId,
        'resource_type': res['resource_type'] as String? ?? '',
        'url': res['url'] as String? ?? '',
        'title': res['title'] as String? ?? '',
        'description': res['description'] as String? ?? '',
        'metadata': res['metadata'] != null
            ? jsonEncode(res['metadata'])
            : null,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getResources(String scanId) async {
    final db = await database;
    return db.query(
      'resources',
      where: 'scan_id = ?',
      whereArgs: [scanId],
    );
  }

  // ---------------------------------------------------------------------------
  // Search helpers
  // ---------------------------------------------------------------------------

  /// Return scans matching [query] in summary/keywords and optionally within
  /// [from]..[to] date range (ISO-8601 strings).
  Future<List<Map<String, dynamic>>> searchScans({
    required String userId,
    String? query,
    String? from,
    String? to,
  }) async {
    final db = await database;

    final conditions = <String>['s.user_id = ?'];
    final args = <dynamic>[userId];

    if (query != null && query.isNotEmpty) {
      conditions.add(
        '(s.summary LIKE ? OR EXISTS ('
        '  SELECT 1 FROM scan_keywords k'
        '  WHERE k.scan_id = s.scan_id AND k.keyword LIKE ?'
        '))',
      );
      final like = '%$query%';
      args.addAll([like, like]);
    }

    if (from != null && from.isNotEmpty) {
      conditions.add('s.created_at >= ?');
      args.add(from);
    }

    if (to != null && to.isNotEmpty) {
      conditions.add('s.created_at <= ?');
      args.add(to);
    }

    final where = conditions.join(' AND ');
    final sql = '''
      SELECT s.*
      FROM scans s
      WHERE $where
      ORDER BY s.created_at DESC
    ''';

    return db.rawQuery(sql, args);
  }

  // ---------------------------------------------------------------------------
  // Offline queue
  // ---------------------------------------------------------------------------

  Future<int> addQueuedOperation({
    required String operationType,
    required Map<String, dynamic> payload,
  }) async {
    final db = await database;
    return db.insert('queued_operations', {
      'operation_type': operationType,
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
      'attempt_count': 0,
      'last_error': null,
    });
  }

  Future<List<Map<String, dynamic>>> getQueuedOperations() async {
    final db = await database;
    return db.query(
      'queued_operations',
      orderBy: 'created_at ASC',
    );
  }

  Future<int> getQueuedOperationCount() async {
    final db = await database;
    return Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM queued_operations'),
        ) ??
        0;
  }

  Future<void> removeQueuedOperation(int id) async {
    final db = await database;
    await db.delete(
      'queued_operations',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markQueuedOperationFailed(
    int id, {
    required String error,
  }) async {
    final db = await database;
    await db.rawUpdate(
      '''
      UPDATE queued_operations
      SET attempt_count = attempt_count + 1,
          last_error = ?
      WHERE id = ?
      ''',
      [error, id],
    );
  }
}
