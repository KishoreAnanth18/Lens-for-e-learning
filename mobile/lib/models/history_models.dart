import 'scan_models.dart';

/// A lightweight summary of a past scan shown in the history list.
class ScanHistoryItem {
  final String scanId;
  final String userId;
  final String status;
  final String createdAt;
  final String updatedAt;
  final String? imageLocalPath;
  final String? imageThumbnailUrl;
  final String? summary;
  final String? errorMessage;
  final List<String> keywords;

  const ScanHistoryItem({
    required this.scanId,
    required this.userId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.imageLocalPath,
    this.imageThumbnailUrl,
    this.summary,
    this.errorMessage,
    this.keywords = const [],
  });

  factory ScanHistoryItem.fromDb(
    Map<String, dynamic> row, {
    List<String> keywords = const [],
  }) {
    return ScanHistoryItem(
      scanId: row['scan_id'] as String? ?? '',
      userId: row['user_id'] as String? ?? '',
      status: row['status'] as String? ?? '',
      createdAt: row['created_at'] as String? ?? '',
      updatedAt: row['updated_at'] as String? ?? '',
      imageLocalPath: row['image_local_path'] as String?,
      imageThumbnailUrl: row['image_thumbnail_url'] as String?,
      summary: row['summary'] as String?,
      errorMessage: row['error_message'] as String?,
      keywords: keywords,
    );
  }

  /// Build a history item from a live [ScanStatusData] result.
  factory ScanHistoryItem.fromScanResult({
    required String userId,
    required String localImagePath,
    required ScanStatusData result,
  }) {
    return ScanHistoryItem(
      scanId: result.scanId,
      userId: userId,
      status: result.status,
      createdAt: result.createdAt ?? DateTime.now().toIso8601String(),
      updatedAt: result.updatedAt ?? DateTime.now().toIso8601String(),
      imageLocalPath: localImagePath,
      imageThumbnailUrl: result.imageThumbnailKey,
      summary: result.summary,
      keywords: result.keywords,
    );
  }
}
