import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/camera_models.dart';
import 'camera_service.dart';

/// Concrete implementation of [ICameraService].
///
/// Uses:
///  - `camera` plugin for live-preview capture
///  - `image_picker` for gallery selection
///  - `flutter_image_compress` for client-side compression
///  - `path_provider` for local storage
class CameraServiceImpl implements ICameraService {
  CameraController? _controller;
  final ImagePicker _picker = const ImagePicker();
  final _uuid = const Uuid();

  // ── Initialisation ──────────────────────────────────────────────────────────

  /// Initialise the camera controller for the given [camera].
  /// Call this before [captureImage].
  Future<void> initCamera(CameraDescription camera) async {
    _controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
    );
    await _controller!.initialize();
  }

  CameraController? get controller => _controller;

  // ── ICameraService ───────────────────────────────────────────────────────────

  /// Requirement 2.1 / 2.2 – capture via live preview and save locally.
  @override
  Future<CapturedImage> captureImage() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      throw StateError('Camera is not initialised. Call initCamera() first.');
    }

    final xFile = await _controller!.takePicture();
    final savedPath = await _saveLocally(xFile.path, ImageFormat.jpeg);

    final sizeBytes = await File(savedPath).length();
    return CapturedImage(
      path: savedPath,
      format: ImageFormat.jpeg,
      sizeBytes: sizeBytes,
    );
  }

  /// Requirement 2.3 – gallery picker with JPEG / PNG / HEIC filtering.
  @override
  Future<CapturedImage> pickFromGallery() async {
    final xFile = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 100, // no quality loss at pick time; we compress later
    );

    if (xFile == null) {
      throw StateError('No image selected from gallery.');
    }

    final ext = p.extension(xFile.path).replaceFirst('.', '').toLowerCase();
    final format = ImageFormatExtension.fromExtension(ext);

    if (format == null) {
      throw UnsupportedError(
        'Unsupported image format "$ext". '
        'Only JPEG, PNG, and HEIC are accepted.',
      );
    }

    final savedPath = await _saveLocally(xFile.path, format);
    final sizeBytes = await File(savedPath).length();

    return CapturedImage(
      path: savedPath,
      format: format,
      sizeBytes: sizeBytes,
    );
  }

  /// Requirement 2.4 – compress to at most [maxSizeBytes] (default 2 MB).
  @override
  Future<CompressedImage> compressImage(
    CapturedImage image,
    int maxSizeBytes,
  ) async {
    final capturesDir = await _capturesDirectory();
    final filename =
        '${DateTime.now().millisecondsSinceEpoch}_${_uuid.v4()}.jpg';
    final targetPath = p.join(capturesDir.path, filename);

    int quality = 85;
    XFile? result;

    // Iteratively reduce quality until the file fits within maxSizeBytes.
    while (quality >= 10) {
      result = await FlutterImageCompress.compressAndGetFile(
        image.path,
        targetPath,
        quality: quality,
        format: CompressFormat.jpeg,
      );

      if (result == null) {
        throw Exception('Image compression failed.');
      }

      final size = await File(result.path).length();
      if (size <= maxSizeBytes) break;

      quality -= 10;
    }

    if (result == null) {
      throw Exception('Image compression produced no output.');
    }

    final compressedSize = await File(result.path).length();
    final ratio = image.sizeBytes > 0
        ? compressedSize / image.sizeBytes
        : 1.0;

    // Delete the original uncompressed file to save space (per spec).
    final original = File(image.path);
    if (await original.exists() && original.path != result.path) {
      await original.delete();
    }

    return CompressedImage(
      path: result.path,
      format: ImageFormat.jpeg,
      sizeBytes: compressedSize,
      compressionRatio: ratio,
    );
  }

  @override
  Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
  }

  // ── Private helpers ──────────────────────────────────────────────────────────

  /// Save a file from [sourcePath] into the app's captures directory.
  /// Returns the new path.
  Future<String> _saveLocally(String sourcePath, ImageFormat format) async {
    final dir = await _capturesDirectory();
    final filename =
        '${DateTime.now().millisecondsSinceEpoch}_${_uuid.v4()}.${format.extension}';
    final dest = p.join(dir.path, filename);
    await File(sourcePath).copy(dest);
    return dest;
  }

  Future<Directory> _capturesDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'captures'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
