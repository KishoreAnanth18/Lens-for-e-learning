import '../models/camera_models.dart';

/// Abstract interface for camera and image-picking operations.
///
/// Requirement 2.1 – live camera preview capture
/// Requirement 2.2 – save image locally before upload
/// Requirement 2.3 – gallery selection with format filtering
/// Requirement 2.4 – client-side compression to max 2 MB
abstract class ICameraService {
  /// Capture an image using the device camera.
  /// The image is saved locally before being returned.
  Future<CapturedImage> captureImage();

  /// Pick an image from the device gallery.
  /// Only JPEG, PNG, and HEIC formats are accepted.
  Future<CapturedImage> pickFromGallery();

  /// Compress [image] so that its size does not exceed [maxSizeBytes].
  /// Returns a [CompressedImage] with the resulting path and metadata.
  Future<CompressedImage> compressImage(
    CapturedImage image,
    int maxSizeBytes,
  );

  /// Release any resources held by the service (e.g. camera controller).
  Future<void> dispose();
}
