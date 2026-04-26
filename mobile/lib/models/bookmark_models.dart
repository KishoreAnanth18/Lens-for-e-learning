class BookmarkItem {
  final String bookmarkId;
  final String scanId;
  final String resourceType;
  final String resourceUrl;
  final String resourceTitle;
  final String resourceDescription;
  final String bookmarkedAt;

  const BookmarkItem({
    required this.bookmarkId,
    required this.scanId,
    required this.resourceType,
    required this.resourceUrl,
    required this.resourceTitle,
    required this.resourceDescription,
    required this.bookmarkedAt,
  });

  factory BookmarkItem.fromJson(Map<String, dynamic> json) {
    return BookmarkItem(
      bookmarkId: json['bookmark_id'] as String? ?? '',
      scanId: json['scan_id'] as String? ?? '',
      resourceType: json['resource_type'] as String? ?? '',
      resourceUrl: json['resource_url'] as String? ?? '',
      resourceTitle: json['resource_title'] as String? ?? '',
      resourceDescription: json['resource_description'] as String? ?? '',
      bookmarkedAt: json['bookmarked_at'] as String? ?? '',
    );
  }
}
