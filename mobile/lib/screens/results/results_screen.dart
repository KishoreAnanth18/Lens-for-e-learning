import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/bookmark_provider.dart';
import '../../models/scan_models.dart';
import '../../providers/scan_provider.dart';

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({
    super.key,
    required this.sessionId,
  });

  final String sessionId;

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<BookmarkProvider>().loadBookmarks();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ScanProvider>();
    final progress = provider.sessionById(widget.sessionId);

    if (progress == null || progress.result == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Scan Results')),
        body: const Center(child: Text('Results are not available yet.')),
      );
    }

    final result = progress.result!;
    final tabs = <_ResultTabData>[
      _ResultTabData(title: 'Videos', resources: result.videos),
      _ResultTabData(title: 'Articles', resources: result.articles),
      _ResultTabData(title: 'Websites', resources: result.websites),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Scan Results'),
          actions: [
            IconButton(
              tooltip: 'Share results',
              onPressed: () => _shareResults(context, progress),
              icon: const Icon(Icons.share_outlined),
            ),
          ],
          bottom: TabBar(
            tabs: [
              for (final tab in tabs)
                Tab(text: '${tab.title} (${tab.resources.length})'),
            ],
          ),
        ),
        body: Column(
          children: [
            _ResultsContextCard(progress: progress),
            Expanded(
              child: TabBarView(
                children: [
                  for (final tab in tabs)
                    _ResultsList(
                      sessionId: widget.sessionId,
                      scanId: progress.scanId ?? result.scanId,
                      resourceType: tab.title.toLowerCase().replaceAll('s', ''),
                      resources: tab.resources,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareResults(BuildContext context, ScanProgress progress) async {
    final result = progress.result;
    if (result == null) return;

    final buffer = StringBuffer();
    buffer.writeln('Lens for E-Learning results');
    if (result.summary != null && result.summary!.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Summary:');
      buffer.writeln(result.summary!);
    }

    void appendCategory(String title, List<ScanResource> resources) {
      if (resources.isEmpty) return;
      buffer.writeln();
      buffer.writeln('$title:');
      for (final resource in resources) {
        buffer.writeln('- ${resource.title}');
        buffer.writeln('  ${resource.url}');
      }
    }

    appendCategory('Videos', result.videos);
    appendCategory('Articles', result.articles);
    appendCategory('Websites', result.websites);

    await Share.share(buffer.toString(), subject: 'Lens for E-Learning results');
  }
}

class _ResultsContextCard extends StatelessWidget {
  const _ResultsContextCard({required this.progress});

  final ScanProgress progress;

  @override
  Widget build(BuildContext context) {
    final result = progress.result!;
    final imagePath = progress.localImagePath;

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
                if (imagePath != null && imagePath.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(imagePath),
                      width: 88,
                      height: 88,
                      fit: BoxFit.cover,
                    ),
                  )
                else
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.image_outlined),
                  ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Extracted Summary',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        result.summary?.isNotEmpty == true
                            ? result.summary!
                            : 'Summary is not available for this scan.',
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (result.keywords.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final keyword in result.keywords)
                    Chip(label: Text(keyword)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResultsList extends StatelessWidget {
  const _ResultsList({
    required this.sessionId,
    required this.scanId,
    required this.resourceType,
    required this.resources,
  });

  final String sessionId;
  final String scanId;
  final String resourceType;
  final List<ScanResource> resources;

  @override
  Widget build(BuildContext context) {
    if (resources.isEmpty) {
      return const Center(
        child: Text('No resources found in this category.'),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: resources.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final resource = resources[index];
        final bookmarked = context.watch<BookmarkProvider>().isBookmarked(resource.url);

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
            trailing: IconButton(
              tooltip: bookmarked ? 'Remove bookmark' : 'Bookmark',
              onPressed: () => context.read<BookmarkProvider>().toggleBookmark(
                    scanId: scanId,
                    resourceType: resourceType,
                    resource: resource,
                  ),
              icon: Icon(
                bookmarked ? Icons.bookmark : Icons.bookmark_border,
              ),
            ),
            onTap: () => _openResource(context, resource.url),
          ),
        );
      },
    );
  }

  Future<void> _openResource(BuildContext context, String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This resource URL is invalid.')),
      );
      return;
    }

    final launchedInApp = await launchUrl(
      uri,
      mode: LaunchMode.inAppBrowserView,
    );
    if (launchedInApp) return;

    final launchedExternal = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!launchedExternal && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the selected resource.')),
      );
    }
  }
}

class _ResultTabData {
  const _ResultTabData({
    required this.title,
    required this.resources,
  });

  final String title;
  final List<ScanResource> resources;
}
