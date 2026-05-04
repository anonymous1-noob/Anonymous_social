import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    final normalizedTag = widget.tag.startsWith('#') ? widget.tag : '#${widget.tag}';
    final postRows = await _supabase
        .from('posts')
        .select('id, content, created_at')
        .ilike('content', '%$normalizedTag%')
        .order('created_at', ascending: false);

    final commentRows = await _supabase
        .from('comments')
        .select('post_id')
        .ilike('content', '%$normalizedTag%');

    final idsFromComments = commentRows
        .map((e) => (e['post_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();

    final existingIds = postRows.map((e) => (e['id'] ?? '').toString()).toSet();
    final missingIds = idsFromComments.where((id) => !existingIds.contains(id)).toList();

    if (missingIds.isNotEmpty) {
      final extraPosts = await _supabase
          .from('posts')
          .select('id, content, created_at')
          .inFilter('id', missingIds)
          .order('created_at', ascending: false);
      return [...postRows, ...extraPosts];
    }

    return List<Map<String, dynamic>>.from(postRows);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.tag)),
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
