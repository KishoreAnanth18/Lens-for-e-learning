import 'package:flutter/material.dart';

import '../models/camera_models.dart';
import 'camera/camera_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _openCamera(BuildContext context) async {
    final result = await Navigator.of(context).push<CompressedImage>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const CameraScreen(),
      ),
    );

    if (result != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Image ready for upload (${(result.sizeBytes / 1024).toStringAsFixed(1)} KB)',
          ),
        ),
      );
      // TODO: pass `result` to the scan processing screen (task 12.2+)
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lens for E-Learning'),
      ),
      body: const Center(
        child: Text('Welcome to Lens for E-Learning'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCamera(context),
        icon: const Icon(Icons.camera_alt),
        label: const Text('Scan'),
      ),
    );
  }
}
