import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/comments_sheet.dart';
import '../services/saved_posts_service.dart';

class SavedPostsScreen extends StatefulWidget {
  const SavedPostsScreen({super.key});

  @override
  State<SavedPostsScreen> createState() => _SavedPostsScreenState();
}

class _SavedPostsScreenState extends State<SavedPostsScreen> {
  final _client = Supabase.instance.client;

  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _posts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final savedIds = await SavedPostsService.fetchSavedPostIds();
      if (savedIds.isEmpty) {
        _posts = [];
      } else {
        final res = await _client.from('posts').select('*').inFilter('id', savedIds.toList());
        _posts = (res as List).cast<Map<String, dynamic>>();
        _posts.sort((a, b) {
          final aT = (a['created_at'] ?? '').toString();
          final bT = (b['created_at'] ?? '').toString();
          return bT.compareTo(aT);
        });
      }
    } on PostgrestException catch (e) {
      _error = e.message;
      _posts = [];
    } catch (_) {
      _error = 'Failed to load saved posts.';
      _posts = [];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text('Saved posts'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : (_error != null)
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        _error!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                  )
                : (_posts.isEmpty)
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(vertical: 60),
                        children: const [
                          Icon(Icons.bookmark_border, size: 46, color: Colors.black38),
                          SizedBox(height: 12),
                          Center(
                            child: Text(
                              'No saved posts yet',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black54),
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
                        itemCount: _posts.length,
                        itemBuilder: (context, i) {
                          final p = _posts[i];
                          final postId = (p['id'] ?? '').toString();
                          final content = (p['content'] ?? '').toString();
                          final createdAt = (p['created_at'] ?? '').toString();

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Material(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: postId.isEmpty
                                    ? null
                                    : () => showCommentsSheet(context: context, postId: postId, categoryId: 0),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const CircleAvatar(radius: 14, child: Icon(Icons.person_off, size: 16)),
                                          const SizedBox(width: 10),
                                          const Text('Anon', style: TextStyle(fontWeight: FontWeight.w900)),
                                          const Spacer(),
                                          Text(
                                            createdAt.isEmpty ? '' : createdAt.substring(0, createdAt.length > 10 ? 10 : createdAt.length),
                                            style: const TextStyle(color: Colors.black45, fontWeight: FontWeight.w700, fontSize: 12),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Text(content, style: const TextStyle(fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: const [
                                          Icon(Icons.chat_bubble_outline, size: 18, color: Colors.black54),
                                          SizedBox(width: 6),
                                          Text('Open comments', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
