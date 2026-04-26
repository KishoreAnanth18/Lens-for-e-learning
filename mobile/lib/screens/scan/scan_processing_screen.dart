import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/scan_models.dart';
import '../../providers/scan_provider.dart';
import '../results/results_screen.dart';

class ScanProcessingScreen extends StatefulWidget {
  const ScanProcessingScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  State<ScanProcessingScreen> createState() => _ScanProcessingScreenState();
}

class _ScanProcessingScreenState extends State<ScanProcessingScreen> {
  bool _didNavigateToResults = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ScanProvider>().markBackgrounded(widget.sessionId, false);
    });
  }

  @override
  void dispose() {
    context.read<ScanProvider>().markBackgrounded(widget.sessionId, true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ScanProvider>();
    final progress = provider.sessionById(widget.sessionId);

    if (progress == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Processing Scan')),
        body: const Center(child: Text('Scan session not found.')),
      );
    }

    if (progress.isSuccessful && !_didNavigateToResults) {
      _didNavigateToResults = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ResultsScreen(sessionId: widget.sessionId),
          ),
        );
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Processing Scan'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatusHeader(progress: progress),
              const SizedBox(height: 24),
              LinearProgressIndicator(value: progress.progress.clamp(0, 1)),
              const SizedBox(height: 12),
              Text(
                '${(progress.progress * 100).toStringAsFixed(0)}% complete',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                progress.statusMessage,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (!progress.isTerminal) ...[
                const SizedBox(height: 12),
                Text(
                  'You can leave this screen. Processing will continue in the background.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              if (progress.errorMessage != null) ...[
                const SizedBox(height: 20),
                Text(
                  progress.errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ],
              if (progress.result?.summary != null && progress.result!.summary!.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  'Summary',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(progress.result!.summary!),
                  ),
                ),
              ] else
                const Spacer(),
              const SizedBox(height: 16),
              if (progress.isSuccessful)
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => ResultsScreen(sessionId: widget.sessionId),
                      ),
                    );
                  },
                  child: const Text('View Results'),
                )
              else if (progress.stage == ScanStage.failed)
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.progress});

  final ScanProgress progress;

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;

    switch (progress.stage) {
      case ScanStage.complete:
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case ScanStage.failed:
        icon = Icons.error;
        color = Theme.of(context).colorScheme.error;
        break;
      default:
        icon = Icons.sync;
        color = Theme.of(context).colorScheme.primary;
    }

    final result = progress.result;
    final resourceCount = (result?.videos.length ?? 0) +
        (result?.articles.length ?? 0) +
        (result?.websites.length ?? 0);

    return Column(
      children: [
        Icon(icon, size: 56, color: color),
        const SizedBox(height: 12),
        Text(
          _titleForStage(progress.stage),
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        if (progress.scanId != null) ...[
          const SizedBox(height: 8),
          Text(
            'Scan ID: ${progress.scanId}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (progress.stage == ScanStage.complete) ...[
          const SizedBox(height: 8),
          Text(
            '$resourceCount resources found',
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  static String _titleForStage(ScanStage stage) {
    switch (stage) {
      case ScanStage.upload:
        return 'Uploading';
      case ScanStage.ocr:
        return 'Extracting Text';
      case ScanStage.summarization:
        return 'Summarizing';
      case ScanStage.keywords:
        return 'Extracting Keywords';
      case ScanStage.search:
        return 'Finding Resources';
      case ScanStage.complete:
        return 'Results Ready';
      case ScanStage.failed:
        return 'Processing Failed';
      case ScanStage.idle:
        return 'Preparing';
    }
  }
}
