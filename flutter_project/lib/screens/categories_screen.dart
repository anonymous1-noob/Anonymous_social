import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/hashtags.dart';
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

  Future<List<Map<String, dynamic>>> _fetchTags() async {
    final query = _searchController.text.trim();
    final normalizedQuery = normalizeHashtag(query);

    final baseQuery = _supabase
        .from('tags')
        .select('name, normalized_name, post_count')
        .gt('post_count', 0);

    final filteredQuery = normalizedQuery.isEmpty
        ? baseQuery
        : baseQuery.ilike('normalized_name', '%$normalizedQuery%');

    final rows = await filteredQuery
        .order('post_count', ascending: false)
        .order('normalized_name')
        .limit(100);
    return List<Map<String, dynamic>>.from(rows);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                  child: FutureBuilder<List<Map<String, dynamic>>>(
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

                      if (tags.isEmpty) {
                        return const Center(child: Text('No tags found'));
                      }

                      return ListView.separated(
                        itemCount: tags.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final row = tags[index];
                          final tag = (row['name'] ?? '').toString();
                          final normalized = (row['normalized_name'] ?? '').toString();
                          final postCount = row['post_count'] ?? 0;
                          final displayTag = tag.isNotEmpty ? tag : displayHashtag(normalized);

                          return ListTile(
                            leading: const Icon(Icons.tag),
                            title: Text(displayTag),
                            subtitle: Text('$postCount posts'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => TagPostsScreen(tag: displayTag)),
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
