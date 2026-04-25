import 'dart:io';

/// Supported image formats for capture and gallery selection.
enum ImageFormat { jpeg, png, heic }

extension ImageFormatExtension on ImageFormat {
  String get extension {
    switch (this) {
      case ImageFormat.jpeg:
        return 'jpg';
      case ImageFormat.png:
        return 'png';
      case ImageFormat.heic:
        return 'heic';
    }
  }

  String get mimeType {
    switch (this) {
      case ImageFormat.jpeg:
        return 'image/jpeg';
      case ImageFormat.png:
        return 'image/png';
      case ImageFormat.heic:
        return 'image/heic';
    }
  }

  static ImageFormat? fromExtension(String ext) {
    switch (ext.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return ImageFormat.jpeg;
      case 'png':
        return ImageFormat.png;
      case 'heic':
        return ImageFormat.heic;
      default:
        return null;
    }
  }
}

/// Represents a raw captured or picked image before compression.
class CapturedImage {
  final String path;
  final ImageFormat format;
  final int sizeBytes;

  const CapturedImage({
    required this.path,
    required this.format,
    required this.sizeBytes,
  });

  File get file => File(path);

  @override
  String toString() =>
      'CapturedImage(path: $path, format: $format, sizeBytes: $sizeBytes)';
}

/// Represents a compressed image ready for upload.
class CompressedImage {
  final String path;
  final ImageFormat format;
  final int sizeBytes;
  final double compressionRatio;

  const CompressedImage({
    required this.path,
    required this.format,
    required this.sizeBytes,
    required this.compressionRatio,
  });

  File get file => File(path);

  bool get isUnderSizeLimit => sizeBytes <= 2 * 1024 * 1024; // 2 MB

  @override
  String toString() =>
      'CompressedImage(path: $path, format: $format, sizeBytes: $sizeBytes, '
      'compressionRatio: ${compressionRatio.toStringAsFixed(2)})';
}
