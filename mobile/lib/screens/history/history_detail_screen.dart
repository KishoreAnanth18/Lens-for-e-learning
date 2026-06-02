import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/scan_models.dart';
import '../../providers/history_provider.dart';

/// Displays the full cached results for a historical scan.
class HistoryDetailScreen extends StatefulWidget {
  const HistoryDetailScreen({super.key, required this.scanId});

  final String scanId;

  @override
  State<HistoryDetailScreen> createState() => _HistoryDetailScreenState();
}

class _HistoryDetailScreenState extends State<HistoryDetailScreen> {
  ScanStatusData? _result;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadResult();
  }

  Future<void> _loadResult() async {
    try {
      final result = await context
          .read<HistoryProvider>()
          .getCachedResult(widget.scanId);
      if (mounted) {
        setState(() {
          _result = result;
          _isLoading = false;
          if (result == null) {
            _error = 'Cached results not found for this scan.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to load cached results: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Results')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!),
        ),
      );
    }

    final result = _result!;
    final tabs = <_TabData>[
      _TabData(title: 'Videos', resources: result.videos),
      _TabData(title: 'Articles', resources: result.articles),
      _TabData(title: 'Websites', resources: result.websites),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Column(
        children: [
          _ContextCard(result: result),
          TabBar(
            tabs: [
              for (final t in tabs)
                Tab(text: '${t.title} (${t.resources.length})'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (final t in tabs)
                  _ResourceList(resources: t.resources),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContextCard extends StatelessWidget {
  const _ContextCard({required this.result});

  final ScanStatusData result;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thumbnail placeholder (no local path available from cache)
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.image_outlined),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Summary',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        result.summary?.isNotEmpty == true
                            ? result.summary!
                            : 'No summary available.',
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (result.keywords.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final kw in result.keywords) Chip(label: Text(kw)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResourceList extends StatelessWidget {
  const _ResourceList({required this.resources});

  final List<ScanResource> resources;

  @override
  Widget build(BuildContext context) {
    if (resources.isEmpty) {
      return const Center(child: Text('No resources in this category.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: resources.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final resource = resources[index];
        return Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            title: Text(resource.title),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(resource.description),
                  const SizedBox(height: 8),
                  Text(
                    resource.url,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            onTap: () => _openUrl(context, resource.url),
          ),
        );
      },
    );
  }

  Future<void> _openUrl(BuildContext context, String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This resource URL is invalid.')),
      );
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    if (!launched && context.mounted) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _TabData {
  const _TabData({required this.title, required this.resources});

  final String title;
  final List<ScanResource> resources;
}
