enum ScanStage {
  idle,
  upload,
  ocr,
  summarization,
  keywords,
  search,
  complete,
  failed,
}

class ScanResource {
  final String title;
  final String description;
  final String url;

  const ScanResource({
    required this.title,
    required this.description,
    required this.url,
  });

  factory ScanResource.fromJson(Map<String, dynamic> json) {
    return ScanResource(
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      url: json['url'] as String? ?? '',
    );
  }
}

class ScanStatusData {
  final String scanId;
  final String status;
  final String? createdAt;
  final String? updatedAt;
  final String? imageThumbnailKey;
  final String? errorMessage;
  final String? extractedText;
  final String? summary;
  final List<String> keywords;
  final List<ScanResource> videos;
  final List<ScanResource> articles;
  final List<ScanResource> websites;

  const ScanStatusData({
    required this.scanId,
    required this.status,
    this.createdAt,
    this.updatedAt,
    this.imageThumbnailKey,
    this.errorMessage,
    this.extractedText,
    this.summary,
    this.keywords = const [],
    this.videos = const [],
    this.articles = const [],
    this.websites = const [],
  });

  factory ScanStatusData.fromJson(Map<String, dynamic> json) {
    List<ScanResource> parseResources(String key) {
      final raw = json[key];
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((item) => ScanResource.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    }

    return ScanStatusData(
      scanId: json['scan_id'] as String? ?? '',
      status: json['status'] as String? ?? 'processing',
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
      imageThumbnailKey: json['image_thumbnail_key'] as String?,
      errorMessage: json['error_message'] as String?,
      extractedText: json['extracted_text'] as String?,
      summary: json['summary'] as String?,
      keywords: (json['keywords'] as List?)?.whereType<String>().toList() ?? const [],
      videos: parseResources('videos'),
      articles: parseResources('articles'),
      websites: parseResources('websites'),
    );
  }
}

class ScanProgress {
  final String sessionId;
  final String? scanId;
  final ScanStage stage;
  final double progress;
  final String statusMessage;
  final bool isInBackground;
  final String? localImagePath;
  final String? errorMessage;
  final ScanStatusData? result;

  const ScanProgress({
    required this.sessionId,
    required this.stage,
    required this.progress,
    required this.statusMessage,
    this.scanId,
    this.isInBackground = false,
    this.localImagePath,
    this.errorMessage,
    this.result,
  });

  bool get isTerminal => stage == ScanStage.complete || stage == ScanStage.failed;
  bool get isSuccessful => stage == ScanStage.complete;

  ScanProgress copyWith({
    String? sessionId,
    String? scanId,
    ScanStage? stage,
    double? progress,
    String? statusMessage,
    bool? isInBackground,
    String? localImagePath,
    String? errorMessage,
    ScanStatusData? result,
  }) {
    return ScanProgress(
      sessionId: sessionId ?? this.sessionId,
      scanId: scanId ?? this.scanId,
      stage: stage ?? this.stage,
      progress: progress ?? this.progress,
      statusMessage: statusMessage ?? this.statusMessage,
      isInBackground: isInBackground ?? this.isInBackground,
      localImagePath: localImagePath ?? this.localImagePath,
      errorMessage: errorMessage ?? this.errorMessage,
      result: result ?? this.result,
    );
  }
}
