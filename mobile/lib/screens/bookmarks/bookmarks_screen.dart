import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/bookmark_provider.dart';

class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<BookmarkProvider>().loadBookmarks(force: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BookmarkProvider>();
    final bookmarks = provider.bookmarks;

    return Scaffold(
      appBar: AppBar(title: const Text('Bookmarks')),
      body: provider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : bookmarks.isEmpty
              ? const Center(child: Text('No bookmarks saved yet.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: bookmarks.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final bookmark = bookmarks[index];
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        title: Text(bookmark.resourceTitle),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(bookmark.resourceDescription),
                              const SizedBox(height: 8),
                              Text(
                                bookmark.resourceUrl,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        trailing: IconButton(
                          tooltip: 'Remove bookmark',
                          onPressed: () => context
                              .read<BookmarkProvider>()
                              .removeBookmark(bookmark.bookmarkId),
                          icon: const Icon(Icons.delete_outline),
                        ),
                        onTap: () => _openResource(context, bookmark.resourceUrl),
                      ),
                    );
                  },
                ),
    );
  }

  Future<void> _openResource(BuildContext context, String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This bookmark URL is invalid.')),
      );
      return;
    }

    final launchedInApp = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    if (launchedInApp) return;

    final launchedExternal = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!launchedExternal && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the selected bookmark.')),
      );
    }
  }
}
