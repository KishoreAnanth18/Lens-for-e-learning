import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/scan_models.dart';
import 'auth_service.dart';
import 'local_database.dart';
import 'network_utils.dart';

class OfflineQueueService {
  OfflineQueueService({
    required String baseUrl,
    required IAuthService authService,
    LocalDatabase? database,
  })  : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 8),
            sendTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 12),
          ),
        ),
        _authService = authService,
        _database = database ?? LocalDatabase.instance;

  final Dio _dio;
  final IAuthService _authService;
  final LocalDatabase _database;

  Future<void> enqueueBookmarkCreate({
    required String scanId,
    required String resourceType,
    required ScanResource resource,
  }) {
    return _database.addQueuedOperation(
      operationType: 'create_bookmark',
      payload: {
        'scan_id': scanId,
        'resource_type': resourceType,
        'resource_url': resource.url,
        'resource_title': resource.title,
        'resource_description': resource.description,
      },
    );
  }

  Future<void> enqueueBookmarkDelete(String bookmarkId) {
    return _database.addQueuedOperation(
      operationType: 'delete_bookmark',
      payload: {'bookmark_id': bookmarkId},
    );
  }

  Future<void> enqueueScanDelete(String scanId) {
    return _database.addQueuedOperation(
      operationType: 'delete_scan',
      payload: {'scan_id': scanId},
    );
  }

  Future<int> pendingCount() => _database.getQueuedOperationCount();

  Future<void> syncPendingOperations() async {
    final operations = await _database.getQueuedOperations();
    if (operations.isEmpty) return;

    final token = await _authService.getValidToken();

    for (final operation in operations) {
      final id = operation['id'] as int?;
      final operationType = operation['operation_type'] as String? ?? '';
      final rawPayload = operation['payload'] as String? ?? '{}';
      final payload = Map<String, dynamic>.from(
        jsonDecode(rawPayload) as Map<String, dynamic>,
      );

      if (id == null) {
        continue;
      }

      try {
        await retryWithBackoff(
          () => _executeOperation(
            token: token,
            operationType: operationType,
            payload: payload,
          ),
        );
        await _database.removeQueuedOperation(id);
      } catch (error) {
        await _database.markQueuedOperationFailed(
          id,
          error: friendlyNetworkMessage(error, action: 'sync your pending changes'),
        );

        if (!isRetryableNetworkError(error)) {
          await _database.removeQueuedOperation(id);
        }

        if (isOfflineError(error)) {
          return;
        }
      }
    }
  }

  Future<void> _executeOperation({
    required String token,
    required String operationType,
    required Map<String, dynamic> payload,
  }) async {
    final options = Options(headers: {'Authorization': 'Bearer $token'});

    switch (operationType) {
      case 'create_bookmark':
        await _dio.post<void>(
          '/api/v1/scans/${payload['scan_id']}/bookmarks',
          data: {
            'resource_type': payload['resource_type'],
            'resource_url': payload['resource_url'],
            'resource_title': payload['resource_title'],
            'resource_description': payload['resource_description'],
          },
          options: options,
        );
        return;
      case 'delete_bookmark':
        await _dio.delete<void>(
          '/api/v1/bookmarks/${payload['bookmark_id']}',
          options: options,
        );
        return;
      case 'delete_scan':
        await _dio.delete<void>(
          '/api/v1/scans/${payload['scan_id']}',
          options: options,
        );
        return;
      default:
        return;
    }
  }
}
