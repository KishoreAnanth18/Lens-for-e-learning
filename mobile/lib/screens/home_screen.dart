import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/camera_models.dart';
import '../models/scan_models.dart';
import '../providers/scan_provider.dart';
import 'camera/camera_screen.dart';
import 'results/results_screen.dart';
import 'scan/scan_processing_screen.dart';

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
      final scanProvider = context.read<ScanProvider>();
      final sessionId = await scanProvider.startScan(result);

      if (!context.mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ScanProcessingScreen(sessionId: sessionId),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final latestScan = context.watch<ScanProvider>().latestSession;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lens for E-Learning'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Welcome to Lens for E-Learning'),
            if (latestScan != null) ...[
              const SizedBox(height: 24),
              _ActiveScanCard(progress: latestScan),
            ],
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCamera(context),
        icon: const Icon(Icons.camera_alt),
        label: const Text('Scan'),
      ),
    );
  }
}

class _ActiveScanCard extends StatelessWidget {
  const _ActiveScanCard({required this.progress});

  final ScanProgress progress;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              progress.isTerminal ? 'Latest Scan' : 'Active Scan',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(progress.statusMessage),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress.progress.clamp(0, 1)),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => progress.isSuccessful
                        ? ResultsScreen(sessionId: progress.sessionId)
                        : ScanProcessingScreen(sessionId: progress.sessionId),
                  ),
                );
              },
              child: Text(progress.isSuccessful ? 'View Results' : 'Open Progress'),
            ),
          ],
        ),
      ),
    );
  }
}
