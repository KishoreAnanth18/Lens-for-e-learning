import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/history_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/history_provider.dart';
import '../../providers/scan_provider.dart';
import '../results/results_screen.dart';
import 'history_detail_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final userId = context.read<AuthProvider>().currentUser?.userId ?? '';
      context.read<HistoryProvider>().loadHistory(userId);
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String get _userId =>
      context.read<AuthProvider>().currentUser?.userId ?? '';

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      context.read<HistoryProvider>().setSearchQuery(query, _userId);
    });
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      helpText: 'Filter by date range',
    );

    if (range == null || !mounted) return;

    context.read<HistoryProvider>().setDateFilter(
          userId: _userId,
          from: range.start.toIso8601String(),
          to: range.end
              .add(const Duration(hours: 23, minutes: 59, seconds: 59))
              .toIso8601String(),
        );
  }

  void _clearFilters() {
    _searchController.clear();
    context.read<HistoryProvider>().clearFilters(_userId);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    ScanHistoryItem item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete scan?'),
        content: const Text(
          'This will remove the scan from your history and the server. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      // ignore: use_build_context_synchronously
      await context.read<HistoryProvider>().deleteScan(item.scanId);
    }
  }

  void _openItem(BuildContext context, ScanHistoryItem item) {
    // If the scan is still in the active session map, show the live results
    // screen; otherwise load from cache.
    final scanProvider = context.read<ScanProvider>();
    final liveSession = scanProvider.sessions.entries
        .where((e) => e.value.scanId == item.scanId)
        .map((e) => e.key)
        .firstOrNull;

    if (liveSession != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ResultsScreen(sessionId: liveSession),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => HistoryDetailScreen(scanId: item.scanId),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HistoryProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan History'),
        actions: [
          if (provider.hasActiveFilter)
            IconButton(
              tooltip: 'Clear filters',
              onPressed: _clearFilters,
              icon: const Icon(Icons.filter_alt_off_outlined),
            ),
          IconButton(
            tooltip: 'Filter by date',
            onPressed: _pickDateRange,
            icon: const Icon(Icons.date_range_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          if (provider.errorMessage != null)
            MaterialBanner(
              content: Text(provider.errorMessage!),
              actions: [
                TextButton(
                  onPressed: () => provider.loadHistory(_userId, force: true),
                  child: const Text('Retry'),
                ),
              ],
            ),
          _SearchBar(
            controller: _searchController,
            onChanged: _onSearchChanged,
          ),
          if (provider.filterFrom != null || provider.filterTo != null)
            _DateRangeChip(
              from: provider.filterFrom,
              to: provider.filterTo,
              onClear: _clearFilters,
            ),
          Expanded(
            child: _buildBody(context, provider),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, HistoryProvider provider) {
    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.errorMessage != null && provider.items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 16),
              Text(provider.errorMessage!),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () => provider.loadHistory(_userId, force: true),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (provider.items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.history, size: 48),
              const SizedBox(height: 16),
              Text(
                provider.hasActiveFilter
                    ? 'No scans match your search.'
                    : 'No scans yet. Tap the Scan button to get started.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => provider.loadHistory(_userId, force: true),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        itemCount: provider.items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final item = provider.items[index];
          return _HistoryCard(
            item: item,
            onTap: () => _openItem(context, item),
            onDelete: () => _confirmDelete(context, item),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: 'Search history…',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                )
              : null,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}

class _DateRangeChip extends StatelessWidget {
  const _DateRangeChip({
    required this.from,
    required this.to,
    required this.onClear,
  });

  final String? from;
  final String? to;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    String label = 'Date: ';
    if (from != null) {
      label += _fmt(from!);
    }
    if (to != null) {
      label += ' – ${_fmt(to!)}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Chip(
            label: Text(label),
            deleteIcon: const Icon(Icons.close, size: 16),
            onDeleted: onClear,
          ),
        ],
      ),
    );
  }

  static String _fmt(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.item,
    required this.onTap,
    required this.onDelete,
  });

  final ScanHistoryItem item;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final imagePath = item.imageLocalPath;
    final hasLocalImage =
        imagePath != null && imagePath.isNotEmpty && File(imagePath).existsSync();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: hasLocalImage
                    ? Image.file(
                        File(imagePath),
                        width: 72,
                        height: 72,
                        cacheWidth: 144,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        width: 72,
                        height: 72,
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child: const Icon(Icons.image_outlined),
                      ),
              ),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatDate(item.createdAt),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.summary?.isNotEmpty == true
                          ? item.summary!
                          : 'No summary available.',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (item.keywords.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        item.keywords.take(3).join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              // Delete button
              IconButton(
                tooltip: 'Delete scan',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
                iconSize: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);

      if (diff.inDays == 0) return 'Today ${_time(dt)}';
      if (diff.inDays == 1) return 'Yesterday ${_time(dt)}';
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${_time(dt)}';
    } catch (_) {
      return iso;
    }
  }

  static String _time(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}
