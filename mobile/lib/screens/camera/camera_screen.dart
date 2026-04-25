import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models/camera_models.dart';
import '../../services/camera_service_impl.dart';

/// Full-screen camera experience.
///
/// Requirement 2.1 – live camera preview with capture controls
/// Requirement 2.2 – save image locally before upload
/// Requirement 2.3 – gallery picker (JPEG / PNG / HEIC)
/// Requirement 2.4 – compress to max 2 MB before navigating forward
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  final CameraServiceImpl _cameraService = CameraServiceImpl();

  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;
  bool _isInitialised = false;
  bool _isBusy = false;
  FlashMode _flashMode = FlashMode.off;

  // Preview state after capture
  CapturedImage? _capturedImage;

  static const int _maxSizeBytes = 2 * 1024 * 1024; // 2 MB

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isInitialised) return;
    if (state == AppLifecycleState.inactive) {
      _cameraService.dispose();
      setState(() => _isInitialised = false);
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraService.dispose();
    super.dispose();
  }

  // ── Initialisation ───────────────────────────────────────────────────────────

  Future<void> _initCamera() async {
    final granted = await _requestCameraPermission();
    if (!granted) return;

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        _showError('No cameras found on this device.');
        return;
      }
      await _cameraService.initCamera(_cameras[_selectedCameraIndex]);
      if (mounted) setState(() => _isInitialised = true);
    } catch (e) {
      _showError('Failed to initialise camera: $e');
    }
  }

  Future<bool> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (status.isDenied || status.isPermanentlyDenied) {
      if (mounted) {
        _showPermissionDialog(
          'Camera Permission',
          'Camera access is required to capture images.',
        );
      }
      return false;
    }
    return true;
  }

  // ── Actions ──────────────────────────────────────────────────────────────────

  Future<void> _captureImage() async {
    if (_isBusy || !_isInitialised) return;
    setState(() => _isBusy = true);
    try {
      final image = await _cameraService.captureImage();
      setState(() => _capturedImage = image);
    } catch (e) {
      _showError('Capture failed: $e');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _pickFromGallery() async {
    final status = await Permission.photos.request();
    if (status.isDenied || status.isPermanentlyDenied) {
      _showPermissionDialog(
        'Photo Library Permission',
        'Photo library access is required to select images.',
      );
      return;
    }

    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      final image = await _cameraService.pickFromGallery();
      setState(() => _capturedImage = image);
    } on UnsupportedError catch (e) {
      _showError(e.message ?? 'Unsupported image format.');
    } on StateError catch (e) {
      // User cancelled – no-op
      debugPrint('Gallery pick cancelled: $e');
    } catch (e) {
      _showError('Gallery pick failed: $e');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _confirmCapture() async {
    if (_capturedImage == null || _isBusy) return;
    setState(() => _isBusy = true);
    try {
      final compressed = await _cameraService.compressImage(
        _capturedImage!,
        _maxSizeBytes,
      );
      if (mounted) {
        Navigator.of(context).pop(compressed);
      }
    } catch (e) {
      _showError('Compression failed: $e');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _retake() {
    setState(() => _capturedImage = null);
  }

  Future<void> _toggleFlash() async {
    if (!_isInitialised) return;
    final next = _flashMode == FlashMode.off ? FlashMode.torch : FlashMode.off;
    await _cameraService.controller?.setFlashMode(next);
    setState(() => _flashMode = next);
  }

  Future<void> _flipCamera() async {
    if (_cameras.length < 2) return;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    await _cameraService.dispose();
    setState(() => _isInitialised = false);
    await _cameraService.initCamera(_cameras[_selectedCameraIndex]);
    if (mounted) setState(() => _isInitialised = true);
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showPermissionDialog(String title, String message) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _capturedImage != null
            ? _buildPreview()
            : _buildCameraView(),
      ),
    );
  }

  // ── Camera view ──────────────────────────────────────────────────────────────

  Widget _buildCameraView() {
    return Stack(
      fit: StackFit.expand,
      children: [
        _isInitialised
            ? CameraPreview(_cameraService.controller!)
            : const Center(child: CircularProgressIndicator(color: Colors.white)),
        _buildTopControls(),
        _buildBottomControls(),
      ],
    );
  }

  Widget _buildTopControls() {
    return Positioned(
      top: 16,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 28),
            onPressed: () => Navigator.of(context).pop(),
          ),
          IconButton(
            icon: Icon(
              _flashMode == FlashMode.off ? Icons.flash_off : Icons.flash_on,
              color: Colors.white,
              size: 28,
            ),
            onPressed: _toggleFlash,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    return Positioned(
      bottom: 32,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Gallery picker
          IconButton(
            icon: const Icon(Icons.photo_library, color: Colors.white, size: 32),
            onPressed: _isBusy ? null : _pickFromGallery,
          ),
          // Shutter button
          GestureDetector(
            onTap: _isBusy ? null : _captureImage,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
                color: _isBusy ? Colors.grey : Colors.white24,
              ),
              child: _isBusy
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          // Flip camera
          IconButton(
            icon: const Icon(Icons.flip_camera_ios, color: Colors.white, size: 32),
            onPressed: _isBusy ? null : _flipCamera,
          ),
        ],
      ),
    );
  }

  // ── Preview view ─────────────────────────────────────────────────────────────

  Widget _buildPreview() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(
          File(_capturedImage!.path),
          fit: BoxFit.cover,
        ),
        Positioned(
          bottom: 32,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Retake
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black54,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.refresh),
                label: const Text('Retake'),
                onPressed: _isBusy ? null : _retake,
              ),
              // Confirm
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                icon: _isBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.check),
                label: const Text('Use Photo'),
                onPressed: _isBusy ? null : _confirmCapture,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
