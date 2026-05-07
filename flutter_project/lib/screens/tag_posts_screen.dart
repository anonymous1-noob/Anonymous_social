import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/hashtags.dart';
import '../widgets/comments_sheet.dart';

class TagPostsScreen extends StatefulWidget {
  final String tag;
  const TagPostsScreen({super.key, required this.tag});

  @override
  State<TagPostsScreen> createState() => _TagPostsScreenState();
}

class _TagPostsScreenState extends State<TagPostsScreen> {
  final _supabase = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> _fetchPosts() async {
    final normalizedTag = normalizeHashtag(widget.tag);
    if (normalizedTag.isEmpty) return [];

    final rows = await _supabase.rpc(
      'get_posts_for_tag',
      params: {'tag_name': normalizedTag},
    );

    return List<Map<String, dynamic>>.from(rows);
  }

  @override
  Widget build(BuildContext context) {
    final title = displayHashtag(widget.tag);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _fetchPosts(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Failed to load tag: ${snap.error}'));
          }
          final posts = snap.data ?? [];
          if (posts.isEmpty) {
            return const Center(child: Text('No posts found for this tag yet.'));
          }
          return ListView.builder(
            itemCount: posts.length,
            itemBuilder: (_, i) {
              final p = posts[i];
              final content = (p['content'] ?? '').toString();
              final postId = (p['id'] ?? '').toString();
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: ListTile(
                  title: Text(content.isEmpty ? '(No content)' : content),
                  onTap: () => showCommentsSheet(context: context, postId: postId, categoryId: 0),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
