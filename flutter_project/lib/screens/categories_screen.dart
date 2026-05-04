import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'tag_posts_screen.dart';

class CategoriesScreen extends ConsumerStatefulWidget {
  final int selectedCategoryId;
  final ValueChanged<int> onSelectCategory;

  const CategoriesScreen({
    super.key,
    required this.selectedCategoryId,
    required this.onSelectCategory,
  });

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  final _searchController = TextEditingController();
  final _supabase = Supabase.instance.client;

  Future<List<String>> _fetchTags() async {
    final postRows = await _supabase.from('posts').select('content');
    final commentRows = await _supabase.from('comments').select('content');

    final tagRegex = RegExp(r'(?<!\w)#([A-Za-z0-9_]+)');
    final tags = <String>{};

    void collectTags(List<dynamic> rows) {
      for (final row in rows) {
        final content = (row['content'] ?? '').toString();
        for (final match in tagRegex.allMatches(content)) {
          final raw = match.group(1);
          if (raw == null || raw.isEmpty) continue;
          tags.add('#${raw.toLowerCase()}');
        }
      }
    }

    collectTags(postRows);
    collectTags(commentRows);

    final sorted = tags.toList()..sort();
    return sorted;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8FA),
      appBar: AppBar(
        title: const Text('Explore'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search tags…',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(() => _searchController.clear()),
                          ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: FutureBuilder<List<String>>(
                    future: _fetchTags(),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snap.hasError) {
                        return Center(
                          child: Text(
                            'Failed to load tags\n${snap.error}',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Theme.of(context).colorScheme.error),
                          ),
                        );
                      }

                      final tags = snap.data ?? [];
                      final filtered = tags.where((tag) {
                        return query.isEmpty || tag.contains(query);
                      }).toList();

                      if (filtered.isEmpty) {
                        return const Center(child: Text('No tags found'));
                      }

                      return ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final tag = filtered[index];

                          return ListTile(
                            leading: const Icon(Icons.tag),
                            title: Text(tag),
                            subtitle: const Text('Tap to view posts for this tag'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => TagPostsScreen(tag: tag)),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
